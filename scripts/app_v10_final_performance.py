"""V10 final protected optimization layer.

Runs after all original R5/V9 transformations and regression checks.
Only touches image presentation, public metadata request coalescing, and the
Home catalog load policy. NEVER mutates FrameXTVPlayerV6, VLC, IPTV account
selection, subtitles or source/server rotation.
"""
from pathlib import Path

def replace_one(text, old, new, label):
    count = text.count(old)
    if count != 1:
        raise SystemExit(f"V10 {label}: expected one marker, found {count}")
    return text.replace(old, new, 1)

# Replace built-in per-cell image decoding with the shared downsampled pipeline.
# Keep RemotePoster initializer, layout, and aspect/corner semantics identical
# so every previously working card and NavigationLink remains intact.
path = Path("FrameNative/Views/Components.swift")
text = path.read_text(encoding="utf-8")
a = text.find("struct RemotePoster: View {")
b = text.find("struct GlassBadge: View {", a)
if a < 0 or b < a:
    raise SystemExit("V10 poster boundaries missing")
poster = r'''// V10_OPTIMIZED_POSTERS: downsampled bitmap cache, canceled cell assignments,
// no per-poster appearance animation and no full-resolution decode on main.
struct RemotePoster: View {
    @Environment(\.displayScale) private var displayScale
    let item: MediaItem
    var backdrop = false
    var cornerRadius: CGFloat = 18

    @State private var renderedImage: UIImage?
    @State private var imageFailed = false

    var body: some View {
        GeometryReader { proxy in
            let pixelWidth = max(120, Int((proxy.size.width * displayScale).rounded(.up)))
            let pixelHeight = max(120, Int((proxy.size.height * displayScale).rounded(.up)))
            let url = item.imageURL(backdrop: backdrop, width: pixelWidth)

            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.055))

                if let renderedImage {
                    Image(uiImage: renderedImage)
                        .resizable()
                        .scaledToFill()
                } else {
                    placeholder
                    if url != nil && !imageFailed {
                        ProgressView().tint(.white.opacity(0.72))
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
            // Each SwiftUI cell cancels state updates when recycled; shared
            // in-flight fetch remains reusable by the next cell.
            .task(id: url) {
                renderedImage = nil
                imageFailed = false
                guard let url else { return }
                let image = await XSArtworkPipeline.shared.image(
                    for: url, maxDimension: max(pixelWidth, pixelHeight)
                )
                guard !Task.isCancelled else { return }
                renderedImage = image
                imageFailed = image == nil
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.11), Color.purple.opacity(0.05),
                         Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.kind.symbol)
                .font(.system(size: backdrop ? 54 : 38, weight: .thin))
                .foregroundStyle(.white.opacity(0.24))
        }
    }
}

'''
text = text[:a] + poster + text[b:]
path.write_text(text, encoding="utf-8")

# Metadata cache preserves original HTTP code handling, decoding, and safety
# gates (including V36 adult content checks); only coalesces the transport.
path = Path("FrameNative/Services/TMDBClient.swift")
text = path.read_text(encoding="utf-8")
needle = "        let (data, response) = try await URLSession.shared.data(for: request)"
text = replace_one(text, needle,
    "        let (data, response) = try await XSMetadataRequestCache.shared.fetch(request)",
    "metadata transport")
path.write_text(text, encoding="utf-8")

# Home was all-or-nothing: one failed popular TV request could blank Movies too.
# Also show last successful home snapshot instantly after a cold start or when
# a user opens the app without coverage, then safely refresh old data.
path = Path("FrameNative/Core/AppState.swift")
text = path.read_text(encoding="utf-8")
init_old = '''    init() {
        language = UserDefaults.standard.string(forKey: Keys.language) ?? "en-US"
    }
'''
init_new = '''    private struct HomeSnapshot: Codable {
        let date: Date
        let trendingMovies: [MediaItem]
        let trendingTV: [MediaItem]
        let popularMovies: [MediaItem]
        let popularTV: [MediaItem]
    }

    private var homeLastUpdated: Date = .distantPast

    private static var homeSnapshotURL: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("xstv-v10-home-snapshot.json")
    }

    init() {
        language = UserDefaults.standard.string(forKey: Keys.language) ?? "en-US"
        if let url = Self.homeSnapshotURL,
           let bytes = try? Data(contentsOf: url),
           let snapshot = try? JSONDecoder().decode(HomeSnapshot.self, from: bytes),
           Date().timeIntervalSince(snapshot.date) < 7 * 24 * 3600 {
            trendingMovies = snapshot.trendingMovies
            trendingTV = snapshot.trendingTV
            popularMovies = snapshot.popularMovies
            popularTV = snapshot.popularTV
            homeLastUpdated = snapshot.date
            didLoad = !(trendingMovies.isEmpty && trendingTV.isEmpty &&
                        popularMovies.isEmpty && popularTV.isEmpty)
        }
    }

    private func saveHomeSnapshot() {
        guard let url = Self.homeSnapshotURL else { return }
        let snapshot = HomeSnapshot(
            date: Date(),
            trendingMovies: trendingMovies,
            trendingTV: trendingTV,
            popularMovies: popularMovies,
            popularTV: popularTV
        )
        homeLastUpdated = snapshot.date
        // Disk persistence is infrequent and doesn't run when the user
        // scrolls or interacts with playback controls.
        if let bytes = try? JSONEncoder().encode(snapshot) {
            try? bytes.write(to: url, options: .atomic)
        }
    }
'''
text = replace_one(text, init_old, init_new, "home snapshot init")
a = text.find("    func loadHome(force: Bool = false) async {")
b = text.find("    func list(for kind: MediaKind)", a)
if a < 0 or b < a:
    raise SystemExit("V10 AppState.loadHome boundaries missing")
load = '''    // V10_PARTIAL_HOME_RECOVERY: each rail may succeed independently;
    // keep previous images and progress visible while refreshing.
    func loadHome(force: Bool = false) async {
        guard !isLoading else { return }
        if didLoad && !force &&
            Date().timeIntervalSince(homeLastUpdated) < 5 * 60 { return }

        isLoading = true
        errorMessage = nil
        // Separate async tasks avoid the original tuple's all-or-nothing
        // failure: one temporary 403 or network timeout can't hide all rails.
        async let movies = client.trendingMovies()
        async let series = client.trendingTV()
        async let popularMovieItems = client.popularMovies()
        async let popularSeriesItems = client.popularTV()
        let m = try? await movies
        let s = try? await series
        let pm = try? await popularMovieItems
        let ps = try? await popularSeriesItems

        var successfulRails = 0
        if let m { trendingMovies = m; successfulRails += 1 }
        if let s { trendingTV = s; successfulRails += 1 }
        if let pm { popularMovies = pm; successfulRails += 1 }
        if let ps { popularTV = ps; successfulRails += 1 }

        // Anime stays hidden, as required by the protected V37 boundary.
        anime = []
        if successfulRails > 0 {
            didLoad = true
            saveHomeSnapshot()
        } else if !didLoad {
            errorMessage = "تعذّر تحميل المحتوى الآن. تحقق من اتصال الإنترنت."
        }
        isLoading = false
    }

'''
text = text[:a] + load + text[b:]
path.write_text(text, encoding="utf-8")

print("V10: cached/downsampled posters, coalesced TMDB, partial home success and cold-start snapshot installed.")

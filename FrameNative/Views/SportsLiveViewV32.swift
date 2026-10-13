import SwiftUI
import AVKit
import AVFoundation

private let xsSportsV32Accent = Color(red: 1.0, green: 0.12, blue: 0.38)

struct XSSportsLiveViewV32: View {
    @StateObject private var store = IPTVSportsStore()
    @State private var query = ""
    @State private var selectedCategoryID: String?
    @State private var selectedStream: IPTVLiveStream?
    @AppStorage("xs.iptv.favoriteStreamIDs") private var favoriteIDsRaw = ""

    private var favoriteIDs: Set<Int> {
        Set(favoriteIDsRaw.split(separator: ",").compactMap { Int($0) })
    }

    private var filteredStreams: [IPTVLiveStream] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.streams.filter { stream in
            let categoryMatch = selectedCategoryID == nil || stream.categoryID == selectedCategoryID
            let queryMatch = text.isEmpty || stream.name.localizedCaseInsensitiveContains(text)
            return categoryMatch && queryMatch
        }
    }

    private var featured: IPTVLiveStream? {
        let favorites = filteredStreams.filter { favoriteIDs.contains($0.streamID) }
        return favorites.first ?? filteredStreams.first
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if store.credentials == nil {
                unavailableState
            } else if store.isLoading && store.streams.isEmpty {
                loadingState
            } else {
                content
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black.opacity(0.97), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 7) {
                    Circle().fill(Color.red).frame(width: 7, height: 7)
                    Text("SPORTS LIVE")
                        .font(.system(size: 15, weight: .black, design: .rounded))
                        .tracking(0.6)
                }
            }
        }
        .task {
            guard store.credentials != nil, store.streams.isEmpty, !store.isLoading else { return }
            try? await store.refresh()
        }
        .fullScreenCover(item: $selectedStream) { stream in
            XSSportsPlayerV32(
                stream: stream,
                urls: playbackURLs(for: stream),
                logoURL: resolvedLogoURL(for: stream)
            )
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 22) {
                header
                categoryStrip

                if let error = store.errorMessage {
                    errorCard(error)
                }

                if let featured {
                    featuredCard(featured)
                }

                sectionHeader
                channelGrid
            }
            .padding(.bottom, 34)
        }
        .scrollDismissesKeyboard(.interactively)
        .scrollIndicators(.hidden)
        .refreshable { try? await store.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Live Sports")
                    .font(.system(size: 29, weight: .black, design: .rounded))
                Text("Fast access to your live sports channels")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.56))
            }

            HStack(spacing: 10) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white.opacity(0.44))
                    TextField("Search sports channels…", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13))
                .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))

                Button {
                    Task { try? await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 46, height: 46)
                        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.10)))
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    private var categoryStrip: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 8) {
                categoryChip(title: "All Sports", id: nil, count: store.streams.count)
                ForEach(store.categories) { category in
                    let count = store.streams.lazy.filter { $0.categoryID == category.categoryID }.count
                    categoryChip(title: category.categoryName, id: category.categoryID, count: count)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }

    private func categoryChip(title: String, id: String?, count: Int) -> some View {
        let selected = selectedCategoryID == id
        return Button {
            withAnimation(.easeOut(duration: 0.15)) { selectedCategoryID = id }
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .black.opacity(0.62) : .white.opacity(0.48))
            }
            .foregroundStyle(selected ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(selected ? Color.white : Color.white.opacity(0.055), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(selected ? 0 : 0.10)))
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private func featuredCard(_ stream: IPTVLiveStream) -> some View {
        Button {
            selectedStream = stream
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        LinearGradient(
                            colors: [Color(red: 0.10, green: 0.12, blue: 0.17), Color.black],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )

                XSSportsChannelArtwork(name: stream.name, logoURL: resolvedLogoURL(for: stream), compact: false)
                    .padding(.horizontal, 90)
                    .padding(.vertical, 28)
                    .opacity(0.76)

                LinearGradient(colors: [.clear, .black.opacity(0.94)], startPoint: .top, endPoint: .bottom)

                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 8) {
                        Label("LIVE", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(Color.red.opacity(0.92), in: Capsule())

                        if let category = categoryName(for: stream.categoryID) {
                            Text(category)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.64))
                                .lineLimit(1)
                        }
                    }

                    Text(stream.name)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Label("Watch Live", systemImage: "play.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.black)
                        .padding(.horizontal, 15)
                        .frame(height: 39)
                        .background(Color.white, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(18)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.10)))
            .padding(.horizontal, 18)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    private var sectionHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text(selectedCategoryID.flatMap(categoryName(for:)) ?? "Sports Channels")
                    .font(.title3.bold())
                Text("\(filteredStreams.count) live channels")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.50))
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }

    private var channelGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 148, maximum: 220), spacing: 12)], spacing: 16) {
            ForEach(filteredStreams) { stream in
                XSSportsChannelCardV32(
                    stream: stream,
                    category: categoryName(for: stream.categoryID),
                    logoURL: resolvedLogoURL(for: stream),
                    isFavorite: favoriteIDs.contains(stream.streamID),
                    toggleFavorite: { toggleFavorite(stream.streamID) },
                    play: { selectedStream = stream }
                )
            }
        }
        .padding(.horizontal, 18)
    }

    private var loadingState: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
                .tint(xsSportsV32Accent)
            Text("Loading live sports…")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white.opacity(0.66))
        }
    }

    private var unavailableState: some View {
        VStack(spacing: 14) {
            Image(systemName: "sportscourt")
                .font(.system(size: 40, weight: .semibold))
                .foregroundStyle(xsSportsV32Accent)
            Text("Sports IPTV isn’t configured")
                .font(.title3.bold())
            Text("Rebuild XS TV with the IPTV build secrets enabled.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .padding(24)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(message)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.78))
            Spacer()
            Button("Retry") { Task { try? await store.refresh() } }
                .font(.caption.bold())
        }
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.10)))
        .padding(.horizontal, 18)
    }

    private func categoryName(for id: String) -> String? {
        store.categories.first(where: { $0.categoryID == id })?.categoryName
    }

    private func toggleFavorite(_ id: Int) {
        var ids = favoriteIDs
        if ids.contains(id) { ids.remove(id) } else { ids.insert(id) }
        favoriteIDsRaw = ids.sorted().map(String.init).joined(separator: ",")
    }

    private func resolvedLogoURL(for stream: IPTVLiveStream) -> URL? {
        guard var raw = stream.streamIcon?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        raw = raw.replacingOccurrences(of: " ", with: "%20")
        if raw.hasPrefix("//") {
            return URL(string: "http:" + raw)
        }
        if let url = URL(string: raw), url.scheme != nil {
            return url
        }
        guard let base = store.credentials?.normalizedHost else { return nil }
        let path = raw.hasPrefix("/") ? raw : "/" + raw
        return URL(string: base + path)
    }

    private func playbackURLs(for stream: IPTVLiveStream) -> [URL] {
        guard let credentials = store.credentials else { return [] }
        let user = credentials.username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.username
        let pass = credentials.password.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? credentials.password
        var extensions = ["m3u8"]
        if let providerExt = stream.containerExtension?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
           !providerExt.isEmpty, !extensions.contains(providerExt) {
            extensions.append(providerExt)
        }
        if !extensions.contains("ts") { extensions.append("ts") }

        var seen = Set<String>()
        return extensions.compactMap { ext in
            let raw = "\(credentials.normalizedHost)/live/\(user)/\(pass)/\(stream.streamID).\(ext)"
            guard seen.insert(raw).inserted else { return nil }
            return URL(string: raw)
        }
    }
}

private struct XSSportsChannelCardV32: View {
    let stream: IPTVLiveStream
    let category: String?
    let logoURL: URL?
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let play: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack {
                Button(action: play) {
                    XSSportsChannelArtwork(name: stream.name, logoURL: logoURL, compact: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)

                VStack {
                    HStack {
                        Text("LIVE")
                            .font(.system(size: 9, weight: .black, design: .monospaced))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.92), in: Capsule())

                        Spacer()

                        Button(action: toggleFavorite) {
                            Image(systemName: isFavorite ? "star.fill" : "star")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(isFavorite ? .yellow : .white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.64), in: Circle())
                        }
                        .buttonStyle(.plain)
                        .contentShape(Circle())
                    }
                    Spacer()
                }
                .padding(8)
            }
            .aspectRatio(16/10, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 15))
            .overlay(RoundedRectangle(cornerRadius: 15).stroke(.white.opacity(0.10)))

            Button(action: play) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(stream.name)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let category {
                        Text(category)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.48))
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
        }
    }
}

private struct XSSportsChannelArtwork: View {
    let name: String
    let logoURL: URL?
    let compact: Bool

    var body: some View {
        ZStack {
            LinearGradient(
                colors: artworkColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            if let logoURL {
                AsyncImage(url: logoURL, transaction: Transaction(animation: nil)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .padding(compact ? 22 : 12)
                    default:
                        generatedArtwork
                    }
                }
            } else {
                generatedArtwork
            }
        }
    }

    private var generatedArtwork: some View {
        VStack(spacing: compact ? 6 : 9) {
            Image(systemName: brandSymbol)
                .font(.system(size: compact ? 26 : 38, weight: .bold))
                .symbolRenderingMode(.hierarchical)
            Text(brandText)
                .font(.system(size: compact ? 13 : 18, weight: .black, design: .rounded))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.68)
        }
        .foregroundStyle(.white.opacity(0.94))
        .padding(14)
    }

    private var normalizedName: String { name.lowercased() }

    private var brandText: String {
        if normalizedName.contains("bein") { return "beIN SPORTS" }
        if normalizedName.contains("ssc") { return "SSC SPORTS" }
        if normalizedName.contains("espn") { return "ESPN" }
        if normalizedName.contains("dazn") { return "DAZN" }
        if normalizedName.contains("sky") { return "SKY SPORTS" }
        let cleaned = name
            .replacingOccurrences(of: "|", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(cleaned.prefix(compact ? 22 : 34))
    }

    private var brandSymbol: String {
        if normalizedName.contains("football") || normalizedName.contains("soccer") || normalizedName.contains("كرة") { return "soccerball" }
        if normalizedName.contains("tennis") { return "tennisball.fill" }
        if normalizedName.contains("basket") { return "basketball.fill" }
        if normalizedName.contains("formula") || normalizedName.contains("f1") { return "flag.checkered" }
        return "sportscourt.fill"
    }

    private var artworkColors: [Color] {
        if normalizedName.contains("bein") {
            return [Color(red: 0.27, green: 0.04, blue: 0.46), Color(red: 0.52, green: 0.08, blue: 0.63), Color.black]
        }
        if normalizedName.contains("ssc") {
            return [Color(red: 0.02, green: 0.31, blue: 0.20), Color(red: 0.04, green: 0.16, blue: 0.13), Color.black]
        }
        if normalizedName.contains("espn") {
            return [Color(red: 0.55, green: 0.02, blue: 0.04), Color(red: 0.21, green: 0.01, blue: 0.02), Color.black]
        }
        return [Color(red: 0.08, green: 0.10, blue: 0.16), Color(red: 0.05, green: 0.06, blue: 0.10), Color.black]
    }
}

struct XSSportsPlayerV32: View {
    @Environment(\.dismiss) private var dismiss
    let stream: IPTVLiveStream
    let urls: [URL]
    let logoURL: URL?

    @StateObject private var model: XSSportsPlayerModel
    @State private var controlsVisible = true

    init(stream: IPTVLiveStream, urls: [URL], logoURL: URL?) {
        self.stream = stream
        self.urls = urls
        self.logoURL = logoURL
        _model = StateObject(wrappedValue: XSSportsPlayerModel(urls: urls))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            XSAVPlayerController(player: model.player)
                .ignoresSafeArea()

            if model.statusText != "Live" {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                    Text(model.statusText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 15)
                .background(.black.opacity(0.60), in: Capsule())
            }

            VStack {
                HStack(spacing: 10) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 42, height: 42)
                            .background(.black.opacity(0.62), in: Circle())
                            .overlay(Circle().stroke(.white.opacity(0.16)))
                    }
                    .buttonStyle(.plain)
                    .contentShape(Circle())

                    XSSportsChannelArtwork(name: stream.name, logoURL: logoURL, compact: true)
                        .frame(width: 52, height: 34)
                        .clipShape(RoundedRectangle(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(stream.name)
                            .font(.subheadline.bold())
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(Color.red).frame(width: 6, height: 6)
                            Text("LIVE")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(.white.opacity(0.70))
                    }

                    Spacer()

                    if urls.count > 1 {
                        Menu {
                            ForEach(Array(urls.enumerated()), id: \.offset) { index, url in
                                Button {
                                    model.play(index: index)
                                } label: {
                                    Label(
                                        index == model.currentIndex ? "Source \(index + 1) · Active" : "Source \(index + 1) · \(url.pathExtension.uppercased())",
                                        systemImage: index == model.currentIndex ? "checkmark.circle.fill" : "play.circle"
                                    )
                                }
                            }
                        } label: {
                            Image(systemName: "antenna.radiowaves.left.and.right")
                                .font(.system(size: 15, weight: .bold))
                                .frame(width: 42, height: 42)
                                .background(.black.opacity(0.62), in: Circle())
                                .overlay(Circle().stroke(.white.opacity(0.16)))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .onAppear { model.start() }
        .onDisappear { model.stop() }
    }
}

@MainActor
private final class XSSportsPlayerModel: ObservableObject {
    let player = AVPlayer()
    let urls: [URL]

    @Published var statusText = "Connecting…"
    @Published var currentIndex = 0

    private var itemObservation: NSKeyValueObservation?
    private var timeObservation: NSKeyValueObservation?
    private var fallbackTask: Task<Void, Never>?
    private var generation = 0

    init(urls: [URL]) {
        self.urls = urls
        player.automaticallyWaitsToMinimizeStalling = true
    }

    func start() {
        guard !urls.isEmpty else {
            statusText = "No playable stream URL"
            return
        }
        play(index: 0)
    }

    func play(index: Int) {
        guard urls.indices.contains(index) else { return }
        generation += 1
        let myGeneration = generation
        currentIndex = index
        statusText = index == 0 ? "Connecting…" : "Trying backup source…"
        fallbackTask?.cancel()
        itemObservation?.invalidate()
        timeObservation?.invalidate()

        let asset = AVURLAsset(url: urls[index])
        let item = AVPlayerItem(asset: asset)
        item.preferredForwardBufferDuration = 3
        player.replaceCurrentItem(with: item)

        itemObservation = item.observe(\.status, options: [.initial, .new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, myGeneration == self.generation else { return }
                switch item.status {
                case .readyToPlay:
                    self.statusText = "Live"
                    self.verifyVideoTrack(asset: asset, generation: myGeneration)
                case .failed:
                    self.tryNextSource()
                default:
                    break
                }
            }
        }

        timeObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, myGeneration == self.generation else { return }
                switch player.timeControlStatus {
                case .playing:
                    self.statusText = "Live"
                case .waitingToPlayAtSpecifiedRate:
                    if self.statusText == "Live" { self.statusText = "Buffering…" }
                case .paused:
                    break
                @unknown default:
                    break
                }
            }
        }

        player.play()

        fallbackTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, myGeneration == self.generation else { return }
                if self.player.timeControlStatus != .playing {
                    self.tryNextSource()
                }
            }
        }
    }

    private func verifyVideoTrack(asset: AVURLAsset, generation myGeneration: Int) {
        Task { [weak self] in
            do {
                let videoTracks = try await asset.loadTracks(withMediaType: .video)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let self, myGeneration == self.generation else { return }
                    if videoTracks.isEmpty {
                        self.tryNextSource()
                    } else {
                        self.statusText = "Live"
                    }
                }
            } catch {
                // Some live HLS providers do not expose tracks until later; keep playback running.
            }
        }
    }

    private func tryNextSource() {
        let next = currentIndex + 1
        if urls.indices.contains(next) {
            play(index: next)
        } else {
            statusText = "Video format unavailable"
        }
    }

    func stop() {
        generation += 1
        fallbackTask?.cancel()
        itemObservation?.invalidate()
        timeObservation?.invalidate()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }
}

private struct XSAVPlayerController: UIViewControllerRepresentable {
    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.showsPlaybackControls = true
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.videoGravity = .resizeAspect
        controller.view.backgroundColor = .black
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        if controller.player !== player {
            controller.player = player
        }
    }
}

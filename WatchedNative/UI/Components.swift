import SwiftUI
import UIKit

enum WatchedTheme {
    static let background = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
    static let surface = Color(red: 19 / 255, green: 19 / 255, blue: 19 / 255)
    static let accent = Color(red: 255 / 255, green: 74 / 255, blue: 85 / 255)
    static let red = Color(red: 229 / 255, green: 9 / 255, blue: 20 / 255)
}

actor ImageRepository {
    static let shared = ImageRepository()
    private let cache = NSCache<NSString, UIImage>()
    private let bundled: [String: String]
    init() {
        if let path = Bundle.main.url(forResource: "image-map", withExtension: "json"),
           let data = try? Data(contentsOf: path), let map = try? JSONDecoder().decode([String: String].self, from: data) { bundled = map }
        else { bundled = [:] }
        cache.totalCostLimit = 32_000_000
    }
    func image(_ url: URL) async throws -> UIImage {
        let key = url.absoluteString as NSString
        if let value = cache.object(forKey: key) { return value }
        if let name = bundled[url.lastPathComponent], let path = Bundle.main.url(forResource: name, withExtension: nil),
           let image = UIImage(contentsOfFile: path.path) {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4); return image
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let image = UIImage(data: data) else { throw WatchedError.malformed }
        cache.setObject(image, forKey: key, cost: Int(image.size.width * image.size.height) * 4)
        return image
    }
}

struct RemoteImage: View {
    var url: URL?
    var contentMode: ContentMode = .fill
    @State private var image: UIImage?
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.white.opacity(0.045)
                if let image { Image(uiImage: image).resizable().aspectRatio(contentMode: contentMode) }
                else { Image(systemName: "film").font(.title).foregroundStyle(.white.opacity(0.12)) }
            }
            .frame(width: proxy.size.width, height: proxy.size.height).clipped()
        }
        .task(id: url) {
            image = nil
            if let url {
                let loaded = try? await ImageRepository.shared.image(url)
                guard !Task.isCancelled else { return }
                image = loaded
            }
        }
    }
}

struct Wordmark: View {
    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "play.rectangle.fill").font(.system(size: 21)).foregroundStyle(WatchedTheme.accent)
            Text("watched").font(.system(size: 26, weight: .bold, design: .rounded)).tracking(-1.4)
        }.environment(\.layoutDirection, .leftToRight).accessibilityElement(children: .combine)
    }
}

struct PosterCard: View {
    let item: MediaTitle
    var width: CGFloat = 130
    var rank: Int? = nil
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack(alignment: .bottomLeading) {
                RemoteImage(url: item.posterURL).frame(width: width, height: width * 1.5)
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                HStack(spacing: 4) {
                    if let rank { Text(String(format: "%02d", rank)).font(.system(size: 24, weight: .black, design: .rounded)).foregroundStyle(.white.opacity(0.9)) }
                    Spacer(minLength: 0)
                    if item.rating > 0 {
                        Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow)
                        Text(item.rating, format: .number.precision(.fractionLength(1))).font(.system(size: 11, weight: .semibold))
                    }
                }.padding(9).environment(\.layoutDirection, .leftToRight)
            }
            .frame(width: width, height: width * 1.5)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.08), lineWidth: 0.5))
            Text(item.name).font(.system(size: 12, weight: .semibold)).lineLimit(1).foregroundStyle(.white)
                .environment(\.layoutDirection, .leftToRight).frame(maxWidth: .infinity, alignment: .leading)
            Text(item.year).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.name), \(item.year)")
        .contextMenu {
            Button { store.toggleSaved(item) } label: {
                Label(store.isSaved(item) ? store.t("إزالة من قائمتي", "Remove from My List") : store.t("إضافة إلى قائمتي", "Add to My List"),
                      systemImage: store.isSaved(item) ? "bookmark.slash" : "bookmark")
            }
        }
    }
}

struct TitleRail: View {
    let rail: MediaRail
    @EnvironmentObject private var store: AppStore
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(localizedTitle).font(.system(size: 20, weight: .bold))
                Spacer()
                Text("\(rail.items.count)").font(.system(size: 12, weight: .medium)).foregroundStyle(.white.opacity(0.35))
            }.padding(.horizontal, 20)
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(Array(rail.items.enumerated()), id: \.element.id) { index, item in
                        NavigationLink(value: item) { PosterCard(item: item, rank: rail.title.lowercased().contains("top") ? index + 1 : nil) }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 20)
            }.scrollIndicators(.hidden)
        }
    }
    private var localizedTitle: String {
        guard store.language == "ar" else { return rail.title }
        return ["Top rated": "الأعلى تقييماً", "Top shows of the week": "مسلسلات الأسبوع", "Top movies of the week": "أفلام الأسبوع",
                "Top rated shows": "مسلسلات تستاهل المشاهدة", "On Disney+": "على Disney+", "Staff Picks": "اختياراتنا"][rail.title] ?? rail.title
    }
}

struct StatusPill: View {
    let text: String
    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "wifi.exclamationmark").foregroundStyle(WatchedTheme.accent)
            Text(text).font(.system(size: 11, weight: .medium))
            Spacer(minLength: 0)
        }.foregroundStyle(.white.opacity(0.65)).padding(.horizontal, 16).padding(.vertical, 11)
            .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyMessage: View {
    let symbol: String
    let title: String
    let message: String
    var body: some View {
        VStack(spacing: 13) {
            Image(systemName: symbol).font(.system(size: 38, weight: .light)).foregroundStyle(WatchedTheme.accent)
            Text(title).font(.title3.bold())
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }.padding(30).frame(maxWidth: .infinity, minHeight: 280)
    }
}

struct PrimaryAction: ButtonStyle {
    var bodyColor: Color = .white
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(size: 15, weight: .bold)).frame(maxWidth: .infinity).padding(.vertical, 15)
            .background(bodyColor, in: RoundedRectangle(cornerRadius: 13))
            .foregroundStyle(bodyColor == .white ? Color.black : Color.white)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

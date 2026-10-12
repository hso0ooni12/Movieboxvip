import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
}

struct RemotePoster: View {
    let item: MediaItem
    var backdrop = false
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                if let url = item.imageURL(backdrop: backdrop, width: backdrop ? 1280 : 500) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        case .empty:
                            ZStack {
                                placeholder
                                ProgressView().tint(.white.opacity(0.8))
                            }
                        @unknown default:
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [Color.white.opacity(0.12), Color.white.opacity(0.025)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: item.kind.symbol)
                .font(.system(size: backdrop ? 60 : 42, weight: .thin))
                .foregroundStyle(.white.opacity(0.28))
        }
    }
}

struct MediaCard: View {
    let item: MediaItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RemotePoster(item: item)
                .frame(width: 148, height: 220)
                .overlay(alignment: .topTrailing) {
                    if item.voteAverage > 0 {
                        Text("★ \(item.ratingText)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(8)
                    }
                }
            Text(item.title)
                .font(.subheadline.bold())
                .lineLimit(1)
                .foregroundStyle(.white)
            Text(item.year)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 148, alignment: .leading)
    }
}

struct MediaRail: View {
    let title: String
    let items: [MediaItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text(title)
                    .font(.title3.bold())
                    .padding(.horizontal, 16)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink(value: item) { MediaCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ContinueWatchingCard: View {
    let progress: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottom) {
                RemotePoster(item: progress.item, backdrop: true, cornerRadius: 14)
                    .frame(width: 245, height: 138)
                GeometryReader { proxy in
                    VStack {
                        Spacer()
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.18)).frame(height: 3)
                            Rectangle().fill(.white).frame(width: proxy.size.width * progress.fraction, height: 3)
                        }
                    }
                }
                .frame(width: 245, height: 138)
                Image(systemName: "play.fill")
                    .font(.headline)
                    .frame(width: 46, height: 46)
                    .background(.black.opacity(0.68), in: Circle())
                    .foregroundStyle(.white)
            }
            Text(progress.item.title)
                .font(.subheadline.bold())
                .lineLimit(1)
            Text(progress.episodeLabel ?? "Resume")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 245, alignment: .leading)
    }
}

struct HeroView: View {
    let item: MediaItem

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, backdrop: true, cornerRadius: 28)
                    .frame(height: 455)
                LinearGradient(colors: [.clear, .black.opacity(0.98)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                VStack(alignment: .leading, spacing: 10) {
                    Text("FEATURED")
                        .font(.caption.bold())
                        .tracking(2)
                        .foregroundStyle(.cyan)
                    Text(item.title)
                        .font(.system(size: 36, weight: .black, design: .rounded))
                        .lineLimit(2)
                    Text("\(item.year)  •  ★ \(item.ratingText)  •  \(item.subtitle)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(2)
                    HStack(spacing: 12) {
                        Label("Play", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                        Label("Details", systemImage: "info.circle")
                            .font(.headline)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(22)
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle().fill(.white.opacity(0.06)).frame(width: 86, height: 86)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(title).font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 34)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 56)
    }
}

struct RemotePoster: View {
    let item: MediaItem
    var backdrop = false
    var cornerRadius: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous).fill(Color.white.opacity(0.055))
                if let url = item.imageURL(backdrop: backdrop, width: backdrop ? 1280 : 500) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.22))) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        case .failure: placeholder
                        case .empty:
                            ZStack { placeholder; ProgressView().tint(.white.opacity(0.8)) }
                        @unknown default: placeholder
                        }
                    }
                } else { placeholder }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Image(systemName: item.kind.symbol)
                .font(.system(size: backdrop ? 54 : 38, weight: .thin))
                .foregroundStyle(.white.opacity(0.24))
        }
    }
}

struct GlassBadge: View {
    let text: String
    var systemImage: String? = nil
    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage).font(.caption2.weight(.bold)) }
            Text(text).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.08), lineWidth: 1))
    }
}

struct MediaCard: View {
    let item: MediaItem
    var width: CGFloat = 148
    private var height: CGFloat { width * 1.49 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            RemotePoster(item: item, cornerRadius: 15)
                .frame(width: width, height: height)
                .overlay(alignment: .topTrailing) {
                    if item.voteAverage > 0 { GlassBadge(text: item.ratingText, systemImage: "star.fill").padding(7) }
                }
                .overlay { RoundedRectangle(cornerRadius: 15, style: .continuous).stroke(.white.opacity(0.08), lineWidth: 1) }
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(1).foregroundStyle(.white)
            HStack(spacing: 6) { Text(item.year); Text("•"); Text(item.kind.title) }
                .font(.caption2.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
        .contentShape(Rectangle())
    }
}

struct SectionHeader: View {
    let title: String
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.bold())
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
    }
}

struct MediaRail: View {
    let title: String
    let items: [MediaItem]
    var subtitle: String? = nil
    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 13) {
                SectionHeader(title: title, subtitle: subtitle)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 13) {
                        ForEach(items) { item in
                            NavigationLink(value: item) { MediaCard(item: item) }.buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ContinueWatchingCard: View {
    let progress: WatchProgress
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                RemotePoster(item: progress.item, backdrop: true, cornerRadius: 16).frame(width: 258, height: 145)
                LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .center, endPoint: .bottom)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                VStack(spacing: 0) {
                    Spacer()
                    HStack {
                        ZStack {
                            Circle().fill(.white)
                            Image(systemName: "play.fill").font(.caption.bold()).foregroundStyle(.black).offset(x: 1)
                        }
                        .frame(width: 34, height: 34)
                        Spacer()
                        Text(progress.episodeLabel ?? "Resume").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.9))
                    }
                    .padding(12)
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.2))
                            Rectangle().fill(.white).frame(width: proxy.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 3)
                }
            }
            Text(progress.item.title).font(.subheadline.bold()).lineLimit(1)
            Text(progress.episodeLabel ?? "Continue watching").font(.caption).foregroundStyle(.secondary)
        }
        .frame(width: 258, alignment: .leading)
    }
}

struct HeroView: View {
    let item: MediaItem
    @State private var animate = false

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                    .frame(height: 500)
                    .scaleEffect(animate ? 1.0 : 1.045)
                    .offset(y: animate ? 0 : -4)

                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.18), .black.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [.cyan.opacity(animate ? 0.10 : 0.02), .clear],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .blendMode(.screen)

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        GlassBadge(text: "FEATURED")
                        GlassBadge(text: item.year)
                        if item.voteAverage > 0 { GlassBadge(text: item.ratingText, systemImage: "star.fill") }
                    }

                    Text(item.title)
                        .font(.system(size: 39, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.78)

                    if !item.overview.isEmpty {
                        Text(item.overview)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.78))
                            .lineLimit(3)
                            .lineSpacing(2)
                    }

                    HStack(spacing: 10) {
                        Label("Watch Now", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 19)
                            .padding(.vertical, 12)
                            .background(.white, in: Capsule())
                            .foregroundStyle(.black)
                        Label("Details", systemImage: "info.circle")
                            .font(.headline)
                            .padding(.horizontal, 17)
                            .padding(.vertical, 12)
                            .background(.ultraThinMaterial, in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
                .offset(y: animate ? 0 : 18)
                .opacity(animate ? 1 : 0)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 0.85)) { animate = true }
        }
        .onDisappear { animate = false }
    }
}

struct PremiumLoadingView: View {
    let message: String
    var body: some View {
        VStack(spacing: 16) {
            ProgressView().scaleEffect(1.15).tint(.white)
            Text(message).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
    }
}

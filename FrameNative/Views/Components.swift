import SwiftUI
import Combine

struct XSBackground: View {
    var body: some View {
        ZStack {
            Color.black
            RadialGradient(
                colors: [Color.purple.opacity(0.16), Color.clear],
                center: .topTrailing,
                startRadius: 10,
                endRadius: 430
            )
            RadialGradient(
                colors: [Color.orange.opacity(0.055), Color.clear],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 360
            )
        }
        .ignoresSafeArea()
    }
}

struct EmptyStateView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                Circle()
                    .fill(.ultraThinMaterial)
                    .frame(width: 92, height: 92)
                Circle()
                    .stroke(
                        LinearGradient(colors: [.purple.opacity(0.6), .pink.opacity(0.45), .orange.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing),
                        lineWidth: 1
                    )
                    .frame(width: 92, height: 92)
                Image(systemName: systemImage)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.88))
            }
            Text(title)
                .font(.title2.bold())
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
    var cornerRadius: CGFloat = 18

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.white.opacity(0.055))

                if let url = item.imageURL(backdrop: backdrop, width: backdrop ? 1280 : 500) {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.28))) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            placeholder
                        case .empty:
                            ZStack {
                                placeholder
                                ProgressView().tint(.white.opacity(0.76))
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
                colors: [Color.white.opacity(0.11), Color.purple.opacity(0.05), Color.white.opacity(0.02)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
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
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.12), lineWidth: 1))
    }
}

struct MediaCard: View {
    let item: MediaItem
    var width: CGFloat = 152
    private var height: CGFloat { width * 1.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, cornerRadius: 17)
                    .frame(width: width, height: height)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.58)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))

                if item.voteAverage > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(.yellow)
                        Text(item.ratingText)
                    }
                    .font(.caption2.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.black.opacity(0.62), in: Capsule())
                    .padding(9)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(.white.opacity(0.09), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.32), radius: 13, y: 7)

            Text(item.title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .foregroundStyle(.white)

            HStack(spacing: 6) {
                Text(item.year)
                Text("•")
                Text(item.kind == .tv ? "Series" : item.kind.title)
            }
            .font(.caption2.weight(.medium))
            .foregroundStyle(.secondary)
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
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title3.bold())
                if let subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
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
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: title, subtitle: subtitle)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 14) {
                        ForEach(items) { item in
                            NavigationLink(value: item) {
                                MediaCard(item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

struct ContinueWatchingCard: View {
    let progress: WatchProgress

    private var remainingText: String? {
        guard progress.duration > progress.currentTime, progress.duration > 0 else { return nil }
        let minutes = Int((progress.duration - progress.currentTime) / 60)
        guard minutes > 0 else { return "Almost finished" }
        return "\(minutes)m left"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottom) {
                RemotePoster(item: progress.item, backdrop: true, cornerRadius: 18)
                    .frame(width: 278, height: 158)

                LinearGradient(
                    colors: [.clear, .black.opacity(0.88)],
                    startPoint: .center,
                    endPoint: .bottom
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                VStack(spacing: 0) {
                    Spacer()
                    HStack(alignment: .bottom) {
                        ZStack {
                            Circle().fill(.white)
                            Image(systemName: "play.fill")
                                .font(.caption.bold())
                                .foregroundStyle(.black)
                                .offset(x: 1)
                        }
                        .frame(width: 38, height: 38)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(progress.episodeLabel ?? "Resume")
                                .font(.caption.bold())
                            if let remainingText {
                                Text(remainingText)
                                    .font(.caption2)
                                    .foregroundStyle(.white.opacity(0.68))
                            }
                        }
                        Spacer()
                    }
                    .padding(12)

                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(.white.opacity(0.18))
                            LinearGradient(
                                colors: [.purple, .pink, .orange],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            .frame(width: proxy.size.width * progress.fraction)
                        }
                    }
                    .frame(height: 4)
                }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            )

            Text(progress.item.title)
                .font(.subheadline.bold())
                .lineLimit(1)

            Text("Continue watching")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: 278, alignment: .leading)
    }
}

struct HeroCarousel: View {
    let items: [MediaItem]
    @State private var currentIndex = 0
    private let timer = Timer.publish(every: 7, on: .main, in: .common).autoconnect()

    var body: some View {
        if !items.isEmpty {
            VStack(spacing: 10) {
                TabView(selection: $currentIndex) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HeroSlide(item: item)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 520)
                .onReceive(timer) { _ in
                    guard items.count > 1 else { return }
                    withAnimation(.easeInOut(duration: 0.5)) {
                        currentIndex = (currentIndex + 1) % items.count
                    }
                }

                HStack(spacing: 6) {
                    ForEach(items.indices, id: \.self) { index in
                        Capsule()
                            .fill(index == currentIndex ? Color.white : Color.white.opacity(0.24))
                            .frame(width: index == currentIndex ? 24 : 7, height: 5)
                            .animation(.easeInOut(duration: 0.25), value: currentIndex)
                    }
                }
            }
        }
    }
}

private struct HeroSlide: View {
    let item: MediaItem
    @State private var appeared = false

    var body: some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: item, backdrop: true, cornerRadius: 0)
                    .frame(height: 520)
                    .scaleEffect(appeared ? 1.0 : 1.035)

                LinearGradient(
                    colors: [.black.opacity(0.04), .black.opacity(0.18), .black.opacity(0.98)],
                    startPoint: .top,
                    endPoint: .bottom
                )

                LinearGradient(
                    colors: [.purple.opacity(0.18), .pink.opacity(0.07), .clear],
                    startPoint: .bottomLeading,
                    endPoint: .topTrailing
                )
                .blendMode(.screen)

                VStack(alignment: .leading, spacing: 13) {
                    HStack(spacing: 8) {
                        GlassBadge(text: "XS SPOTLIGHT")
                        GlassBadge(text: item.year)
                        if item.voteAverage > 0 {
                            GlassBadge(text: item.ratingText, systemImage: "star.fill")
                        }
                    }

                    Text(item.title)
                        .font(.system(size: 40, weight: .black, design: .rounded))
                        .lineLimit(2)
                        .minimumScaleFactor(0.74)

                    if !item.subtitle.isEmpty {
                        Text(item.subtitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }

                    if !item.overview.isEmpty {
                        Text(item.overview)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(3)
                            .lineSpacing(2)
                    }

                    HStack(spacing: 10) {
                        Label("Watch", systemImage: "play.fill")
                            .font(.headline)
                            .padding(.horizontal, 20)
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
                .padding(.horizontal, 20)
                .padding(.bottom, 26)
                .offset(y: appeared ? 0 : 14)
                .opacity(appeared ? 1 : 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onAppear {
            withAnimation(.easeOut(duration: 0.72)) { appeared = true }
        }
    }
}

struct TopTenRail: View {
    let items: [MediaItem]

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeader(title: "Top 10 on XS TV", subtitle: "What everyone is watching right now")
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 6) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            NavigationLink(value: item) {
                                TopTenCard(rank: index + 1, item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 4)
                }
                .scrollIndicators(.hidden)
            }
        }
    }
}

private struct TopTenCard: View {
    let rank: Int
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Text("\(rank)")
                .font(.system(size: 126, weight: .black, design: .rounded))
                .foregroundStyle(.black)
                .overlay {
                    Text("\(rank)")
                        .font(.system(size: 126, weight: .black, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.white.opacity(0.9), .white.opacity(0.18)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .mask(Text("\(rank)").font(.system(size: 126, weight: .black, design: .rounded)))
                }
                .frame(width: 88, alignment: .leading)
                .offset(x: -5, y: 5)

            RemotePoster(item: item, cornerRadius: 16)
                .frame(width: 128, height: 192)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(.white.opacity(0.1)))
                .offset(x: 62)
        }
        .frame(width: 196, height: 202, alignment: .bottomLeading)
    }
}

struct PremiumLoadingView: View {
    let message: String
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shimmer = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            RoundedRectangle(cornerRadius: 0)
                .fill(.white.opacity(0.06))
                .frame(height: 410)
                .overlay(shimmerOverlay)

            VStack(alignment: .leading, spacing: 14) {
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.07)).frame(width: 210, height: 22)
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.055)).frame(height: 14)
                RoundedRectangle(cornerRadius: 8).fill(.white.opacity(0.055)).frame(width: 260, height: 14)
                HStack(spacing: 14) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.white.opacity(0.055))
                            .frame(width: 126, height: 186)
                    }
                }
            }
            .padding(.horizontal, 18)
            .overlay(shimmerOverlay)

            HStack(spacing: 10) {
                ProgressView().tint(.white.opacity(0.8))
                Text(message)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 18)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(XSBackground())
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.25).repeatForever(autoreverses: false)) {
                shimmer = true
            }
        }
    }

    private var shimmerOverlay: some View {
        LinearGradient(
            colors: [.clear, .white.opacity(0.09), .clear],
            startPoint: .leading,
            endPoint: .trailing
        )
        .rotationEffect(.degrees(18))
        .offset(x: shimmer ? 430 : -430)
        .allowsHitTesting(false)
    }
}

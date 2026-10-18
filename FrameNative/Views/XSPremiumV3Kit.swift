import SwiftUI

// Premium V3: reusable presentation primitives only.
// This file has no authority over media URLs, credentials, servers, subtitles or playback.

enum XSV3 {
    static let ink = Color(red: 0.025, green: 0.029, blue: 0.049)
    static let lifted = Color(red: 0.098, green: 0.104, blue: 0.143)
    static let coral = Color(red: 1.0, green: 0.29, blue: 0.40)
    static let amber = Color(red: 1.0, green: 0.79, blue: 0.54)
    static let lilac = Color(red: 0.66, green: 0.48, blue: 1.0)
    static let muted = Color.white.opacity(0.63)
}

struct XSV3PressStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.975 : 1.0)
            .opacity(configuration.isPressed ? 0.90 : 1.0)
            .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.78),
                       value: configuration.isPressed)
    }
}

struct XSV3SectionTitle: View {
    let eyebrow: String
    let title: String
    var count: String? = nil

    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.6)
                    .foregroundStyle(XSV3.coral)
                Text(title)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let count {
                Text(count)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.55))
            }
        }
        .padding(.horizontal, 22)
    }
}

struct XSV3WorldCard: View {
    let item: MediaItem
    let title: String
    let eyebrow: String
    let icon: String
    let accent: Color

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(item: item, backdrop: true, cornerRadius: 20)
                .frame(height: 211)
                .clipped()

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.02), location: 0),
                    .init(color: .black.opacity(0.36), location: 0.37),
                    .init(color: .black.opacity(0.94), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Label(eyebrow.uppercased(), systemImage: icon)
                        .font(.system(size: 10, weight: .heavy))
                        .tracking(1.3)
                        .foregroundStyle(accent)
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .bold))
                        .frame(width: 31, height: 31)
                        .background(.white.opacity(0.19), in: Circle())
                        .foregroundStyle(.white)
                }
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .tracking(-0.5)
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .minimumScaleFactor(0.78)
                Text("Explore the collection")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(15)
        }
        .frame(height: 211)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.16)))
    }
}

struct XSV3RankingCard: View {
    let item: MediaItem
    let index: Int

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            RemotePoster(item: item, cornerRadius: 18)
                .frame(width: 150, height: 215)
                .clipped()
                .padding(.leading, 25)

            LinearGradient(colors: [.clear, .black.opacity(0.64)],
                           startPoint: .center, endPoint: .bottom)
                .frame(width: 150, height: 215)
                .padding(.leading, 25)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            Text(String(index))
                .font(.system(size: 94, weight: .black, design: .rounded))
                .tracking(-11)
                .foregroundStyle(XSV3.ink)
                .shadow(color: .white.opacity(0.74), radius: 1.5)
                .offset(x: 0, y: 12)
                .accessibilityHidden(true)
        }
        .frame(width: 175, height: 223)
        .overlay(alignment: .bottomTrailing) {
            Text(item.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.75), in: Capsule())
                .padding(.trailing, 7)
                .padding(.bottom, 4)
        }
    }
}

struct XSV3ProgressCard: View {
    let entry: WatchProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .bottomLeading) {
                RemotePoster(item: entry.item, backdrop: true, cornerRadius: 18)
                    .frame(width: 260, height: 147)
                LinearGradient(colors: [.clear, .black.opacity(0.88)],
                               startPoint: .center, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 28))
                        Spacer()
                        if let episodeLabel = entry.episodeLabel {
                            Text(episodeLabel).font(.system(size: 11, weight: .bold))
                        }
                    }
                    ProgressView(value: entry.fraction)
                        .tint(XSV3.coral)
                }
                .foregroundStyle(.white)
                .padding(12)
            }
            .frame(width: 260, height: 147)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))

            HStack(spacing: 7) {
                Text(entry.item.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Text("\(Int(entry.fraction * 100))%")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(XSV3.amber)
            }
            .foregroundStyle(.white)
            .frame(width: 260)
        }
        .accessibilityElement(children: .combine)
    }
}

struct XSV3ScreenBackdrop: View {
    var body: some View {
        ZStack {
            XSV3.ink
            RadialGradient(
                colors: [XSV3.lilac.opacity(0.13), .clear],
                center: .topLeading,
                startRadius: 20,
                endRadius: 470
            )
            RadialGradient(
                colors: [XSV3.coral.opacity(0.08), .clear],
                center: .bottomTrailing,
                startRadius: 45,
                endRadius: 450
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

import SwiftUI

struct XSBrandMark: View {
    var size: CGFloat = 80
    var showGlow = true

    var body: some View {
        ZStack {
            if showGlow {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.purple.opacity(0.28), Color.pink.opacity(0.10), .clear],
                            center: .center,
                            startRadius: 2,
                            endRadius: size * 0.78
                        )
                    )
                    .frame(width: size * 1.45, height: size * 1.45)
            }

            Canvas { context, canvasSize in
                let w = canvasSize.width
                let h = canvasSize.height
                let gradient = Gradient(colors: [
                    Color(red: 0.23, green: 0.05, blue: 1.0),
                    Color(red: 0.73, green: 0.02, blue: 0.63),
                    Color(red: 1.0, green: 0.22, blue: 0.03)
                ])

                func parallelogram(_ points: [CGPoint]) -> Path {
                    var path = Path()
                    guard let first = points.first else { return path }
                    path.move(to: first)
                    for point in points.dropFirst() { path.addLine(to: point) }
                    path.closeSubpath()
                    return path
                }

                let left = parallelogram([
                    CGPoint(x: w * 0.12, y: h * 0.82),
                    CGPoint(x: w * 0.27, y: h * 0.82),
                    CGPoint(x: w * 0.58, y: h * 0.14),
                    CGPoint(x: w * 0.49, y: h * 0.05)
                ])

                let middle = parallelogram([
                    CGPoint(x: w * 0.33, y: h * 0.82),
                    CGPoint(x: w * 0.49, y: h * 0.82),
                    CGPoint(x: w * 0.69, y: h * 0.32),
                    CGPoint(x: w * 0.61, y: h * 0.22)
                ])

                let right = parallelogram([
                    CGPoint(x: w * 0.53, y: h * 0.82),
                    CGPoint(x: w * 0.84, y: h * 0.82),
                    CGPoint(x: w * 0.70, y: h * 0.48),
                    CGPoint(x: w * 0.61, y: h * 0.59)
                ])

                let shading = GraphicsContext.Shading.linearGradient(
                    gradient,
                    startPoint: CGPoint(x: w * 0.82, y: h * 0.10),
                    endPoint: CGPoint(x: w * 0.12, y: h * 0.90)
                )

                context.fill(left, with: shading)
                context.fill(middle, with: shading)
                context.fill(right, with: shading)
            }
            .frame(width: size, height: size)
        }
        .frame(width: size * 1.3, height: size * 1.3)
        .accessibilityHidden(true)
    }
}

struct XSWordmark: View {
    var compact = false

    var body: some View {
        HStack(spacing: compact ? 7 : 10) {
            XSBrandMark(size: compact ? 28 : 38, showGlow: false)

            Text("XS")
                .foregroundStyle(
                    LinearGradient(
                        colors: [.purple, .pink, .orange],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            + Text(" TV")
                .foregroundStyle(.white)
        }
        .font(.system(size: compact ? 19 : 26, weight: .black, design: .rounded))
    }
}

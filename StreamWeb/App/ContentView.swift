import SwiftUI

struct ContentView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView {
                SectionView(title: "Home", icon: "house.fill")
                    .tabItem { Label("Home", systemImage: "house.fill") }
                SectionView(title: "Live", icon: "play.tv.fill")
                    .tabItem { Label("Live", systemImage: "play.tv.fill") }
                SectionView(title: "Movies", icon: "film.fill")
                    .tabItem { Label("Movies", systemImage: "film.fill") }
                SectionView(title: "Series", icon: "rectangle.stack.fill")
                    .tabItem { Label("Series", systemImage: "rectangle.stack.fill") }
                SectionView(title: "Search", icon: "magnifyingglass")
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
            }
            .tint(.red)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(10)
            }
        }
        .preferredColorScheme(.dark)
        .task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation(.easeOut(duration: 0.4)) { showSplash = false }
        }
    }
}

private struct SplashView: View {
    var body: some View {
        ZStack {
            RadialGradient(colors: [Color.red.opacity(0.30), .black], center: .center, startRadius: 30, endRadius: 430)
                .ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer()
                Circle()
                    .fill(.black.opacity(0.75))
                    .frame(width: 170, height: 170)
                    .overlay(Circle().stroke(.red.opacity(0.7), lineWidth: 2))
                    .overlay(Image(systemName: "play.tv.fill").font(.system(size: 70)).foregroundStyle(.white))
                    .shadow(color: .red.opacity(0.4), radius: 28)

                Text("XSSTORE TV")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .tracking(4)

                Text("مرحباً بكم في XsStore TV")
                    .font(.title3.weight(.semibold))
                Text("Welcome to XsStore TV")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    Pill(text: "LIVE")
                    Pill(text: "MOVIES")
                    Pill(text: "SERIES")
                }

                ProgressView().tint(.red).padding(.top, 8)
                Text("Preparing your entertainment...")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                Spacer()
            }
            .padding(28)
        }
    }
}

private struct Pill: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.bold))
            .tracking(2)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay(Capsule().stroke(.white.opacity(0.12)))
    }
}

private struct SectionView: View {
    let title: String
    let icon: String

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                VStack(spacing: 18) {
                    Image(systemName: icon)
                        .font(.system(size: 58))
                        .foregroundStyle(.red)
                    Text(title).font(.largeTitle.bold())
                }
            }
            .navigationTitle(title == "Home" ? "XsStore TV" : title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview { ContentView() }

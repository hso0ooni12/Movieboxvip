"""Improve native app chrome, without replacing any catalog or media engine.
Invoke after all legacy root replacement scripts are finished.
"""
from pathlib import Path

root=Path("FrameNative/Views/EnhancedRootView.swift")
code=root.read_text(encoding="utf-8")
assert "XSCinemaNativeHomeView()" in code and "XSSportsLiveViewV33()" in code
root.write_text(r'''import SwiftUI

struct EnhancedRootView: View {
    @StateObject private var cinema = XSCinemaNativeStore()
    @State private var activeTab = 0
    @State private var splash = true
    @Namespace private var tabIndicator

    private let labels = ["Home", "Movies", "Series", "الرياضة"]
    private let symbols = ["house.fill", "film.stack.fill",
                           "play.tv.fill", "sportscourt.fill"]

    var body: some View {
        ZStack {
            Color(red: 0.028, green: 0.036, blue: 0.055).ignoresSafeArea()
            mainTabs
                .opacity(splash ? 0 : 1)
            if splash {
                XSTVPremiumSplash()
                    .transition(.opacity.combined(with: .scale(scale: 1.04)))
                    .zIndex(10)
            }
        }
        .environmentObject(cinema)
        .task {
            Task { await cinema.boot() }
            try? await Task.sleep(nanoseconds: 410_000_000)
            withAnimation(.easeOut(duration: 0.32)) { splash = false }
        }
        .preferredColorScheme(.dark)
    }

    private var mainTabs: some View {
        TabView(selection: $activeTab) {
            NavigationStack { XSCinemaNativeHomeView() }
                .tabItem { Label("Home", systemImage: "house.fill") }
                .tag(0)
            NavigationStack { XSCinemaNativeBrowseView(kind: .movie) }
                .tabItem { Label("Movies", systemImage: "film.stack.fill") }
                .tag(1)
            NavigationStack { XSCinemaNativeBrowseView(kind: .series) }
                .tabItem { Label("Series", systemImage: "play.tv.fill") }
                .tag(2)
            NavigationStack { XSSportsLiveViewV33() }
                .tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }
                .tag(3)
        }
        .tint(Color(red: 1, green: 0.32, blue: 0.43))
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            floatingNavigation
        }
    }

    private var floatingNavigation: some View {
        HStack(spacing: 2) {
            ForEach(0..<labels.count, id: \.self) { index in
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.76)) {
                        activeTab = index
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: symbols[index])
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 19, weight: .semibold))
                            .frame(height: 24)
                        Text(labels[index])
                            .font(.system(size: 10, weight: activeTab == index ? .bold : .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(activeTab == index ? .white : .white.opacity(0.53))
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background {
                        if activeTab == index {
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(red: 0.92, green: 0.24, blue: 0.40).opacity(0.60))
                                .matchedGeometryEffect(id: "active-tab", in: tabIndicator)
                        }
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 20))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(activeTab == index ? .isSelected : [])
            }
        }
        .padding(7)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 27, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 27, style: .continuous)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .shadow(color: .pink.opacity(0.12), radius: 18, y: 8)
        .padding(.horizontal, 16)
        .padding(.bottom, 7)
        .background {
            LinearGradient(colors: [.black.opacity(0.0), .black.opacity(0.48)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

private struct XSTVPremiumSplash: View {
    @State private var appear = false

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            RadialGradient(colors: [
                Color.pink.opacity(appear ? 0.38 : 0.17),
                Color.purple.opacity(0.20), .clear],
                center: .center, startRadius: 10, endRadius: 340)
                .ignoresSafeArea()
            VStack(spacing: 17) {
                XSBrandMark(size: 150)
                    .scaleEffect(appear ? 1.0 : 0.80)
                XSWordmark()
                    .opacity(appear ? 1 : 0.3)
                Text("CINEMA  ·  SERIES  ·  LIVE SPORTS")
                    .font(.caption2.bold())
                    .tracking(2.2)
                    .foregroundStyle(.white.opacity(0.52))
            }
            .animation(.spring(response: 0.72, dampingFraction: 0.80), value: appear)
        }
        .onAppear { appear = true }
    }
}
''',encoding="utf-8")
print("V25: floating native glass navigation, spring selection, warm radial hero & splash.")

import SwiftUI

struct GemflixHomeScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @State private var testPlayer: PlayerSelection?

    private var top: [MediaTitle] {
        store.gemflixFeatured.isEmpty ? Array(store.movies.prefix(12)) : store.gemflixFeatured
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 29) {
                brandBar
                if let first = top.first {
                    feature(first)
                    rankedRail(Array(top.prefix(10)))
                }
                if !store.series.isEmpty {
                    rail("مسلسلات تشدّك", subtitle: "قصص تستاهل تكملها", items: Array(store.series.prefix(15)))
                }
                if !store.movies.isEmpty {
                    rail("أفلام مختارة", subtitle: "أكشن · دراما · إثارة", items: Array(store.movies.dropFirst(10).prefix(15)))
                }
                if !top.isEmpty { rail("الرائج الآن", subtitle: "من واجهة Gemflix", items: Array(top.reversed())) }
                testCard
            }
            .padding(.bottom, 26)
        }
        .scrollIndicators(.hidden)
        .background(CinemaPalette.base)
        .refreshable { await store.reload() }
        .fullScreenCover(item: $testPlayer) { selection in
            NativePlayerScreen(title: selection.title, entry: selection.entry)
        }
    }

    private var brandBar: some View {
        HStack(spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 13)
                    .fill(LinearGradient(colors: [CinemaPalette.accent, .red.opacity(0.55)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                Image(systemName: "diamond.fill")
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 1) {
                Text("GEMFLIX")
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(.white)
                Text("YOUR CINEMA. YOUR WAY.")
                    .font(.system(size: 8, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(CinemaPalette.secondary)
            }
            Spacer()
            Image(systemName: "sparkles.tv.fill")
                .font(.system(size: 21))
                .foregroundStyle(CinemaPalette.accent.opacity(0.85))
        }
        .padding(.horizontal, 23)
        .padding(.top, 17)
    }

    private func feature(_ item: MediaTitle) -> some View {
        NavigationLink(value: item) {
            ZStack(alignment: .bottomLeading) {
                PosterImage(url: item.backdropURL ?? item.posterURL)
                    .frame(height: 410)
                    .frame(maxWidth: .infinity)
                    .clipped()
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.08), location: 0),
                    .init(color: .black.opacity(0.18), location: 0.38),
                    .init(color: CinemaPalette.base.opacity(0.96), location: 1)
                ], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 13) {
                    Label("الأبرز اليوم", systemImage: "sparkle")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(CinemaPalette.accent)
                    Text(item.title)
                        .font(.system(size: 38, weight: .black, design: .rounded))
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.white)
                        .lineLimit(3)
                    HStack(spacing: 10) {
                        Text(item.year)
                        if !item.rating.isEmpty {
                            Label(item.rating, systemImage: "star.fill")
                                .foregroundStyle(.yellow)
                        }
                        Text("CINEMA")
                            .font(.system(size: 10, weight: .black))
                            .tracking(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 4)
                            .background(.white.opacity(0.17), in: Capsule())
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.86))
                    if !item.synopsis.isEmpty {
                        Text(item.synopsis)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.76))
                            .lineLimit(2)
                    }
                    Label("عرض التفاصيل", systemImage: "play.fill")
                        .font(.system(size: 14, weight: .bold))
                        .padding(.horizontal, 19)
                        .padding(.vertical, 12)
                        .foregroundStyle(.white)
                        .background(CinemaPalette.accent, in: Capsule())
                }
                .padding(22)
            }
            .frame(height: 410)
            .clipShape(RoundedRectangle(cornerRadius: 25))
            .overlay(RoundedRectangle(cornerRadius: 25).stroke(.white.opacity(0.1)))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 17)
    }

    private func rankedRail(_ items: [MediaTitle]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("TOP 10 TODAY", subtitle: "الأكثر رواجًا", system: "flame.fill")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .bottom, spacing: 13) {
                    ForEach(items.indices, id: \.self) { index in
                        let item = items[index]
                        NavigationLink(value: item) {
                            ZStack(alignment: .bottomLeading) {
                                MediaPoster(item: item, width: 145)
                                    .padding(.leading, 16)
                                Text(String(index + 1))
                                    .font(.system(size: 74, weight: .black, design: .rounded))
                                    .foregroundStyle(CinemaPalette.base)
                                    .shadow(color: .white.opacity(0.8), radius: 1)
                                    .overlay {
                                        Text(String(index + 1))
                                            .font(.system(size: 74, weight: .black, design: .rounded))
                                            .foregroundStyle(.white.opacity(0.80))
                                            .mask(LinearGradient(colors: [.white, .clear],
                                                                 startPoint: .bottom, endPoint: .top))
                                    }
                                    .offset(x: -2, y: -48)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func rail(_ headline: String, subtitle: String, items: [MediaTitle]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle(headline, subtitle: subtitle, system: "play.rectangle.on.rectangle")
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(items) { item in
                        NavigationLink(value: item) { MediaPoster(item: item, width: 145) }
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
            }
        }
    }

    private func sectionTitle(_ title: String, subtitle: String, system: String) -> some View {
        HStack(alignment: .center, spacing: 11) {
            Image(systemName: system).foregroundStyle(CinemaPalette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 21, weight: .bold, design: .rounded))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(CinemaPalette.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 22)
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("فحص المشغّل الأصلي", systemImage: "checkmark.shield.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)
            Text("اختبر VLC بمقطع HLS مرخّص للاختبار. عرض الأفلام لا يعني توفر مصدر تشغيل لها؛ فقط الروابط المباشرة الصالحة تشتغل داخل VLC.")
                .font(.system(size: 12))
                .foregroundStyle(CinemaPalette.secondary)
                .lineSpacing(4)
            Button {
                if let entry = store.entry(for: "demo:apple-hls") {
                    testPlayer = PlayerSelection(title: "اختبار مشغّل VLC", entry: entry)
                }
            } label: {
                Label("تشغيل المقطع التجريبي", systemImage: "play.fill")
                    .font(.system(size: 13, weight: .bold))
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(CinemaPalette.accent, in: Capsule())
                    .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(19)
        .background(CinemaPalette.elevated, in: RoundedRectangle(cornerRadius: 19))
        .padding(.horizontal, 20)
    }
}

struct GemflixSavedScreen: View {
    @EnvironmentObject private var store: CinemaStore

    private var saved: [MediaTitle] {
        let all = store.gemflixFeatured + store.movies + store.series
        var seen = Set<String>()
        return all.filter { store.favorites.contains($0.id) && seen.insert($0.id).inserted }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("قائمتي").font(.system(size: 32, weight: .black, design: .rounded))
                        Text("العناوين اللي حفظتها ترجع لها بسهولة")
                            .font(.system(size: 12)).foregroundStyle(CinemaPalette.secondary)
                    }
                    Spacer()
                    Image(systemName: "bookmark.fill")
                        .font(.system(size: 26)).foregroundStyle(CinemaPalette.accent)
                }
                if saved.isEmpty {
                    VStack(spacing: 13) {
                        Image(systemName: "bookmark.slash")
                            .font(.system(size: 48)).foregroundStyle(CinemaPalette.accent.opacity(0.7))
                        Text("قائمتك للحين فاضية").font(.headline)
                        Text("اضغط علامة الحفظ في صفحة أي فيلم أو مسلسل.")
                            .font(.subheadline).foregroundStyle(CinemaPalette.secondary)
                    }
                    .frame(maxWidth: .infinity, minHeight: 330)
                } else {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3), spacing: 17) {
                        ForEach(saved) { item in
                            NavigationLink(value: item) { MediaPoster(item: item, width: nil) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 22)
            .padding(.top, 28)
        }
        .background(CinemaPalette.base)
    }
}

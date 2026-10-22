"""Apply V25 fixes AFTER old V24 compatibility assertions, before Swift build."""
from pathlib import Path

service_path=Path("FrameNative/Services/XSCinemaNativeSource.swift")
ui_path=Path("FrameNative/Views/XSCinemaNativeExperience.swift")
project_path=Path("project-native.yml")
service=service_path.read_text(encoding="utf-8")
ui=ui_path.read_text(encoding="utf-8")

def replace_once(source, old, new, field):
    count=source.count(old)
    assert count==1, f"{field}: expected one match, got {count}"
    return source.replace(old,new,1)

service=replace_once(service,
    "    var episodes: [XSCinemaEpisode]\n",
    "    var episodes: [XSCinemaEpisode]\n    var tmdbID: Int? = nil\n",
    "model TMDB identifier")

service=replace_once(service,
    '    init() { favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? []) }',
    '''    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: favoriteKey) ?? [])
        movies = XSCinemaV25Seed.movies
        series = XSCinemaV25Seed.series
    }''',
    "seeded startup content")
service=service.replace("XSCinemaCatalogAPI.shared.catalog(","XSCinemaV25FlexibleCatalog.shared.catalog(")
service=service.replace("XSCinemaCatalogAPI.shared.search(","XSCinemaV25FlexibleCatalog.shared.search(")
service=service.replace("XSCinemaCatalogAPI.shared.detail(","XSCinemaV25FlexibleCatalog.shared.detail(")

service=replace_once(service,
    '        guard !loaded && !loading else { return }',
    '        guard !loading else { return }',
    "allow refresh")
service=replace_once(service,
    '        async let c = XSCinemaCatalogAPI.shared.openFilms()',
    '''        // Archive item verification can be slow: never block the main movie
        // and series catalog on the secondary free/CC video collection.
        Task { [weak self] in
            let licensed = await XSCinemaCatalogAPI.shared.openFilms()
            guard !licensed.isEmpty else { return }
            self?.freeMovies = licensed
        }''',
    "separate slow archive checking")
service=replace_once(service,
    '        freeMovies = await c\n',
    '',
    "remove blocking await")

# Pervasive search state now also uses resilient metadata parser.
ui=ui.replace("XSCinemaCatalogAPI.shared.search(","XSCinemaV25FlexibleCatalog.shared.search(")
ui=ui.replace("XSCinemaCatalogAPI.shared.detail(","XSCinemaV25FlexibleCatalog.shared.detail(")

ui=replace_once(ui,
    '    @State private var selection:XSVODPlaybackSelection?\n',
    '    @State private var selection:XSVODPlaybackSelection?\n    @State private var etwatchPlayer:XSCinemaV25PlayerSelection?\n',
    "site player presentation")

ui=replace_once(ui,
    '''                        Button {
                            store.toggle(item)
                        } label: {''',
    '''                        if let id = item.tmdbID, id > 0 {
                            Button {
                                etwatchPlayer = XSCinemaV25PlayerSelection(
                                    tmdbID:id,kind:item.kind,title:item.title,
                                    season:1,episode:1)
                            } label: {
                                Label("مشغل ETWatch",systemImage:"play.rectangle.fill")
                                    .frame(maxWidth:.infinity,minHeight:45)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(XSNativeCinemaColors.accent)
                        }
                        Button {
                            store.toggle(item)
                        } label: {''',
    "ETWatch title-specific playback button")

ui=replace_once(ui,
    '''                    if !item.isPlayable {
                        Label("هذا العنوان موجود في الفهرس فقط. ما توفر له رابط تشغيل مصرح به، ولا بنعرض زر تشغيل وهمي.",
                              systemImage:"info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.95))
                    } else {''',
    '''                    if !item.isPlayable && item.tmdbID == nil {
                        Label("هذا العنوان موجود في الفهرس فقط ولا يوجد مصدر مشاهدة متحقق منه.",
                              systemImage:"info.circle")
                            .font(.caption)
                            .foregroundStyle(.orange.opacity(0.95))
                    } else if item.tmdbID != nil {
                        Text("المشاهدة عبر صفحة مشغل ETWatch لهذا العنوان. توفر الرابط والجودة والترجمة يعتمد على الموقع، ولم يتم إثبات تشغيله على الجهاز بعد.")
                            .font(.caption)
                            .foregroundStyle(XSNativeCinemaColors.muted)
                    } else {''',
    "honest site playback disclosure")

ui=replace_once(ui,
    '''                                ForEach(item.episodes.filter{$0.season==selectedSeason}) { ep in
                                    HStack(spacing:12) {''',
    '''                                ForEach(item.episodes.filter{$0.season==selectedSeason}) { ep in
                                    Button {
                                        guard let id = item.tmdbID, id > 0 else { return }
                                        etwatchPlayer = XSCinemaV25PlayerSelection(
                                            tmdbID:id,kind:.series,title:item.title,
                                            season:ep.season,episode:ep.number)
                                    } label: {
                                    HStack(spacing:12) {''',
    "episode playable action")

ui=replace_once(ui,
    '''                                    .padding(.vertical,4)
                                }
                                Text("بيانات الحلقات متوفرة للفهرسة، وليس لدينا روابط مرخصة لتشغيلها.")
                                    .font(.caption2)
                                    .foregroundStyle(XSNativeCinemaColors.muted)''',
    '''                                    .padding(.vertical,4)
                                    }
                                    .disabled(item.tmdbID == nil)
                                    .buttonStyle(.plain)
                                }
                                Text("اضغط الحلقة لفتح مشغل ETWatch الخاص بها. قد لا يتوفر تشغيل كل حلقة.")
                                    .font(.caption2)
                                    .foregroundStyle(XSNativeCinemaColors.muted)''',
    "episode button closing")

ui=replace_once(ui,
    '''        .fullScreenCover(item:$selection) { chosen in
            XSVODVLCPlayerView(source:chosen)
        }''',
    '''        .fullScreenCover(item:$selection) { chosen in
            XSVODVLCPlayerView(source:chosen)
        }
        .fullScreenCover(item:$etwatchPlayer) { chosen in
            XSCinemaV25SitePlayerView(selection:chosen)
        }''',
    "full screen web player")

ui=replace_once(ui,
    '''        var ids=Set(local.map(\.id))
        return Array((local+remoteMovies+remoteSeries)
            .filter { ids.insert($0.id).inserted == false ? local.contains($0) : true }
            .prefix(120))''',
    '''        var ids = Set<String>()
        return Array((local+remoteMovies+remoteSeries)
            .filter { ids.insert($0.id).inserted }
            .prefix(120))''',
    "fix native search duplicate suppression")

# V24's direct licensed streams still work with original VLC.
# New website player WKWebView is *only* in the fullscreen playback component.
assert "XSCinemaV25FlexibleCatalog.shared.catalog" in service
assert "XSCinemaV25Seed.movies" in service
assert "XSCinemaV25SitePlayerView(selection:chosen)" in ui
assert "XSSportsLiveViewV33" in Path("FrameNative/Views/EnhancedRootView.swift").read_text()
assert "get_vod_streams" not in ui

service_path.write_text(service,encoding="utf-8")
ui_path.write_text(ui,encoding="utf-8")

print("V25: non-empty seeded library, resilient refresh/search, title + episode ETWatch player; sports unchanged.")

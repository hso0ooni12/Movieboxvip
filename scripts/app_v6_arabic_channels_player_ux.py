"""Premium V6: final-source AR-only channel UX + player choice feedback.

Runs AFTER the proven V5+R5 pipeline: no source-provider selection, subtitle
bridge/ack protocol, IPTV credentials, stream URL or VLC surface is replaced.
"""
from pathlib import Path
import re

def replace_one(text, old, new, name):
    if text.count(old) != 1:
        raise SystemExit(f"V6 UI expected one {name} marker, found {text.count(old)}")
    return text.replace(old, new, 1)

# 1) Legacy service preferred sports-only rows. For AR channel discovery, make
# every permitted NON-ADULT live row available to the strictly filtered UI.
service_path = Path("FrameNative/Services/IPTVService.swift")
service = service_path.read_text(encoding="utf-8")
start = "                let sportsCategories = categories.filter { Self.isSportsCategory($0.categoryName) }"
end = "                return (candidate, visibleCategories, matched)"
a, b = service.find(start), service.find(end)
if a < 0 or b < a:
    raise SystemExit("V6 service: V5 sports-only response boundary missing")
b += len(end)
service = service[:a] + """                // V6_AR_CATALOG: expose all non-adult channels to the client.
                // Only AR-prefixed non-sports channels are actually displayed.
                // Preserve the successful provider/credentials for playback.
                return (candidate, categories.filter { !excludedIDs.contains($0.categoryID) }, permitted)""" + service[b:]
service_path.write_text(service, encoding="utf-8")

# 2) Use the existing source-owned selection action. Hide the panel after a
# tap; on subtitles, wait for the VERIFIED cue-load acknowledgement before
# claiming that the selected track has loaded.
player_path = Path("FrameNative/FrameXTVPlayerV6.swift")
player = player_path.read_text(encoding="utf-8")
player = replace_one(
    player,
    "    @State private var aspectMode = \"adapt\"",
    """    @State private var aspectMode = "adapt"
    // V6_CHOICE_FEEDBACK: presentation scoped to full-screen player only.
    @State private var selectionNotice: String?
    @State private var selectionNoticeTask: Task<Void, Never>?
    @State private var waitingForSubtitleID: String?
    @State private var waitingForSubtitleName: String?""",
    "player notice state",
)
row_a = player.index("    private func nativeServerRow(")
row_b = player.index("    private func serverQualityTint(", row_a)
server_rows = player[row_a:row_b]
server_rows = replace_one(
    server_rows,
    """            player.selectServer(server)
            holdControls()""",
    """            player.selectServer(server)
            closePanel()
            showSelectionNotice("تم اختيار السيرفر: \\(server.name)")""",
    "server selection action",
)
player = player[:row_a] + server_rows + player[row_b:]

sub_a = player.index("    private var subtitlesPanel: some View {")
sub_b = player.index("    private var audioPanel: some View {", sub_a)
sub = player[sub_a:sub_b]
off = re.compile(r"(?m)^(?P<indent>\s*)player\.selectSubtitle\(nil\)\n(?P=indent)(?:holdControls|closePanel)\(\)")
opt = re.compile(r"(?m)^(?P<indent>\s*)player\.selectSubtitle\(option\)\n(?P=indent)(?:holdControls|closePanel)\(\)")
sub, off_count = off.subn(lambda m: m.group("indent") +
    'waitingForSubtitleID = "off"\n' + m.group("indent") +
    'waitingForSubtitleName = "إيقاف الترجمة"\n' + m.group("indent") +
    'player.selectSubtitle(nil)\n' + m.group("indent") +
    'closePanel()\n' + m.group("indent") +
    'showSelectionNotice("جارٍ إيقاف الترجمة…")', sub, count=1)
sub, opt_count = opt.subn(lambda m: m.group("indent") +
    'waitingForSubtitleID = option.id\n' + m.group("indent") +
    'waitingForSubtitleName = option.displayName\n' + m.group("indent") +
    'player.selectSubtitle(option)\n' + m.group("indent") +
    'closePanel()\n' + m.group("indent") +
    'showSelectionNotice("جارٍ تحميل الترجمة: \\(option.displayName)")', sub, count=1)
if off_count != 1 or opt_count != 1:
    raise SystemExit(f"V6 subtitle actions not found: off={off_count}, track={opt_count}")
player = player[:sub_a] + sub + player[sub_b:]

player = replace_one(
    player,
    """                if !player.isReady {
                    loadingOverlay
                }""",
    """                if !player.isReady {
                    loadingOverlay
                }

                if let selectionNotice {
                    VStack {
                        HStack(spacing: 11) {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(.green)
                            Text(selectionNotice)
                                .font(.system(size: 13, weight: .semibold))
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .foregroundStyle(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 13)
                        .background(.black.opacity(0.90), in: Capsule())
                        .overlay(Capsule().stroke(.white.opacity(0.18)))
                        .shadow(color: .black.opacity(0.38), radius: 13, y: 6)
                        .padding(.top, 47)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity)
                    .allowsHitTesting(false)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .zIndex(25)
                }""",
    "player choice notice",
)

player = replace_one(
    player,
    "    private var playbackTitle: String {",
    """    private func showSelectionNotice(_ message: String) {
        selectionNoticeTask?.cancel()
        withAnimation(.easeInOut(duration: 0.16)) {
            selectionNotice = message
        }
        selectionNoticeTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_700_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.20)) {
                selectionNotice = nil
            }
        }
    }

    private var playbackTitle: String {""",
    "notice helper",
)

player = replace_one(
    player,
    "        .onChange(of: player.currentTime) { _ in handlePlaybackProgress() }",
    """        // The source adapter reports selection only AFTER its cue-load
        // acknowledgement. A tap is never treated as a successful load.
        .onChange(of: player.pendingSubtitleID) { pending in
            guard pending == nil, let expected = waitingForSubtitleID else { return }
            if player.subtitleSelectionError == nil &&
                (expected == "off" || player.selectedSubtitleID == expected) {
                let message = expected == "off" ? "تم إيقاف الترجمة" :
                    "تم تحميل الترجمة: \\(waitingForSubtitleName ?? "الترجمة")"
                showSelectionNotice(message)
            } else {
                showSelectionNotice("تعذّر تحميل الترجمة، جرّب مساراً آخر")
            }
            waitingForSubtitleID = nil
            waitingForSubtitleName = nil
        }
        .onChange(of: player.subtitleSelectionError) { error in
            guard error != nil, waitingForSubtitleID != nil else { return }
            showSelectionNotice("تعذّر تحميل الترجمة، جرّب مرة ثانية")
            waitingForSubtitleID = nil
            waitingForSubtitleName = nil
        }
        .onChange(of: player.currentTime) { _ in handlePlaybackProgress() }""",
    "subtitle acknowledgment overlay",
)
player = replace_one(
    player,
    """        .onDisappear {
            hideTask?.cancel()""",
    """        .onDisappear {
            selectionNoticeTask?.cancel()
            hideTask?.cancel()""",
    "notice cleanup",
)
player_path.write_text(player, encoding="utf-8")

# 3) Arabic TV catalogue: STRICT AR prefix and remove sports by name/category.
# The backend is still untouched beyond the permitted-catalog scope above.
sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = sports_path.read_text(encoding="utf-8")
sports = replace_one(
    sports,
    '    @State private var favoritesOnly = false',
    '    @State private var favoritesOnly = false\n    @State private var compactList = true',
    "list mode state",
)
f_start = sports.index("    private var filteredStreams: [IPTVLiveStream] {")
f_end = sports.index("    private var featured: IPTVLiveStream? {", f_start)
sports = sports[:f_start] + """    // V6_AR_ONLY_FILTER: never display non-AR streams or sports channels.
    // Channel filtering is entirely on-device; auth and playback URL retain
    // the account's verified V5 provider and the stable R5 VLC surface.
    private func isArabicChannel(_ stream: IPTVLiveStream) -> Bool {
        let rawName = stream.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = rawName.uppercased()
        guard name.hasPrefix("AR") else { return false }
        let category = (store.categories.first { $0.categoryID == stream.categoryID }?.categoryName ?? "").uppercased()
        let sportsTerms = ["SPORT", "SSC", "BEIN SPORT", "DAZN", "ESPN", "MATCH", "رياض", "مباراة", "كورة", "كرة القدم"]
        return !sportsTerms.contains { name.contains($0) || category.contains($0) }
    }

    private var arabicStreams: [IPTVLiveStream] {
        store.streams.filter(isArabicChannel)
    }

    private var filteredStreams: [IPTVLiveStream] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return arabicStreams.filter { stream in
            let queryMatch = text.isEmpty || stream.name.localizedCaseInsensitiveContains(text)
            let favoriteMatch = !favoritesOnly || favoriteIDs.contains(stream.streamID)
            return queryMatch && favoriteMatch
        }
    }

""" + sports[f_end:]
sports = replace_one(sports,'Text("SPORTS LIVE")','Text("AR · القنوات العربية")',"channel toolbar title")
sports = replace_one(sports,'.accessibilityLabel("Sports server settings")','.accessibilityLabel("إعدادات سيرفر القنوات")',"settings label")
sports = replace_one(sports,'Text("LIVE ARENA")','Text("ARABIC LIVE TV")',"channel kicker")
sports = replace_one(sports,'Text("\\(store.streams.count) CHANNELS")','Text("\\(arabicStreams.count) قناة")',"channel count")
sports = replace_one(sports,'Text("Every moment. Live.")','Text("تلفزيونك العربي")',"channel title")
sports = replace_one(sports,'Text("Your front row to the action.")','Text("القنوات العربية في مكان واحد، بلا زحمة")',"channel subtitle")
sports = replace_one(sports,'TextField("Search live channels", text: $query)','TextField("ابحث عن قناة عربية", text: $query)',"channel search")
sports = replace_one(sports,'.accessibilityLabel("Refresh live channels")','.accessibilityLabel("تحديث القنوات")',"refresh label")

# Remove sports-focused category browser: all / saved only with instant switches.
cat_start=sports.index("    private var categoryStrip: some View {")
cat_end=sports.index("    private func featuredCard(",cat_start)
sports=sports[:cat_start]+"""    private var categoryStrip: some View {
        HStack(spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.17)) { favoritesOnly = false }
            } label: {
                Label("جميع القنوات", systemImage: "tv")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(favoritesOnly ? .white : .black)
                    .background(favoritesOnly ? XSV3.lifted : .white, in: Capsule())
            }
            Button {
                withAnimation(.easeInOut(duration: 0.17)) { favoritesOnly = true }
            } label: {
                Label("المفضلة", systemImage: favoritesOnly ? "star.fill" : "star")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .foregroundStyle(favoritesOnly ? .black : .white)
                    .background(favoritesOnly ? .white : XSV3.lifted, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 22)
    }

""" +sports[cat_end:]
sports = replace_one(
    sports,
    """                if let featured {
                    featuredCard(featured)
                }

                sectionHeader""",
    """                sectionHeader""",
    "remove sports-only featured carousel",
)
sports = replace_one(sports,'Text(favoritesOnly ? "No saved channels yet" : "No channels match")','Text(favoritesOnly ? "ما أضفت قنوات للمفضلة" : "ما حصلنا قنوات AR")',"empty title")
sports = replace_one(sports,'Text(favoritesOnly ? "Tap the star on a channel to save it here." : "Try another category or search.")','Text(favoritesOnly ? "اضغط النجمة بجانب القناة لإضافتها" : "جرّب تحديث القائمة أو تغيير البحث")',"empty subtitle")
sports = replace_one(sports,'Button("Show all channels")','Button("عرض جميع القنوات")',"empty action")

head_start=sports.index("    private var sectionHeader: some View {")
head_end=sports.index("    private var loadingState: some View {",head_start)
sports=sports[:head_start]+"""    private var sectionHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AR CHANNELS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.3)
                    .foregroundStyle(XSV3.coral)
                Text(favoritesOnly ? "القنوات المفضلة" : "كل القنوات العربية")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("\\(filteredStreams.count) قناة")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(XSV3.muted)
            }
            Spacer()
            Button {
                withAnimation(.easeInOut(duration: 0.18)) { compactList.toggle() }
            } label: {
                Image(systemName: compactList ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 46, height: 46)
                    .background(XSV3.lifted, in: RoundedRectangle(cornerRadius: 15))
            }
            .foregroundStyle(.white)
            .buttonStyle(.plain)
            .accessibilityLabel(compactList ? "عرض كشبكة" : "عرض كقائمة")
        }
        .padding(.horizontal, 22)
    }

    private var channelGrid: some View {
        Group {
            if compactList {
                LazyVStack(spacing: 10) {
                    ForEach(filteredStreams) { stream in
                        XSV6ArabicChannelRow(
                            stream: stream,
                            logoURL: resolvedLogoURL(for: stream),
                            isFavorite: favoriteIDs.contains(stream.streamID),
                            toggleFavorite: { toggleFavorite(stream.streamID) },
                            play: { selectedStream = stream }
                        )
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155, maximum: 250), spacing: 12)], spacing: 16) {
                    ForEach(filteredStreams) { stream in
                        XSSportsChannelCardV33(
                            stream: stream,
                            category: "AR · LIVE",
                            logoURL: resolvedLogoURL(for: stream),
                            isFavorite: favoriteIDs.contains(stream.streamID),
                            toggleFavorite: { toggleFavorite(stream.streamID) },
                            play: { selectedStream = stream }
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 22)
    }

""" + sports[head_end:]
sports = replace_one(sports,'Text("Loading live sports…")','Text("جارٍ تحميل القنوات العربية…")',"loading label")
sports = replace_one(sports,'Text("ON AIR")','Text("مباشر")',"live badge")
# Preserve original playback, artwork and channel selection functionality.
new_row = """private struct XSV6ArabicChannelRow: View {
    let stream: IPTVLiveStream
    let logoURL: URL?
    let isFavorite: Bool
    let toggleFavorite: () -> Void
    let play: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: play) {
                HStack(spacing: 13) {
                    XSSportsChannelArtworkV33(name: stream.name, logoURL: logoURL, compact: true)
                        .frame(width: 82, height: 66)
                        .clipShape(RoundedRectangle(cornerRadius: 13))
                        .overlay(RoundedRectangle(cornerRadius: 13).stroke(.white.opacity(0.11)))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(stream.name)
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .lineLimit(2)
                            .foregroundStyle(.white)
                        HStack(spacing: 6) {
                            Circle().fill(.red).frame(width: 6, height: 6)
                            Text("مباشر · AR")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.64))
                        }
                    }
                    Spacer(minLength: 5)
                    Image(systemName: "play.circle.fill")
                        .font(.system(size: 26))
                        .foregroundStyle(.white.opacity(0.85))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("تشغيل \\(stream.name)")
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.system(size: 18))
                    .foregroundStyle(isFavorite ? XSV3.amber : .white.opacity(0.74))
                    .frame(width: 44, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFavorite ? "إزالة من المفضلة" : "إضافة للمفضلة")
        }
        .padding(9)
        .background(XSV3.lifted.opacity(0.89), in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(.white.opacity(0.09)))
    }
}

"""
anchor="private struct XSSportsChannelCardV33: View {"
sports=replace_one(sports, anchor, new_row+anchor,"channel list cell")
sports_path.write_text(sports, encoding="utf-8")

# 4) Naming matches the AR-only catalogue. Do not remove the sports tab's
# underlying NavigationStack or replace full-screen VLC playback.
root_path=Path("FrameNative/Views/EnhancedRootView.swift")
root=root_path.read_text(encoding="utf-8")
root=replace_one(root,'.tabItem { Label("Sports", systemImage: "sportscourt.fill") }',
                 '.tabItem { Label("القنوات", systemImage: "tv.fill") }',"tab title")
root_path.write_text(root,encoding="utf-8")

home_path=Path("FrameNative/Views/XSCinematicHomeView.swift")
home=home_path.read_text(encoding="utf-8")
home=replace_one(home,'Text("THE LIVE ARENA")','Text("ARABIC LIVE TV")',"home channels section")
home=replace_one(home,'Text("Your front row to sport.")','Text("قنواتك العربية")',"home live hero")
home=replace_one(home,'Text("Explore live sports channels")','Text("قنوات AR المباشرة")',"home channel description")
home_path.write_text(home,encoding="utf-8")
print("V6 AR-only channel design + immediate panel closing + ack-based subtitle feedback applied.")

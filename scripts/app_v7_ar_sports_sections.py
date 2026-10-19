"""V7 correction: AR-PREFIXED SPORTS ONLY, with actual IPTV sports sections.

Applied LAST, after the V6/R5 protected generator and tests. Neither the
native VLC player nor authentication/stream URL/provider is edited.
"""
from pathlib import Path

def replace_one(s, a, b, tag):
    count = s.count(a)
    if count != 1:
        raise SystemExit(f"V7 {tag}: expected exactly one match, got {count}")
    return s.replace(a,b,1)

path=Path("FrameNative/Views/SportsLiveViewV33.swift")
sports=path.read_text(encoding="utf-8")
sports=replace_one(sports,
    '    @State private var compactList = true',
    '''    @AppStorage("xs.iptv.arSportsCompactList.v7") private var compactList = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    // Only rebuild the category/stream index on a provider/cache update, NOT
    // on every keystroke, favorite toggle or SwiftUI view re-render.
    @State private var sportsStreams: [IPTVLiveStream] = []
    @State private var sportsSections: [IPTVCategory] = []
    @State private var sportsCategoryCount: [String: Int] = [:]
    @State private var sportsCategoryName: [String: String] = [:]''',
    "cached AR sports state")

a=sports.index("    // V6_AR_ONLY_FILTER:")
b=sports.index("    private var featured: IPTVL",a)
new_filter='''    // V7_AR_SPORTS_ONLY: BOTH conditions are required:
    // (1) channel name begins with AR; (2) name OR source category is sports.
    // No regional/non-sports content may leak into the list.
    private func sportsKeywordMatch(_ value: String) -> Bool {
        let upper = value.uppercased()
        let terms = [
            "SPORT", "BEIN", "SSC", "ESPN", "DAZN", "EUROSPORT",
            "MATCH", "FOOTBALL", "SOCCER", "ARENA", "F1", "FORMULA",
            "UFC", "WWE", "NBA", "NHL", "TENNIS", "RACING",
            "ALKASS", "AL KASS", "KASS", "الكأس", "كأس",
            "رياض", "مباريات", "مباراة", "كورة", "الكرة", "كرة القدم",
            "دوري", "بطولة", "ملاعب", "مصارعة", "سباق"
        ]
        return terms.contains { upper.contains($0) }
    }

    private func rebuildSportsIndex(categories: [IPTVCategory], streams: [IPTVLiveStream]) {
        let categoriesByID = Dictionary(
            categories.map { ($0.categoryID, $0.categoryName) },
            uniquingKeysWith: { first, _ in first }
        )
        // A single O(n) provider scan. Search & section switching only touch
        // this small sport-only index, not the entire IPTV subscription.
        let matches = streams.filter { stream in
            let name = stream.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.uppercased().hasPrefix("AR") else { return false }
            return sportsKeywordMatch(name) ||
                sportsKeywordMatch(categoriesByID[stream.categoryID] ?? "")
        }
        var counts: [String: Int] = [:]
        for stream in matches {
            counts[stream.categoryID, default: 0] += 1
        }
        let groups = categories.filter { (counts[$0.categoryID] ?? 0) > 0 }

        sportsStreams = matches
        sportsSections = groups
        sportsCategoryCount = counts
        sportsCategoryName = categoriesByID
        if let id = selectedCategoryID, (counts[id] ?? 0) == 0 {
            selectedCategoryID = nil
        }
    }

    private var filteredStreams: [IPTVLiveStream] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return sportsStreams.filter { stream in
            let sectionMatch = selectedCategoryID == nil || stream.categoryID == selectedCategoryID
            let textMatch = text.isEmpty || stream.name.localizedCaseInsensitiveContains(text)
            let favoriteMatch = !favoritesOnly || favoriteIDs.contains(stream.streamID)
            return sectionMatch && textMatch && favoriteMatch
        }
    }

'''
sports=sports[:a]+new_filter+sports[b:]
sports=replace_one(sports,
    '''        .onChange(of: serverOverride) { _ in
            applyConfiguredServer()
        }''',
    '''        .onChange(of: serverOverride) { _ in
            applyConfiguredServer()
        }
        .onReceive(store.$categories) { categories in
            rebuildSportsIndex(categories: categories, streams: store.streams)
        }
        .onReceive(store.$streams) { streams in
            rebuildSportsIndex(categories: store.categories, streams: streams)
        }''',
    "index rebuild on provider update")

header_start=sports.index("    private var header: some View {")
header_end=sports.index("    private var categoryStrip: some View {",header_start)
sports=sports[:header_start]+'''    private var header: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 9) {
                Circle().fill(Color.red).frame(width: 7, height: 7)
                Text("AR SPORTS · LIVE")
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(XSV3.amber)
                Spacer()
                Text("\\(sportsStreams.count) قناة")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(XSV3.muted)
            }

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("عالم الرياضة العربية")
                        .font(.system(size: 30, weight: .black, design: .rounded))
                        .tracking(-0.75)
                        .foregroundStyle(.white)
                        .minimumScaleFactor(0.78)
                        .lineLimit(2)
                    Text("تنقل بين أقسام المباريات والقنوات بسهولة")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(XSV3.muted)
                        .lineLimit(2)
                }
                Spacer(minLength: 6)
                Image(systemName: "sportscourt.fill")
                    .font(.system(size: 34, weight: .ultraLight))
                    .foregroundStyle(XSV3.amber)
                    .frame(width: 62, height: 62)
                    .background(XSV3.amber.opacity(0.10),
                                in: RoundedRectangle(cornerRadius: 20))
                    .accessibilityHidden(true)
            }

            HStack(spacing: 11) {
                HStack(spacing: 9) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.white.opacity(0.64))
                    TextField("ابحث عن قناة أو بطولة...", text: $query)
                        .font(.system(size: 14))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .foregroundStyle(.white)

                    if !query.isEmpty {
                        Button {
                            query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.60))
                                .frame(width: 40, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("مسح البحث")
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 55)
                .background(XSV3.lifted,
                            in: RoundedRectangle(cornerRadius: 17))
                .overlay(RoundedRectangle(cornerRadius: 17)
                    .stroke(.white.opacity(0.12)))

                Button {
                    Task { try? await store.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 55, height: 55)
                        .background(XSV3.lifted,
                                    in: RoundedRectangle(cornerRadius: 17))
                        .overlay(RoundedRectangle(cornerRadius: 17)
                            .stroke(.white.opacity(0.11)))
                }
                .buttonStyle(XSV3PressStyle())
                .accessibilityLabel("تحديث القنوات الرياضية")
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 12)
    }

''' + sports[header_end:]

cat_start=sports.index("    private var categoryStrip: some View {")
cat_end=sports.index("    private func featuredCard(",cat_start)
sports=sports[:cat_start]+'''    // Real sections are derived from Xtream's sports category identifiers.
    // There is no fabricated list of leagues or channel providers.
    private var categoryStrip: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("تصفّح الأقسام")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("\\(sportsSections.count) أقسام")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(XSV3.muted)
            }
            .padding(.horizontal, 22)

            ScrollView(.horizontal) {
                LazyHStack(spacing: 9) {
                    sectionChip("الكل", count: sportsStreams.count,
                                icon: "square.grid.2x2.fill",
                                categoryID: nil, favorite: false)

                    sectionChip("المفضلة",
                                count: sportsStreams.filter { favoriteIDs.contains($0.streamID) }.count,
                                icon: "star.fill", categoryID: nil, favorite: true)

                    ForEach(sportsSections) { group in
                        sectionChip(
                            group.categoryName,
                            count: sportsCategoryCount[group.categoryID] ?? 0,
                            icon: "sportscourt",
                            categoryID: group.categoryID,
                            favorite: false
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 5)
            }
            .scrollIndicators(.hidden)
        }
    }

    private func sectionChip(_ name: String, count: Int, icon: String,
                             categoryID: String?, favorite: Bool) -> some View {
        let selected = favorite
            ? favoritesOnly
            : (!favoritesOnly && selectedCategoryID == categoryID)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.17)) {
                favoritesOnly = favorite
                selectedCategoryID = favorite ? nil : categoryID
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(selected ? .black.opacity(0.64) : .white.opacity(0.52))
            }
            .foregroundStyle(selected ? .black : .white)
            .padding(.horizontal, 13)
            .frame(minHeight: 45)
            .background(selected ? Color.white : XSV3.lifted, in: Capsule())
            .overlay(Capsule().stroke(selected ? .white : .white.opacity(0.10)))
        }
        .buttonStyle(XSV3PressStyle())
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityLabel("\\(name)، \\(count) قناة")
    }

''' +sports[cat_end:]

head_start=sports.index("    private var sectionHeader: some View {")
head_end=sports.index("    private var loadingState: some View {",head_start)
sports=sports[:head_start]+'''    private var sectionHeader: some View {
        HStack(spacing: 11) {
            VStack(alignment: .leading, spacing: 5) {
                Text("AR · SPORTS CHANNELS")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(2.0)
                    .foregroundStyle(XSV3.coral)
                Text(favoritesOnly
                     ? "القنوات المفضلة"
                     : (selectedCategoryID.flatMap { sportsCategoryName[$0] }
                        ?? "جميع القنوات الرياضية"))
                    .font(.system(size: 23, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                Text("\\(filteredStreams.count) قناة مطابقة")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(XSV3.muted)
            }
            Spacer(minLength: 4)
            Button {
                UISelectionFeedbackGenerator().selectionChanged()
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    compactList.toggle()
                }
            } label: {
                Image(systemName: compactList ? "square.grid.2x2" : "list.bullet")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(XSV3.lifted,
                                in: RoundedRectangle(cornerRadius: 15))
                    .overlay(RoundedRectangle(cornerRadius: 15)
                        .stroke(.white.opacity(0.10)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(compactList ? "عرض القنوات كشبكة" : "عرض القنوات كقائمة")
        }
        .padding(.horizontal, 22)
    }

    private var channelGrid: some View {
        Group {
            if compactList {
                LazyVStack(spacing: 9) {
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
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 155, maximum: 250), spacing: 12)],
                    spacing: 17
                ) {
                    ForEach(filteredStreams) { stream in
                        XSSportsChannelCardV33(
                            stream: stream,
                            category: sportsCategoryName[stream.categoryID] ?? "AR · SPORT",
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

''' +sports[head_end:]
sports=replace_one(sports,
                   'Text(favoritesOnly ? "ما أضفت قنوات للمفضلة" : "ما حصلنا قنوات AR")',
                   'Text(favoritesOnly ? "ما أضفت قنوات للمفضلة" : "ما حصلنا قنوات رياضية AR")',
                   "sports-only empty text")
sports=replace_one(sports,
                   'Text(favoritesOnly ? "اضغط النجمة بجانب القناة لإضافتها" : "جرّب تحديث القائمة أو تغيير البحث")',
                   'Text(favoritesOnly ? "اضغط النجمة بجانب القناة لإضافتها" : "غيّر القسم أو البحث، أو حدّث قائمة القنوات")',
                   "sports empty guidance")
sports=replace_one(sports,
                   '''                            selectedCategoryID = nil
                            query = ""''',
                   '''                            selectedCategoryID = nil
                            query = ""''',
                   "reset to all (explicitly unchanged)")
sports=replace_one(sports,'Text("جارٍ تحميل القنوات العربية…")',
                   'Text("جارٍ تجهيز القنوات الرياضية العربية…")',
                   "sports loading state")
sports=replace_one(sports,
                   'Text("AR · القنوات العربية")',
                   'Text("AR · الرياضة")',
                   "sports toolbar label")
sports=replace_one(sports,
                   '.accessibilityLabel("إعدادات سيرفر القنوات")',
                   '.accessibilityLabel("إعدادات سيرفر الرياضة")',
                   "server settings label")
# Do not edit XSSportsPlayerV33, XSVLCStableSurfaceView, provider URLs,
# credentials, or V6 source-based server and subtitle acknowledgement.
path.write_text(sports,encoding="utf-8")

root_path=Path("FrameNative/Views/EnhancedRootView.swift")
root=root_path.read_text(encoding="utf-8")
root=replace_one(root,'.tabItem { Label("القنوات", systemImage: "tv.fill") }',
                 '.tabItem { Label("الرياضة", systemImage: "sportscourt.fill") }',
                 "sports tab restored")
root_path.write_text(root,encoding="utf-8")

home_path=Path("FrameNative/Views/XSCinematicHomeView.swift")
home=home_path.read_text(encoding="utf-8")
home=replace_one(home,'Text("ARABIC LIVE TV")','Text("AR SPORTS LIVE")',"home live heading")
home=replace_one(home,'Text("قنواتك العربية")','Text("رياضتك العربية المباشرة")',"home title")
home=replace_one(home,'Text("قنوات AR المباشرة")','Text("القنوات الرياضية العربية AR فقط")',"home description")
home_path.write_text(home,encoding="utf-8")
print("V7 corrected AR sports-only source index, real sports sections, premium lazy browsing, original VLC preserved.")

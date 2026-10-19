"""V8: include *all* Arabic-tagged sports channels from full provider catalog.

V7 excluded channels whose individual names did not begin with AR even when
the entire source IPTV sports category was AR-labeled. V8 supports either AR
channel prefix OR AR provider sports section, while requiring a sports signal.
Runs after V7 as a presentation-only final postprocessor.
"""
from pathlib import Path

file = Path("FrameNative/Views/SportsLiveViewV33.swift")
source = file.read_text(encoding="utf-8")
start = source.find("    // V7_AR_SPORTS_ONLY:")
end = source.find("    private var filteredStreams:", start)
if start < 0 or end < 0:
    raise SystemExit("V8 sports patch: V7 classification anchors not found")

replacement = """    // V8_AR_SPORTS_COMPLETE:
    // The AR regional marker is carried EITHER by the channel name OR by
    // the provider's category (a common Xtream convention). This avoids the
    // V7 false negatives in AR sports groups with names like 'beIN HD 1'.
    // Sports membership comes from the real provider category, channel name,
    // or known Arabic/international sports broadcaster labels.
    private func sportsKeywordMatch(_ value: String) -> Bool {
        let upper = value.uppercased()
        let terms = [
            "SPORT", "BEIN", "SSC", "ESPN", "DAZN", "EUROSPORT",
            "MATCH", "FOOTBALL", "SOCCER", "ARENA", "F1", "FORMULA",
            "UFC", "WWE", "NBA", "NHL", "TENNIS", "RACING",
            "ALKASS", "AL KASS", "ALKAS", "KASS", "ADSPORT",
            "ON TIME", "ONTIME", "DUBAI SPORT", "AD SPORTS",
            "RIYADI", "RIYADIA", "ARRYADIA", "L'EQUIPE", "W SPORT",
            "GOAL", "STADIUM", "TIVIBU SPOR", "ZIGGO SPORT",
            "الكأس", "كأس", "الرياض", "الرياضية", "رياض",
            "مباريات", "مباراة", "كورة", "الكرة", "كرة القدم",
            "دوري", "بطولة", "ملاعب", "مصارعة", "سباق", "كرة السلة",
            "فورمولا", "أولمبية"
        ]
        return terms.contains { upper.contains($0) }
    }

    private func isARRegion(_ value: String) -> Bool {
        let t = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        return t.hasPrefix("AR") || t.hasPrefix("[AR]") ||
            t.hasPrefix("(AR)") || t.hasPrefix("عربي رياضة") ||
            t.hasPrefix("الرياضة العربية")
    }

    private func rebuildSportsIndex(categories: [IPTVCategory], streams: [IPTVLiveStream]) {
        let categoriesByID = Dictionary(
            categories.map { ($0.categoryID, $0.categoryName) },
            uniquingKeysWith: { first, _ in first }
        )
        let categorySports = Set(categories.filter {
            sportsKeywordMatch($0.categoryName)
        }.map(\\.categoryID))

        // A single provider scan; filter over the derived results on every
        // search or section switch. Do NOT refetch all channels on UI taps.
        let matches = streams.filter { stream in
            let name = stream.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let group = categoriesByID[stream.categoryID] ?? ""
            guard isARRegion(name) || isARRegion(group) else { return false }
            return categorySports.contains(stream.categoryID) ||
                sportsKeywordMatch(name)
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

"""
source = source[:start] + replacement + source[end:]
file.write_text(source,encoding="utf-8")
print("V8 sports coverage: AR-prefixed channels OR AR-tagged sports groups; real provider category membership.")

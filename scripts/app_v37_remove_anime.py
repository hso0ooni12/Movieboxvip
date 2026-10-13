from pathlib import Path

# V37: Remove Anime from the user-facing XS TV product.
# Keep the internal MediaKind.anime case for backward compatibility with old
# local data, but never load, surface, search, recommend, or display it.

root_path = Path("FrameNative/Views/EnhancedRootView.swift")
reference_path = Path("FrameNative/Views/ReferenceBrowseViews.swift")
search_path = Path("FrameNative/Views/GlobalSearchView.swift")
app_state_path = Path("FrameNative/Core/AppState.swift")
tmdb_path = Path("FrameNative/Services/TMDBClient.swift")

root = root_path.read_text(encoding="utf-8")
reference = reference_path.read_text(encoding="utf-8")
search = search_path.read_text(encoding="utf-8")
app_state = app_state_path.read_text(encoding="utf-8")
tmdb = tmdb_path.read_text(encoding="utf-8")

# --- Main navigation: remove the Anime tab completely.
anime_tab = '''            NavigationStack {
                XSReferenceCatalogView(kind: .anime, title: "Anime")
                    .xsGlobalSearchToolbar()
            }
            .tabItem { Label("Anime", systemImage: "sparkles") }

'''
if anime_tab in root:
    root = root.replace(anime_tab, "", 1)
if 'XSReferenceCatalogView(kind: .anime, title: "Anime")' in root:
    raise SystemExit("V37 failed to remove Anime tab")

# --- Home: remove Anime Spotlight rail.
reference = reference.replace(
    '                        XSReferenceRail(title: "Anime Spotlight", subtitle: "Popular animation and new discoveries", items: Array(app.anime.prefix(12)))\n',
    "",
)
if 'title: "Anime Spotlight"' in reference:
    raise SystemExit("V37 failed to remove Anime Spotlight")

# --- App state: never fetch Anime, never return it from catalogs/search, and
# hide any legacy Anime entries already saved in favorites/watch history.
old_load = '''            async let movies = client.trendingMovies()
            async let tv = client.trendingTV()
            async let popularMovieItems = client.popularMovies()
            async let popularTVItems = client.popularTV()
            async let animeItems = client.anime()
            let result = try await (movies, tv, popularMovieItems, popularTVItems, animeItems)
            trendingMovies = result.0
            trendingTV = result.1
            popularMovies = result.2
            popularTV = result.3
            anime = result.4
'''
new_load = '''            async let movies = client.trendingMovies()
            async let tv = client.trendingTV()
            async let popularMovieItems = client.popularMovies()
            async let popularTVItems = client.popularTV()
            let result = try await (movies, tv, popularMovieItems, popularTVItems)
            trendingMovies = result.0
            trendingTV = result.1
            popularMovies = result.2
            popularTV = result.3
            anime = []
'''
if old_load in app_state:
    app_state = app_state.replace(old_load, new_load, 1)
app_state = app_state.replace('        case .anime: return anime\n', '        case .anime: return []\n')
app_state = app_state.replace(
    '        let source = item.kind == .movie ? list(for: .movie) : (item.kind == .anime ? anime : list(for: .tv))\n',
    '        let source = item.kind == .movie ? list(for: .movie) : (item.kind == .anime ? [] : list(for: .tv))\n',
)
app_state = app_state.replace(
    '''    func search(_ query: String) async throws -> [MediaItem] {
        try await client.search(query)
    }
''',
    '''    func search(_ query: String) async throws -> [MediaItem] {
        try await client.search(query).filter { $0.kind != .anime }
    }
''',
)
app_state = app_state.replace(
    '''    var favoriteItems: [MediaItem] {
        favorites.values.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
''',
    '''    var favoriteItems: [MediaItem] {
        favorites.values
            .filter { $0.kind != .anime }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
''',
)
app_state = app_state.replace(
    '''        progress.values
            .filter { $0.currentTime > 5 && ($0.duration <= 0 || $0.fraction < 0.96) }
''',
    '''        progress.values
            .filter { $0.item.kind != .anime }
            .filter { $0.currentTime > 5 && ($0.duration <= 0 || $0.fraction < 0.96) }
''',
)

for forbidden in ["async let animeItems = client.anime()", "anime = result.4"]:
    if forbidden in app_state:
        raise SystemExit(f"V37 AppState still loads Anime: {forbidden}")

# --- Global search UX: no Anime wording and a second defensive result filter.
search = search.replace(
    '                Text("Movies, series and anime in one place")',
    '                Text("Movies and series in one place")',
)
search = search.replace(
    '            results = found\n',
    '            results = found.filter { $0.kind != .anime }\n',
)
if 'Movies, series and anime in one place' in search:
    raise SystemExit("V37 failed to remove Anime wording from search")

# --- TMDB search: reject likely Anime before creating TV search results. This
# prevents Anime from briefly entering app state and saves classification work.
old_tv_case = '            case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)\n'
new_tv_case = '''            case "tv":
                guard !result.isLikelyAnime else { return nil }
                return result.mediaItem(forcedKind: .tv)
'''
if old_tv_case in tmdb:
    tmdb = tmdb.replace(old_tv_case, new_tv_case, 1)

tmdb = tmdb.replace(
    '        return await filterUnsafeAnimeFromMixedResults(items)\n',
    '        return items.filter { $0.kind != .anime }\n',
    1,
)
if 'case "tv": return result.mediaItem(forcedKind: result.isLikelyAnime ? .anime : .tv)' in tmdb:
    raise SystemExit("V37 TMDB search still maps Anime into results")

# Marker used by CI to confirm V37 was applied after older generation scripts.
if "V37_ANIME_REMOVED" not in root:
    root = root.replace("import SwiftUI\n", "import SwiftUI\n\n// V37_ANIME_REMOVED\n", 1)

root_path.write_text(root, encoding="utf-8")
reference_path.write_text(reference, encoding="utf-8")
search_path.write_text(search, encoding="utf-8")
app_state_path.write_text(app_state, encoding="utf-8")
tmdb_path.write_text(tmdb, encoding="utf-8")

print("V37 Anime removal applied")

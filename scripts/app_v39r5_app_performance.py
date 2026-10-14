from pathlib import Path

APP_STATE = Path("FrameNative/Core/AppState.swift")
DETAIL = Path("FrameNative/Views/DetailView.swift")
MARKER = "V39R5_APP_PERFORMANCE"


def replace_once(source: str, old: str, new: str, label: str) -> str:
    if old not in source:
        raise SystemExit(f"V39R5: {label} marker not found")
    return source.replace(old, new, 1)


state = APP_STATE.read_text(encoding="utf-8")
detail = DETAIL.read_text(encoding="utf-8")

if MARKER not in state:
    state = replace_once(
        state,
        "import SwiftUI\n",
        "// V39R5_APP_PERFORMANCE: coalesce home loads and avoid duplicate refresh work.\nimport SwiftUI\n",
        "AppState marker",
    )
    state = replace_once(
        state,
        "        if didLoad && !force { return }",
        "        if isLoading || (didLoad && !force) { return }",
        "AppState loading guard",
    )

if MARKER not in detail:
    detail = replace_once(
        detail,
        "import SwiftUI\n",
        "// V39R5_APP_PERFORMANCE: skip movie season calls while preserving TV concurrency.\nimport SwiftUI\n",
        "DetailView marker",
    )
    old_load = """    @MainActor
    private func load() async {
        loading = true
        error = nil

        do {
            async let detailRequest = app.details(for: item)
            async let seasonRequest = app.seasons(for: item)
            details = try await detailRequest

            if item.kind != .movie {
                seasons = try await seasonRequest
                let preferred = saved?.season.flatMap { season in
                    seasons.contains(where: { $0.seasonNumber == season }) ? season : nil
                }
                let first = preferred ?? seasons.first?.seasonNumber
                selectedSeason = first
                if let first { await loadEpisodes(season: first) }
            }
        } catch {
            self.error = error.localizedDescription
        }

        loading = false
    }
"""
    new_load = """    @MainActor
    private func load() async {
        loading = true
        error = nil

        do {
            if item.kind == .movie {
                // Movies do not have seasons; avoid a needless second network request.
                details = try await app.details(for: item)
            } else {
                async let detailRequest = app.details(for: item)
                async let seasonRequest = app.seasons(for: item)
                details = try await detailRequest
                seasons = try await seasonRequest
                let preferred = saved?.season.flatMap { season in
                    seasons.contains(where: { $0.seasonNumber == season }) ? season : nil
                }
                let first = preferred ?? seasons.first?.seasonNumber
                selectedSeason = first
                if let first { await loadEpisodes(season: first) }
            }
        } catch {
            self.error = error.localizedDescription
        }

        loading = false
    }
"""
    detail = replace_once(detail, old_load, new_load, "DetailView load path")

APP_STATE.write_text(state, encoding="utf-8")
DETAIL.write_text(detail, encoding="utf-8")
print("V39R5 app performance patch applied")


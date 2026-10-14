from pathlib import Path

state = Path("FrameNative/Core/AppState.swift").read_text(encoding="utf-8")
detail = Path("FrameNative/Views/DetailView.swift").read_text(encoding="utf-8")

assert "V39R5_APP_PERFORMANCE" in state
assert "if isLoading || (didLoad && !force) { return }" in state
assert "V39R5_APP_PERFORMANCE" in detail
assert "if item.kind == .movie" in detail
assert "Movies do not have seasons; avoid a needless second network request." in detail

load_start = detail.index("    @MainActor\n    private func load() async {")
load_end = detail.index("\n    @MainActor\n    private func loadEpisodes", load_start)
load = detail[load_start:load_end]
movie_branch = load.index("if item.kind == .movie")
assert load.index("details = try await app.details(for: item)", movie_branch) > movie_branch
assert "async let seasonRequest" in load
assert load.index("async let seasonRequest") > load.index("} else {")
assert "async let seasonRequest" not in load[:movie_branch]

print("V39R5 QA PASS: duplicate home loads are coalesced and movies skip season metadata")


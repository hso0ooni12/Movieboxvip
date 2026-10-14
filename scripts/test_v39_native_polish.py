"""Regression guard for the V39 native-polish layer.

The checks intentionally protect the original source-owned subtitle selection
and server command path.  A UI enhancement must never replace either one.
"""
from pathlib import Path


def require(text: str, needle: str, label: str) -> None:
    if needle not in text:
        raise SystemExit(f"V39 native polish guard failed: missing {label}")


player = Path("FrameNative/FrameXTVPlayerV6.swift").read_text(encoding="utf-8")
adapter = Path("scripts/xs_source_subtitles.js").read_text(encoding="utf-8")
app_state = Path("FrameNative/Core/AppState.swift").read_text(encoding="utf-8")
search = Path("FrameNative/Views/GlobalSearchView.swift").read_text(encoding="utf-8")

# The browser bridge still delegates subtitle clicks to the exact source menu.
require(player, "sourceSubtitles.select(payload);", "source-owned subtitle command")
require(adapter, "choice.row.click();", "source subtitle row click")
require(adapter, "const loaded = wanted.id === 'off' ? tracks().length === 0 : !!trackFor(choice);", "subtitle cue-load acknowledgement")
require(adapter, "if (match && loaded)", "subtitle selection confirmation")
require(adapter, "if (panel()) { hidePanels(); resolve(true); return; }", "immediate source-menu fast path")
require(adapter, "later(verify, tries < 8 ? 90 : 250);", "safe fast subtitle acknowledgement polling")

# Server selection stays on the original name/provider payload and source DOM
# click path.  The polish is display-only.
server_start = player.index("    func selectServer(_ server: XSServerOption)")
server_end = player.index("\n    func selectQuality", server_start)
server_function = player[server_start:server_end]
require(server_function, 'var payload: [String: Any] = ["action": "server", "name": server.name]', "original server payload")
require(server_function, 'if let provider = server.provider { payload["provider"] = provider }', "original server provider")
require(server_function, "send(payload)", "original server send")
require(player, "function selectByText(text)", "source server DOM selection helper")

# Quality labels are normalized only from source text, never inferred from a
# stream URL or a fixed provider table.
require(player, "function sourceServerQuality(raw)", "source quality normalizer")
require(player, "const sourceQuality = (clean.match", "source quality extraction")
require(player, "quality:sourceServerQuality(sourceQuality)", "source-only quality assignment")
require(player, "private func nativeServerRow(_ server: XSServerOption)", "native server presentation")
require(player, "player.selectServer(server)", "native row preserves selection call")

# Small app-wide responsiveness changes are protected independently of player.
require(app_state, "guard !isLoading else { return }", "home-load coalescing")
require(search, "Task.sleep(nanoseconds: 220_000_000)", "faster search debounce")

print("V39 native polish guard PASS: source subtitle/server engines remain intact")

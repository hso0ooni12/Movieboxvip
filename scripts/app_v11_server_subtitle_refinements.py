"""V11 final player adjustments after all protected R5/V10 transformations.

Purpose: real source-owned server selection speed; complete subtitle list;
movie/episode-scoped subtitle timing. Never replace R5/Backup handoff,
V24 source-owned row selection, source cue-load ack, or VLC live drawable.
"""
from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV6.swift")
player = path.read_text(encoding="utf-8")

def one(old, new, label):
    global player
    count = player.count(old)
    if count != 1:
        raise SystemExit(f"V11 {label}: expected exactly one marker, found {count}")
    player = player.replace(old, new, 1)

# Most severe UX bug: subtitle timing was AppStorage-global. A +2 second
# offset chosen for one film was applied to every unrelated movie and episode.
# Every newly opened playback session starts at zero by design.
one(
    '    @AppStorage("XSTV.subtitleDelay") private var subtitleDelay = 0.0',
    '''    // V11_CONTENT_SCOPED_SUBTITLE_TIMING: never persist offset globally.
    @State private var subtitleDelay = 0.0''',
    "global subtitle delay replacement"
)
one(
    '''            installProgressHandler()
            player.setSubtitleDelay(subtitleDelay)
            pushSubtitleStyle()''',
    '''            installProgressHandler()
            // Reset a prior title's persisted delay on EVERY new player open.
            subtitleDelay = 0
            player.setSubtitleDelay(0)
            pushSubtitleStyle()''',
    "per-content initial delay reset"
)
one(
    '''        player.pause()
        player.reset()
        activePlayback = next''',
    '''        player.pause()
        player.reset()
        // The same screen may transition to the next episode: the new
        // content must never inherit its predecessor's subtitle offset.
        subtitleDelay = 0
        player.setSubtitleDelay(0)
        activePlayback = next''',
    "next-episode reset"
)
# Provide a clear, compact explanation without changing source caption layout.
one(
    '''                Text("If subtitles are late, increase the value. If early, decrease it.")''',
    '''                Text("If captions appear late, increase timing. Each movie and episode starts at 0.")''',
    "subtitle timing help"
)

# On server switching, old owner-scoped subtitle rows must be purged. Without
# this, a user could tap subtitle IDs belonging to the previous server while
# the newly selected source provider is still loading.
one(
    '''    func selectServer(_ server: XSServerOption) {
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1''',
    '''    func selectServer(_ server: XSServerOption) {
        clearSubtitleRequest()
        subtitleFrameID = nil
        subtitleGeneration = -1
        subtitleOptions = []
        subtitleScanFinished = false
        selectedSubtitleID = nil
        captionText = ""''',
    "server clears obsolete subtitle tracks"
)

# Source server switching stays single-tap and SOURCE-owned. Backup must not
# be tapped again during provider handoff. When source list is already ready
# selection is immediate; when opening menu, reduce the dead 220ms delay
# to 110ms. R5's confirmed handoff tail and backup semantics remain intact.
start = player.find("const finishDispatchedSelection = () =>")
end = player.find("else if (action === 'metadata')", start)
if start < 0 or end < 0:
    raise SystemExit("V11 unable to locate final R5 source server command")
server = player[start:end]
if "hideSourcePanels();" in server:
    raise SystemExit("V11 refuses to reintroduce hidden Backup handoff")
needle = """                  } else if (attempt < 2) {
                    setTimeout(() => trySelect(attempt + 1), 140);
                  }
                }, 220);"""
if server.count(needle) != 1:
    raise SystemExit("V11 R5 menu render retry timing changed")
server = server.replace(needle, needle.replace("}, 220);", "}, 110);"), 1)
player = player[:start] + server + player[end:]
assert "sourceSubtitles.select(payload);" in player
assert 'var payload: [String: Any] = ["action": "server", "name": server.name]' in player
assert "subtitleFrameID = nil" in player
path.write_text(player, encoding="utf-8")
print("V11: original source-owned servers with faster menu readiness; all subtitle IDs and timing reset per content.")

from pathlib import Path

path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = path.read_text(encoding="utf-8")

if "V36_COMPILE_COMPAT" not in sports:
    sports = "// V36_COMPILE_COMPAT: safe VLCMedia unwrap + deterministic stopped-state recovery.\n" + sports

# The pinned VLCKit imports VLCMedia(url:) as an optional. Never force unwrap a
# live URL; if construction fails, move to the next source cleanly.
old_media = '''        player.stop()
        let media = VLCMedia(url: urls[index])
        let options: [String: Any] = [
'''
new_media = '''        suppressStoppedUntil = Date().addingTimeInterval(0.75)
        player.stop()
        guard let media = VLCMedia(url: urls[index]) else {
            isPlaying = false
            userPaused = false
            statusText = "Stream unavailable"
            tryNextSource()
            return
        }
        let options: [String: Any] = [
'''
if old_media not in sports:
    raise SystemExit("V36 compat: VLCMedia construction block not found")
sports = sports.replace(old_media, new_media, 1)

# Current pinned VLCKit reports end/stopped playback through `.stopped` in its
# Swift enum surface. Explicit stops (source replacement / closing) are briefly
# suppressed so they can never trigger an accidental fallback.
state_anchor = "    private var hasPlayedCurrentSource = false\n"
if state_anchor not in sports:
    raise SystemExit("V36 compat: player state anchor not found")
sports = sports.replace(
    state_anchor,
    state_anchor + "    private var suppressStoppedUntil = Date.distantPast\n",
    1,
)

old_ended = '''        } else if state == .ended {
            isPlaying = false
            if !userPaused { reload() }
        }
'''
new_stopped = '''        } else if state == .stopped {
            isPlaying = false
            guard Date() >= suppressStoppedUntil else { return }
            if !userPaused { tryNextSource() }
        }
'''
if old_ended not in sports:
    raise SystemExit("V36 compat: ended state block not found")
sports = sports.replace(old_ended, new_stopped, 1)

# A real close is always intentional. Mark it paused before stop and suppress a
# possible stopped callback; the delegate is then detached as before.
old_stop = '''    func stop() {
        generation += 1
        fallbackTask?.cancel()
        recoveryTask?.cancel()
        userPaused = false
        player.stop()
        player.delegate = nil
'''
new_stop = '''    func stop() {
        generation += 1
        fallbackTask?.cancel()
        recoveryTask?.cancel()
        userPaused = true
        suppressStoppedUntil = Date().addingTimeInterval(0.75)
        player.stop()
        player.delegate = nil
'''
if old_stop not in sports:
    raise SystemExit("V36 compat: stop() lifecycle block not found")
sports = sports.replace(old_stop, new_stop, 1)

path.write_text(sports, encoding="utf-8")
print("Applied V36 compile compatibility: optional VLCMedia + safe stopped-state recovery.")

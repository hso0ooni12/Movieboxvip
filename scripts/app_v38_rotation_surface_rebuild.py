from pathlib import Path

sports_path = Path("FrameNative/Views/SportsLiveViewV33.swift")
sports = sports_path.read_text(encoding="utf-8")

# V38: Some MobileVLCKit live streams keep rendering into the previous
# portrait/landscape drawable geometry even after a detach/reattach of the SAME
# UIView.  The visible symptom is a correctly-playing picture stranded in one
# corner while the rest of the fullscreen player is black.
#
# The robust fix is to observe the ACTUAL SwiftUI viewport size after rotation,
# debounce until geometry settles, then recreate only the UIViewRepresentable
# drawable (new UIView + new coordinator) while leaving VLCMediaPlayer/media
# untouched.  The stream therefore stays alive, but VLC receives a genuinely
# fresh drawable with the final landscape/portrait bounds.

if "V38_ROTATION_SURFACE_REBUILD" not in sports:
    sports = "// V38_ROTATION_SURFACE_REBUILD: recreate only VLC drawable after settled viewport changes.\n" + sports

state_anchor = "    @State private var isDismissingPlayer = false\n"
if state_anchor not in sports:
    raise SystemExit("V38: dismissal state anchor not found")
state_replacement = state_anchor + '''    @State private var surfaceGeneration = 0
    @State private var lastSurfaceSize: CGSize = .zero
    @State private var surfaceRepairTask: Task<Void, Never>?
'''
sports = sports.replace(state_anchor, state_replacement, 1)

old_surface = '''            XSVLCVideoSurface(player: model.player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)
'''
new_surface = '''            GeometryReader { proxy in
                XSVLCVideoSurface(player: model.player)
                    .id(surfaceGeneration)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .onAppear {
                        observeSurfaceSize(proxy.size)
                    }
                    .onChange(of: proxy.size) { newSize in
                        observeSurfaceSize(newSize)
                    }
            }
            .transaction { transaction in
                transaction.animation = nil
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
'''
if old_surface not in sports:
    raise SystemExit("V38: final V36 surface block not found")
sports = sports.replace(old_surface, new_surface, 1)

old_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            // SwiftUI can transiently remount a full-screen hierarchy while the
            // device changes geometry. Only tear VLC down for a real close.
            if isDismissingPlayer {
                model.stop()
            }
        }
'''
new_disappear = '''        .onDisappear {
            controlsHideTask?.cancel()
            surfaceRepairTask?.cancel()
            // SwiftUI can transiently remount a full-screen hierarchy while the
            // device changes geometry. Only tear VLC down for a real close.
            if isDismissingPlayer {
                model.stop()
            }
        }
'''
if old_disappear not in sports:
    raise SystemExit("V38: V36 lifecycle block not found")
sports = sports.replace(old_disappear, new_disappear, 1)

helper_anchor = '''    private func closePlayer() {
'''
if helper_anchor not in sports:
    raise SystemExit("V38: closePlayer helper anchor not found")

surface_helpers = '''    private func observeSurfaceSize(_ size: CGSize) {
        guard size.width > 1, size.height > 1 else { return }

        // First valid layout establishes the baseline. A later size change is
        // the reliable signal that SwiftUI has actually changed orientation.
        if lastSurfaceSize == .zero {
            lastSurfaceSize = size
            return
        }

        let widthChanged = abs(size.width - lastSurfaceSize.width) > 1
        let heightChanged = abs(size.height - lastSurfaceSize.height) > 1
        guard widthChanged || heightChanged else { return }

        lastSurfaceSize = size
        surfaceRepairTask?.cancel()
        surfaceRepairTask = Task { @MainActor in
            // Rotation reports several intermediate layouts. Debounce them so
            // VLC is rebound once, using the final settled viewport dimensions.
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            surfaceGeneration += 1
            model.recoverAfterSurfaceChange()
        }
    }

'''
sports = sports.replace(helper_anchor, surface_helpers + helper_anchor, 1)

# A real close must also cancel a pending post-rotation remount.
old_close = '''    private func closePlayer() {
        controlsHideTask?.cancel()
        isDismissingPlayer = true
'''
new_close = '''    private func closePlayer() {
        controlsHideTask?.cancel()
        surfaceRepairTask?.cancel()
        isDismissingPlayer = true
'''
if old_close not in sports:
    raise SystemExit("V38: closePlayer body not found")
sports = sports.replace(old_close, new_close, 1)

sports_path.write_text(sports, encoding="utf-8")
print("Applied V38 rotation drawable rebuild fix")

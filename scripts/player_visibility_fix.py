from pathlib import Path

path = Path("FrameNative/FrameXTVPlayerV3.swift")
text = path.read_text()

old = '''                .id(activePlayback.id)
                .ignoresSafeArea()

                if !playerModel.captionText.isEmpty {
'''
new = '''                .id(activePlayback.id)
                .ignoresSafeArea()

                // Dedicated interaction surface above WebKit. The playback engine intentionally
                // has pointer events disabled, so this guarantees every tap can restore XS controls.
                Color.clear
                    .contentShape(Rectangle())
                    .ignoresSafeArea()
                    .onTapGesture {
                        revealControls()
                    }

                if !playerModel.captionText.isEmpty {
'''
if old not in text:
    raise SystemExit("interaction insertion point not found")
text = text.replace(old, new, 1)

old = '''            }
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.18)) { controlsVisible.toggle() }
                if controlsVisible { scheduleHide() }
            }
        }
'''
new = '''            }
        }
'''
if old not in text:
    raise SystemExit("old container tap handler not found")
text = text.replace(old, new, 1)

old = '''        .onChange(of: playerModel.currentTime) { _ in handlePlaybackProgress() }
        .onChange(of: subtitleDelay) { newValue in playerModel.setSubtitleDelay(newValue) }
        .onDisappear {
'''
new = '''        .onChange(of: playerModel.currentTime) { _ in handlePlaybackProgress() }
        .onChange(of: playerModel.isPlaying) { playing in
            if playing {
                scheduleHide()
            } else {
                hideTask?.cancel()
                withAnimation(.easeInOut(duration: 0.16)) { controlsVisible = true }
            }
        }
        .onChange(of: subtitleDelay) { newValue in playerModel.setSubtitleDelay(newValue) }
        .onChange(of: showServers) { presented in
            if presented { revealControls(autohide: false) } else { scheduleHide() }
        }
        .onChange(of: showSubtitles) { presented in
            if presented { revealControls(autohide: false) } else { scheduleHide() }
        }
        .onChange(of: showSettings) { presented in
            if presented { revealControls(autohide: false) } else { scheduleHide() }
        }
        .onDisappear {
'''
if old not in text:
    raise SystemExit("onChange insertion point not found")
text = text.replace(old, new, 1)

old = '''    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible else { return }
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled {
                await MainActor.run { withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false } }
            }
        }
    }

    private func bumpControls() {
        if !controlsVisible { withAnimation(.easeInOut(duration: 0.16)) { controlsVisible = true } }
        scheduleHide()
    }
'''
new = '''    private func scheduleHide() {
        hideTask?.cancel()
        guard controlsVisible,
              playerModel.isPlaying,
              !isScrubbing,
              !showServers,
              !showSubtitles,
              !showSettings else { return }

        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard playerModel.isPlaying,
                      !isScrubbing,
                      !showServers,
                      !showSubtitles,
                      !showSettings else { return }
                withAnimation(.easeOut(duration: 0.2)) { controlsVisible = false }
            }
        }
    }

    private func revealControls(autohide: Bool = true) {
        hideTask?.cancel()
        if !controlsVisible {
            withAnimation(.easeInOut(duration: 0.16)) { controlsVisible = true }
        }
        if autohide { scheduleHide() }
    }

    private func bumpControls() {
        revealControls()
    }
'''
if old not in text:
    raise SystemExit("scheduleHide block not found")
text = text.replace(old, new, 1)

path.write_text(text)
print("XS Player visibility patch applied")

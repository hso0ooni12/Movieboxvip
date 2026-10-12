from pathlib import Path

# Legacy V3 visibility patch kept for older source snapshots.
path = Path("FrameNative/FrameXTVPlayerV3.swift")
if path.exists():
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
    if old in text:
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
    if old in text:
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
    if old in text:
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
    if old in text:
        text = text.replace(old, new, 1)

    path.write_text(text)

# V6 compile normalization for SwiftUI frame overload.
v6 = Path("FrameNative/FrameXTVPlayerV6.swift")
if v6.exists():
    text = v6.read_text()
    old = '.frame(width: width, maxHeight: .infinity, alignment: .topLeading)'
    new = '.frame(width: width)\n            .frame(maxHeight: .infinity, alignment: .topLeading)'
    if old in text:
        text = text.replace(old, new, 1)
        v6.write_text(text)
        print("XS Player V6 frame patch applied")

print("XS Player build patches applied")

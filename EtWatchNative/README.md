# EtWatch Native — SwiftUI iPhone project

An actual native iOS app (SwiftUI + AVFoundation), **not** a WKWebView wrapper.
Only three tabs: movies, series, and football. It has a cinematic dark/teal UI,
search, poster rails, seasons/episodes, favorites, native fullscreen player,
server/quality menus, embedded HLS subtitle tracks, external SRT/WebVTT
subtitles, manual synchronization and appearance controls.

## Critical playback distinction

`etwatch.net` exposes public catalog metadata and server **names**, but the HTML
provided with this project does not provide a documented, licensed API that
returns persistent playable HLS/MP4 URLs and subtitle manifests. Some
site-injected names do not represent working streams. This app deliberately
does **not** reverse protected tokens, bypass DRM, hijack third-party sessions,
or open a site page disguised as a native player.

The public Cinemeta catalog populates discovery cards. **That is metadata only,
not entitlement to playback.** Video playback is enabled for entries with
direct HTTPS HLS/MP4 stream URLs supplied by an authorized content provider.
Without a configured feed the app includes only the Apple HLS sample stream
for engineering validation (`demo:apple-hls`), not actual EtWatch films or
football matches.

## Authorized stream feed

Set GitHub Actions repository **variable** `ETWATCH_NATIVE_FEED_URL` to a
publicly reachable HTTPS JSON endpoint you are entitled to use. (Do not put
private keys or bearer tokens in a URL or in an IPA.) The endpoint must return:

```json
{
  "version": 1,
  "entries": {
    "movie:tt0137523": {
      "sources": [
        {"id":"cdn1","label":"Main","quality":"1080p","url":"https://your-authorized-cdn.example/video/master.m3u8"}
      ],
      "subtitles": [
        {"id":"ar","label":"العربية","language":"ar","url":"https://your-authorized-cdn.example/subtitles/ar.vtt"}
      ]
    },
    "series:tt0903747:1:1": {"sources": [], "subtitles": []},
    "football:match-1": {"sources": [], "subtitles": []}
  },
  "football": [
    {"id":"match-1","title":"Home vs Away","competition":"League",
     "kickoff":"20:30","home":"Home","away":"Away","logoURL":null,
     "playbackKey":"football:match-1"}
  ]
}
```

Add as many distinct servers and native HLS renditions as the provider returns.
HLS "Auto/High/Medium/Data saver" is a bitrate cap, not a guarantee of
particular resolution. AVPlayer supports Apple-compatible video/audio codecs;
site-only encrypted embeds or special HTTP header requirements may not play.

## Build an unsigned IPA from iPhone only

1. Open this GitHub branch on your iPhone.
2. Under **Actions**, open **EtWatch Native - Build Unsigned IPA** and run it,
   or commit a change in `EtWatchNative/` to trigger a build automatically.
3. When it succeeds, open the run and download `EtWatchNative-Unsigned-IPA`.
4. In iOS Files, extract the artifact ZIP; import `EtWatchNative-unsigned.ipa`
   into eSign and sign it with your own certificate.

The workflow uses a macOS 15 GitHub-hosted runner, XcodeGen, Xcode, no code
signing, and uploads a 30-day artifact. `com.hsoooni.etwatchnative` is the
default bundle ID; change it if your signing profile requires another ID.

## Manual checks after installation

- Search should open the selected title's *detail* page, not jump home.
- Portrait and landscape should not shift/clip the native video layer.
- Embedded HLS subtitles are selected through AVFoundation's media selection;
  external SRT/VTT is rendered **in the same native player view as fullscreen**.
- Manual subtitle offset starts at zero for each title. Buttons allow +/-1 or
  +/-10 seconds without an arbitrary 60-second limit.
- Changing servers must use a new AVPlayerItem, preserve playback position,
  and fall back on failed/startup-stalled sources.
- Only valid direct streams from the configured feed should be offered.

No macOS device or Developer account is needed for the unsigned build. A valid
signing method is still required before installing on a physical iPhone.

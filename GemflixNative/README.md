# Gemflix — iPhone / SwiftUI + MobileVLCKit + In-App Playback

SwiftUI-first browsing for **movies and series only**. Navigation, posters,
discovery, search, favorites and episode screens are native iOS views. The
player uses VideoLAN MobileVLCKit when a provider supplies an authorized direct
stream. For titles available only through third-party video embeds, a confined
WKWebView displays **only the player inside the app**, without opening Safari.
The movie, series, search and detail views remain native SwiftUI.

## Real content and playback — important distinction

The app reads the public Gemflix homepage `home-seed` for featured movie
*metadata* and Cinemeta for browse/search and TV episode metadata. Gemflix
offers third-party HTML embed URLs for playback. These are webpage URLs,
**not direct native video streams**, and are never sent into the VLC decoder.
Instead the title opens the player within iOS using VidSrc NetMirror, VidSrc
Automatic/Primary, and VidLink as alternatives. Popup windows and unrelated
top-level advertising redirects are blocked.

Actual playback was verified in a browser with VidSrc NetMirror for the movie
*Avengers: Endgame* (TMDB 299534) and *Breaking Bad* season 1 episode 1
(TMDB 1396). This does not establish that each title will play on every iPhone:
source availability and behavior are controlled by third-party providers. Ads
inside the provider's own video surface cannot be guaranteed absent.

MobileVLCKit supports HLS, MP4, MKV and other media formats given genuine,
authorized stream URLs. This build includes the public Apple HLS sample **only
for player testing**. It is not a Gemflix movie.

## Optional authorized stream feed

The repository variable `GEMFLIX_STREAM_FEED_URL` can point to an HTTPS JSON
feed from a content provider that authorizes playback:

```json
{
  "version": 1,
  "entries": {
    "movie:tt1234567": {
      "sources": [
        {"id": "main", "label": "Main", "quality": "1080p", "url": "https://your-authorized-cdn.example/master.m3u8"}
      ],
      "subtitles": [
        {"id": "ar", "label": "العربية", "language": "ar", "url": "https://your-authorized-cdn.example/ar.vtt"}
      ]
    },
    "series:tt1234567:1:1": {"sources": [], "subtitles": []}
  }
}
```

Gemflix homepage titles are keyed like `movie:tmdb:1400940`; Cinemeta uses
IMDb IDs for its catalogue. There are only movies and series in the app.
Do not put bearer tokens or secrets in a public URL or IPA.

## Player functions

- VLC decoder and SwiftUI overlay for direct playback, ±10s seeking, speed.
- For embedded content: native full-screen presentation with a constrained
  WKWebView, native exit and source switcher, automatic fallback on hard errors.
- External subtitle files can be imported from the iPhone Files app, with
  independent timing, size, position and opacity over the embedded player.
- Source switching, 19-second startup timeout with failover, local resume.
- External SRT/WebVTT subtitles: ±0.5/1/10/60s offsets, font size,
  positioning down to 1pt and working backdrop opacity.
- VLC embedded subtitle and audio track selection. The extra appearance
  settings apply to **external overlay subtitles**, since VLC draws embedded
  captions internally.
- Quality menu lists the source variants actually supplied by the provider.
  Adaptive streams do not guarantee a manually selectable 4K variant.
- Landscape on entering the player, restoring portrait on leaving.

## Build and sign using iPhone only

The `Gemflix Native VLC - Build Unsigned IPA` GitHub Actions workflow compiles
the app for iPhone on a macOS runner and uploads `GemflixNative-VLC-unsigned.ipa`.
Download and extract the workflow artifact using your iPhone, then sign the IPA
with your existing eSign certificate. No laptop is required.

MobileVLCKit is sourced from `VLCKitSPM` at the revision already used in the
prior XS TV project. Observe VideoLAN's open-source licensing requirements.
This is a personal prototype, not an official Gemflix application.

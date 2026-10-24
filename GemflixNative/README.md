# Gemflix Native — iPhone / SwiftUI + MobileVLCKit

SwiftUI-first browsing for **movies and series only**. Navigation, posters,
discovery, search, favorites and episode screens are native iOS views. The
player uses VideoLAN MobileVLCKit with native SwiftUI controls; **no WebView,
iframe or browser is opened inside the app**.

## Real content and playback — important distinction

The app reads the public Gemflix homepage `home-seed` for featured movie
*metadata* and Cinemeta for browse/search and TV episode metadata. Gemflix
offers third-party HTML embed URLs such as `vidlink.pro/movie/{tmdbId}` for
playback. These are webpage URLs, **not direct native video streams**. The app
never sends those embeds to VLC or pretends they are playable media. If an
entry has no direct media URL, it explains that the source is unavailable.

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

- Native VLC decoder and SwiftUI overlay, ±10s seeking, playback speed.
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

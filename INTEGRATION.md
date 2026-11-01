# Watched Native — iOS 17+

The supplied homepage and Clayface Web Archives were inspected locally. Their public scripts provide title metadata, catalogue actions, provider rows, episode parameters, VOD request paths and response field usage. The repository includes only selected public metadata and compressed artwork; it excludes the original archives, browser state, account data, page scripts and signed media/subtitle URLs.

Implemented in this branch:

- SwiftUI home, movies, shows, search, detail, watchlist and settings screens; Arabic/English and RTL.
- Site colours and the homepage’s real featured titles and rows. No live channels screen or channel model.
- A native URLSession adapter for the observed HTML/Flight serialization and catalogue actions; no website execution.
- A clearly identified saved homepage when network refresh fails. Search fallback is limited to that saved copy.
- Film and episode buttons use the observed `/api/vod/server` JSON request with `server: jycdn`. Ordinary unavailable responses may use the observed `/api/vod/moviebox-fallback` request. A 401/403 or rate limit is terminal and is not worked around.
- A single AVPlayer/AVPlayerLayer, fullscreen, seeking/resume, quality selection from actual source metadata/HLS master renditions, embedded/external SRT/VTT captions, Arabic preference and manual timing. HLS quality limits retain the master playlist so alternate audio tracks are not dropped by selecting isolated variant playlists.
- Additional subtitles load from the observed `/api/vod/subtitles` request without delaying video. Allocated playback sessions are released on close. Temporary URLs/session values stay in memory.

## Source access

The observed clearance code uses `/api/vod/clearance` with Cloudflare Turnstile. This implementation does not fabricate clearance tokens, automate verification, copy browser session cookies or work around a 403. If native requests require web verification, a supported site API or an approved interactive authentication design will be needed. The app reports the access failure in that case.

## Validation limits

Fixtures come from the supplied page's public title data. Tests cover Flight and normalized detail/season parsing, VOD request fields, terminal 403 behavior, subtitle URL resolution and caption/HLS parsing. Native UI tests capture home/details in an explicit offline mode; they do not substitute sample video for a Watched title.

The GitHub workflow performs simulator unit/UI tests and builds/packages an unsigned iPhone/iPad app. A successful build does not validate live Watched playback. Live catalogue and playback remain unverified from the inspection network rejected by the site.

## Build

Run `xcodegen generate --spec project-watched.yml`, then build/test the `WatchedNative` scheme. Device builds are unsigned and need signing for installation. Version 0.2.0 includes the observed playback integration but is not represented as live-stream verified.

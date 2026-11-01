# Watched Native — iOS 17+

The supplied homepage, movie/show archives and Silo watch-page source were inspected locally. The Silo server-rendered payload identifies the initial stream, exact episode progress target, subtitles and server clearance status. The repository includes selected public metadata, compressed artwork and sanitized test fixtures; it excludes the original archives, account data, page scripts, captured tickets/cookies and signed media/subtitle URLs.

Implemented in this branch:

- SwiftUI home, movies, shows, search, detail, watchlist and settings screens; Arabic/English and RTL.
- Site colours and the homepage’s real featured titles and rows. No live channels screen or channel model.
- A native URLSession adapter for the observed HTML/Flight serialization and catalogue actions.
- A clearly identified saved homepage when network refresh fails. Search fallback is limited to that saved copy.
- Film and episode buttons first GET their canonical `/movie/{id}` or `/tv/{id}?s={season}&e={episode}` watch page and read its initial stream. The exact progress target must match, relative URLs are resolved and `cleared: false` is respected. Cached/archived stream links are never reused. The previous release incorrectly started at a protected server-switch API.
- Only a matched, cleared but unavailable initial stream can use the observed server-switch/fallback request. A denied request does not probe alternate routes. Expired playback can refresh its watch-page session once.
- A single AVPlayer/AVPlayerLayer, fullscreen, seeking/resume, quality selection from actual source metadata/HLS master renditions, embedded/external SRT/VTT captions, Arabic preference and manual timing. HLS quality limits retain the master playlist so alternate audio tracks are not dropped by selecting isolated variant playlists.
- Additional subtitles load from the observed `/api/vod/subtitles` request without delaying video. Allocated playback sessions are released on close. Temporary URLs/session values stay in memory.

## Source access

If the source asks for verification, an explicit native action opens a separate first-party verification sheet. WebKit is confined to this security step; no web film player is used by the app. The user completes the site's own check and chooses to return. Only that in-app first-party session is shared with the native client and AVFoundation using standard cookie APIs. No Safari cookies, archived tokens, fabricated clearance, automated challenge solving or browser/user-agent impersonation is used. If the site continues to reject the native request, its access failure remains visible.

## Validation limits

Tests reproduce the sanitized Silo payload across split script chunks and cover watch-page GETs, exact episode matching, relative stream/subtitle URLs, fresh leases, cleared-false handling, terminal access denial and first-party cookie boundaries. Native UI tests cover home/details and a cancellable, offline verification-sheet preview. A separate generated local MP4 smoke test requires AVPlayer to deliver real decoded frames. The test pattern is a test-target resource and is never substituted for a Watched title or shipped in the app.

The GitHub workflow performs simulator unit/UI tests and builds/packages an unsigned iPhone/iPad app. A successful build does not validate live Watched playback. Live catalogue and playback remain unverified from the inspection network rejected by the site.

## Build

Run `xcodegen generate --spec project-watched.yml`, then build/test the `WatchedNative` scheme. Device builds are unsigned and need signing for installation. Version 1.1.0 fixes watch initialization and adds explicit source verification; live Watched playback still requires validation on a network the site accepts.

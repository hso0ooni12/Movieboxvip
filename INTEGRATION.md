# Watched native integration — work in progress

The supplied `Home · watched.webarchive` was inspected locally. Its HTML and public JavaScript provide actual title metadata, catalogue actions, provider rows and episode-loading parameters. The repository includes only selected public title metadata and compressed artwork; it excludes the original archive, browser headers, cookies, page scripts and account data.

Implemented in this branch:

- SwiftUI home, movies, shows, search, detail, watchlist and settings screens; Arabic/English and RTL.
- Site colours and the homepage’s real featured titles and rows. No live channels screen or channel model.
- A native URLSession adapter for the observed HTML/Flight serialization and catalogue actions; no website execution.
- A clearly identified saved homepage when network refresh fails. Search fallback is limited to that saved copy.
- A single AVPlayer/AVPlayerLayer implementation with source selection, embedded/external SRT/VTT captions, manual timing, resume state, cancellation and cleanup.

## Blocking dependency

The homepage archive contains no VOD watch-page JavaScript, playback response, direct movie stream URL or subtitle response. The native player is therefore **not connected** to the movie buttons. The browsing preview displays an explicit pending-playback message and uses no sample video in place of the requested content.

Required next input: a Web Archive of a film watch page, saved after playback starts. A series watch-page archive is also useful for confirming episode playback parameters.

The observed clearance code uses `/api/vod/clearance` with Cloudflare Turnstile. This implementation does not fabricate clearance tokens, automate verification, copy browser session cookies or work around a 403. If native requests require web verification, a supported site API or an approved interactive authentication design will be needed.

## Validation limits

Fixtures come from the supplied page’s public title data. The local environment has no Apple SDK. The GitHub workflow performs simulator unit/UI tests and an unsigned device build when repository workflow permissions permit it. A successful build does not validate live Watched playback. Live catalogue refresh also remains unverified from the blocked inspection network.

## Build

Run `xcodegen generate --spec project-watched.yml`, then build or test the `WatchedNative` scheme. The deployment target is iOS 17. Device builds are unsigned and must be signed by the installer. Version 0.1 is a browsing preview, not a completed streaming release.

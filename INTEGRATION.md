# Watched — iOS 17+

Version 1.2.0 keeps SwiftUI browsing and replaces the active native-playback launch with the website's own player, as requested after native source access continued to fail on the user's phone.

## Playback and return

- Tapping a film or episode immediately presents one fullscreen WKWebView at `https://watched.cx/movie/{id}` or `/tv/{id}?s={season}&e={episode}`. No native stream-resolution request runs before presentation. Saved resume time is included only for the matching episode.
- The website owns video playback, quality, subtitles, session refresh and any interactive verification. The persistent default WebKit data store retains its ordinary in-app website session. No Safari session, captured tickets, custom user agent, clearance fabrication or automated security check is used.
- A native close button always returns to the original SwiftUI detail/episode list. The site's own Back button, regular links to browsing/home, Next.js history changes out of a watch route and the iPhone video fullscreen Done event also dismiss the player instead of opening the website catalogue.
- Next-episode watch routes stay in the same web player. External windows cannot replace the app. Normal HTTPS provider/security subframes remain available.
- Progress events contain only the watch-page target and playback timing. The app keeps matching-title progress; no media URLs, tokens, page contents or cookies are extracted by the player bridge.
- Closing pauses and unloads the web document. Reopening creates a new player. Detail data and the selected season remain intact when the modal closes.

## Browsing

The home, movie/show catalogue, search, detail, watchlist and settings remain native SwiftUI, with Arabic/English and RTL. There is no channels tab. The metadata adapter still reads the supplied site's HTML/Flight data. A saved homepage is clearly identified when a live refresh fails. Original web archives, account data, captured tickets/cookies and signed media/subtitle URLs are not shipped.

The earlier AVPlayer implementation and its parsing/decoder tests remain in the repository, but film/episode buttons no longer launch it. Subtitle and quality preferences now belong to the website player and the app settings explain where to change them.

## Validation

Unit tests cover exact direct movie/episode URLs, fresh player identity, return-to-app routing, next-episode handling and external-window boundaries. Simulator UI tests use an explicitly labelled offline HTML navigation fixture to exercise native close, website Back, SPA Back, fullscreen Done, exact episode selection and reopening while preserving the episode list. The fixture is compiled only in DEBUG and does not ship in the release IPA. No sample film is substituted for site content.

The GitHub workflow runs unit/UI checks and packages an unsigned arm64 iPhone/iPad IPA. Live Watched playback remains unverified from the inspection network rejected by the source. Device signing and the website's own normal access checks still apply.

## Build

Run `xcodegen generate --spec project-watched.yml`, then build/test the `WatchedNative` scheme. Version 1.2.0 uses the website player for playback and returns directly to the native app on close.

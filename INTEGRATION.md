# Watched — iOS 17+

Version 1.3.0 replaces the customized WKWebView player with Apple's genuine SFSafariViewController after the user demonstrated the same title/provider playing in Safari and remaining at Connecting in the app. Those screenshots establish a compatibility difference, not the precise failing request or cause.

## Playback

- A film/episode tap directly builds the canonical HTTPS watch-page URL. No native stream-resolution request runs before opening it. The selected season/episode is preserved; stale native resume timing is no longer injected.
- A small UIKit presentation host calls `present(_:animated:)` to display the real Safari controller modally. Safari is never embedded as a child, hidden behind another view or covered by a custom player toolbar.
- There is no player script injection, navigation interception, history replacement, custom user agent, cookie transfer, certificate exception, provider proxy or custom content blocker. The source controls playback, subtitle/quality selection, verification and its own browsing session.
- Safari's visible system Close (x) control dismisses directly to the original native detail/episode list. A single presentation guard handles repeated taps. Closing and reopening creates a fresh Safari controller while preserving native selection and scroll state.
- Website Back and fullscreen controls now behave as the website/system defines them. Their navigation cannot be intercepted by this app in SFSafariViewController. Use the system Safari Close button to return to the native app. No claim is made that existing Safari app cookies are shared or that the screenshots' exact cause is proven.

## Browsing

The home, movie/show catalogue, search, details, watchlist and settings remain native SwiftUI with Arabic/English and RTL. There is no channels tab. The earlier native decoder and source-verification implementations remain in the repository, but film/episode buttons do not launch them. The app does not inspect live Safari page content or track Safari playback progress.

Original web archives, account data, captured tickets/cookies and signed media/subtitle URLs are not shipped.

## Validation

Unit checks validate direct movie/episode targets and instantiate Apple's actual Safari controller with its system Close control. Simulator UI checks open the real Safari service against a DEBUG-only loopback HTML fixture, then exercise closing, ordinary website navigation, exact episode selection and reopening. The fixture is explicitly labelled offline, contains no substitute film, binds only to loopback and is not compiled into the release IPA. No mock browser is used to stand in for Safari UI.

Successful tests establish app presentation/return behavior. Live Watched playback and the user's specific Trojan stream remain unverified from the inspection network rejected by the source.

## Build

Run `xcodegen generate --spec project-watched.yml`, then build/test the `WatchedNative` scheme. Version 1.3.0 is an unsigned arm64 iPhone/iPad app for iOS 17+, requiring signing for installation.

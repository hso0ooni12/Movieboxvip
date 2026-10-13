# XS TV V24 subtitle repair

The current `build-native-ipa.yml` builds V24 (2.0.24). It applies the working
V11 playback baseline followed by `player_v24_source_menu_bridge.py`. Historical
V21–V23 workflows are retained for old builds; their subtitle hooks are not used
by the current workflow. Do not apply them on top of V24.

## Root causes verified against FrameXTV's public player source

- `controls=0` maps to `hideControls=true`. The player conditionally omits the
  toolbar containing the CC button. DOM activation could not work with this URL.
- The source combines subtitle arrays from multiple requests before rendering
  its menu; network-array indexes are not source-menu indexes.
- Source rows have a separate checkmark span. Whole-row text matching can fail
  after a language is already selected.
- The source loads/parses a subtitle and creates a populated **hidden** TextTrack
  while its own cue overlay renders the text. An optimistic click acknowledgement
  or independently inserted track does not establish successful source selection.
- Document-start injection can run before `documentElement` exists. Observing a
  null element aborted initialization before the recurring bridge work was set up.

## Behavior

Keep `controls=1` so the source CC component exists. Visually hide only control
containers and popup panels that do not contain video/iframes. Discover subtitle
rows in that CC component, preserving duplicate labels with distinct identities.
Click the exact row through its normal handler, and confirm both the source's
checkmark and a matching loaded cue track. Off uses the source Off row.

Commands and acknowledgements are scoped to a document/frame, source generation
and selection request. Rapid selections and server changes invalidate old work.
Failed loading is shown in the subtitle panel instead of interrupting playback.
Default rendering stays with the source player. XS style applies to its dedicated
cue element; nonzero timing adjustment uses the same source-loaded cues.

## Validation

The workflow runs DOM regression tests using a fixture reproducing the public
source CC markup and its asynchronous hidden-TextTrack behavior, then compiles a
Release iPhoneOS app. Tests include Arabic selection, checkmarks, duplicate names,
Off, rapid changes, stale frames/servers, loading failure and document-start setup.

These tests are not a live iPhone playback test. The live cloud-browser session
returned to about:blank, so subtitle availability/load success for an individual
provider still needs verification on the signed device build.

Source inspected 2026-10-13: FrameXTV `EmbedPage-CgbwE_v6.js` and
`Player-BWTuYVh6.js`. The adapter intentionally uses the visible CC component,
not React internals, guessed network indexes, or inferred subtitle URLs.

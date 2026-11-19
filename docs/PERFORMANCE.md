# Performance and concurrency

This slice preserves the screens, raw measurements, chart semantics, corrections,
and Health ownership rules. It changes where and how often work happens.

## Four stages

1. **Measure and protect behavior.** `ZoopData` tests compare rolling values with
   the original calculation, check exact dates/DST, chart window boundaries,
   cancellation and cache isolation. `PerformanceNavigationTests` records Trends
   interactions and screenshots using synthetic history.
2. **Reduce UI work.** Property-level Observation replaces root change forwarding.
   Live heart rate, temperature and the timeline marker update in their own views.
   Trends prepares all series on history/range changes. Weight draws the visible
   window and neighbouring line endpoints, retaining all recorded values, selection,
   gaps, scrolling bounds and accessibility actions.
3. **Reduce data work.** GET reuse is bounded to 64 entries / 8 MiB, scoped by URL
   and credentials, with a 10-second lifetime for summaries. Mutation invalidation
   prevents cache reuse without interrupting unrelated callers. Each caller owns a
   cancellation lease. API decoders reuse date parsers within one decode. Trends
   requests compact night summaries. Weight sync uses a paginated change cursor,
   including tombstones, with a full-history fallback for older servers.
4. **Harden lifecycle and maintenance.** SQLite setup/counts and Health journal I/O
   run off the UI executor. Atomic journal revisions prevent delayed settings writes
   overwriting newer receipts. Sleep/workout corrections share a store with scope
   and request fences; follow-up checks fetch affected identities. Reset polling is
   bounded and always clears its busy state. Complete Swift concurrency checking,
   app-state tests and unsigned CI builds cover the shared paths.

## Data safety

Frames still reach durable SQLite storage before a history acknowledgement, and
only a complete validated server receipt removes them. Captured frames retain
Bluetooth source identity; a source binds once to its reported strap serial. An
old unscoped backlog is retained for explicit recovery, never guessed to belong to
another strap. This migration does not discard or rewrite its original bytes or
upload identity. The diagnostic error identifies any such retained backlog.
After explicitly confirming that backlog belongs to the currently connected strap,
a developer can launch the app once with `-recoverLegacyFrames`. This binds only
unscoped rows on the next live serial binding and submits them through normal
receipt validation. The flag is not persisted and is never enabled automatically.

Health journals remain scoped by connection and strap. Per-page cursors are saved
with the records they acknowledge. Imported readings are never re-exported as
Zoop measurements. Workout exports use [Apple's workout builder](https://developer.apple.com/documentation/healthkit/hkworkoutbuilder);
its completion saves the workout, so there is no second save call.

## Repeatable checks

```sh
for package in ZoopProtocol ZoopSync ZoopBattery ZoopHealth ZoopData; do
  swift test --package-path "Packages/$package"
done
xcodegen generate
xcodebuild -scheme Zoop -configuration Release \
  -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO \
  SWIFT_TREAT_WARNINGS_AS_ERRORS=YES build
xcodebuild -scheme Zoop -destination 'platform=iOS Simulator,name=Zoop UI Review' \
  CODE_SIGNING_ALLOWED=NO -only-testing:ZoopTests test
```

UI tests require an isolated synthetic backend. `PerformanceNavigationTests`
uses loopback port 28476 by default. For other suites pass
`TEST_RUNNER_SNOOP_UI_SERVER_URL=http://127.0.0.1:28476` to `xcodebuild`.
The backend's `tools/performance-fixture.sql` supplies one year of summaries,
1,022,000 samples and 730 weights; apply only to a fresh development database.
Run its API with history analysis disabled to keep the visual fixture stable.
Correction/reset database tests use a different schema per test.

Use Instruments' SwiftUI / CPU Profiler / Animation Hitches templates with the
`Zoop` performance signposts: `Trend preparation`, `API decode`, and
`Health journal save`. Measure Release on the same device, with a connected strap,
while switching ranges, scrolling, receiving history, and syncing Health. Keep
personal data and credentials out of traces attached to public issues.

## Validation recorded for this slice

- 90 package tests, 4 app-state tests and 5 UI tests passed; strict simulator
  checks and the signed Release build passed with no Swift compiler warnings.
- Original and updated Trends screenshots match pixel-for-pixel below the status
  bar for the same synthetic fixture.
- Trends range switching, scrolling, tab return, Yesterday navigation, and Weight
  period swipes pass in the simulator. The original idle-scroll CPU measurement
  targeted the UI-test runner, so it is not app CPU evidence; the follow-up benchmark below corrects that target.
- Physical iPhone check: user confirmed smooth Trends scrolling/range switching
  and unchanged charts while connected to the strap. No phone screen capture or
  debugger attachment was used.
- On the synthetic 1,022,000-sample fixture, the original 30-day SQL scan took
  763 ms; the final warm 30-day endpoint took a median 12 ms including the local
  connection. Cold year preparation remained around 0.7 s. These are development
  measurements, not production latency or phone frame-rate claims.
- Backend `just ci` and 34 database-backed tests passed. Checks include cold/warm equivalence to the original query, DST, late
  sample changes, concurrent ingestion/cache creation, weight cursor upgrade,
  tombstones and existing correction/reset/Health regressions.

Production backend deployment is a separate step. The app remains compatible with
an older backend, but server-side performance benefits require migrations 0010 and
0011 and the matching server binary. No detection algorithm version is changed.

## Interactive Trends follow-up

Selection state lives inside `TrendChartCard`, separate from the heat strip and
weekday chart. Binary lookup selects an actual daily point across gaps; it never
reports an interpolated or rolling value. Main sleep details load on demand from
the existing session endpoint, with cancellation/request guards. A changed sleep
must substantially overlap the selected main sleep; a nap is never substituted.

Validation: 15 data-package tests, 6 app-state/matching tests, 4 chart-interaction UI
tests and the existing Trends performance navigation test passed. The unselected
screen is pixel-identical below the status bar to the performance build. Tests cover
vertical scrolling over the chart, selection/reset without layout movement, detail
navigation/back, metric/range changes and the largest text size in dark appearance.
VoiceOver actions are implemented; physical VoiceOver interaction is not yet verified.

## Range-switch follow-up

Changing 7/30/90/Year previously changed the chart identity, prepared every metric
before and after a range-specific reload, and discarded wider day history when
loading a smaller range. A tap could therefore show an interim range and render
again when its response arrived.

Trends now fetches at most one year of compact summaries and prepares all four
ranges off the UI executor in one immutable snapshot. Picker changes select an
already-prepared series and clear only inspection state. The chart keeps its
identity, and the unchanged sleep heat map is an equatable child. Refresh, tab
entry, foreground return and analysis/correction changes update history; ranges do
not trigger requests. Source/request/cancellation guards still fence stale results.
The initial compact read is larger for accounts with extensive history, bounded to
365 summaries of each kind, to keep subsequent range changes local.

`TrendRangePerformanceTests` measures the app process explicitly. In the same
Release simulator and synthetic fixture, six 7/30-day changes averaged 12.45 billion
retired CPU instructions before and 8.66 billion after (30% less); cycles fell from
4.55 billion to 3.31 billion (27% less). CPU time averaged 1.65 s versus 1.47 s, but
varied more. XCTest's tap/idle waits dominate wall-clock duration, and simulator
hitch recording is unsupported: these figures do not establish physical frame rate.
The final comparison used no profiler attached. The unselected month screenshot
matched pixel-for-pixel below the status bar.

Twelve app tests and six affected UI tests passed, including calendar cutoffs, absent
steps, all metrics, retained larger ranges, source changes, cancellation, selection,
detail/back navigation, vertical scrolling and largest text. Both range and scroll
CPU/memory metrics now target the app instead of the UI-test runner.

The range-switch follow-up is built for the phone; physical confirmation remains
pending until the device is reconnected.

# Build 96 independent verification

**Status:** Build 97 (`0.9.64+97`, algorithm 97, schema 50) implements all seven faults
found in released Build 96 source `f05969f0`. Local desired-behavior regressions pass;
full cloud checks, visual artifacts and the replacement IPA are pending. Build 96 remains the
cached candidate until replacement validation. No phone installation or acceptance is inferred.

## Repair contract and verification

- B96-01: stage the exact final session payload alongside the captured profile and HR/zone trace
  in WorkoutClock before GPS/final-row writes; cold retry replays it, including after six hours.
  Preserve current privacy/RPE and keep older traces without fabricating missing peaks/means.
- B96-02/03/04: exclusive photo-file creation cannot replace another save's file. Reject repeated
  incoming photo IDs, impossible calendar days (including baseline/tape/photo dates), unsafe
  basenames and unsupported weight units before import writes. Storage entry points validate too.
- B96-05: failed preference writes reload authoritative storage, so optimistic cache state cannot
  make Retry appear durable. False and thrown writes cover individual/all-read and cold reload.
- B96-06: retained device detail reloads health/forecast on committed battery revisions and return
  to foreground; generation guards reject late reads. Charging immediately suppresses discharge
  predictions. Unrelated live notifications do not trigger battery-history reads.
- B96-07: one safe basename policy carries underscore, short, dotted, spaced and Unicode legacy
  names. Export validates references from the database snapshot; media restore checks referenced
  files before committing database rows. Missing/unsupported references fail explicitly.
- Enhancements: quieter one-day Body state with all history/charts retained; notification
  submission/due/legacy provenance; a parallel cloud synthetic visual-smoke job with full-scroll
  captures and an inspectable image index. Body deletion Undo is deferred because its profile
  and photo recovery semantics need their own contract.
- No dependency, scientific coefficient, schema, algorithm version, signing capability or BLE ACK
  order changed. Unnecessary private-derived details were removed from a source comment.

Focused evidence: ten integrity checks (`test/build97_integrity_test.dart`), five notification
checks (`test/build97_notification_test.dart`), one retained-device widget check
(`test/build97_device_test.dart`), and nine normal/enlarged full-scroll render cases
(`test/build95_repair_render_test.dart`) pass locally: 25 checks. A static refinement preview
preceded the UI edits; actual Flutter captures were inspected at normal and enlarged text.
They use synthetic data and a Windows font substitute. Cloud evidence will be recorded after it
finishes; no successful diagnostic assertion from the original fault harness is counted as a fix.

## Original Build 96 findings

The following descriptions refer to the old Build 96 IPA, not unfixed Build 97 source.
This independent application/data-flow review used source tracing and runnable fault probes;
Impeccable supplied a secondary UI checklist. No private export was opened or uploaded.

## Confirmed faults

### B96-01 · P1 · Restart after a failed finish can erase saved workout evidence

- Flow: record a workout with HR → final session insert fails → close/restart the app → Retry saving.
- The stopped clock and its saved HR/zone arrays survive. However, orphan reconciliation creates a
  new empty `LiveWorkoutState` and returns when the clock is closed. Retry then overwrites the
  saved arrays using that empty accumulator and saves absent average/peak HR.
- Reproduced with no raw-band records to rescue the result: the original saved trace became empty,
  and the final row's HR fields became null. The session ID/end survive; this is not a claim that
  every failed finish loses the entire workout.
- Source: `lib/state/app_state.dart:4972` / closed-clock branch near 5003, final arrays near 5149;
  `lib/gps/workout_clock.dart`; historical consumers in `workout_screen.dart`.
- Fix: durably stage the complete measured final-save payload before attempting the session write.
  A cold-restart retry must replay that payload, not rebuild it from a blank live accumulator.
  Preserve exact saved evidence; do not invent one-second samples from minute means.
- Required regression: fail final insert, reset process-owned state, reconcile, retry; assert
  identical duration/end/profile/privacy, HR trace, zones and measured summary fields.
  This extends the earlier B95-19 same-process retry test.

### B96-02 · P1 · Duplicate Body photo IDs can destroy the first imported file

- Flow: import a Body manifest containing the same photo ID twice, with its selected JPEG.
- Preflight checks only IDs already in the database, not duplicates within the incoming list.
  The first photo commits. The second attempt overwrites its file, hits the database PK, then its
  failure cleanup deletes that file. The first photo row is left pointing to a missing image.
- Source: `lib/data/body_log.dart:863`–photo-plan loop; `BodyLogDb.addPhoto` near 635.
- Fix: reject/deduplicate incoming IDs before any write, and make photo publication collision-safe.
  A failed attempt must never remove or replace a file belonging to an existing committed row.
- Required regressions: duplicate manifest; repeated/stale preview; injected insert failure with
  a pre-existing file. Verify both database references and original bytes.

### B96-03 · P2 · Impossible Body dates are accepted

- Flow: import a generated Body-history weight with a nonexistent calendar date.
- `_validDay` uses a format regex plus `DateTime.tryParse`. Dart normalizes some invalid dates.
  Reproduced: a February 31 label was stored while its reading timestamp fell in March.
- Source: `lib/data/body_log.dart:738`, `planBodyImport`, `putWeight`.
- Fix: require the parsed calendar date to round-trip exactly to the supplied label. Use the same
  validation for weight, tape, photo and declared baseline dates. Reject the file before changes.
- Required regression: invalid day/month, leap-year and valid-date controls; no rows land on rejection.

### B96-04 · P2 · Unknown imported weight units silently become kilograms

- Flow: generated Body-history import declares an unsupported unit.
- The importer and weight validator special-case lb and treat every other string as kg.
  A supported-date probe independently reproduced the unsupported unit being saved as kg.
  Imported weights remain history-only, but their body history/goal evidence is still wrong.
- Source: `lib/data/body_log.dart:258`, `planBodyImport` near 816.
- Fix: accept only the documented kg/lb values. Any new unit needs an explicit supported
  conversion; never infer it from an unknown string.
- Required regression: kg/lb preserve physical quantity; unsupported/blank malformed units reject
  before writing any imported record.

### B96-05 · P2 · Failed notification-read writes can appear saved after Retry

- Flow: Mark read → preference storage refuses the write → Retry/reload → reopen after restart.
- SharedPreferences changes its in-memory cache optimistically. The first action reports failure,
  but a later read sees the uncommitted read flag. The same-content write shortcut skips retrying
  persistence; the page/bell can look successful until a cold reload restores unread state.
- Source: `lib/notify/notification_log.dart:129` / changed check near 137, `markRead` near 354.
- Reproduced with a refusing preference store: only one log write was attempted, retry returned
  a read entry, and cold-cache reload returned the durable unread entry.
- Fix: restore/reload the authoritative state after a refused write, or explicitly retain a dirty
  pending write and retry it. Only durable success may clear the error/update the saved read state.
- Required regressions: false and thrown writes, Mark read/Mark all read, retry then cold reload.

### B96-06 · P2 · Band detail can retain an obsolete battery forecast

- Flow: leave band detail open → new battery/charging data arrives.
- Live percentage/charging/name correctly follow AppState, but the forecast and charge-health
  queries run only in `initState`. A new charging state can coexist with the old discharge forecast.
- Source: `lib/ui2/profile/devices.dart:560`, `_loadForecast` and `DeviceDetailView`.
- Reproduced in a widget test: charging changed, the retained forecast object stayed usable, while
  recomputing the existing forecaster against the new committed samples correctly abstained.
- Fix: refresh on relevant durable battery/charging changes and foreground return, with stale-read
  protection. Do not query the database on every live-HR tick. Use the unchanged existing estimator.
- Required regression: battery update/charger attach and detach while retained; late reads cannot
  reinstall an older forecast. Actual band event delivery still needs the phone.

### B96-07 · P1 · A photo accepted by Body import can be silently excluded from backup

- Flow: import a photo with a normal, safe filename whose ID contains an underscore → encrypted
  database-plus-photos backup.
- Body import accepts and stores it, but the media packer only admits a narrower alphanumeric/
  hyphen filename regex. The library contains a real file, yet the media count/ZIP omits it.
  Restore can therefore bring back its database row without its photo.
- Reproduced through preflight and apply, then both the real media counter and ZIP packer.
- Source: `lib/data/body_log.dart` photo import; `lib/data/media_backup.dart:20`, count/pack/unpack.
- Fix: share a safe filename policy across import, storage, pack and restore. Preserve already
  accepted safe files, and report any genuinely unsupported/missing references explicitly.
  Do not solve this by silently dropping photos or by allowing archive path traversal.
- Required regression: imported photo → media backup → restore, including underscore/legacy
  safe names; file bytes/references/counts agree. Unsafe names are rejected before publication.

## Evidence and limits

The ignored `build/research-local/build96_deep_probe_test.dart` ran eleven named checks in the
final targeted run (about five seconds after compilation), recorded in
`build/audit96-probe-final.log`. They comprise:

- Eight diagnostic cases demonstrating the seven functional faults (one combined validation
  case was followed by independent date/unit cases).
- One storage-helper path-hardening diagnostic.
- Two positive controls: an ordinary valid photo/weight import remains intact and history-only;
  filename-only picker input does not resolve a traversal photo ID.

The diagnostic assertions deliberately describe the observed broken behavior. Their successful
test-run exit is reproduction evidence, not eleven healthy-flow regressions. The first harness
run had a log-file cleanup race; adding the existing log barrier resolved that harness error.
No real database, image, sensor trace or personal measurement was used.

The helper can be called with a crafted path-bearing ID, but the ordinary file-picker path uses
basenames and did not resolve that selection. Archive restore already rejects traversal paths.
It is a hardening opportunity, not an additional confirmed end-user exploit in this report.

The prior release's 3,403 passing tests remain tied to `f05969f0`. Of its 429 skips, 408 were
golden-image cases; the remaining cases depend on unavailable fixtures or opt-in measurements/
profiling. A green result is not a pixel/gesture pass over every possible page state.
Existing approved Body/Notifications captures were re-inspected; they are synthetic Windows
Flutter captures with a font substitute, not new native-iPhone screenshots.

## Flow families reviewed

This is an evidence map, not a claim that every possible click sequence was executed.

| Family | Paths traced | Current conclusion |
|---|---|---|
| Today/heart | card destinations, 10 min/hour/day cursor bounds, latest finite recorded point, freshness | Existing range guards retained; native scrubbing and new samples still need phone evidence. |
| Trends/metrics | range/date propagation, retained revision reload, stale-read tokens, metric factory and day links | No additional confirmed fault in these paths; numerical/visual combinations are not exhaustively executed. |
| Food | calendar/day notification route, meal detail, quantity/unit edits, saved foods/meals, filtered/grouped drag, copy review and transactional writes | Earlier contracts retained; device gestures/camera/offline lookup remain open. No new claim of complete click coverage. |
| Train/live/summary | durable start, pause/window clock, typed details, finish failure, cold restart, history re-score, privacy and bounded traces | B96-01 remains; original same-process retry/end guards are present. |
| Lift/Pushups | split-save errors, revision publication, active-session ownership, away cancellation, Home return | Original repairs present; long-running reminders, spoken cues and real region events need phone checks. |
| Progress/Body | fixed-week verdict versus rolling history, partial-read warnings, history refresh, reading/profile stages, photos/import | B96-02/03/04/07; valid-input daily-first/latest-reading distinction retained. |
| Sleep/Recovery | stored-zone edit helpers, dated detail links, absent stages, shared explanations, nap mutations | Original repairs retained; real travel/DST pickers and physiological/reference accuracy not proven by this pass. |
| Notifications | due-plan ledger, unread/history, routes, serialized writes, false-write/cold-cache retry | B96-05. Inferred scheduled occurrences still need honest delivery provenance. |
| Settings/devices | profile/units, Status reload, pairing/alarm failure copy, retained band detail | B96-06. Rename/find/alarm acknowledgements require a real connection. |
| Data/recovery | per-file import outcome, staging/cleanup, photo references, export cleanup, reset writer barriers | B96-07 and Body import faults remain. Full native Files/share/space-pressure cases need device verification. |
| BLE/analytics | ledger/cursor before ACK seam, derivation/version boundaries, known null/estimate rules | No formula/ACK changes or new protocol-fault reproduction; native interruption/transfer integrity remains a device gate. |

## Enhancement rationale

1. **Continuous synthetic visual coverage.** Add a cloud visual-smoke job covering routed screens
   and deeper forms in empty, thin-data, populated, failed-write and stale/offline states, with
   normal/enlarged text and full scroll. Retain inspectable synthetic images and assert layout/
   semantics even without a committed pixel baseline. Keep actual-device acceptance separate.
2. **Body with one reading.** The existing capture legitimately repeats the same reading in
   Latest, average and chart-endpoint slots. A concise single-reading explanation can replace
   redundant endpoint comparisons until there is a real comparison. Keep the reading/chart and
   full history reachable; show a full-page before/after preview before changing the composition.
3. **Notification provenance.** Distinguish shown-now records from inferred due schedules. A due
   plan is not proof iOS delivered it, particularly with permission/Focus changes. Store the
   provenance and explain it briefly without adding another dashboard.
4. **Recovery convenience.** Consider Undo for accidental Body deletions after the integrity fixes.
   It is an optional feature, not a current broken-flow claim; its storage/profile/photo semantics
   and preview need agreement first.

Keep the current calm A+B layout. Do not reopen the goal window, calorie/recovery formulas, dark
appearance or icon family as incidental polish; those are existing product decisions.

## Phone and other blind spots

- Build 96 installation and current-version signing enrollment are not reported.
- BLE restoration/commit continuity, overnight/background/kill behavior, GPS/motion/audio,
  Home-region and notification delivery still require real hardware evidence.
- Native Files/share completion, Photos/camera permissions, low space and interrupted recovery
  require a disposable test install and the existing recovery prerequisites.
- Actual SF typography, VoiceOver order/announcements, keyboard insets, edge-back and hold/drag
  are not proven by Windows captures or platform mocks.
- Every table-corruption pattern, migration pair, overlapping event ordering, locale/content
  extreme and long-history phone-memory limit has not been exhaustively exercised.

The existing detailed device checklist is retained locally under the main checkout's ignored
`build/research-local/full-flow-device-checks.md`; use it against the repaired candidate and record
Pass/Fail/Not run. Do not execute reset or induced storage faults on the live health database.

## Source/document hygiene

An existing device-family provenance comment in `lib/ui2/profile/devices.dart` quotes evidence
derived from the owner's private export. Remove that unnecessary private-derived detail in the
next source cleanup; do not repeat its contents in public audit notes. This audit does not change
published history or repository visibility. No private excerpt is included here.

The optional Impeccable product adapter is older than its current metadata schema. This is
tooling drift, not an app-flow failure; its `init` refresh can wait and is not part of these fixes.

## Release gate

The authorized repair bundle is implemented above. Release only after full cloud checks,
synthetic visual artifacts, native compilation and downloaded IPA validation pass at the same
source. Then run the real-device matrix. The original diagnostic harness remains reproduction
evidence; native phone gestures, OS delivery and background behavior remain separate gates.

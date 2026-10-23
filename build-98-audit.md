# Build 98 comprehensive flow review

**Status:** In progress against released app source `7c13f1a6` and release record `3033e427`.
The accepted scope includes independent source tracing, synthetic boundary/failure interactions,
full-scroll visual review and repairs that preserve the locked A+B interface and recorded data.
Work continues on `build-99`; no successor binary or new verification result is claimed yet.

## Baseline and scope

Build 98's completed baseline is 3,478 Flutter tests, 429 intentional skips, eight iOS contract
checks and 137 visual checks/570 synthetic captures (full run `39943912609`, native
`39942864975`). The 18 B97 repairs remain implemented. Additional corrections made while
finishing them were lazy photo staging for numeric-only Body imports and preserving the actual
haptic transport result. Seven older-suite regressions were reconciled and an HR-only-run
absence control was added. `setup.md` owns the exact artifact and source-equivalence record.

The source inventory contains 314 code/configuration files and 203,796 lines, including six
generated localization files. A static action/navigation scan finds 636 bindings. These are
discovery counts, not passed click tests or a claim that every line has been manually verified.
Local inventories, probes and captures stay in ignored `build/research-local/`.

## Review contract

For each reachable flow, trace the visible entry, validation/cancel/retry, owning write/read,
commit and refresh signal, dated/units/privacy meaning, dependent consumers and user outcome.
Check empty, partial, populated and stale states; duplicate/overlapping operations; failure and
cold reload; normal/large text, keyboard, scrolling and accessibility semantics.

Review families:

- Startup/onboarding, navigation/deep links, tab reselection, dirty drafts and permission return.
- Today, heart/wear charts, metric/day details, Sleep/Naps and Recovery explanations.
- Trends, comparisons, dated findings, notification history and notification actions.
- Food diary/calendar/targets, picker/search/order, portions, saved foods/meals, labels,
  barcode/consent, copy/save, completeness, maintenance and exports.
- Train, every activity/setup/live/summary family, GPS/motion/voice/laps, Lift Log, Pushups/Home,
  manual sessions, history/privacy/edit/delete and all refresh dependencies.
- Progress goal/check/exploration, Body weights/tape/history/edit/photos/compare and milestones.
- Profile/units/language/settings, devices/pairing/alarm/status and their failure outcomes.
- Database migration/repair/salvage, imports/exports/backup/media/reset and recovery boundaries.
- BLE decode/ledger/ACK/reconnect, background ownership/expiry, analytics/energy/recovery/sleep
  inputs, dated attribution, absence/quality and idempotent publication.
- Native channel/capability/permission contracts, release metadata, performance and privacy.

## Findings and repair evidence

Seven synthetic failure probes in `test/build99_durability_test.dart` initially fail against
Build 98, confirming six repair families. Their source repairs now pass all nine tests in that
file, including ordered read/removal and keychain refusal/retry controls. Five existing settings
and calculation-cache cases also pass in the combined targeted run (14 distinct cases across
these runs). Full cloud/native and new UI-state checks remain pending. Build 98 stays cached.

- **B98-01, P1 — profile rollback can erase database-only calculation history.**
  `_updateProfile` snapshots `ProfileHistory.key` and `StepGoals.key` from preferences even
  though `CalculationStore` makes SQLite authoritative. A missing/stale mirror plus a failed
  profile write can delete/replace real history during rollback. The synthetic database retains
  its original history before the edit and loses it after the rejected save. Snapshot the
  authoritative values and preserve the complete previous history on every failure path.
- **B98-02, P2 — calculation removal can resurrect from its failed cache deletion.**
  `CalculationStore.remove` deletes the authoritative row before unchecked preference removal.
  A refused removal looks successful; a cold read can migrate the stale preference back into
  the database. Removal and concurrent read/mirror operations need an ordered, acknowledged
  contract; test retry and a cold reload, not only the warm cache.
- **B98-03, P2 — automatic-backup Off can fail without being reported.**
  `AppState.setBackupCadence` uses a fire-and-forget write. The UI displays Off while a cold
  launch restores Daily, and the schedule resumes. Use acknowledged persistence before changing
  the selected state; inspect last-run/error metadata and the user-facing outcome as well.
- **B98-04, P2 — forgetting a band can silently recreate its identity.**
  `PairedDevice.clear` deletes the database row before unchecked mirror removal. Refused
  deletion leaves the recovery mirror able to pair it again on cold load. A failed forget must
  report failure and retain a retryable identity; successful retry must clear both copies.
- **B98-05, P2 — Home settings can claim persistence/stop without completing either.**
  `setHome` ignores refused boundary/state writes before starting native monitoring. `clear`
  swallows a failed native stop and removes the app's state, making the feature appear Off
  while iOS may still watch the area. Two probes confirm both paths. Preserve retry state,
  acknowledge persistence and native outcomes, and keep changes/cancellation ordered.
- **B98-06, P1 — reset can claim completion after refused preference deletion.**
  `_resetAllData` ignores false from `prefs.clear` and catches thrown failures, while `signOut`
  also ignores failed profile removal. The database is already wiped and private preferences
  can remain. Report partial completion honestly, keep reset retryable, and verify keychain,
  pending writers, UI drafts and native cleanup instead of reporting a fresh install early.

The shared repair orders cache reads/writes/removal, snapshots profile history from SQLite,
acknowledges backup Off/forget/Home persistence, preserves Home stop errors and reports partial
reset, including verified keychain cleanup. The affected screens retain a visible retry path.
No scientific coefficient, schema, dependency or capability changes. Algorithm 99 versions the
additional recorded-day and lifting-window corrections below.

- **B98-07, P2 — travel days diverge across Food, streaks and Today.** Food windows/months,
  profile edits, step qualification and activity-window splitting still use the operating system's
  calendar in some paths. During a westward held day they omit/file the current evidence under
  yesterday, and Today's graph starts at the wrong midnight. Use the existing stored-day helpers
  for instants; retain calendar-only arithmetic for already chosen labels. Synthetic Tokyo to
  Honolulu tests reproduce missing Food/current step awards and verify the repaired date paths.
- **B98-08, P1 — empty startup profile overwrites restored calculation anchors.** A database
  restore without local profile preferences passes an empty map to `ProfileHistory.record`,
  replacing the current dated anchor with `{}`. An absent startup profile is not an edit;
  preserve the restored history. Explicit populated edits/cleared fields still record normally.
- **B98-09, P2 — lifting deduplication drops active time and session anchors.** Trimming a
  later session's start to an earlier elapsed end loses exercise occurring during a pause and
  prevents its clock/profile from matching. Union active windows with original starts and
  captured profiles; a missing current weight must not hide valid historical session anchors.
  Tests cover pause-only overlap, real overlap and different captured weights. No MET changes.
- **B98-10, P2 — arbitrary barcode text changes the request path/query.** Reject non-ASCII
  numeric identifiers before HTTP construction. Six synthetic malformed inputs previously
  reached the mocked service; valid numeric barcodes continue through the same endpoint.
- **B98-11, P2 — first-use barcode disclosure is bypassed.** Source defaults a fresh install
  to allowed despite the canonical opt-in contract. Default to off, retain explicit choices and
  require an acknowledged grant before camera/lookup. A refused grant stays closed and says why.
- **B98-12, P2 — barcode disclosure actions overflow.** The non-scrolling half-height sheet
  overflows at normal and accessibility text sizes. Give the existing content a full-height
  scrollable sheet; both Allow and Not now remain reachable without camera or network access.

Seven recorded-day/restore/lifting tests pass; four new barcode tests plus the existing nutrient
and consent suite pass (37 combined). Before-fix logs reproduce the failures. The running
coefficient's comment now accurately calls 0.85 a budgeting calibration, above the cited 0.81
mean and not a guaranteed personal minimum; the coefficient itself is unchanged.

The recorded-day trace also covers dense chart positions/freshness, metric comparisons, weekly
averages, Sleep signals, dated workout-profile selection, Food/Body calendars and Pushups.
Pushups' background mirror carries actual day bounds, so it can validate a Done action without
opening SQLite. Calendar-only goal-window arithmetic and elapsed-time GPS/retention limits keep
their original meanings. Three added travel controls exercise dense charts, Pushups status/
actions and the unhydrated background mirror.
Wake-window planning reads each night's stored-zone wall time and constructs the next target
by calendar date across DST; the 90-minute lease and three-sample rule stay unchanged. Recovery
association lookup bounds use the same recorded calendar, without changing association thresholds.

- **B98-13, P2 — run voice Off does not acknowledge storage.** The live switch flips before
  an unchecked preference write. Persist before changing the selection, retain the old choice
  on refusal/cold reload, prevent repeated in-flight taps and show a retry message.
- **B98-14, P2 — reminder Off/reset can hide failed native cancellation.** NotificationService
  swallows cancellation failures and removes its plan first. Retain the plan on refusal and
  require acknowledgement for user Off/reset paths. Body's weekday/hour/On changes also need
  acknowledged persistence and serialized application; restore previous settings/plan where
  possible and show an explicit uncertain-state message if rollback cannot finish. Food's Off
  follows the same acknowledged contract, and daily scheduling exposes its actual result.
- **B98-15, P2 — backup bookkeeping claims success without durable status.** Last-run/error
  writes are unchecked, and a manual backup releases the global lock before marking its time.
  A queued automatic decision can export again. Mark inside the shared lock and acknowledge
  metadata. A valid written file remains successful with a separate warning if bookkeeping fails;
  Data distinguishes that warning from a failed export. Tests cover both ordering and refusal.
- **B98-16, P2 — Body entry read/camera failure paths are unsafe.** An initial history-read
  failure escapes without an on-page retry; a late camera failure calls setState after leaving.
  Catch day-read failures, keep typed fields, block blind saving and offer Retry loading. Capture
  the intended photo date, prevent concurrent photo/date/save actions and guard late callbacks.
  Synthetic widget tests exercise a missing-table/read retry and a delayed camera refusal.
- **B98-17, P2 — What changed can silently drop a failed month-grid metric.** Its per-row
  catch hides the failed metric, potentially implying a complete review. Propagate the failure
  to the page's existing visible Retry state. The grid header/axis also wrap without truncating
  metric labels or overflowing at enlarged text sizes; shading/coverage meaning stays unchanged.

The Strength summary also uses singular/plural labels correctly. No metric or detail is hidden.
Version `0.9.66+99` and matching RunnerTests metadata reserve the successor identity; the actual
Build 99 binary/release checks remain pending.

Current focused evidence: 28 passing checks across `build99_durability_test.dart`,
`build99_recorded_days_test.dart` and `build99_barcode_test.dart`, plus two backup publication/
ordering cases in `auto_backup_test.dart`. The compound Body widget check exercises normal and
3.1x settings failure, read retry with retained input and leaving during a camera operation in
one test-clock zone. This avoids a Windows FFI fixture-order stall; isolated read retry also
passes. Initial fixture mistakes/stalled batches are not counted as app passes. Full-scroll
captures of the disclosure and reminder error states were inspected with substitute fonts.
The cloud visual job now includes these states; its successor result is still pending.
The full test job also retains instrumented Dart line coverage. This measures exercised lines
in imported Dart libraries; generated/unimported code and native iOS behavior must be identified
separately and cannot be certified from a green test count.
Five additional secondary-flow checks pass: DST wake target, grid failure propagation, actual
What changed Retry and complete month-grid labels at normal/3.1x text. Seven existing wake/grid
controls pass as well. This makes 35 distinct added checks; repeat executions are not extra tests.

Additional review queues, not yet closed: historical journal/custom-field drafts
(first establish personal-build reachability); short arrival-day wall-clock choices; all remaining
activity/metric/data/lifecycle consumers. Scientific coefficients remain unchanged.

## Boundaries

Keep the approved kraft/cream framework and calorie ring/macros. Local readability fixes are
authorized; material replacements still need full-page before/after review. Remove no feature,
change no scientific coefficient or dependency, and preserve commit-before-ACK. Formula or
headline-output changes outside the approved repair contract require an explicit decision.

Windows synthetic tests cannot certify physical BLE/GPS/audio/background behavior, system
permission/delivery, actual SF typography/VoiceOver/gestures, signing enrollment, low-space
recovery or the 72-hour soak. Generated code consistency and static discovery are distinct from
manually reviewed application logic. No private data or live database is used for fault tests.

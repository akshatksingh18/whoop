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
No scientific coefficient, analytics version, schema, dependency or capability changed so far.

Additional review queues, not confirmed findings: barcode numeric-input/disclosure/large-text
sheet contracts; run voice and Body reminder persistence; historical journal/custom-field drafts
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

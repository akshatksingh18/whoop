# Coverage-directed audit

**Status:** Coverage-directed software review and all 16 repair families are complete in
validated Build 100. Full run `40046857679` passes at fixture revision `40f9fee6`, whose app
source is identical to `1277cd3a`. Native run `40044650218` and downloaded IPA validation pass.
Build 100 is the single testing candidate; physical iPhone/signing acceptance remains open.

## Baseline and reuse

The baseline is app source `e52d571a`, verified by `18324f76` in run `40003142620`.
Root LCOV exercises 37,534/49,891 instrumented handwritten Dart lines (75.23%): **12,357
instrumented lines were not executed**. Five handwritten files were not imported at all.
This is execution coverage, not the proportion of source reviewed. It excludes native iOS
and independent package suites, and does not measure branch correctness or physical delivery.

## Verified result

The clean full run passes **3,589 app tests / 429 intentional skips**, including all 65 new
cases. Of the skips, 408 need absent golden baselines. Analysis has zero errors/warnings and
235 informational lints. Protocol passes 433/skip four; analytics passes 645/skip six. The
visual jobs pass 152 checks and produce 607 synthetic captures. Eight iOS contract checks
and the four original inventory controls pass in CI; all five inventory controls pass locally.

Root LCOV records 38,375/57,649 lines (66.57%) across 203 imported Dart files. Excluding seven
generated localization files, handwritten execution is **38,324/50,048 (76.57%)** in 196 files,
up from 75.23%. There are 790 more executed lines; the instrumented denominator also grew by
157, so this is not a claim that 790 old missed lines were all exercised. **11,724 instrumented
handwritten lines remain unexecuted.** The production entrypoint and error logger are now
imported/exercised. The three unimported files are the build-profile constant and two UI barrel
exports; importing them would not establish another user flow.

The exact final inventory is ignored `build/coverage-audit/build100-final.json`, alongside the
canonicalized Build 99 baseline. No denominator filters or exclusions were added to raise the
percentage. Native iOS, independent package suites, branch correctness and physical delivery
remain outside this root line-coverage measure.

## Further automated execution

**Status:** Active on `coverage-expansion`; baseline is the verified Build 100 result above.
Add meaningful outcomes for missed deep Lift/Food/settings/history and state/storage boundaries,
with real synthetic ledger writes and failure/retry/restart checks where applicable. Keep the
same denominator and retain earlier tests. Do not import dormant screens, assert only widget
existence or call private helpers solely to raise a percentage. New gains require a clean full
cloud coverage artifact. The incline-walking proposal remains separate and unimplemented.

The extension adds 96 passing targeted cases in five files:
`coverage_deep_lift_test.dart` (27), `coverage_data_actions_test.dart` (28),
`coverage_motion_retention_test.dart` (27), `coverage_meal_actions_test.dart` (8) and
`coverage_analysis_pipeline_test.dart` (6). All data are synthetic. Real SQLite writes cover
split/load identity, history-preserving edits, finished-set correction/deletion, refused-write
retry, meal copy/save, import review/commit and analysis-file provenance/privacy/denominators.
Share/picker/native-motion substitutes check Dart outcomes and cleanup; backup/profile/rebuild
substitutes check the data screen's responses, not native delivery or the underlying engines.
Existing independent storage/crypto/engine regressions remain required.

**COV-17 — split/exercise sheets return into disposed owners.** Three negative navigation
controls reproduced `setState() called after dispose()` on rename, exercise edit and exercise
add. Mounted guards now reject the late result before mutation. The sibling live set,
variation, add/remove, rest-setting and recent-exercise callbacks also check their owner before
applying a returned result or touching disposed text controllers. Successful persistence already
in flight remains durable; the fix does not undo a committed workout. All 27 Lift checks pass
with the real bundled font substitute. No layout, metric, ACK, schema or dependency change.

Build 101 (`0.9.68+101`, algorithm 99/schema 50) contains this lifecycle repair. Full cloud
analysis/app/package/visual coverage and native compilation are pending; Build 100 remains
the cached testing candidate until a replacement passes downloaded-artifact validation.

Reuse the repair contracts and passing tests in `build-98-audit.md`, `build-97-audit.md`,
`build-96-audit.md` and `build-95-repairs.md`. Revisit their implementation only where an
unexecuted sibling/failure path or changed dependency exposes a new question. Do not repeat
the previous broad screen sweep or count a previously passing test as a new regression.

`tool/coverage_gaps.py` records all uncovered line ranges, unimported files and source hashes
from an LCOV artifact. Generated output belongs in ignored `build/coverage-audit/`; unchanged
source hashes allow review evidence to carry forward. A changed hash requires checking the
affected paths again. No exclusions or no-op calls may be added just to improve the percentage.
Hashes normalize CRLF to LF so Windows/Linux checkout formatting does not invalidate unchanged
source evidence. Every handwritten baseline hash is checked against the `e52d571a` Git blob;
generated checkout files are excluded from source-review carryover. The five inventory controls
include equivalent LF/CRLF content and a real-edit counterexample.

## Review coverage and remaining execution

- [x] Inventory every baseline LCOV miss/unimported file with source hashes; preserve the
  complete raw ranges in ignored `build/coverage-audit/build99-baseline.json`.
- [x] Exercise formerly absent entrypoint/error-log and zero/low-coverage GPS, BG-task,
  restoration/gate and cold-retry boundaries with meaningful outcomes and retained writes.
- [x] Trace uncovered AppState initialization, import/publication, foreground/background,
  band-owner/reconnect, active-clock/route and calculation scheduling branches. New contracts
  are COV-01/02/07/09/10; retained session/reset/phone-step contracts remain in Build 98's map.
- [x] Review deeper editor/settings callbacks and their storage/read seams, using the prior
  full flow map rather than duplicating the main-screen sweep. COV-05/06/08/11–13/15/16 add
  previously absent failure/retry, disposed-caller, route-refresh and accessibility evidence.
- [x] Trace the BLE/derivation/repository misses against commit-before-ACK, cancellation,
  retention/finalization, absent input and versioned publication. COV-14 adds the failed-rescan
  retry control; no decoder, coefficient, ACK or scientific definition changes.
- [x] Complete full cloud analysis, app/package suites, final coverage and full-scroll capture
  review for the final implementation in `40046857679`; earlier failed/cancelled runs are not release proof.
- [ ] Physical iPhone/band acceptance remains separate: permissions, radio/restoration,
  real GPS/background/audio/notifications, camera/share gestures, signing and soak.

This completes a coverage-directed **software review pass**, not execution of every missed
line. The remaining LCOV regions retain their exact file/range inventory; they are not erased,
excluded or declared unreachable to improve a percentage. Evidence is carried by concern:

- **Executable host paths:** startup/onboarding, diagnostic chaining, settings, Food/Body/Lift
  saves, recorded-zone edits, background callback reactions and cache publication now have
  the new controls below. Existing `startup_and_rebuild_recovery_test`, `app_state_regressions_test`,
  `workout_stop_durability_test`, `workout_reliability_test`, `route_tracker_test`,
  `ui2_food_flow_test`, `db_paged_import_export_test`, `import_data_safety_test` and Build 98/99
  nested/durability/secondary controls retain their prior evidence. They do not prove every
  exception branch in each containing file.
- **Storage/calculation/protocol defenses:** DB repair ladders, archive/quarantine, incomplete-day
  preservation, isolate failure/cancellation, baseline gates, unknown signal families and native
  GATT outcomes are source-traced alongside the existing ACK, migration, result-protection,
  readiness/baseline, decode and independent package tests. Rare corrupt-page/low-space/process
  loss combinations and absent private replay fixtures remain execution gaps; no real record was
  used to manufacture those cases.
- **Concrete iOS delivery:** GATT, ASK, zone/pedometer/home bridges, precise GPS, MapKit, camera,
  notifications and audio have host adapters or source contracts, not a physical certification.
  Swift BG-task completion/expiry and BLE-restore handoff were source-reviewed; compilation and
  synthetic callbacks cannot establish OS scheduling, native UI behavior or band receipt.
- **Retained dormant/developer branches:** manual Journal/custom fields and appearance settings
  are not current personal navigation. Sleep's sole RoughNightCard uses `ask: 'never'`; shared
  Journal input widgets remain live and are not classified dormant. Gallery fixture controls,
  default abstract repository throws, older import/schema compatibility and non-iOS plugin
  branches remain in the source. A dormant screen is not an exercised user flow, and legacy
  import/migration code is still a real recovery concern covered by its own contracts.
- **Non-executable/absent baselines:** build-profile constants and two UI barrel files do not
  become meaningful flows just by importing them. Generated localization is reported separately.
  Missing golden baselines remain explicit skips; synthetic screenshots are not pixel-baseline
  tests or native SF-font/VoiceOver evidence.

The context extracts under ignored `build/coverage-audit/` identify the reviewed gap clusters;
`build-98-audit.md` owns the complete retained end-to-end flow map. Neither static action counts
nor source context extraction is counted as new runtime verification.

## Confirmed findings and targeted evidence

- **COV-01 — restoration expiry omits the transport stop.** Native sends `expire`, but the
  Dart callback stops only calculation. The synthetic registered headless stop remains
  uncalled before the fix. The callback now requests the same lease-owned transport stop as
  BG-task expiry. Its entrypoint is shared by registration and the synthetic channel checks.
- **COV-02 — the headless ceiling releases ownership without asking transport to stop.**
  The five-millisecond synthetic ceiling reproduces the omitted callback. Request cooperative
  stop before forced lease release; retain token protection against a late old completion.
  This does not prove native disconnect completion or shorten the production ceiling.
- **COV-03 — diagnostics can remain silent after an initialization/handler failure.** A
  temporary path-provider failure latches FileLog unavailable for the process. A throwing prior
  FlutterError handler also prevents the current error from reaching the file. Both failing
  controls now pass: directory lookup retries, and logging precedes the chained handler.
- **COV-04 — concurrent Pushups actions overwrite the shared inbox.** Twelve simultaneous
  background callbacks retain only one action before the fix. Each delivery now publishes its
  own atomic file; legacy arrays remain readable, receipt IDs deduplicate replay, and reset
  clears the owned directory. Malformed input is retained and reported rather than read as
  empty. Lifecycle reconciliation logs its failure; the Pushups screen retains its Retry state.
- **COV-05 — linked Lift edits can commit only their split.** Refusing the workout insert
  after the split write changes the reusable split despite the failure message. Add, remove
  and split-sync controls reproduce all three paths. One transaction now owns both records;
  preference mirrors and controller state change after commit. All three controls pass.
- **COV-06 — a picker returns to a disposed workout editor.** Date, start, end and activity
  pickers all call setState after their editor is removed. Four failing navigation controls
  now pass with mounted guards; suggestion-adjust return and onboarding's file-picker return
  use the same guard. The Food calendar and metric-day/quiet-hour pickers also refuse results
  after their caller closes; Food meal selection and late workout-detail navigation check their
  owner before updating. A fifth real-navigation control confirms the Food callback. No feature
  or layout changes.
- **COV-07 — onboarding advances after a refused preference write.** Both New and Imported
  ignore the platform's false acknowledgement. The shared acknowledged preference writer now
  owns the choice before the route advances. Setup reports failure and remains retryable;
  an already-imported history keeps its successful report if only setup continuation fails.
- **COV-08 — historical workout corrections use today's time zone.** The form displays and
  reconstructs saved instants in the current OS zone; date/start/end controls reproduce shifts,
  including a DST seam. It now shares the existing recorded-day wall-clock resolver with Food.
  Untouched instants stay exact, repeated hours use the nearby occurrence, and nonexistent
  clocks are refused without altering the form. This changes explicit edits, not stored history
  or analytics formulas; algorithm 99 remains appropriate.

- **COV-09 — expiry during transfer permits a fresh calculation.** An expired BG wake can
  return from transfer and create an engine with the new cancellation generation. The wake
  now retains its starting generation and checks it after transfer/profile loading and before
  a rescan. A held-transfer/expiry control confirms that no calculation starts afterward.
- **COV-10 — a storage read that never answers leaves startup spinning.** Initialization now
  shares the existing six-second startup bound and presents Retry. A retry joins the same
  pending initialization instead of creating a competing one; late success can recover the
  route. This bounds the UI wait, not the native operation itself. The held-read control and
  existing startup/quarantine controls pass.
- **COV-11 — a Zones read failure masquerades as missing measurements.** The deeper
  Train → Strain → Zones page now shows a retryable read failure rather than empty age/ceiling
  guidance. Retrying a repaired repository displays the measured values.
- **COV-12 — enlarged Zones ranges overflow.** Measured range/unit rows now reflow beneath
  their labels at enlarged text, preserving standard-size composition and the locked palette.
  Full-scroll controls pass at 1× and 3.1×; the cloud capture job includes both and the read-failure state.
- **COV-13 — an optional Lift refresh falsely reports a committed save as unsaved.** An
  unreadable earlier log reproduces the misleading failure after a new set is durable. The
  controller now distinguishes save failure from refresh failure, retains a saved warning and
  still starts the chosen rest timer. A subsequent clean edit clears the warning. Initial
  history failures remain explicit. Linked split/import cache hydration is best-effort only
  after commit; ordinary startup hydration remains strict and logs the post-commit failure.

- **COV-14 — a failed recent-day refresh consumes its retry.** A real refused `day_result`
  insert reproduces a stored baseline signature despite the failed day. The rescan now
  acknowledges the signature only when every prepared day succeeds; failed/null preparations
  retain the pending change and existing results. Retry with unchanged baseline succeeds, then
  the subsequent clean rescan becomes a no-op. This repairs scheduling, not a scientific output
  definition; algorithm 99 and every formula remain unchanged.

- **COV-15 — a corrected route reuses its earlier map/projection.** The snapshot cache used
  only session ID/size, despite correction changing the track. It now matches immutable copies
  of the coordinates, retains newer requests after an older failure, rejects malformed projected
  point counts/values and safely handles empty thinning input. The actual map widget uses its
  plain-route fallback while a new image is pending rather than retaining an earlier projection.
  Five synthetic channel/widget controls pass; no map service or location request was used.
- **COV-16 — secondary settings have silent read/write failure paths.** Notification and
  Pushups settings can spin or show no feedback after a failed read/save. Body settings also
  expose initial defaults before its saved configuration loads, and Journey start lacks save
  error handling. These screens now withhold editable defaults until reading succeeds, offer
  Retry and retain prior choices after a refused save. Six actual-widget controls cover all
  three readers and Pushups goal/interval plus Journey start refusal/retry. Failure captures
  at standard/enlarged text are included in the cloud visual job.

Sixteen added Dart files contain **65 targeted cases** for these contracts, real cold-start
routing with an optional notification failure, and GPS service/permission/sample boundaries.
The GPS checks use simulated plugin results, not physical location delivery. Existing manual
workout (11), startup/quarantine (7), baseline-rescan (3) and three legacy failure/cancellation
cases also pass.
Five Python inventory checks and eight iOS contract checks pass locally. The four original
inventory controls also pass in the cloud; the fifth checks cross-host source-hash equivalence.
Fixture/compiler failures
are not counted as app findings. Logs stay in ignored `build/coverage-audit/`.

The first full cloud run, [40015378904](https://github.com/akshatksingh18/whoop/actions/runs/40015378904),
passed analysis, package suites and the original visual job, but the app suite had three old
fixtures without an application-support path provider. The stricter Pushups inbox correctly
surfaced that missing fixture. Those fixtures now supply a synthetic path, retain their
original assertions and pass all three targeted cases. A clean full rerun is still required;
coverage from the failed run is preliminary, not successor verification. Intermediate runs `40042565354`, `40043039909` and native
`40043061254` were cancelled as superseded while the remaining source review found additional
repairs; cancellation is not a failing test or a release result.

Full app/package/visual/coverage run `40044648006` at source `1277cd3a` passes analysis,
packages and visuals, with 3,588 app cases passing, 429 skips and one old fixture failure.
The pairing source-row fixture started platform initialization without awaiting it, leaving
the six-second startup timeout pending at test teardown. It now uses `AppState.forTesting`;
all pairing assertions remain. All 39 router cases and both separate real startup controls
pass together. The clean full rerun `40046857679` passes; the earlier run's interim coverage is not release proof.
Native run `40044650218` passes, and the cached unsigned `0.9.67+100` IPA passes downloaded
manifest/source/version/checksum, full ZIP CRC and compiled Runner/AOT payload checks. Its
SHA-256 is `3251c08089021f18af9d551e6b1738fb46e02294f01dc796ac7dbcb078f1d183`.
Full software/native/payload checks now pass and the testing cache contains Build 100. Phone
acceptance and signing gates remain open; Build 70 recovery is unchanged.

The final cloud visual job in `40046857679` passes **152 checks and 607 synthetic captures**,
including 19 focused phone-width captures. Review of the earlier job found its new settings
failure captures used the default wide test window; the two fixtures now use a
390-logical-pixel phone viewport. A focused nine-case local run also passes. Standard/3.1×
read failures and every enlarged Zones scroll position were inspected; Retry remains reachable
through the enlarged Pushups page. Existing Today/Trends/Food/Train/Progress/Body samples retain
their composition. These are test-fixture corrections only: app source remains identical to
`1277cd3a`. One earlier Today scroll frame is no longer required to reach the bottom; the final
viewport still contains the maintenance card and navigation. Captures use substituted fonts,
not physical iPhone typography, and are not comparisons with absent golden baselines.

## Limits

Keep the locked A+B interface and all features. No scientific tuning, dependency/capability
change, live-data fault injection or private export is authorized by a coverage target. Native
radio/GPS/audio/permission delivery, signing and soak still need the iPhone. Synthetic native
channel checks establish app reactions, not what iOS or the band physically did. Pure constants,
barrel exports, generated strings and dormant upstream-era screens must not be called tested
user flows. A 100% headline is not a substitute for these distinctions.

## Focused phone acceptance

Use the existing encrypted database/photo recovery and same-ID upgrade procedure before installing
the candidate. Keep Build 70 recovery until current-version device/signing acceptance is reported.
Do not corrupt live storage, alter the phone clock or force database failures to repeat synthetic tests.

- **Closed-app Pushups:** take separate Done/Pause notification actions, reopen, inspect the
  session history, then reopen again. Each real delivery must appear once and reminders must
  follow the saved session. Actual iOS delivery remains unproved by the file/receipt tests.
- **Train and Lift:** log a set with rest enabled, change a linked split, return through history
  and relaunch. The saved set/split and timer must agree; initial history failure must retain Retry.
- **Historical workout editing:** inspect an existing recorded travel day if available. An
  untouched start/end must remain exact, and an explicit edit must display in that day's zone.
- **Run/Walk maps:** record a short safe route, inspect its cursor, correct the saved route if
  that flow is used, and revisit it. Real GPS accuracy, native snapshots and background voice
  need the phone; the automated map check substitutes the channel response.
- **Deeper pages:** open Train → Strain → Zones, Settings → Notifications, Pushups settings and
  Progress → Body settings at normal/enlarged text. Reach the last section and every action.
  Saved choices must survive returning to the page; Retry must remain available if a read fails.
- **Startup/background/signing:** cold-open and resume after ordinary background use, then
  complete the existing BLE-restoration, notification/permission, data-preserving upgrade,
  current-version refresh enrollment and 72-hour matrix in `todo.md` and the iOS guides.

The 16 repaired families are software contracts, not a substitute for those physical outcomes.

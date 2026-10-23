# Build 97 independent end-to-end audit

**Status:** All eighteen findings have source repairs on `build-98`, version `0.9.65+98`,
algorithm 98 and schema 50. Desired-behavior regressions replace the diagnostic assumptions;
focused data/editor checks and normal/3.1x nested interactions pass. The first full run passes
137 visual checks/570 captures, with seven older-suite failures. Those seven and an added
HR-only-run case pass targeted corrections; full rerun and rebuilt native artifact remain gates. Build 97 is
still the cached testing binary until that successor is validated. Build 70 recovery is unchanged;
no Build 98 installation or hardware acceptance is claimed.

## Repair verification

- B97-01–04: database merges rebuild the first-reading projection; Body identity and tape
  validation completes before writing; module application is transactional with staged media and
  rollback cleanup. The Data screen explicitly reports missing photo files, even with no new rows.
- B97-05: serialized, acknowledged preference writes retain the prior choice on failure; Units,
  Notifications, Trends pins, Food reminder, rest timer and phone steps use the same helper.
  Find my band carries the transport write result through both haptic methods and AppState;
  rejected/thrown writes and successful writes are covered for gen4/gen5. It never claims physical delivery.
- B97-06–08: private Lift/Run sessions stay in direct history and out of result summaries. Daily
  measured movement remains an input to maintenance. Food times, copied/regrouped entries,
  Progress/Train/milestone/export membership and session profile/run attribution use stored zones.
  Algorithm 98 versions the changed date attribution; no scientific coefficient changed.
- B97-09/18: native Home events are peeked and acknowledged after durable session receipts and
  automation state. Failed/replayed writes preserve one transition. Live clock and draft save
  failures remain visible in the scrollable live view, with explicit retry and foreground retry of their original values.
- B97-10/11: finished-set and diary-portion editors retain drafts until successful validation and
  writes. Primary action labels can grow beyond two lines; full-scroll Copy a day tests inspect
  `didExceedMaxLines`, not just overflow exceptions.
- B97-12–16: nested Lift/Pushups identities, integer counts, chronology and load meaning are
  validated; full metadata determines conflicts. Settings/splits are available without new history
  and commit with history. Stale previews preserve newer local rows and return actual additions.
- B97-17: paged restores retain bounded memory and expose committed counts on failure, reconcile
  projections/cache, publish AppState/Food revisions and allow a safe retry. No failed merge is
  presented as a fully completed restore.

Tracked regression sources are `test/build98_integrity_test.dart`,
`test/build98_boundary_test.dart` and `test/build98_nested_render_test.dart`; all fixtures are
synthetic. The current execution and release results live in `todo.md` 3m and `setup.md`.
The descriptions below reproduce faults in **old Build 97**, not outstanding source defects.

## Original Build 97 scope and evidence

This is a new source/flow review of the shipped candidate, with real Flutter widget interactions,
SQLite writes/imports, injected failures, cold preference reloads and synthetic travel-day data.
It traces the five tabs and the secondary flow families below through their stores and update
signals. It does **not** mean every possible click sequence, sensor event ordering or native
permission/lifecycle condition has been executed. The on-disk interaction inventory contains 509
callback bindings and 231 navigation/modal references; those are discovery counts, not passed
button tests or unique user-visible controls.
The Impeccable native checklist was read alongside the independent source audit. Windows blocked
its optional context launcher; no engine, browser detector or simulator pass is claimed.

All newly created data is synthetic. No personal export, photo, measurement, route or log was
opened or sent anywhere. Local-only harnesses, screenshots, inventories and logs are under this
checkout's ignored `build/research-local/`:

- `build97_deep_audit_test.dart` / `build97-deep-audit.log`: 16 checks complete successfully,
  comprising 15 diagnostic cases that assert observed faulty behavior and one valid-import
  control. Successful diagnostics reproduce a defect; they are not healthy-flow regression passes.
- `build97-existing-regressions.log`: 18 existing regression/contract checks pass across
  `build97_integrity_test.dart`, `build97_notification_test.dart`, `build97_device_test.dart` and
  `table_coverage_test.dart`. These verify the earlier seven repairs and table-list coverage.
- `build97_nested_visual_test.dart` / `build97-nested-visual.log`: four new widget checks exercise
  populated Strength and the complete Copy a day review at 1x and 3.1x, including full scroll and
  explicit submission with an unknown-calorie item. `build97-copy-label-probe.log` separately
  confirms the two-line truncation in B97-11 through `RenderParagraph.didExceedMaxLines`.
- `build97-nested-visual/`: fifteen fresh full-scroll synthetic captures. Manrope substitutes for SF;
  these are Flutter test renders, not iPhone screenshots.
- `build97-control-bindings.txt` and `build97-navigation-bindings.txt`: static discovery inventory.

There are **38 distinct targeted checks** across those three groups; the two label checks repeat
existing cases and are not added again. The first copy-review harness checked route removal before
the reverse animation settled; awaiting navigation settlement resolved that harness failure.
The initial food-copy hypothesis concerned the hour; the actual reproduced fault was a changed
stored-zone calendar date, retained as B97-07. Neither harness correction changed app code.

The coverage-gap review extends the same audit and report, without changing the source:

- `build97_boundary_audit_test.dart` / `build97-boundary-audit.log`: **21 completed checks**,
  six healthy controls and fifteen diagnostic cases. These cover all three module importers,
  nested identities/fields, replayed previews, settings/split recovery, a failed database merge,
  private running summaries and a failed pause checkpoint. Several cases exercise a validation
  matrix, not just one malformed field. Diagnostics remain reproductions of open faults.
- `build97-expanded-regressions.log`: thirteen Food checks completed before the Windows batch
  stalled in the Train history-retry case. The process was stopped. The remaining tests/files in
  that batch are **not** claimed as executed or passed. `build97-train-retry-isolated.log` records
  that exact Train case passing on its own. A clean whole-batch Windows result is still absent;
  no new app fault is inferred from that harness-order stall. The unchanged-source cloud result
  above remains the full-suite evidence.
- Initial extensions of the diagnostic harness had constructor/method/fixture-column mistakes;
  correcting those test-only mistakes produced the complete 21-case result. No production fix
  was made to turn a probe green. Repeated harness runs are not additional coverage counts.

The earlier eleven-finding answer was not a sufficient stopping point. Reviewing a screen's
happy path, a screenshot and one rejected write does not establish its sibling paths. This report
therefore distinguishes source tracing, new execution, existing cloud evidence and device-only
verification. It cannot certify every possible action ordering or that no further defects exist.

The prior full Linux run `39815813645` remains successful at this exact app source: 3,426 tests,
429 intentional skips, no analysis errors/warnings; its visual job has 131 checks/550 synthetic
captures. Native build `39815817300` and IPA validation also remain successful. They were not rerun
for this audit-only work. The new diagnostics exercise cases those successful runs did not cover.

## Original Build 97 confirmed findings

### B97-01 · P1 · A backup merge can violate the first-reading daily-weight rule

- **Flow:** keep an earlier weigh-in locally, then merge a backup that carries a later reading
  for the same date.
- **Reproduction:** the local ledger retains both timed readings, with the earlier reading first,
  but `body_weight` is replaced by the backup's different daily value. Thus Body's readings list
  and the daily weight used by averages/goal evidence disagree.
- **Cause:** `_mergeFromDbFile` replaces `body_weight` and `body_weight_reading` independently.
  Only legacy exports without the reading table get a seeding pass; modern imports never rebuild
  the touched daily projections from the merged ledger.
- **Source:** `lib/data/db.dart:7267`, insert at 7518 and post-import block near 7565;
  canonical rule in `lib/data/body_log.dart:313` (`_refreshDay`).
- **Fix:** rebuild each affected day's projection from its earliest retained reading after the
  merge, using the same canonical helper and preserving provenance/history-only flags. Test a
  merge into nonempty history, repeated import, correction and deletion, not only empty restore.

### B97-02 · P1 · Duplicate Body import identities can silently lose records

- **Flow:** import two different weight dates carrying the same origin ID, or two tape sessions
  carrying the same ID.
- **Reproduction:** two weights are reported imported but only one timed reading survives; the
  old date retains a phantom `body_weight` row. Two tape sessions are counted as imported while
  only the last survives.
- **Cause:** weight preflight rejects repeated dates but not repeated origin IDs. `putWeight`
  finds the prior row by origin, moves it to the second date and refreshes only that date. Tape
  preflight checks existing IDs but not duplicates inside the incoming file; storage uses REPLACE.
- **Source:** `lib/data/body_log.dart:347`, origin lookup at 390, `putMeasure` at 531,
  `planBodyImport` near 833/857, and `applyBodyImport` at 947.
- **Fix:** reject conflicting/repeated incoming identities before any write; recheck stale plans
  against storage. If a supported operation moves an identity, rebuild both old and new dates.
  Keep the existing photo collision protection; this finding concerns weight/tape identities.

### B97-03 · P2 · Body preflight accepts an empty tape session, then partly imports the file

- **Flow:** select a manifest with a valid weight and a tape session whose sites map is empty.
- **Reproduction:** preflight and preview succeed. Apply commits the weight, then `putMeasure`
  rejects the empty tape session. The overall operation fails after already changing history.
- **Source:** measurement-validation loop in `lib/data/body_log.dart:857`, storage validation at
  531, sequential apply at 947; generic action failure in `lib/ui2/profile/data.dart`.
- **Fix:** share complete storage validation with preflight, including at least one site. Any
  unavoidable partial apply, such as a later photo-encoding/storage failure, must name what
  committed and offer a safe retry rather than leaving that outcome unspecified.

### B97-04 · P2 · Selecting only a photo manifest can misleadingly say “Nothing new”

- **Flow:** import a Body manifest containing photos but omit the JPEG selections.
- **Reproduction:** the plan records missing photo files, zero already-here records and no ready
  records. `isEmpty` is true, so the screen returns “Nothing new: 0 already here” before reaching
  the missing-photo explanation. The user is not told what to select.
- **Source:** `BodyImportPlan.isEmpty`, `lib/data/body_log.dart:808`;
  `lib/ui2/profile/data.dart:288` precedes the warning at 300.
- **Fix:** distinguish no new records from missing required selections; show missing filenames
  or counts and a clear reselect instruction before the empty-plan return.

### B97-05 · P2 · Some actions ignore a failed persistence or command acknowledgement

- **Flows:** Settings → Units; Settings → Notifications, including quiet hours/alert switches.
- **Reproduction:** a preference store returning `false` leaves the UI/cache changed without an
  error. Cold reload restores the previous/default choice. Units also return early when retrying
  the same choice, so that retry never attempts another write.
- **Cause:** `UnitsController` mutates/notifies first and discards `setString`'s result.
  `NotificationPrefs.save` discards every boolean acknowledgement; the screen only handles throws.
- **Source:** `lib/state/units_controller.dart:100`, 109, 118;
  `lib/notify/notification_prefs.dart:125`; `lib/ui2/profile/settings.dart:588`.
- **Fix:** acknowledge writes, reconcile optimistic caches on failure and retain a retryable
  choice. Cover both false and thrown writes, rapid changes, and a cold reload. The repaired
  notification **history read flags** are a separate path and still pass their failure tests.
- **Sibling-path source check:** Trends pin saving (`health_screen.dart:217`) also changes the
  visible choice and ignores both a false acknowledgement and thrown persistence failure.
  `FoodDayReminder.setEnabled` and several Rest Timer/phone-step preference writes also discard
  the boolean result. Include them in the acknowledgement audit rather than fixing only Units.
  The original false-write/cold-reload probe executed Units and NotificationPrefs; these sibling
  findings are source-traced, not additional newly executed UI cases.
- **Device sibling:** `profile/devices.dart:663` always says “Buzz sent to the band” after
  `AppState.buzzBand`, which deliberately returns normally on disconnection/write failure
  (`app_state.dart:3737`). Return an actual write-attempt result to this one-shot action or use
  honest attempt wording. Do not imply physical delivery or invent a band acknowledgement.
  This is source-confirmed; no native buzz was executed. The nonthrowing helper's original
  timer/hunt rationale does not justify unconditional success copy in its current caller.

### B97-06 · P2 · Private workouts still appear in some summary inputs

- **Flow:** record a lift with “Private session — Hidden from summaries and exports”, then open
  Progress/Strength or the goal's strength evidence.
- **Reproduction:** `ProgressData.load` correctly omits the private session from its workout list
  but includes its linked lift log. Strength counts/comparisons/milestones and goal evidence consume
  that unfiltered list, contradicting the switch's summary promise.
- **Source:** `lib/ui2/screens/progress_screen.dart:268` versus the session filter at 292;
  `_strengthSection` in `progress_details.dart:1110`; `goal_review.dart`/`liftComparisons` consume it.
- **Fix:** filter aggregate lift inputs through the linked session's privacy state at the shared
  read seam; retain the private workout and set log in its own history/detail. Preserve the
  existing exclusion in CSV/analysis exports. No external disclosure was demonstrated here.
- **Running sibling reproduced:** a private run with a real synthetic saved route is absent from
  `getWorkouts()['summary']`, but `loadRuns()` still returns it. Train feeds that list into its
  running-distance trend, predicted pace and records (`run_history.dart:133`,
  `workout_screen.dart:536`, 2203; summary history at `activity/summary.dart:959`). This is another
  violation of the same “Hidden from summaries” promise. Filter presentation aggregates at a
  shared read seam. Keep direct private history/detail and physiological movement accounting;
  this is not permission to remove measured movement from daily maintenance or strain.

### B97-07 · P2 · Historical Food time handling bypasses the stored day zone

- **Flows:** quick/default past-date logging, Copy a day/meal and changing a meal heading after
  travel.
- **Reproduction:** a historical breakfast defaults to 8 AM in the phone's current zone rather
  than the recorded day's zone. Copying a timed entry can put its timestamp outside the destination
  day. Even `inGroup`, which changes only a heading, calls `copyTo` and can shift an unchanged
  historical entry's timestamp by a day.
- **Source:** `lib/data/nutrition_store.dart:290`, `FoodEntry.copyTo` at 416 and `inGroup` at 526;
  Food detail/Quick add construct timestamps in `food_diary.dart` using current local DateTime.
- **Fix:** preserve the original instant when only grouping/metadata changes; use recorded-zone
  wall clocks and destination-day construction for an actual copy/time edit. Audit every writer,
  including Quick add, the saved-food portion screen and saved-meal logging. Keep `logged_at`
  separate and unchanged by edits to when food was eaten.

### B97-08 · P2 · Progress can move a workout into the wrong comparison week after travel

- **Flow:** revisit a session near midnight in its original zone after the phone changes zone.
- **Reproduction:** the stored day assignment is one date, while `ProgressData.load` uses the
  current OS zone and labels it the previous date. A last-seven-days comparison then counts it
  in the prior period instead. No timestamp or scientific formula change is needed to reproduce it.
- **Source:** `lib/ui2/screens/progress_screen.dart:295`; similar current-zone conversions in
  strength/goal history (`progress_details.dart`, `goal_review.dart`, `progress_review.dart`).
- **Fix:** assign absolute session/lift/chart instants through `dayLabelAtSec`/the stored day
  context. Keep calendar-only label arithmetic separate. Check Train grouping, milestones,
  analysis export and dated chart readers for the same boundary before calling travel complete.

### B97-09 · P2 · A failed Pushups save can permanently consume a Home boundary event

- **Flow:** a Home-exit event arrives while a Pushups day runs; its database write fails once.
- **Reproduction:** the native-style inbox drain removes the event. The automation state commits
  “outside”, but the Pushups session remains running because its subsequent save fails. On retry,
  the event is gone and the day stays running outside; reminders can continue.
- **Source:** `ios/Runner/AppDelegate.swift:267` removes the inbox on read;
  `lib/data/pushup_reminders.dart:512`, automation save at 548 precedes session commit at 559.
- **Fix:** retain native events until durable application succeeds, or first stage them in an
  app-owned durable inbox. Acknowledge by event ID/high-water only after the dependent writes
  commit, with idempotent replay. Cover exit, arrival, failure between both stores and restart.
  The diagnostic uses the native contract in a method-channel mock; real region delivery remains
  an additional phone test.

### B97-10 · P2 · Some editors discard the correction before it is valid or durably saved

- **Flows:** a finished Lift Log set's Fix sheet; a diary entry's portion editor.
- **Reproduction:** an invalid set Save closes the sheet, then reports the validation error;
  reopening restores the old load/reps. An injected food write failure likewise closes the
  portion editor and loses the newly typed amount, despite telling the user to retry.
- **Source:** `lib/ui2/activity/lift_log_ui.dart:1561`, Save pops at 1600 before validation/write;
  `lib/ui2/screens/food_diary.dart:387` awaits `GramsSheet.show` then writes at 446/464.
- **Fix:** validate and commit while the editor owns its draft. Close only on durable success;
  keep the error, typed values and a usable Save/Retry in place on failure. Apply the same
  contract to sibling set/portion editors without moving unrelated layouts.

### B97-11 · P2 · The shared primary button can silently clip its label at enlarged text

- **Flow:** Copy a day with four reviewed items and a partial calorie total, at 3.1x text.
- **Reproduction:** the button visually ends at “Copy 4 items · ≥”, losing the numeric total/unit.
  It still submits correctly and has the full semantic label. No RenderFlex overflow is raised,
  so ordinary “no exception” render checks pass. Flutter reports `didExceedMaxLines == true`.
- **Source:** `lib/ui2/grammar.dart:2557`, `BigButton` text at 2605 has `maxLines: 2`;
  long Copy a day label in `lib/ui2/screens/food_day_copy.dart`.
- **Fix:** let essential labels grow or keep the action short and place the reviewed item/calorie
  summary beside it in a separately readable block. Test actual paragraph truncation as well as
  layout exceptions. Recheck sibling long primary actions at 2x/3.1x and narrow widths.

### B97-12 · P2 · Lift import does not validate nested identities, timing or all load meanings

- **Flow:** Your data → Import Lift Log → review → imported workout → edit/delete a set.
- **Reproduced:** duplicate set IDs survive preflight; removing one then deletes both. Duplicate
  exercise IDs also survive and make ID-based edits ambiguous. Fractional repetitions are silently
  truncated. A set outside the workout window is accepted. An unknown **split** load mode becomes
  `platesPerSide`, although an unknown workout-exercise mode is correctly rejected.
- **Source:** `lift_log.dart:1066` preflight checks only parent workout IDs; repetitions use
  `toInt()`. `LiftSplit.fromJson` at 221 supplies a default mode; `deleteFinishedSet` at 602 uses
  `removeWhere` on set identity.
- **Fix:** validate each identity scope, integer repetitions, timing and declared enum values
  before offering the plan. Keep explicitly supported legacy missing fields distinct from an
  unknown supplied value. Reject the whole malformed payload before writing; never reinterpret
  one load meaning as another. Controls confirm valid imports and existing parent-level rejections.

### B97-13 · P2 · Pushups import accepts internally inconsistent history

- **Flow:** Your data → Import Pushups → day history/streak.
- **Reproduced:** repeated Done-event IDs count as two sets and can qualify a day twice from one
  event. An impossible calendar label passes the regex. Ended days with no end, reversed bounds,
  out-of-window events and invalid captured historical goals also pass preflight.
- **Source:** `pushups.dart:588` validates parent IDs, a date-shaped string, interval and active
  state, but does not validate the nested event identities/calendar/bounds/captured goal.
- **Fix:** strict calendar validation and per-session event identity/time/state consistency at
  preflight, with a documented legacy treatment for genuinely absent historical fields. Do not
  invent missing times or infer completed sets. Controls confirm active/duplicate-parent/bad
  top-level-settings files are already rejected. This fault requires inconsistent input; normal
  well-formed backups are not claimed to double-count.

### B97-14 · P2 · Lift imports mislabel changed metadata as unchanged

- **Flow:** export a finished lift, correct its notes/times/split information in the source app,
  then import that updated backup against existing history.
- **Reproduced:** keeping the same sets but changing notes and start time yields `unchanged=1`,
  no conflict, and the old metadata remains. Preserving a local conflict is correct; calling a
  different record “already here” without disclosing the difference is not.
- **Source:** `lift_log.dart:1157` compares only the serialized `exercises` lists.
- **Fix:** compare all portable persisted workout fields with stable normalization; exclude only
  destination-owned linkage/provenance. Report the difference as a conflict unless a reviewed
  replacement workflow is explicitly chosen. Also count actual inserted rows: a stale Lift plan
  currently reports an `INSERT OR IGNORE` collision as an imported workout.

### B97-15 · P2 · Auxiliary import settings can be skipped or become unrecoverable after failure

- **Flows:** import Lift splits or Pushups settings when there are no new history records; retry
  after history committed but the selected split/settings write failed.
- **Reproduced:** fail the Lift split write after its workouts commit. The retry plan has no new
  workouts but still contains the requested splits. Source tracing confirms Data immediately
  returns “Nothing new” and never offers those splits. The same early return blocks Pushups
  settings-only imports. A valid backup with an empty history cannot import its settings either.
- **Source:** `profile/data.dart:201`, 473; `applyLiftImport` at `lift_log.dart:1221` saves splits
  after the workout transaction; `applyPushupImport` saves settings after history.
- **Fix:** plan and apply history and optional configuration independently, with accurate outcomes
  and a retry path for every selected part. Preserve local choices until the user accepts the
  configuration replacement. A failure after one committed part must identify what remains.

### B97-16 · P2 · Pushups history import is neither atomic nor protected from a stale preview

- **Flow:** accept an import plan, then encounter a later row failure or an intervening writer.
- **Reproduced:** refusing the second session insert leaves the first committed. A row added
  after preview is overwritten by the old planned copy because `PushupDb.save` uses REPLACE,
  despite the import contract saying existing days are never overwritten.
- **Source:** `pushups.dart:655` applies rows individually through `PushupDb.save` at 505.
- **Fix:** recheck identity/conflicts within the apply transaction, preserve intervening local
  records and return actual added/skipped/conflicted counts. Save all selected history atomically
  or expose durable partial receipts. Test interruptions and replay. The stale-plan case is a
  boundary/concurrency diagnostic, not a claim that the ordinary UI routinely creates ID collisions.

### B97-17 · P2 · A failed database merge leaves committed data without refreshing its consumers

- **Flow:** Your data → restore/merge a valid database → a later table write fails.
- **Reproduced:** a food row commits before an injected reading-ledger failure. The operation
  throws, `lastImportRecords` remains zero and neither the app insight revision nor Food revision
  advances. The database changed, while already-open consumers retain their old state. Later
  hydration/projection repair is also skipped. File-level failure wording cannot describe the
  rows already committed within that file.
- **Source:** `db.dart:7267` intentionally commits pages; error propagation bypasses post-merge
  work at 7565 onward. `AppState.importEdgeBackup` at 390 publishes only after a full return.
- **Fix:** retain bounded paged memory use, but track durable progress and publish/reconcile any
  committed changes even when a later page fails. Report partial counts and an explicit retry;
  validate what can be checked before publication. Do not solve this with an unbounded in-memory
  whole-history buffer or silently claim rollback. Verify the failure through the actual UI too.

### B97-18 · P2 · Failed pause checkpoints are silent and can change resumed active duration

- **Flow:** pause/resume a live workout → checkpoint write fails → process restarts before a
  later successful checkpoint → resume the session.
- **Reproduced:** after a valid initial checkpoint, refuse the pause write. The live clock is
  paused, but the public pause API reports no failure; after clearing the in-memory clock, its
  stored counterpart is unpaused and counts the paused interval as active. The diagnostic uses
  synthetic timing and a real database refusal, not an actual phone termination.
- **Source:** `WorkoutClock.setPaused` at `gps/workout_clock.dart:101` calls fire-and-forget
  `save` at 206, which swallows persistence failures. `LiveDraft.setPaused`/the live button at
  `activity/live.dart:320`, 725 update the visible state without an acknowledged checkpoint.
- **Fix:** keep the live pause immediate while exposing/retrying unsaved state; retain an ordered
  checkpoint and acknowledge it before claiming durable recovery. Preserve the original transition
  instant on retry. Review the same rule for resume and draft writes. Do not alter the accepted
  active-time or calorie formulas, and do not reopen the already repaired final-save snapshot.

## Coverage discipline and closure

The unit of review is a user action plus its dependencies, not a page count. Applicable branches
are normal/empty/thin data, invalid/conflicting input, rejected write, retry/replay, cancellation,
restart, out-of-order completion, date/unit/privacy changes and the resulting cross-tab refresh.
All callback/navigation bindings remain a discovery aid rather than an execution certificate.

This review followed the remaining mutation families through their callers and stores:

| Family | Cross-path checks and boundaries | Evidence/remaining gap |
|---|---|---|
| Imports | Body, Lift, Pushups and database merge; parent/nested identities, malformed fields, existing data, preview/apply collision, committed-part recovery | New boundary probes confirm B97-12–17; Body findings remain B97-01–04. Vendor/NOOP container routing and protections traced, with existing CI coverage; every native picker sequence was not replayed. |
| Food writes | individual entry, Quick add food+entry, saved meal, copied meal/day, portion/regroup, filtered order, labels, delete/Undo, count refresh | Existing transactions traced; explicit day-copy second-write rollback passes. Food travel/portion faults remain B97-07/10. Library drag/manual scan/native camera remain separate physical acceptance. |
| Workout writes | private start, manual window/type/RPE, pause/resume, route tail, final stop/retry, finished correction, deletion and linked sets | B97-18 extends the checkpoint boundary. Prior exact-final-save tests pass. Route flush requeues failed buffers; no point-loss fault is inferred from that code. Real GPS/background/audio still require a device. |
| Privacy and aggregates | raw session history versus counts/weekly totals, Lift Strength/goal inputs, running charts/records, CSV/analysis versus full recovery backup | B97-06 expanded across both leaking presentation aggregates. Existing CSV filters retained. Backups intentionally preserve owned private history; daily measured movement is not a privacy-filter target. |
| Preferences and caches | Units, profile/goals, notifications/quiet hours, pins, reminders, phone steps, calculation anchors, reset/hydration | B97-05 captures ignored acknowledgements; do not fix only its two executed example consumers. Profile typed-invalid values are rejected; calculation anchors are already included in backup tables. |
| Dates and timers | stored-zone calendar boundaries, copy/regroup, period membership, nap/window correction, active clock, dated notification routes | B97-07/08/18; Naps/window edits use DayClock. Foreground zone-check errors are caught in DayZoneStore, so a suspected thrown-error foreground latch fault was ruled out. Native zone changes/ambiguous pickers are not executed here. |
| Read/render/navigation | parked-tab revisions, stale read tokens, load failure/retry, dated/direct links and Back, long labels/unknown totals | Captures and nested widget checks support layout claims; B97-11 checks paragraph truncation explicitly. No physical VoiceOver/keyboard/edge-back conclusion. The Windows batch stall is disclosed above. |
| Lifecycle/destructive actions | writer/backup draining before reset, lossless export/cleanup, rejected share/import, geofence inbox, notification action receipts, BLE ledger/ACK | B97-09/17/18 remain open. Previous encrypted media/table-list and retention regressions pass. Source review cannot certify low-space recovery, OS delivery or live-data reset safety on a real installation. |

No family is marked universally verified from source inspection. The report includes affirmative
controls and ruled-out suspicions, not only a list of faults. An audit stopping rule is completion
of this declared review/evidence matrix and disclosure of unresolved cases; it is not “no new bug
appeared after the last prompt.” Repairs need desired-behavior regressions and a successor's
cross-feature check before release. There is no finite exhaustive proof over every user/device
event sequence, and the user must not have to infer that limitation from repeated discoveries.

## End-to-end flow map

“Traced” below means source and dependencies were reviewed; it does not claim a new physical tap
or execution of every state. Earlier cloud checks remain tied to the unchanged released source.

| Family | Entry points and deeper flows traced | Result/evidence |
|---|---|---|
| Launch/onboarding | loading/failure/retry, new user, mixed imports/passphrase cancellation, pairing/skip/re-pair, profile/optional fields, onboarding latch | No new confirmed fault. Profile comma input is rejected by `Typed`, not silently erased; that suspicion was ruled out. Native pairing/permissions remain open. |
| Today | hero/detail links, Food/Protein targets, weigh-in, Body/tape prompt, Pushups, Train/Resume, notification bell, Settings, maintenance drill-down | Existing composition retained; source/captures rechecked. No new Today-specific fault. |
| Heart and wear | 10 min/hour/day, latest recorded point, gaps, no live reading, daily timeline, charging/off-wrist/pending distinctions | Existing cursor/data bounds retained in source. Native scrubbing and arriving samples remain unexecuted here. |
| Trends/metric details | Today/7/30/90 days, pins, measured-day coverage, Step calorie models, exact-day links, empty/error/retry and stored revisions | B97-05 includes pin persistence; recorded-zone consumers require the B97-08 follow-through. No new metric-formula fault. Main/large/narrow captures sampled. |
| Sleep/Recovery | date stepping, window confirm/edit/reject/reset, gaps/stages/absence, HRV explanations/history, Naps log/remove/restore, breathing pattern and methods | Prior stored-zone edit repair retained. No new physiological/reference-accuracy validation; imported nights with totals but no hypnogram need more precise absence copy. |
| Food diary | week/month/history, meal/detail, Add, My foods/meals, portion/unit, Quick add, companions, copy/save, headings/regroup, drag/swipe, delete/Undo, Log again, goals and day counting | B97-07/10/11. New copy review/explicit-commit and unknown-calorie preservation exercised at 1x/3.1x; other paths traced and existing regression evidence retained. Camera/physical drag/native share remain phone tests. |
| Food library/scan | filtered ordering, labels rename/merge/remove, food edit/delete, removed-unit handling, saved-meal review, barcode consent/cache/error/manual fallback | Source traced; no new lookup/data-source claim. No network request or camera was used. |
| Train and activity archetypes | Run/Walk/Lift/Other picker/setup, private start, pause/resume/minimise, intervals/laps/flow/match inputs, finished summary/tabs, history, retime/delete and unknown end/type | B97-06/18. Original cold final-save repair still passes, including restart and old stopped clock. Native GPS, voice/music/call/headphone and interruptions remain gates. |
| Lift Log | Gym/Home/track-only, splits/exercises/variations/load meanings, sets/repeat/rest, summary corrections/deletion, import linking, CSV/backup | B97-06/10/12/14/15. Populated Strength has fresh normal/3.1x full-scroll renders; its previously empty fixtures were insufficient evidence for privacy/real comparisons. |
| Pushups/Home | Start/away choice, Pause/Resume/Done/Undo/End, history/streaks/goals, settings, notification actions/inbox, Home permission/radius/exit/arrival | B97-09/13/15/16. Durable-event and import failures reproduced; native region delivery and lock-screen behavior remain open. |
| Progress/Body | one closed-week goal check, first-check/Next/method, rolling outcomes/inputs, all eight detail periods, latest/daily/average readings, tape/milestones, photos/compare/settings/history/edit/import | B97-01/02/03/04/06/08/10. Other weight/tape/photo functions remain accessible; no feature removed. One-day/lone-tape preservation retained. |
| Settings/devices | profile and independent units, notification classes/quiet hours, permission return, devices/find/rename/forget/re-pair, alarm set/change/test/cancel and Status | B97-05. Retained battery freshness regression rerun and passes. Band acknowledgements and current-version signing enrollment need the phone. |
| Data/recovery | CSV/database/analysis/module exports, encrypted formats 1/2, media reference counts, cleanup/cancel, restore/merge, auto backup and reset writer barriers | B97-01–05/09/12–17 cover deeper persistence gaps. Prior safe-photo/zero-image restore regressions and table coverage pass. No live-data reset or induced fault was performed. |
| BLE/analytics/lifecycle | decoder/orchestration boundaries, ledger/cursor before ACK, token/session guards, headless ownership/expiry, paused derivation and foreground catch-up, dated profiles and net-energy read seams | No production change or new confirmed protocol/formula finding. This source pass is not band continuity, power, physiological accuracy or 72-hour-soak proof. |

## Visual clarity and feature preservation

The accepted kraft/cream A+B framework remains coherent: values align on Today/Trends, Food keeps
the calorie ring and four visible macro rows, actions lead into the relevant page, and the goal
check is separate from rolling exploration. Saved full-scroll captures were re-inspected beyond
the initial viewport, including Body, Recovery, Sleep, Food, Train and their lower sections.
Fresh populated Strength and Copy a day renders add evidence beyond earlier empty/static fixtures.
The confirmed visual defect is B97-11. Hardware typography, keyboard, edge-back and VoiceOver
cannot be signed off from these captures.

Optional refinements, distinct from broken flows:

- Strength milestones repeat the before/after comparison in paragraph form. Compact dated best-set
  rows with the complete setup/details still available would reduce reading, especially at large text.
- Progress's waiting goal card can still occupy most of the first viewport. A shorter date/Next
  block with expandable evidence can preserve every checklist item without leading with a long card.
- Show missing-day denominators on Progress inputs only when coverage is incomplete, consistent
  with Trends, without adding a count under every complete metric.
- When a night has stage totals but no retained/imported timeline, say that the timeline is
  unavailable rather than asserting that a particular sensor input was missing.

These are suggestions, not accepted replacement layouts. Full-page synthetic before/after
previews remain the gate before a material UI rearrangement. No extra decorative visuals,
scientific thresholds, scores, feature removals or formula tuning are proposed by this audit.

## Repair contracts and remaining acceptance

1. Fix B97-01/02 first: canonical merged weight and lossless import identities.
2. Complete all module-import validation/outcomes and replay/configuration recovery
   (B97-03/04/12–16). Reconcile partial database merges and publish committed changes (B97-17).
3. Acknowledge settings/actions, private aggregate inputs and all recorded-zone consumers
   (B97-05/06/07/08), including sibling callers in each finding.
4. Make Home events replayable and pause checkpoints recoverable after failed writes; retain
   editor drafts until successful save (B97-09/10/18).
5. Repair visible primary-action text at enlarged sizes (B97-11), then verify full-scroll layouts.

Convert each diagnostic into a desired-behavior regression before considering it repaired. Run
targeted checks locally and the full analysis/test/visual jobs on GitHub for a source successor;
a changed binary needs its own native build, source/hash validation and testing-cache replacement.
The original diagnostic runs are not repaired-behavior evidence. Replace the cached candidate only after the successor checks pass.

Still unverified: actual Build 97 installation/upgrade and signing enrollment, BLE range loss /
restoration / background / termination / reboot, GPS/motion/audio, Home-region/notification delivery,
native Files/share/Photos/camera, VoiceOver and physical gestures, low-space/interrupted recovery,
long-history phone memory/performance, travel/DST system pickers and the 72-hour soak. The prior
429 intentional full-suite skips include 408 golden-baseline cases; synthetic render checks do not
turn those skips into pixel verification. Use disposable test data for reset/storage-fault tests.

Optional Body deletion Undo remains deferred for its profile/photo recovery contract. It is not
an additional confirmed defect. No work is waiting on Claude; release verification remains with Codex.

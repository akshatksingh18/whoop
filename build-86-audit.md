# Build 86 Reliability, Progress And UX Audit

**State:** Static audit of installed-source `0.9.52`/`85` and Akshat's reported screenshot
issues, incorporated into Build 86, which Akshat approved for implementation as one build. Findings
below are the build's repair contracts; implemented state is tracked in `todo.md`. `todo.md` owns combined approval;
`fitness-app-plan.md` owns the integrated product design; `background-sync-plan.md` owns BLE/
calculation repair; `lift-log-integration-plan.md` owns lifting parity. Build 85 remains installed
and build 70 remains accepted recovery. Findings are current work items, not a session diary.

## Audit Boundary

Reviewed the shared day controls and their callers, Today/revision/catch-up paths, wearable
detail charts, route/live/summary/history paths, diary/library/serving/weekly-food paths,
streak computation, settings reset/recovery, and AkshatOS Pushups scheduling/action persistence.
This is an end-to-end source/workflow audit, not a physical end-to-end test of every screen.
The exact early-sleep gap and individual background stalls still require timestamped on-device
evidence. Do not label every reported symptom as independently reproduced.

P1 means freshness/data reliability or misleading insight risk; P2 means a localized defect,
destructive-action risk or missing expected workflow. The screenshot issue descriptions below
contain no private food/weight/HR readings, image files or device logs. Public test fixtures
must remain synthetic. Actual historical imports stay in their private owning source area.

Existing focused tests were attempted for day navigation, sleep, routes, foods/flow, streaks and
strain step sources. They did not execute: the Flutter launcher failed with an empty
`resolved_executable_name`; a direct cached-tool retry failed to canonicalize the tool snapshot
with Windows OS error 5. A direct Dart version probe succeeds, which does not establish test
health. Existing build-85 CI evidence is unchanged; no new test pass is claimed for this audit.
A later run from the spaced path failed in the `objective_c` native-assets hook (`'D:\AI' is
not recognized`), the known path-with-spaces defect in `../dev/README.md`; use the `subst`
procedure in `setup.md` for local runs. The working tree holds documentation changes only, so
the CI-passing build-85 commit `3c141b7a` is still the code baseline.

## Findings And Repair Contracts

### B86-01: Strain Date Arrows Are Reversed (P2, Confirmed)

**Build-86 source:** day_strain sorts newest first; test pins the load-to-control order.

`lib/ui2/activity/day_strain.dart:109` sorts its dates oldest first, then passes them to
`dayNavRow` at line 271. `lib/ui2/screens/metric_detail.dart:2176` documents newest-first
dates; its left button selects index + 1 and right selects index - 1. This explains the
reported active right button going to yesterday on Today.

Normalize the shared day-control contract and fix the caller. Audit every consumer, not every
left/right icon indiscriminately: the generic metric chart uses its own oldest-first index,
and Food's -1/+1 calendar navigation is already chronological. Test the actual Strain load-to-
control path, Today, an old day, gaps, empty/single-day data, bounds and accessible labels.
Existing shared-control tests alone missed the caller's ordering error.

### B86-02: Walking Speed Is A Session Average (P2, Confirmed)

**Build-86 source:** freshSpeedMps (10 s max age, speedAccuracy gate, stationary fixes update it); live walk shows current km/h, the average is labelled avg.

`lib/ui2/activity/live.dart:999` computes speed from cumulative distance / elapsed hours.
`lib/ui2/screens/workout_screen.dart:1286` supplies distance but no current speed to `LiveFeed`.
`lib/gps/route_tracker.dart:138` already exposes per-fix `currentSpeedMps`. The displayed
number therefore changes slowly even when the location stream is healthy.

Expose fresh, accuracy-qualified per-fix speed as Current, retaining Avg in the summary/detail.
Use a timestamped short smoothing window; preserve pause/moving/elapsed distinctions. Do not
pretend an old average is current speed. A measured stationary zero is valid; missing/stale
speed is unavailable. Convert from m/s once, with unit-independent plausibility thresholds.

Additional route risks: speed is updated only after a distance-noise rejection, so valid
stationary fixes can leave old speed; `speedAccuracy` is captured but not applied; error/stall
must expire the last value. Track usable-speed freshness separately from any incoming fix.
The existing EMA uses alpha 0.15 (`route_math.dart:53`), and the iOS stream uses a 5 m movement
filter (`gps_source.dart:83`). Measure responsiveness versus noise/battery before changing it.
Do not promise a fixed 1 Hz GPS schedule, activate fake location to keep BLE awake, or request
Always permission just to record an explicitly started walk.

### B86-03: Sleep Signals Use A Calendar-Day Read (P1, Confirmed Window Risk)

**Build-86 source:** getNightSignals reads HR/HRV/respiration/temperature over onset-to-wake across every day it touches.

`lib/ui2/screens/sleep_detail.dart:247` loads the night and then `getDayTimeline(day)`.
`lib/data/local_repository_impl.dart:1648` uses that day's bundle/HR curve, preferring
calendar-day `hrv_day` when present at line 1727; respiration/temperature are day-based too.
Sleep can begin on the preceding date. Those signals can omit the pre-midnight part even if
the sleep stages span the full night. This is consistent with the reported early missing
signals, but the exact screenshot requires its retained input/export to prove attribution.

Read the absolute sleep onset-to-wake window across every intersected local day, merge/dedupe
real timestamps and preserve quality gates. Do not weaken build-85 exact-day reads for Today.
The scrubber's nearest-value search currently permits a 15-minute distance; audit each signal's
appropriate tolerance and disclose a windowed HRV value rather than claiming an instantaneous
sample. Do not interpolate missing HRV/HR or stretch the first point backward to fill a chart.
Test first/last points, midnight/DST, long nights, genuine gaps, pruned/partial data, manually
corrected sleep and stage/cursor alignment; apply the same edge/gap checks to other charts.

### B86-04: Open-To-Fresh-History Has A Derived-Data Bottleneck (P1, Confirmed Paths)

**Build-86 source:** Today's HR chart appends recorded per-minute HR past the last calculated point (provisional, 6 h bound); commits publish a revision at most once a minute.

Automatic catch-up already exists: `AppState.openSession` can call `foregroundCatchUp`.
However `refreshForeground` at `lib/state/app_state.dart:742` queues compute without awaiting
fresh Today results, and `_onDataStored` at line 2515 schedules calculation without immediately
publishing a historical-curve revision. `getChart('hr')` at
`lib/data/local_repository_impl.dart:1917` reads derived `hr_curve`, not newly committed raw
records. Pull-to-refresh performs a stronger ordered catch-up/wait/revision sequence.

Coalesce first open/resume/manual refresh around one guarded catch-up operation, publish
durable-input revisions and prioritize a bounded recent-HR/today read. Reuse the existing HR
downsampling semantics on durable history or a small incremental Today result; never persist
the RAM live-HR stream as recorded history. Show latest saved dated data, pending calculation,
coverage and distinct raw/insight freshness. No previous-day fallback labelled Today, spinning
until every old day finishes, or success stamp on cancelled compute. The full background CPU,
ownership, expiration and capability repair remains in `background-sync-plan.md`.

### B86-05: Diary Delete Does Not Ask First (P2, Confirmed)

**Build-86 source:** One confirmed delete for swipe and menu with duplicate-submit guard; drag regroup/reorder is one transaction.

`lib/ui2/screens/food_diary.dart:811` removes a row with a short Undo notice; menu Delete
at line 963 writes directly. `SwipeDelete` at `food_picker.dart:1634` delegates deletion
and does not itself prompt. My Foods already uses `confirmRemove`.

Use one diary delete command/confirmation for swipe and menu, naming meal/date/entry/amount,
with Cancel as the safe default. Keep the row on cancel/write failure, prevent duplicate
submissions and publish revisions after durable success. Undo can remain an extra safeguard,
not the only one. Unsaved draft-row removal is distinct from deleting saved diary history.

Adjacent failure risk: `_arrange` at `food_diary.dart:852` saves changed groups one row at a
time before saving order. A later failure can commit half the rearrangement. Make grouping/
order one atomic mutation and retain/reload the durable state on failure; test interrupted
multi-row moves without disturbing independent draft-only editing.

### B86-06: Workout Delete Moves The Expander; Summary Has No Delete (P2, Confirmed)

**Build-86 source:** Session delete is one transaction and cascades to the lift log; the row keeps its chevron fixed; summaries delete their own saved workout.

`lib/ui2/screens/workout_screen.dart:1033` adds trash only when expanded, shifting the
chevron. Existing history deletion asks first, but its moving placement invites the wrong tap.
`lib/ui2/activity/summary.dart:830` exposes no deletion callback on either just-finished or
opened summaries. Its result is a snapshot, not revision-reloaded late sensor history.

Keep a fixed expander position/hit target; put destructive actions in a stable overflow menu
and on the summary, with dated confirmation. Preserve Pause/Finish as explicit live controls.
Separate Discard unsaved draft from Delete saved session; provide retry if finish failed to
save. Navigate away only after deletion succeeds, and refresh open summaries after relevant
backfill/retime without losing an in-progress rating or editing state.

`lib/data/db.dart:9068` independently deletes session, route, splits and strength sets, so a
failure can leave a partial cascade. Use a transaction and one session-type-aware command;
vendor/imported workouts have separate deletion paths. Invalidate records, history, maintenance
and streaks only after success. Do not delete unrelated raw band HR or daily records. Tests
must cover failure at every stage, double taps, just-finished summaries, imported workouts,
retimed/overnight/paused workouts, and actual persisted end rather than start + active duration.

### B86-07: Gram Portions Omit The Named Equivalent (P2, Confirmed)

**Build-86 source:** Equivalents both ways from explicit conversions; each entry snapshots its conversion (`food_entry.conv`).

`lib/data/nutrition_store.dart:1216` returns early for g/ml in `portionWithWeight`.
`unitInBase` already supports the conversion needed for the reverse direction. Preserve the
entered amount as primary and show its equivalent named serving when an explicit conversion
exists, including fractional scoops/pieces. Do not infer grams from ml without density or
invent a conversion for a food that has none. Round display only, not nutrient calculations.

The diary looks up the current food definition, while `FoodEntry` snapshots macros but no
serving conversion. An edited/deleted definition can alter or remove an old entry's equivalent.
Snapshot the conversion at logging/copy time; define honest legacy fallback and do not rewrite
old macro totals. Cover picker, saved meal, log/review, diary/detail/edit/copy and quick-add paths.

### B86-08: Food Category Creation Is Missing (P2, Confirmed Gap)

**Build-86 source:** Personal labels: create, reuse, rename/merge, clear; matching ignores case.

The editor offers `kFoodCategories` only, although the string storage and category filtering
already accept custom labels. Replace required fixed chips with create/reuse/search of the
user's labels, optional blank/Uncategorised, and explicit rename/merge/clear management.
Trim and normalize matching while retaining display spelling. Preserve existing labelled foods
and diary snapshots; do not silently recategorize imported history or remove stored categories.
Test scan/manual/edit flows, empty/duplicate/long labels and filter fallback after a merge.

### B86-09: Calorie Warning Uses The Diet Goal (P2, Confirmed)

**Build-86 source:** Red only above Budget maintenance; unknown maintenance neutral; over goal within maintenance says so.

`CalorieCard` at `nutrition_screen.dart:942` treats negative goal remaining as over;
history at line 1452 turns kcal red above the typed goal despite receiving maintenance.
Separate goal remaining/progress from estimated energy balance. Apply one shared status rule:
over-goal but at/below known Budget maintenance stays non-warning/green; red means above that
estimated maintenance, not a missed diet target. Budget is the proposed primary threshold;
retain ACSM separately and expose disagreement, never pick whichever model excuses intake.

Unknown/stale maintenance is neutral, not automatic green. Today's growing maintenance/partial
food remains provisional; past-day conclusions require eligible coverage. Preserve exact goal
remaining numbers and protein/macro semantic colours. Test equality, rounding, absent inputs,
late sync, historical profile changes, model disagreement and partial today. Green does not
mean low intake is advisable or authorize automatic target rewriting.

### B86-10: Activity Streak Excludes Lifting (P2, Confirmed Scope Gap)

**Build-86 source:** Lifting and other purposeful exercise count; Rest / Life happens protection with the proposed allowance.

`lib/compute/streak.dart:223` accepts only completed runs/walks plus qualifying step-goal
days. Generalize physical-activity qualification to lifts and other purposeful exercise,
without treating meditation/breathing or a duplicate session as a second activity day.
Preserve deduped active windows, pause/midnight rules, date-specific step goals and existing
awards. Imported sets without duration must not manufacture a timed workout.

Offer separately labelled planned Rest and limited Life happens protection. Preserve continuity
without fabricating activity, and show activity days versus protected/rest days separately.
Recommend a weekly-consistency view too. Exact grace allowance, retroactive use and Pushups'
qualification rule require approval; a candidate is one unplanned protection per rolling week,
no consecutive protections, with real daily Pushups-goal completion qualifying as movement.
Do not activate this suggested policy silently. Today remains at risk, not already broken.
Pending sensor offload must be distinct from a confirmed inactive day; late activity should
reconcile the same day's protection/counts without duplicate awards or a false permanent break.

Performance risk: the loader reads all session history and the step-goal resolver performs
per-day reads from activation. Bound/aggregate reads or retain a versioned qualifying-day ledger
before adding more sources. Test deletes/edits/imports, rest/protection exhaustion, DST/timezone,
restore and no duplicate awards. A ledger must remain recoverable and recomputable from sources.

### B86-11: Weekly Protein And Coverage Can Mislead (P1, Confirmed)

**Build-86 source:** Complete-protein denominator independent of maintenance; exclusions scoped to the shown week.

`lib/ui2/screens/week_card.dart:95` accumulates protein only after maintenance is known,
then accepts any non-null protein total rather than `NutrientTotal.complete`. This can exclude
valid nutrition days because wearable maintenance is absent, or present a partial macro floor
as a complete protein mean. `NutritionWindow._mean` at `nutrition_store.dart:671` already
has the stronger nutrient-completeness rule. The card also returns `win.daysExcluded` before
limiting excluded days to its chosen week; its Monday last-week window includes today's date.

Use separate dated denominators for food calories, complete protein, paired intake/maintenance,
body, lifting and wearable measurements; scope every count to the displayed window. Preserve
lower-bound nutrient totals with explicit coverage. `weightChangeKg` is raw first-to-last,
not a seven-day-trend delta. Add seven-calendar-day means with observed-day counts and weekly/
monthly comparisons to Progress, not an unlabelled reuse of current first/last fields.

### B86-12: Reset/Media Recovery Needs An Honest Outcome (P2, Confirmed Failure Risk)

**Build-86 source:** Reset counts and offers retry for leftover backup copies and progress photos.

`lib/ui2/profile/settings.dart:504` catches every backup-pruning error after reset as if
there were no folder. A permission/storage failure can leave a recovery copy despite wording
claiming no copy remains. Distinguish absence from deletion failure and offer a visible retry.
Future Body JPEGs, Pushups receipts/protection ledger and rest timers must participate in
encrypted recovery, explicit exports and reset. Never report full wipe/restore success when
some files or notification state remain. Existing user-exported copies cannot be recalled.
Current `.osbk` covers SQLite, not external JPEGs; media-complete recovery is already a gate.

### B86-13: Damaged-Database Salvage Drops Weights And Saved Meals (P1, Confirmed)

**Build-86 source:** Salvage lists every imported only-copy table; `table_coverage_test` enforces it.

`LocalDb._salvageTables` (`lib/data/db.dart`), used by `_openOrRebuild` after a migration fails,
omits `body_weight`, `meal_template` and `live_coverage`, although the backup-import list
includes them. A failed Build 86 migration would reopen with an empty weight history and no
saved meals; the quarantined file still holds them, but nothing restores them. Add the missing
tables now, and add every new Lift Log/Body/Pushups table to salvage, import, export, wipe and
day/session delete in the same change. Add a test that fails when a table exists in the schema
but not in those lists, as AkshatOS's `check-backup-coverage.py` does for modules.

### B86-14: `body_weight` Already Changes Past Calculations (P1, Confirmed Design Conflict)

**Build-86 source:** Decided: history only. `body_weight.history_only`; ProfileHistory.on and Food's estimator skip it.

`ProfileHistory.on` uses the latest `body_weight` row on or before a day as that day's weight.
`DayUpkeep.read` (resting energy, step/run calories) and `workout_measurements` (any workout
without a captured `WorkoutClock` profile) both read it, and maintenance is computed on read.
Writing imported Body/MyFitnessPal weights into this table would therefore immediately change
past maintenance and older workout calories. That contradicts the plan's "historical import
must not reprice" rule and build 85's "data stays exactly as calculated" decision. Decide
before implementation: mark imported rows as history-only (excluded from `ProfileHistory.on`),
or accept the repricing explicitly and show it in the import preview. Test both directions.

### B86-15: Photo Capture And Media Backup Are Not Yet Feasible As Planned (P2, Confirmed Gap)

**Build-86 source:** Native camera bridge plus `photo_encode.dart` (image package, no metadata); exported encrypted backups are format 2 with photos; the automatic backup stays database-only.

No image picker or image re-encoding plugin is in `pubspec.yaml` (only `mobile_scanner` and
`file_picker`), so Body photos need a new reviewed dependency or a native bridge, including
resize and location-metadata stripping. The camera usage string says no photo is ever kept.
Encryption is pure-Dart AES-GCM at about 1.5 MB/s: 100 photos of about 0.7 MB add over 45 s per
backup, which a two-to-three-minute daily visit can cut off when the app is backgrounded.
Plan media backup as resumable or incremental (unchanged photos not re-encrypted every run),
with honest "backup incomplete" status, and measure it on the phone before cutover.

### B86-16: Rollback Target Is 15 Builds Old (P2, Release Risk)

**Build-86 source:** schemaVersion is still 49 (new tables are added on open), so build 70/85 can open the database; format-2 backups are refused by them. Promote build 85 or keep 70 deliberately before installing 86.

Build 70 is the only accepted recovery build. `schemaVersion` is still 49, as in build 70, so
rollback works today. Build 86 will likely add tables (schema 50) and a new backup format
version; existing readers reject unknown `OSBK` versions, so build-86 backups will not restore
in build 70 or 85, and Lift Log/Body/photo data entered in 86 would be invisible after a
rollback. Before installing 86: finish build 85's phone acceptance and promote it, or choose
build 70 explicitly; take a database-only export that the rollback build can read.

## Whole-App Redesign And Convenience Review

**Build-86 source:** Today, Food and Train are restructured as described in `todo.md` section 8;
rendered pages await Akshat's approval and route/back-gesture checks need the phone.

The requested makeover is structural, not a new accent on the same ring/card layout. Keep
Today / Trends / Food / Train reachable and add the planned Progress destination. Prototype
complete flows before code: brief Today review, Food logging/editing, one Lift/Walk session,
Body backdated entry/photo comparison, combined Progress and failure/recovery states.

- Today: compact date/freshness header, readable recovery/sleep/strain status and a broader HR
  history canvas, followed by daily actions/current workout. Do not let a giant recovery ring
  force the user's immediate questions below the fold. Recovery inputs/details remain reachable.
- Train: clear Start/Resume, live session identity, stable control bar, exercises integrated
  with sensor context, and chronological history with a fixed expander and safe menu.
- Food: diary-first flow, fixed add affordance, consistent portions, editable custom labels,
  and goal versus estimated maintenance clearly separated without punitive colour at the goal.
- Progress: weight trend/waist/comparable strength as the opening summary, then one weekly or
  monthly review spanning food, training and recovery; detailed measurement/photo history opens
  from compact previews. No additional dashboard of duplicated stores or opaque success score.
- All screens: stable icon/hit areas, no nested gesture conflicts, semantic Back/previous/next,
  preserved selected day/filter/scroll position where appropriate, readable large text, small-
  screen safe areas, loading/empty/stale/partial/error/offline distinctions and retry-safe writes.

Nice-to-have candidates for review, not automatically selected: Jump to Today/calendar on date
details; a compact pending-work/freshness drawer linking to the existing status screen; Return
to live workout from any tab; recent/custom-label reuse; user-marked Food day complete/incomplete
instead of treating an evening entry as proof; due-measurement shortcut; review reminders only
after durable summaries. Do not add a shortcut by removing a unique metric, restore removed AI
coach/journal/Live Activity, enable effort/scheduling features, or add mandatory tutorials.

## Pushups And Evidence-Based Combined Insights

Pushups belongs under Train as Movement breaks / Pushups, with compact Today start/Done access,
its own daily goal/streak/history, and independently deduped general-activity contribution.
`../akshatos/features.md` is the parity contract. The proposed port must preserve protected
action receipts, idempotency, Start/Pause/End, interval/nudges, goal snapshots and recovery.
It is not another WHOOP workout clock or a measured repetition/duration/calorie source.

AkshatOS schedules a bounded batch of 60 active requests; WHOOP has other critical notifications.
Use a shared notification budget and one early coordinator, not a second native delegate.
Done/Pause must persist safely while locked/cold before callback completion; tapping opens the
right feature, background actions do not switch screens. Home auto-pause currently needs Always
location, outside WHOOP's personal capability contract: resolve optional parity explicitly,
never silently grant it or remove the AkshatOS behavior. Both apps/stores stay intact for now.

`fitness-app-plan.md` specifies daily intake, seven-day weight trends, closed-week/calendar-month/
since-start reviews, actual tape dates, comparable sets, food/protein and wearable coverage.
Suggestions can ask the user to review fueling/training/recovery or gather better records.
They cannot automatically adjust calories, identify measured muscle growth, or claim a single
day's calculated deficit caused a precise amount of fat loss.

## Public Research And Acceptance

Sources checked 2026-10-09 after Akshat authorized general Apple/NIH/NIDDK research. No repo,
logs, screenshots or personal health records were transmitted.

- Apple's [speed accuracy contract](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy)
  describes speed uncertainty and invalid negative accuracy. Apply it to a fresh per-fix read.
  [When In Use authorization](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization%28%29)
  allows foreground-started location services to continue with background location enabled;
  it is not a blanket guarantee of route delivery after force-quit.
- Apple's [efficient location guidance](https://developer.apple.com/documentation/xcode/accessing-the-device-s-location-efficiently)
  makes frequency/accuracy an energy tradeoff. Tune with a locked real walk, not a UI timer.
- Apple's [local notification scheduling](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app)
  supports bounded OS-scheduled reminders. The historical 64-request limit is documented for
  deprecated UILocalNotification, not verified here as an iOS 26 UNUserNotificationCenter
  guarantee; use a conservative shared budget and inspect actual pending requests on device.
- [NIDDK's Body Weight Planner research](https://www.niddk.nih.gov/research-funding/at-niddk/labs-branches/laboratory-biological-modeling/integrative-physiology-section/research/body-weight-planner)
  models changing metabolism/expenditure over time. A fixed energy-per-kg conversion is an
  approximate retrospective estimate, not an exact forward prescription for recomposition.
- The [energy-deficit/resistance-training meta-analysis](https://pubmed.ncbi.nlm.nih.gov/34623696/)
  found different effects on lean-mass gains and strength; group findings cannot identify an
  individual's muscle gain from an app log. The [protein/exercise randomized trial](https://pubmed.ncbi.nlm.nih.gov/26817506/)
  shows context matters, not that its intensive protocol or doses should become a personal target.

Implementation gate: resolve shared contracts, retain synthetic regression tests, run the full
suite/payload checks and perform screenshot/hit-target/large-text/navigation QA. Physical gates
include locked speed/stationary/permission tests, complete-night signals, app-open recent HR
without pull, safe deletion/recovery, Pushups action races and the existing two-hour/overnight/
72-hour sync soak. Research or static source review is not device acceptance.

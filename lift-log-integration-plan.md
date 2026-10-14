# Lift Log Inside WHOOP

**State:** Implemented in build-86 source `0.9.53`/`86` (not phone-tested), with no change of
data ownership. Code: `lib/data/lift_log.dart`, `lib/data/lift_reminders.dart`,
`lib/ui2/activity/lift_log_ui.dart`. An import proposes linking each AkshatOS workout to the
finished WHOOP lift session it overlaps most (asked, one import per session, never one with sets);
the summary HR trace marks the minute each set was logged (log time, not a set duration). Installed
Build 89 retains integrated set logging, awaiting gym-session acceptance. `build-90-audit.md`
proposes improved access and optional finished-set correction; neither proposal is approved;
AkshatOS still owns its installed Lift Log. No module removal, migration, new entitlement or
calorie-model change is authorized. `todo.md` owns combined build approval;
`../akshatos/hub-plan.md` owns the cross-project boundary.

## Recommendation

Make set logging part of the existing WHOOP strength workout: one Start, one workout ID, one
clock, one Finish and one history entry. Keep the existing band/HR/strain/calorie workflow, with
Lift Log's exercises and sets alongside it. Do not launch AkshatOS, synchronize two active
workouts, embed the whole hub, or introduce a second BLE owner.

WHOOP is Flutter/Dart with SQLite; Lift Log is SwiftUI with a separate SwiftData store. Reuse
WHOOP's session host, clock, transport controls, summary and storage foundation, and port Lift
Log's domain behavior and UI into that flow. A native-view bridge would still need the same
session/data reconciliation and adds another state/persistence boundary; it is not the recommended
first implementation. No new dependency is needed merely to plan this integration.

`fitness-app-plan.md` places this flow in the implemented Body/Food/wearable Progress direction for
Akshat's confirmed recomposition goal. It owns set/HR timeline truth, unified weight/profile data,
comparability/coverage and weekly/monthly/since-start diet/body/strength reviews. That wider proposal does not change this
parity contract, MET-only calories or approval gates, and does not automatically restore old
strength-volume charts or RPE/programming features. Akshat selected repeat last set, an optional
rest timer and context-qualified records, plus persisted live Started and summary start/end times;
those additions are implemented in WHOOP Build 86 and retained in Build 87, not changes to AkshatOS.

## Current Source Boundaries

- Personal lifting uses the existing timed/sensor workout plus `LiftLivePanel`, session-linked
  `LiftWorkout` records and the same summary. The dormant `LiveStrength`/legacy `LoggedSet`
  kg/RPE UI is not the port and is not re-enabled by Build 87.
- `LiftLogDb` saves a whole domain workout durably in `lift_log`; its modes, snapshots,
  skipped/order state and source IDs are not the legacy `strength_set` sequence convention.
  The latter adapter cannot implement mode-aware deletion/Undo by resending fewer rows; the
  personal domain path uses its own durable mutations.
- `beginLiftLog`, `finishLiftLogFor` and `reconcileLiftLogs` bind to `WorkoutClock`'s session
  ID. Session and lift finalization are separate writes with reconciliation, as documented under
  Storage below; do not describe them as an atomic cross-record transaction.
- Export/restore and session deletion include `lift_log`. Recovery retains captured profile,
  pause windows and old logs, including sessions finalized after the six-hour orphan limit.
  Synthetic tests do not establish lock/kill/relaunch and failed-write behaviour on the phone.
- AkshatOS `ios/AkshatOS/features/liftlog/` and `lift-log.md` remain the source for its native
  domain/import contract. WHOOP's port does not remove the native module, change coaching CSV
  activation, or establish two-way synchronization. `../akshatos/hub-plan.md` owns that gate.

## Current Daily Flow

1. In Train, choose Lift or another existing strength activity. Setup offers a saved split,
   Empty workout, or tracking without a set log. Keep the activity type and its
   existing calorie assumptions; choosing Chest day is not choosing a different MET.
2. Start creates one durable WHOOP session with its optional lift draft before claiming success.
   The existing live sensor flow starts for that same ID. Returning to an already-running workout
   resumes it rather than opening another one; set logging also works with the band disconnected,
   with unavailable wearable measurements left absent.
3. Local Build 87 puts elapsed/Started time first, then exercise/set entry and previous
   comparable performance, followed by HR/strain/calorie context. Pause/Finish stays fixed and
   reachable; no extra top-level tab or second Start button. Splits management remains reachable
   from setup and the live workout. The installed Build 86 has the same data/IDs in its old layout.
4. Each set/edit/delete/Undo commits before a success state. Switching tabs, minimizing, locking
   or relaunching returns to the same ordered exercises and saved sets. Timing comes from the
   shared clock, not seconds for which the set screen happened to run.
5. Finish saves one combined summary: actual saved start/end times, WHOOP metrics plus split name, performed exercises and
   their sets. Train history opens that same detail. Split rename/delete never rewrites history;
   last-performance lookup uses finished logs, normalized exercise name and the same load mode.

Runs, walks and other non-strength workouts retain their current workflow. The initial strength
boundary uses `isLiftType`: weight training, bodyweight, functional, calisthenics and
powerlifting. All five offer splits while preserving tracking-only; this is not a global archetype toggle.

## Lift Log Behavior To Preserve

- Editable/reorderable splits and exercises; split name snapshots; Empty workout; up to 20 splits
  and 40 exercises per split; name validation and user-defined equipment notes.
- All six load modes: plates per side, per hand, stack setting, added bodyweight load, weight
  loaded, and known total. Retain the entered value and its unit, with no guessed bar, sled,
  machine resistance, cable ratio or bodyweight conversion. Existing data is in pounds.
- Set timestamps and stable IDs; active-set edit/delete and per-exercise Undo; all previous sets
  visible, not a truncated single previous/best set. Keep the current name-plus-mode comparison;
  adding equipment-specific comparison would be a separate change.
- Flexible split/workout linking: additions can join both, saved split edits update unlogged
  exercises, logged snapshots stay intact, first-performed ordering, today-only reorder, search,
  and explicit Remove from today versus Remove from today and split. Warn when removing logged
  sets. Do not resurrect a today-skipped exercise during later split reconciliation.
- Month-grouped finished history, confirmed workout deletion, durable active-workout recovery,
  local JSON recovery and load-mode-preserving CSV export.
- The one-hour inactivity reminder, correct workout routing, cancellation on finish/discard and
  a workout-ID-bound forgotten-finish action, subject to the timing decision below.

Keep Lift Log's remaining deferrals: finished-set editing, target reps/programming, RIR/RPE,
pinning, warm-up flags, progression, cross-mode volume charts, private historical lifting CSV
import, HealthKit and cloud/social features are not silently added. Repeat last set, rest timer
and context-qualified records are implemented in WHOOP Build 86, with behavior in
`fitness-app-plan.md`; this does not change AkshatOS itself. The dormant WHOOP strength UI is not approval to
restore them or its removed kg-lifted/fitness screens.

## Timing, Calories And Reminders

- Preserve build 85's single lifting estimate: `(conservativeMet - 1) * kg * activeHours`, using
  the captured profile and shared pause windows. Between-set rest remains part of the session;
  logging a set or resting never automatically pauses WHOOP. HR remains measured context, not
  lifting calorie pricing. Lifting stays separate from maintenance.
- Do not sum plates-per-side, per-hand, stack and total values into a purported total kg lifted,
  compare their top sets or estimate a 1RM from them. Show exercises/sets/reps and same-mode
  per-exercise performance; preserve old WHOOP rows without guessing missing mode metadata.
- Zero logged sets must not block ending a legitimate timed WHOOP workout. Save its wearable
  session without a performed lift log; confirmed Discard deletes both only when requested.
  A separate clear-set-log action must say that the WHOOP workout is retained.
- WHOOP already has a 20-minute HR-quiet workout nudge; Lift Log has a one-hour no-entry nudge.
  Use one coordinated policy for a log-enabled strength session, with the one-hour logging
  policy recommended there; retain the existing policy for tracking-only/other workouts.
  No duplicate nudges, HR-based automatic finish, or timer used as background keep-alive.
  Pushups, Body and rest-timer alerts share the implemented early notification coordinator and
  pending-request budget. `fitness-app-plan.md` and `build-86-audit.md` own the contracts; actual
  cold/locked action and ignored-request behaviour remains a phone gate.
- Ordinary Finish ends now, as WHOOP does today. Lift Log's notification Finish instead ends at
  its last set. That changes the combined duration and every time-bounded metric, not just the
  set log. WHOOP's approved Build 86 policy opens an explicit Now / Last set finish review;
  it never silently backdates the wearable record. Reminder routing and end-time reconciliation
  remain physical acceptance checks.
- Any approved last-set action must target the original ID, handle duplicate/stale/locked
  callbacks durably, reconcile pause windows and HR/zone results, invalidate affected calories/
  summaries, and leave missing data absent. Notification permission is WHOOP's own, not inherited
  from AkshatOS; denied access must not prevent logging or imply reminders are working.

## Storage And Existing Data

Build 86 stores a versioned domain workout in session-linked `lift_log` rows and splits under
`lift.splits`. The domain retains load value/unit/mode, stable set/exercise IDs, equipment/split
snapshots, active skipped/order state and provenance. Legacy `strength_set` rows stay separate;
no unknown total is smuggled into `load_kg` or notes. The database owns the log; screen drafts
are disposable input state, not another ledger.

Mutations await durable whole-workout writes and preserve recoverable input on failure. Start
and finish share the WHOOP session ID but are not one cross-record transaction: the session
stops first, `finishLiftLogFor` uses its saved end, and `reconcileLiftLogs` repairs an open log
left by a failed finalization. This is a recovery path, not proof of an atomic combined finish.
Injected failures, retry visibility, split/workout reconciliation and delete-last-set remain
part of the acceptance matrix; Build 87 does not change this persistence contract.

Offer a user-selected import of AkshatOS's existing Lift Log JSON, including a `lift-log.json`
part from its full backup. Validate the whole payload, preview and confirm before committing;
preserve source IDs, split/exercise links, snapshots, notes, date encoding/precision, modes and
units. Use synthetic Swift-to-Dart golden fixtures, including older backups without splits.
Retain origin IDs so importing again is a no-op for unchanged records and reports conflicts,
not duplication or silent overwrite.

Import old set history as source-labelled lift history with wearable metrics absent. If the same
workout already exists in WHOOP, offer reviewed linking to that session instead of creating a
second calorie-bearing workout; never automatically match on date/name alone. Unlinked imports
must not enter daily strain/lifting expenditure or manufacture historical calories. Show them
once in lift history and allow them to supply same-mode previous performance. Refuse unresolved
active-workout conflicts without dropping either draft; finishing the AkshatOS draft before a
cutover is the recommended first-use path.

Take both apps' backups before migration. Include all new records in WHOOP's encrypted automatic
and explicit backup/restore, salvage, deletion and export tests. Retain compatible Lift Log JSON
and CSV exports for recovery/review. No direct cross-app store sharing, App Group, server,
account, new app identity or private health-history read/upload is needed for this proposal.

AkshatOS remains intact during evaluation. A later switch to WHOOP as the place for new lifts,
any removal of the AkshatOS entry/store, and any change to the coaching CSV source of truth each
require explicit approval and migration proof; importing once does not establish live two-way
sync. The existing coaching-source activation gate in `lift-log.md` remains unchanged.

## Build 86 Gates And Decisions

The integrated workout and selected extras are implemented in installed Build 86. All existing
lift types, tracking-only/zero-set behavior, reminder finish and source-labelled import are covered
by its contracts/tests; physical acceptance and AkshatOS ownership cutover remain open. Local
Build 87 brings set entry directly below the shared clock and puts saved start/end/active time
first on summary, retaining the same workout/set IDs and finish path. No pinning, warm-up flags,
RPE/RIR or scheduling is selected.

The combined session and import/export use the Build 86 background ownership/persistence repair. No per-set full-day derive, scan of all history on
each tick, second BLE engine, invisible set-list redraw, extension or always-running rest timer.
Queue metric recomputation through the existing repaired scheduler. This integration cannot
promise fresh wearable metrics while iOS denies execution or the band is disconnected.

Required verification: single Start/Finish across every entry path; every load mode and unit;
split edits/skips/order and previous-performance parity; zero sets and delete-last-set; injected
save failures/retries; minimize/lock/kill/relaunch including over six hours; stale notification
actions and timing; synthetic JSON interoperability, repeat import/link conflicts, encrypted
backup/restore and schema upgrade without loss; unchanged build-85 calorie worked examples;
confirmed summary/history deletion with an atomic session/route/split/set cascade and revision-
safe backfill without overwriting manual edits (`build-86-audit.md` B86-06);
desktop/mobile layout checks; and a physical iPhone 17/iOS 26.6.2 gym session plus the background
two-hour/overnight/72-hour acceptance gates. Existing source regressions and the Build 87 layout
checks do not establish these physical results; `todo.md` owns open phone acceptance.

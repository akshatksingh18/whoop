# Lift Log Inside WHOOP

**State:** Implemented in build-86 source `0.9.53`/`86` (not phone-tested), with no change of
data ownership. Code: `lib/data/lift_log.dart`, `lib/data/lift_reminders.dart`,
`lib/ui2/activity/lift_log_ui.dart`. An import proposes linking each AkshatOS workout to the
finished WHOOP lift session it overlaps most (asked, one import per session, never one with sets);
the summary HR trace marks the minute each set was logged (log time, not a set duration). Build 85 still runs lifts as timed WHOOP sessions;
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

`fitness-app-plan.md` places this flow in the accepted planned Body/Food/wearable Progress direction for
Akshat's confirmed recomposition goal. It owns set/HR timeline truth, unified weight/profile data,
comparability/coverage and weekly/monthly/since-start diet/body/strength reviews. That wider proposal does not change this
parity contract, MET-only calories or approval gates, and does not automatically restore old
strength-volume charts or RPE/programming features. Akshat selected repeat last set, an optional
rest timer and context-qualified records, plus persisted live Started and summary start/end times;
those are accepted planned additions, not current Lift Log parity or implemented WHOOP behavior.

## Current Source Findings

- WHOOP `lib/ui2/activity/summary.dart`: `archOf` deliberately sends personal `Track.sets`
  workouts to the timed/basic screen. `LoggedSet` only models a kg load, reps, RPE and rest;
  its volume/top-set calculations do not understand Lift Log's load conventions.
- WHOOP `lib/ui2/activity/live.dart`: the unused-in-personal `LiveStrength` screen and
  `ActivityHost.onSets` already exist. They are not Lift Log parity: a fixed exercise catalogue,
  kg entry, RPE and a 90-second rest countdown replace editable splits and explicit load modes.
  `LiveDraft` preserves entries across navigation, but is not the transactional source of truth
  proposed for the combined log.
- WHOOP `lib/ui2/screens/workout_screen.dart`: `activityHost`, `_startSession`, `_bankSets` and
  `_finishSession` connect screens to AppState. `_bankSets` currently swallows save errors;
  `_finishSession` closes the session before writing its sets. Every finish path needs the same
  durable combined command, not just the live-screen button.
- WHOOP `lib/data/db.dart`: `strength_set` and `exercise_def` already exist, keyed to a session
  by convention. `saveStrengthSets` replaces supplied sequence rows but does not remove omitted
  ones; an empty list does nothing. It cannot implement set deletion/Undo by simply resending a
  shorter list. The backup-import, salvage, wipe/day-delete and session-delete paths need coverage
  for any added data. A new table is not automatically included in those allow-lists.
- WHOOP `WorkoutClock`/AppState already own manual pauses, profile capture and session recovery.
  Recent live rows resume; rows older than six hours may be finalized with an explicitly unknown
  finish. Linked lift data must remain recoverable even when that reconciliation runs.
- AkshatOS `ios/AkshatOS/features/liftlog/`: `domain/LiftWorkout.swift`, `LiftLogStore.swift`,
  the data adapters, reminder service and entry/split/history UI own the product to preserve.
  `lift-log.md` owns its contract. Build 34 is installed; the focused Build 33/34 phone checks
  are still open in AkshatOS `todo.md`.

## Proposed Daily Flow

1. In Train, choose Lift or another existing strength activity. Add a split selector to setup:
   a saved split, Empty workout, or tracking without a set log. Keep the activity type and its
   existing calorie assumptions; choosing Chest day is not choosing a different MET.
2. Start creates one durable WHOOP session with its optional lift draft before claiming success.
   The existing live sensor flow starts for that same ID. Returning to an already-running workout
   resumes it rather than opening another one; set logging also works with the band disconnected,
   with unavailable wearable measurements left absent.
3. The live screen keeps elapsed time, persisted Started time, HR, strain, calories and Pause/Finish reachable. Below that,
   show the exercises, all sets from the last comparable performance, and load/reps entry. Reuse
   WHOOP styling, with compact tracking and exercise views only if needed; no extra top-level tab
   or second Start button. Splits management is reachable from setup and the live workout.
4. Each set/edit/delete/Undo commits before a success state. Switching tabs, minimizing, locking
   or relaunching returns to the same ordered exercises and saved sets. Timing comes from the
   shared clock, not seconds for which the set screen happened to run.
5. Finish saves one combined summary: actual saved start/end times, WHOOP metrics plus split name, performed exercises and
   their sets. Train history opens that same detail. Split rename/delete never rewrites history;
   last-performance lookup uses finished logs, normalized exercise name and the same load mode.

Runs, walks and other non-strength workouts retain their current workflow. The initial strength
boundary should reuse `isLiftType`: weight training, bodyweight, functional, calisthenics and
powerlifting. Whether every one offers splits is a scope decision, not a global archetype toggle.

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
and context-qualified records are now selected for WHOOP's accepted plan, with behavior in
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
  The expanded Pushups exploration and Body/rest-timer alerts require a shared pending-request
  budget and one early WHOOP notification coordinator; `fitness-app-plan.md` and
  `build-86-audit.md` own that planning, not an approved port or delegate replacement.
- Ordinary Finish ends now, as WHOOP does today. Lift Log's notification Finish instead ends at
  its last set. That changes the combined duration and every time-bounded metric, not just the
  set log. Prefer a reminder opening a finish review with explicit Now / Last set choices until
  a one-tap last-set action is approved and tested. This changes the current Lift Log action,
  so it needs Akshat's decision; never silently backdate the wearable record.
- Any approved last-set action must target the original ID, handle duplicate/stale/locked
  callbacks durably, reconcile pause windows and HR/zone results, invalidate affected calories/
  summaries, and leave missing data absent. Notification permission is WHOOP's own, not inherited
  from AkshatOS; denied access must not prevent logging or imply reminders are working.

## Storage And Existing Data

Extend the existing SQLite session-linked strength storage, with the smallest additive schema
that preserves load value/unit/mode, stable set/exercise IDs, exercise/equipment snapshots,
split definitions/order, active skipped/order state and source provenance. Choose exact tables
during implementation review; do not overload `load_kg` or unstructured `note` with an unknown
total or a second hidden data contract. Retain legacy rows and optional fields. The database owns
the set log; screen drafts are disposable input state, not an independent workout ledger.

Start, mutations and finish need awaited, serialized, retryable persistence, including split+
active-workout edits in one transaction where appropriate. Finish uses one persisted end intent
and session ID across UI, resumed/draft-less workouts, reminder and existing gesture paths;
sensor teardown and calculation must remain idempotent around the database commit. A failed
save must keep the log recoverable and visibly unsaved, including deletion of the final set.

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

The integrated workout and selected extras are accepted for Build 86 planning, not implemented.
Resolve before implementation: enable logging for
all existing lift types or weight training first; tracking-only/zero-set behavior; reminder finish
semantics; and import/linking plus the later source-of-truth transition. Recommendations above
remain recommendations where Akshat has not decided; scope collection and a separate code
go-ahead are still required. No pinning, warm-up flags, RPE/RIR or scheduling is selected.

Implement the approved background-sync ownership/persistence repair first, then the combined
session, feature parity and import/export. No per-set full-day derive, scan of all history on
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
two-hour/overnight/72-hour acceptance gates. No tests or phone results for the proposal are claimed.

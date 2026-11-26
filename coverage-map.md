# Reachability and removal decisions

**Status:** every handwritten Dart line executes (`coverage-audit.md`). The resolved
static-reference graph is verified; manual purpose, dynamic-dispatch and native classification is
still open (`todo.md` 3r). This file records what was removed as unreachable, what is kept on
purpose, and how to judge the next candidate.

## How to judge reachability

- `tool/coverage_callers.dart` (`test.yml` scope `caller-map`) resolves method, constructor,
  operator and tear-off references. Zero inbound references starts an investigation; it is not
  permission to delete. Check interface overrides, callbacks, native channels and the developer
  Gallery before calling anything dead.
- A branch that cannot run for any real input is restructured with unchanged output. A whole
  feature or API that no production path reaches is removed only with the gates in `rules.md`:
  list what is lost, then Akshat's decision. Its tests go with it; no other assertion weakens.
- Removing UI never stops computation or storage unless that is decided too.

## Removed as unreachable

Each item had no production caller or could not run on the iPhone build; Git history keeps the
code.

- **Android, altogether:** the native target, gen5 OS bonding, LE 2M PHY, bond-refusal give-up and
  reconnect pause, the link-priority policy, notification channels and permissions, Android GPS
  settings and the legacy pairing actuator. iOS cannot remove a bond, so bond resets only log.
- **Live wrist pedometer:** `ble/live_step_runs.dart`, `ble/live_cadence.dart`,
  `BleEngine.onLiveFrame`, strap `live_coverage` writes, the wrist cadence fallback, orphan
  checkpoint recovery and `workoutStepsMeasured`. Steps come only from the phone; stored history
  stays readable.
- **HR-only live mode:** `enableHrOnlyLive`, `liveHrOnly` and the background downgrade. The live
  stream was already heart rate only, so `enableLiveStreams` is the one live path.
- **Dead round trips and helpers:** the iOS pedometer `stop`; guided-breathing cardiac coherence
  (`breathingCoherence`; the breathing screen was removed earlier); `currentWeekSoFar` and the app
  `roundTo`; `DerivationEngine.runDays`; the never-invoked batch sink; `LocalDb.samplesInRange`;
  the cycle-log write wrappers; detector `reset` methods; the one-shot shortfall option; the Home
  `clock(num?)` adapter; the deleted sleep-override writer.
- **Dormant UI:** legacy theme APIs and `AppText`, uncalled `AppColors` wrappers and palette
  getters, `DashedRing` and `Poincare` painters, the shared-axis transition, the TodayPlan
  summary mode, unshipped Body entry routes, the branded Settings row, the legacy Recovery note,
  the Gallery-only RingTrio facts row, the dormant Journal correlation report and uncalled
  journal wrappers.
- **By-construction branches restructured (output unchanged):** alarm none state, crossday
  absent notes, the single `derivableSourceSql` predicate, the day-zone consumed-change check,
  Activity Splits only where a splits builder exists, the duplicate live-distance arm, Today's
  still-filling baseline card and the last candidate-176 misses.

## Kept on purpose

Do not remove these as "unused":

- **Developer Gallery configurations** (`lib/ui2/profile/gallery.dart`) and canonical thermal
  routing: they drive the synthetic page renders. Its example-write leak is an open repair
  (`bugs.md`).
- **`PlanRow`**: active in TodayBodyRow, TodayPushupRow and the Gallery.
- **Phone source rows**: `MyDevicesView` opens `DeviceDetail` for the phone too; its tier
  labels and no-band fallback are live.
- **Typed producer fallbacks**: short-array guards in substrate preparation and similar defensive
  checks stay even where today's producer cannot trigger them.
- **Abstract-final namespaces**: the static-only classes use Dart's `abstract final` form; their
  members and call sites are unchanged.
- **`BandEntry.notify`** and the registry's non-framed handling: no current band uses it, but
  removing it reshapes the registry's nullability; take it as its own decision (`todo.md`).
- **Compatibility names** in `lib/migration/legacy_names.dart` until migration N+1.

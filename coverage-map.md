# Reachability and removal decisions

**Status:** every handwritten Dart line executes (`coverage-audit.md`). Every declaration without
an app caller is classified below by caller and purpose, and the `todo.md` 3r removal decisions are taken. This
file records what was removed as unreachable, what is kept on purpose, the
classification and how to judge the next candidate.

## How to judge reachability

- `tool/coverage_callers.dart` (`test.yml` scope `caller-map`) resolves method, constructor,
  operator and tear-off references. Zero inbound references starts an investigation; it is not
  permission to delete. Check interface overrides, callbacks, native channels and the developer
  Gallery before calling anything dead.
- A branch that cannot run for any real input is restructured with unchanged output. A whole
  feature or API that no production path reaches is removed only with the gates in `rules.md`:
  list what is lost, then Akshat's decision. Its tests go with it; no other assertion weakens.
- Removing UI never stops computation or storage unless that is decided too.

## Caller classification

From the `caller-map` artifact of main `a7b5f572` (7,434 declarations, 434 dynamic or unresolved
call sites). Each candidate was then checked by hand: its source and purpose, its test references,
dynamic-name collisions (none) and string or native dispatch (none). Everything else has an app
caller. 646 overrides have no direct caller and are reached through Flutter or an interface. The
other 220 have no app caller and fall into these classes.

**Reached; the static map cannot see the call (keep):** enum constructors (`AnalysisRange`,
`ProgressRange`, `ShellDomain`, `SourceTier`, `WorkoutActivityFilter`) and sealed-base constructors
called implicitly by their subclasses (`ProgressMetric`, `LiftChoice`).

**Test seams (keep):** the 37 `debug*`, `*ForTest` and `forTesting` members, plus
`@visibleForTesting` or test-only members: `BleEngine.bandClaimed`, the `DerivationEngine` stage
entries (`daytimeHrv`, `restlessness`, `stepsAndEnergy`, `attachNaps`, `workouts`,
`wristOrientation`), `runCancellableIsolate`, `ScreenWake.isHeld`, `DeviceAlerts.settled`,
`gallerySessions` and `HomeData.copyOrIllness`.

**Test support around a live path (keep).** The app uses an in-transaction, batch or sibling form,
and tests use these to check it or inspect state:
- **Public forms of live paths:**
  - `LocalDb.close`, `counts` and `tableNames`;
  - `thinRawArchiveBefore` (retention runs `_thinRawArchiveVia`);
  - `putObservation`, `putWorkoutSplits` and `insertRecordsBatch`;
  - `packMediaBackup` (the app uses `packMediaBackupWithCount`);
  - `dayHrCeiling`, `BootstrapClockGate.needsCorrection` and `PreparedDerivationPayload.fromJson`;
  - `NoopImporter.stepRuns`/`decideRow` (moved to `NoopIngest`);
  - `UnitsController.seed` and `CalculationStore.clearCache`;
  - `FileLog.path`/`clear` and `SleepProfilePolicy.isLegacy`.
- **Read-only state and counters:**
  - `BleEngine`: `pendingCommandCount`, `helloFailureCount`, `helloIdentity`, `clockRef`,
    `lastPagesBehind`, `historyPausedForClock` and `offloadSnapshot`;
  - BLE bookkeeping: `BurstStats.eventCount`, `ChunkFailureLedger.failureCount`,
    `SyncActivityWindow.expiresAtMs`, `AlarmConfirmation.isUnconfirmed` and
    `PendingCommand.isCompleted`;
  - calculation and data: `DeriveScheduler.offloadActive`, `StepGoals.flush`/`busy`,
    `Substrate.firstTs`/`hrValidAt`, the `isEmpty` getters of `CsvExportResult`,
    `JournalCsvParse` and `DayGraph`, and `ResolvedDaySteps.dominant`;
  - sync: `RouteTracker.pointCount`, `HeadlessSyncGate` (`busy`, `totalSkips`, `isStarved`,
    `timedOutRuns`), `BandOwnership.owner`/`foregroundIntent`, `AutoContinueRun.active` and
    `NoDurableProgressEscalation.gaveUp`;
  - screens and alerts: `FiredKeyStore.hasFired`, `BatteryForecast.isUsable`,
    `WorkoutIdleWatch.lastAskAt` and `RoughNight.rough`.
- **Resets the app does by replacement** (the engine builds a new detector instead):
  `FrameCorruptionDetector.reset`, `EmptySyncTracker.reset` and `CounterRegressionDetector.reseed`.

**App-dead capability:** Akshat approved removing the retired-feature remnants, superseded
siblings and Gallery-only components (`todo.md` 3r); they are listed under "Removed as unreachable".
The few test-only seams left are under "Kept on purpose".

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
- **Retired-feature remnants (3r):** the wrist `LiveStepDayWindow`; journal metric writes and
  readers (`putJournalMetrics`, `journalMetricFields`, `getJournal`, `getWeekdayEffect`); cycle-log
  writes; the removed Stress, heart and beats readers; the telemetry `unuploadedEvents` queue;
  `LocaleController.setCode`; the former diagnostics readers (`rawArchiveStats`, `syncLedger`,
  `recentDayDiagnostics`, `deviceRows` and the rest); the `workoutSplits` reader (splits are still
  written, backed up and wiped); the `AppState` per-day data-management wrappers; the old scan
  path; `MarginalRadioDetector`; the `LiveTick` widget; the earlier Progress windows.
- **Superseded siblings (3r):** `BleEngine.getAlarm`/`getHello`, `AlarmPayloads.simple`,
  `BurstStats.onUnknown`, `AppState.status`, `LiveWorkoutState.caloriesOrNull`, the
  `ActivityResult` ACSM/movement getters, the `LocalRepository` step-goal, sessions and workout
  writers, `UnitsController.pace`/`speed` (pages print through `DistUnit` and `formatPace`),
  `speedKmh`, `splitUnit`, `seriesOf`, `AppColors.zoneOnDark`, `sourceState`, `wearGapWhy`,
  `recoveryTau`, the sweep summaries, `protectionRefusal`, the unused food getters and summaries,
  `emaSpeed`, `fallbackSpeedMps`, `activeRouteCoverage`, `Split.paceSecPerUnit` and
  `LocalDb.liveStepsForDay`. Orphans they left: `_round2`, `_avgHr`, `_maxHr`, `_mean`,
  `NutrientMean`, `_movementCalories`, `_clock`, `_kGapMinSec`, `_caloriesScored`,
  `saveProfileFields` and `getPayloadForBand`.
- **Gallery-only components (3r):** `MacroRing`, `Actogram`, `Spectrum`, `NightStack`, the
  `SignalCard`, `ProgressCard`, `TrendCard`, `ActionCard`, `DeepDiveCard`, `Recommendation`,
  `GoalTrajectory`, `Consistency` and `StatTile` cards with `_Bar`, `RingTrio` (Home keeps a
  private any-ring check), `Legend`, `LiveHrCard.preview`, the `ZoneBar` and `IntervalLadder`
  legends and `dayNotes`. The Gallery keeps its own private `archLabel` and fixture kcal;
  `LiveHrCard` reads `AppState` and is out of the Gallery sweeps, covered by its own handoff test.
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
- **Test seams over live code:** `DerivationEngine.crossDayInputs` and
  `substrateFromDecodedPage` are `@visibleForTesting` doors onto the private paths the app runs;
  `AppState.endSession` is the link teardown the connection-lifecycle tests drive.
- **The data `Observation` model** (`lib/data/observation.dart`): nothing in `lib` builds one, but it
  is the vendor-import contract the observation-isolation test pins; take it with that import work.
- **`DayNote` and `TimelineData.notes`**: the timeline still renders notes, though production never
  sets them; the Gallery shows the rendering. Whether to feed or drop them is a later decision.
- **`LocalDb.dataHistoryDays`, `exportDaysDb` and `deleteDays`**: only tests call them since the
  `AppState` wrappers went; their DST and selection regressions stay until Akshat decides the
  per-day data feature (`todo.md`).
- **Compatibility names** in `lib/migration/legacy_names.dart` until migration N+1.

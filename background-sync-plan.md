# Background Sync And Insight Freshness

**Status:** Implemented in build-86 source `0.9.53`/`86` (not built or phone-verified): one
process-wide `DeriveStop` cancels running calculation on backgrounding and on BLE/BG-task
expiration (isolates killed, no day marked skipped, job requeued); BLE wakes queue calculation
instead of deriving; launch kind is settled before the scheduler arms and native `ready` waits for
the band owner; personal `fetch`/`processing` tasks run bounded calculation with single
completion; native breadcrumbs go to `openstrap_native.log`; background UI notifications
coalesce; open shows recorded HR past the last calculation, and Today shows band-data age apart
from the calculation time. Still open: per-input invalidation (gated on measuring short-wake
compute on the phone),
high-rate-path CPU profiling, and every device gate below. Build
`0.9.52`/`85` remains installed. Akshat reports an iPhone 17 on iOS `26.6.2`, normally
opening WHOOP for only two or three minutes a day to read insights. He is unsure whether
the supplied afternoon gap included swiping the app away. `todo.md` owns approval and
release gates; `bugs.md` owns the private-log findings and their attribution limits.

## Required Behavior

Brief daily viewing must be the normal supported workflow. Keeping the screen on,
leaving WHOOP visible, charging throughout the day, and repeatedly pulling to refresh
must not be prerequisites for collection. Ordinary backgrounding and screen lock are
different tests from force-quit, Bluetooth disablement, and reboot.

Keep two independent freshness measures: the newest durably stored band timestamp and
the input timestamp/revision covered by a derived result. A live HR event, calculation
completion time, or successful connection must not make old historical data look current.
On open, show the last valid dated result immediately, catch up today's inputs first,
and replace it when calculation really commits. Never label an older day's value as today.

The expanded report explicitly asks for the last ten minutes of recorded HR on open without
pull-to-refresh. Live HR and historical HR are different sources: a fresh live value cannot
prove saved coverage. Display true empty versus pending transfer/calculation distinctly, while
body, food and lift logs remain usable offline. `build-86-audit.md` B86-02/B86-03/B86-04 covers
current speed, complete-night chart reads and the recorded-HR publication bottleneck.

The engineering target is regular background history commits near the existing 15-minute
cadence in normal connected use and fresh Today results during a brief visit, preferably
within the current 15-second refresh wait. These are device acceptance targets, not iOS
scheduling guarantees. Range loss, denied permissions, disabled Bluetooth, first unlock
after reboot, resource pressure, and OS scheduling can delay freshness. Catch-up must be
resumable and the UI must report that delay honestly.

## What The Research Establishes

Public platform research was checked on 2026-10-09 without uploading logs, source, or
personal records. No authoritative source establishes an iPhone-17-specific fix for this
app; the observed CPU-limit exits and the app's execution paths are the stronger evidence.

- Apple permits background BLE notifications and restoration but describes short wake
  windows, approximately ten seconds, and possible throttling or termination for excess
  work. This is not a fixed entitlement to continuously calculate in Dart. A Dart timer
  cannot itself wake a suspended process. [Apple background BLE guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html).
- Restoration requires a preserved pending/active Bluetooth operation and a corresponding
  event. For iOS 26, AccessorySetupKit adds documented force-quit/Control Center restoration
  cases; it is not a requirement for every ordinary system-termination restoration.
  Reboot restoration waits for first unlock, not necessarily an app open. ASK support in
  source is not proof of this phone's provisioning or relaunch. [Apple TN3115](https://developer.apple.com/documentation/technotes/tn3115-bluetooth-state-restoration-app-relaunch-rules),
  [Apple DTS clarification and test advice](https://developer.apple.com/forums/thread/840468).
- `BGAppRefreshTask` and `BGProcessingTask` provide separate OS-granted opportunities for
  refresh and longer processing. Native expiration must cancel work, not just report
  completion. The earliest requested date is only a floor; neither API promises a
  15-minute schedule. [Apple background-task setup and cancellation](https://developer.apple.com/documentation/uikit/using-background-tasks-to-update-your-app),
  [Apple scheduling contract](https://developer.apple.com/documentation/backgroundtasks/bgtaskrequest/earliestbegindate).
- `BGContinuedProcessingTask` on iOS 26 is for finite, user-initiated work begun in the
  foreground, with visible progress and cancellation. It is not an all-day unattended
  sensor-sync service. It may later suit an explicit reanalysis, but is not the first
  repair. [Apple continued-processing guide](https://developer.apple.com/documentation/BackgroundTasks/performing-long-running-tasks-on-ios-and-ipados).
- Phone steps can be queried from the motion coprocessor's last seven days; this does not
  require WHOOP to count every phone step live. It does not recover wrist-only motion when
  the phone is absent. [Apple CMPedometer history](https://developer.apple.com/documentation/coremotion/cmpedometer/querypedometerdata%28from%3Ato%3Awithhandler%3A%29).
- Low Power Mode disables Background App Refresh and reduces available background time.
  Record actual power/refresh state during tests; do not infer it from the iPhone model.
  These settings cannot repair code that overspends its CPU budget. [Apple runtime status](https://developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus),
  [Apple Low Power Mode guidance](https://support.apple.com/en-us/101604).
- MetricKit's CPU-resource-limit exit count means background termination for excess CPU,
  but the supplied daily aggregate has no individual timestamps or build attribution.
  [Apple exit-metric definition](https://developer.apple.com/documentation/metrickit/mxbackgroundexitdata/cumulativecpuresourcelimitexitcount).

## Confirmed Source Findings

These are execution-path findings, not proof that any particular one caused an individual
logged gap. Existing build-84 fixes remain present in build 85.

1. `lib/main.dart` already calls `FlutterBluePlus.setOptions(restoreState: true)` before
   other plugin work. The pinned Darwin plugin implements `willRestoreState`, including
   connected peripherals and notifying characteristics. The separate native recovery
   central is also restorable. Adding the same option again or arming a competing central
   while connected is not the repair.
2. `_initSteps` initializes/arms the derive scheduler before awaiting `_settleLaunchKind`.
   `OpenStrapApp`'s first-frame callback calls `openSession` and starts a foreground timer
   without checking native foreground state. `openSession` clears the background gate.
   These leave possible startup races despite the later UIKit classification fix.
3. `DeriveScheduler.setBackground` only cancels queued timers. Already-running day workers,
   cross-day work, and detached baseline rescans can continue. The logs demonstrate a
   heavy pass finishing almost a minute after backgrounding.
4. `runHeadlessSync` still calls `DerivationEngine.run(background: true)` after transfer.
   "Light" selects one day, not a cheap calculation: it can stage sleep, refresh baselines,
   run cross-day work, notifications and storage housekeeping. `DerivePacing` allows four
   minutes per background worker, inappropriate as a BLE wake's execution budget.
5. `IosBleRestore.init` announces `ready` before `AppState` and its wake handler exist.
   A queued native wake can start headless sync while AppState also initializes its band
   session. `BandOwnership.acquireForeground` waits without a deadline. The headless
   gate's 15-minute future timeout does not cancel its body. Do not shorten it and assume
   work stopped: an orphan could continue touching the band/DB after ownership changed.
6. Native BLE expiration currently ends its UIKit background assertion without telling
   Dart to stop. The full-source BG-task expiration likewise reports completion without
   cancelling Dart, and can report completion again when Dart returns. That BG scheduler
   is excluded from the installed personal build; it is not an observed build-85 wake.
7. Personal iOS deliberately retains roughly 100 Hz wrist motion for passive band-only
   steps. The logs measure approximately 105 samples/second, not 105 BLE callbacks/second.
   The ingest path also emits UI notifications each second while backgrounded. Profile
   these costs; do not assume the motion stream alone caused the CPU exits.

## Recommended Repair

One coordinated candidate after approval, reusing existing schedulers, leases, isolate
helpers and database jobs. No cloud service, push backend, silent audio, fake GPS usage,
new library, or wholesale native rewrite is proposed.

1. **Make lifecycle and bootstrap authoritative.** Resolve UIKit state before starting
   compute or foreground-only services. Guard the shared `openSession` path and its
   callers, including the first-frame callback. Coordinate native `ready` with the chosen
   band owner so a cold wake cannot launch competing app/headless sessions. Handle true
   foreground arrival during initialization without permanently holding work.
2. **Cancel actual calculation on ordinary backgrounding.** Extend existing cancellable
   isolate machinery to a lifecycle/run-generation stop signal. Stop dispatching days,
   cancel active CPU workers, and suppress follow-on rescans/housekeeping. Keep completed
   atomic results; requeue unfinished jobs. Cancellation must bypass generic day-failure
   handling, raw pruning and success/finalization stamps. A future timeout alone is not
   cancellation. Resume remaining work on the next appropriate execution opportunity.
3. **Keep BLE wakes capture-first and bounded.** Connect/adopt, receive, durably commit,
   then ACK. Remove the unconditional whole-day derive from the short BLE fallback, and
   enqueue affected compute work instead. Propagate native expiration to Dart, stop safely
   at transaction/protocol boundaries, and leave a valid restoration owner/pending operation.
   Bound ownership waits with coordinated cancellation/retirement; never forcibly release
   a lease while its old worker can still issue ACKs. Do not replace one safe owner with
   endless reconnect loops or disconnect every healthy live connection after ten seconds.
4. **Preserve wrist-only steps while reducing unnecessary CPU.** First remove invisible UI
   refresh/repeated readout work and profile decoding, counting and checkpointing separately.
   Keep measured dense sample windows, per-minute counting/checkpoints and active-workout
   behavior. Do not silently switch passive capture to HR-only, duty-cycle it, or count
   sparse samples as full coverage. If capture alone still fails the phone budget, present
   the measured tradeoff to Akshat before changing this unique primary metric.
5. **Recompute changed inputs, not every recent day on every open.** Prioritize today and
   the newest completed sleep; cache reusable night results; invalidate on raw, phone-step,
   food, session, profile, manual sleep/nap, algorithm and baseline changes, not just one
   global cursor. Keep cross-day dependency windows correct. Only permit small, measured
   units in short background slots, with margin for transfer/commit/expiration. Preserve
   existing formulas; any changed analytics output requires a separate version decision.
6. **Add OS-granted calculation opportunities to the personal profile, if approved.**
   Recommend a bounded short-refresh task plus opportunistic processing for pending
   insights, with no external-power requirement for freshness-critical processing. Use
   charging for optional expensive backlog work; normal daily use must not depend on it.
   Repair cancellation and single completion before activating the existing BG bridge;
   do not merely remove `kPersonalSideload` guards. Change AppDelegate registration,
   permitted identifiers, modes, transformation, payload validator, manifest and tests
   together. No widget/Live Activity extension, App Group or HealthKit is needed for this
   proposal. Sideload signing/install and real task execution still require validation.
   Scheduling is supplementary; fast foreground catch-up remains necessary if iOS skips it.
7. **Prove recovery and expose honest freshness.** Preserve stable plugin/native restoration
   identifiers and ASK provisioning. Verify notification subscriptions and queued wake
   delivery after system termination, not only after explicit disconnect. Add local launch
   ID/build/OS, native owner/restoration/expiration breadcrumbs, worker duration/CPU measures,
   and separate raw/derived freshness. Native diagnostics must be available even when Dart
   never becomes ready. Avoid per-frame logging and personal payloads. A missing wake is
   diagnosable separately from a launched app that never reached its sync handler.

### Automatic Foreground Freshness And Workout GPS

`refreshForeground` queues derive, while pull-to-refresh performs an ordered catch-up and
wait for Today. `_onDataStored` publishes neither an immediate recorded-curve revision nor a
new derived curve; the repository currently serves historical HR from `hr_curve`. Automatic
catch-up already exists, but it must produce visible durable progress without a manual gesture.
Coalesce cold foreground open, resume, reconnect and pull around the existing single owner;
await/observe today's committed input/result and retire stale loads. Use bounded durable-record
downsampling or incremental Today work for recent HR, preserving the existing formula and gaps.
Heavy backlog/fitness reports/media work must not block this fast path or run in short BLE wakes.

GPS is a separate route-workout capability, not a band-sync workaround. An explicitly started
walk already configures background location with While In Use. Pass fresh accuracy-qualified
tracker speed to the live UI, distinguish Current from Avg, expire stale speed and fix stationary/
pause handling. Tune movement filtering/smoothing only after response/noise/battery measurement.
Do not enable location outside a real route session, add Always for ordinary walks or promise
fixed GPS timing. [Apple When In Use contract](https://developer.apple.com/documentation/corelocation/cllocationmanager/requestwheninuseauthorization%28%29)
and [speed accuracy](https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy)
support this boundary. A missing pre-midnight sleep chart signal also requires the correct read
window; repairing sync alone does not repair a calendar-day/night-window mismatch.

## Decisions And Verification Gates

- Approval is needed for implementation and for adding `fetch`/`processing` to the personal
  profile. Recommendation: include both with bounded work, preserve passive wrist steps,
  and keep charging-only processing optional. The existing build/profile is unchanged.
- No feature removal is proposed. HR-only passive background capture would lose wrist-only
  step measurement when the phone is absent; it requires a separate explicit decision if
  profiling shows the preserved stream cannot meet the budget. Sleep, HRV, recovery, strain,
  HR, breathing, workouts, step formulas and maintenance formulas must remain reachable.
- Tests must cover background cold startup, queued wake before AppState, foreground arrival
  mid-startup, cancellation during sleep/day/cross-day/rescan, native expiration, ownership
  retirement, commit-before-ACK, killed-before-commit replay, interrupted jobs/pruning,
  step checkpoints, dependency invalidation, date rollover and raw-versus-derived timestamps.
- Test fresh recent recorded HR after ordinary cold open/resume without pulling, coalesced
  concurrent requests, a true empty day, late commits during a visible chart/summary, complete
  sleep-window reads and locked walking current-speed/stationary/stale/pause behavior. Separate
  GPS delivery failure from a healthy GPS stream displayed as a cumulative workout average.
- On iPhone 17 / iOS 26.6.2, test an ordinary locked two-hour afternoon and overnight, with
  only two-to-three-minute visits. Check maximum durable-data age and insight input age,
  not just log activity. Separately test range loss/return, system termination, force-quit
  with ASK provisioning verified, Settings versus Control Center Bluetooth changes, reboot
  followed by first unlock, power/refresh restrictions and a locked workout.
- Require a 72-hour soak, retained step/metric parity, no repeated CPU/resource exits in
  fully covered MetricKit windows, and no permanent recovery stall before acceptance. Daily
  counts cannot timestamp individual kills; compare like-for-like windows/builds. Record
  battery impact and actual task execution. Unit/CI success or one successful background
  transfer cannot establish this behavior. Keep build 70 as recovery until all gates pass.

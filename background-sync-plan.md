# Background Sync And Insight Freshness

**Status:** Build 99 (`e52d571a`) is the validated testing candidate; Build 91 is the last reported
installation and background phone acceptance remains open. `todo.md` and `setup.md` own
release/device evidence; full app/package/visual run `40003142620`, native `40002250844` and IPA
validation pass. The repairs in `build-95-repairs.md`, retained in Build 99,
leave commit-before-ACK and derivation formulas unchanged. Reset invalidates and drains backup
publication, stops capture, holds calculation on every platform, and awaits active phone-step,
profile and workout writes before wiping. Route arming also rechecks reset/stopped state after
permission/storage waits; a failed final session save stays stopped and retryable.
The independent Build 96 audit found that a cold restart before retry can still overwrite
previously saved HR/zone evidence with an empty accumulator (B96-01 in `build-96-audit.md`).
Build 97 stages the exact final session row and HR/zone trace in the existing durable workout
clock before final writes. Cold retry replays it, even beyond the live-resume age ceiling, while
privacy/RPE retain their current stored values. Local and full cloud regressions preserve end/profile/trace and
measured summary fields across restart. No native background behavior is claimed by these tests.

Build 98 repairs `build-97-audit.md` B97-09/17/18. Home-region reads retain the native inbox;
Dart persists session receipts and automation before acknowledging event IDs. Failed session or
preference writes replay without duplicate transitions. Pause/draft save failures expose retry,
including on foreground return, and retain their original instants. Partial paged restores report
committed rows, reconcile derived projections/cache and publish refresh revisions even on failure.
Synthetic failure/replay tests, full Linux/visual run `39943912609`, native run `39942864975`
and downloaded IPA checks pass; `todo.md` 3m tracks the completed software release. Real region
delivery, termination and background scheduling remain phone gates.
BLE commit-before-ACK remains unchanged; algorithm 98 only changes recorded-zone attribution.

The completed Build 99 review (`build-98-audit.md`) adds repairs for acknowledged Home
configuration/native stop, cache-removal ordering and reset preference/keychain cleanup. A
failed cleanup remains retryable and cannot report complete deletion. Targeted synthetic checks
and full cloud/native checks pass; real Home-delivery checks remain open. The band history
drain and ACK protocol are untouched.
The successor also waits for iPhone notification cancellation during reset and retains reminder
plans when cancellation fails. Its Pushups background mirror includes recorded day bounds, so
travel-day actions can be validated without a background SQLite open. Backup last-run marking
stays inside the publication lock; bookkeeping refusal produces a warning about a valid file.
Wake-window wall times follow the recorded zone, with calendar-next-day targets across DST;
the existing history minimum, window duration, band commands and transfer/ACK rules stay unchanged.
Reset table deletion, calculation-mirror removal and final native/preference cleanup also hold
the CalculationStore read/write gate. Concurrent readers cannot heal an erased anchor from a
remaining mirror. This gate is per isolate; capture/derivation shutdown and the physical reset
and background-delivery matrix remain necessary. No ACK or band command ordering changes.

The following background contract originated in Build 86 and retains subsequent repairs.
The active coverage follow-up (`coverage-audit.md`, not in the cached Build 99 IPA) also fixes
the restoration-expiry and gate-ceiling paths that omitted the registered headless transport
stop. Synthetic callbacks verify the request and late-lease protection; native disconnect,
expiration timing and physical delivery remain phone gates. Cooperative stop is not cancellation
of an arbitrary unresolved future, and the production gate ceiling/ACK protocol are unchanged.
An expired transfer also retains its original cancellation generation so a new calculation
cannot start afterward. Startup presents Retry after its existing six-second ceiling, sharing
one pending initialization across retries instead of overlapping it. Synthetic controls pass;
these bounds do not cancel an arbitrary unresolved native read.
Build 86 introduced one
process-wide `DeriveStop` cancels running calculation on backgrounding and on BLE/BG-task
expiration (isolates killed, no day marked skipped, job requeued); BLE wakes queue calculation
instead of deriving; launch kind is settled before the scheduler arms and native `ready` waits for
the band owner; personal `fetch`/`processing` tasks run bounded calculation with single
completion; native breadcrumbs go to `whoop_native.log` (`openstrap_native.log` before Build 89); background UI notifications
coalesce. Build 86 exposes recent recorded HR through the repository, but Today's chart still
read only its calculated timeline and Status used a launch-only sample. Build 87 connects
Today to the raw-extended chart plus recorded 10-minute/hour windows and makes Status/Today read
the advancing durable record frontier, separately from calculation time. Queued calculation is
labelled separately from a running pass. Today's activity payload and calculation timestamp now
come from the same committed, served-version result; a later-day cancellation cannot leave that
result hidden behind stale end-of-pass freshness. A bounded adapter-state probe precedes cold connect;
burst continuation stops if no new history records arrive, rather than trusting cumulative
connection totals. Synthetic regressions pass locally and in CI; physical cold-wake/short-visit checks remain open. Build 87's validated testing IPA includes exact-input/version-stamped reuse of pure RR/HR
night calculations (process-local, bounded to three days). Profile, baselines, temperature, day
HR/strain/steps and remaining cross-day preparation still recompute; any RR/timestamp/window/
stage change invalidates its corresponding cached work. Forced runs clear reuse. Worker
cancellation cannot publish new cache state or finalize/prune a partial day. Completed worker
elapsed time and reuse counts are logged, not asserted as CPU savings. Build 87 also scopes
wear evidence to the current connection: known off-wrist silence suppresses the liveness bounce,
stream re-arm and fast battery polling; actual disconnects/write failures still recover, and
normal RTC/battery/offload polling stays active. Pre-link replay and far-future wear stamps are
refused (60-second RTC slop); older events cannot override newer current-link evidence. These source repairs do not recover unrecorded data or guarantee iOS wake scheduling.
Still open: phone CPU/freshness profiling and every device gate below. Installed Build 89 counts
phone steps only and arms the heart-rate-only live stream; high-rate wrist capture is no longer
personal scope. Akshat reports an iPhone 17 on iOS `26.6.2`, normally
opening WHOOP for only two or three minutes a day to read insights. He is unsure whether
the supplied afternoon gap included swiping the app away. `todo.md` owns approval and
release gates; `bugs.md` owns the private-log findings and their attribution limits.

Build 90 source records time-zone changes from the native timezone/significant-time-change
notifications in a durable inbox, acknowledged after a SQLite transaction. Launch, foreground
and headless/foreground sync also check the current IANA zone. Workers receive a persisted
snapshot so re-derivation cannot silently switch to the phone's new zone. A forward date jump
opens the new label at the change instant; a westward jump holds the current label until a
midnight advances it. These seams partition absolute time without repeated labels. The pure
travel/DST and storage/restore checks pass; open-app and background native delivery still need
phone verification. No new background permission or guaranteed wake schedule is introduced.

Build 90 adds local `[WAKE]` records with a wake id/reason, absolute start time and
monotonic elapsed time. Transfer start/end, durable commit (or failure), queued calculation,
calculation start/end and budget/native expiry share that id. Connection-total record counts
are explicitly separate from records committed during the wake. BLE callbacks created before
a wake are attributed only when exactly one wake is active; ambiguous attribution remains
absent. Logging is best effort and never awaited by an ACK decision. `[BURST]` lines report
announced versus received traffic/historical counts, buffered decoded-record timestamps, and
continuity against the preceding received burst (contiguous, gap, overlap/replay or unknown).
These observations do not prove loss and do not enable a stricter WHOOP 4 count gate. The
existing commit-before-ACK, cancellation and headless ownership policies remain unchanged.
Phone validation still requires three ordinary nights and one force-quit night; logs stay local.

Session enrichment in a foreground-owned repository/derivation engine publishes AppState's
shared session-change signal after each successful session write, including deferred HRR.
The callback is omitted in a headless instance; no UI owner is manufactured. This does not
move decoded-row/cursor commits or the history ACK, and native phone acceptance remains open.

## Required Behavior

An isolated current-code synthetic DB/repository test reproduces the B88-05 overnight mismatch:
a no-sleep row today sets overnight freshness to today while `getToday` serves the previous
night's readiness with no held-over flag. This verifies the read contract, not a phone symptom.
The repair must derive night identity and values from the same committed served result, and
retain an explicit absence/dated-prior state. `bugs.md` owns the reproduction; implementation
remains deferred in `build-88-plan.md`.

Build 88's proposed B88-05 package in `build-88-plan.md` starts with physical verification of
these Build 87 repairs, not another assumed rewrite from Build 86 screenshots. Its bounded
diagnostics distinguish transfer progress, durable record frontier, derive queue/start/cancel/
finish, served algorithm version and visible age. Evaluate actual CPU/freshness before tuning
speed filters or adding collection work. The HRV integrity repair needs compatible versioned
recomputation but must preserve cancellation, reuse invalidation, commit-before-ACK and pruning
protection; missing raw history cannot be recreated by sync. No new background permissions or
constant execution guarantee is selected by the accuracy plan.

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

These findings describe the Build 85 audit baseline, not the current repaired implementation.
They are not proof that any particular path caused an individual logged gap. Build 86 implements
bounded ownership/cancellation and personal tasks; Build 87 adds reuse and wear-aware recovery.

**Build 87 source re-audit (read-only):** findings 3 and 5 persist in part. Detached rescan,
reanalyze, sleep-override and nap passes still escape background cancellation.
`acquireForeground` still has no deadline. BG expiry cancels calculation, not the headless drain,
so the gate timeout can release the band while that run continues, which breaks repair contract
item 3 below. Newly found: the engine's `_running` refusal makes the scheduler mark a queued job
complete, and `openSession`'s busy early return skips its background-flag reset. The overnight
freshness row can label a prior night as today's, and short WHOOP 4 bursts are ACKed by design.
Background log lines also never reach the file log. `bugs.md` "Overnight Freshness And Sync
Lifecycle Gaps" owns the details; B88-05 owns the repair.

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

## Repair Contract

The approved repair reuses existing schedulers, leases, isolate helpers and database jobs.
The status above separates implemented Build 86/87 work from remaining phone measurement. No cloud service, push backend, silent audio, fake GPS usage,
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
   behavior. Superseded for the personal build by Akshat's explicit Build 89 decision: steps
   are phone only and live capture is HR-only (`kHighRateLive`), so no passive wrist capture
   remains to budget.
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

`refreshForeground` queues derivation, while pull-to-refresh performs ordered catch-up and
waits for Today. Build 86 publishes durable-commit revisions and serves recent recorded HR beyond
`hr_curve` through bounded six-hour durable-record downsampling; recorded gaps stay gaps and the
next calculation replaces provisional points. Cold open/resume/reconnect/pull share existing
ownership. Build 87 reuses unchanged pure calculation inputs and distinguishes known off-wrist
silence from a failed link. Automatic foreground freshness still requires timed phone verification.
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

- Akshat approved implementation and personal `fetch`/`processing` modes; both ship in installed
  Build 86 with bounded work and preserved passive wrist steps. Charging-only processing is an
  extra opportunity, not required for freshness. Local Build 87 changes no capability/profile.
- Akshat made the explicit decision this item reserved (Build 89): the personal build counts
  phone steps only and arms the HR-only live stream, giving up wrist-only steps when the phone is
  absent. Sleep, HRV, recovery, strain,
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

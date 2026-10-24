# Reconnection Evidence and iPhone Verification Risk

The Android observations below are retained as protocol/implementation evidence only. Akshat's
personal product scope is now iPhone-only, so no Android fix, build, or device validation is planned
unless that scope is explicitly reopened. The active work is proving the separate CoreBluetooth
restoration and reconnection path on the personal iPhone build.

**Current verification:** Build 91 is the last reported installation. Build 99 (`e52d571a`,
`0.9.66+99`, algorithm 99/schema 50) is the validated testing candidate. All 22 B98-01–22,
eighteen B97, seven B96 and 29 earlier repair contracts are retained. Full app/package/visual
checks, the macOS build and downloaded IPA validation pass; `setup.md` owns source/hash/workflow
evidence. The calm A+B presentation remains; no feature or scientific coefficient changed.
Build 70 recovery is unchanged. Physical background/restoration, native permissions, gestures,
delivery, current-version installation and signing gates remain open in `todo.md`.

**Build 98 repair state:** imports validate identities/counts/times and commit history/configuration
together; Body projections and partial-restore readers reconcile; settings/actions acknowledge
write refusal, and haptics preserve transport success/failure for both generations without claiming
physical delivery. Private summaries and recorded-day consumers follow their contracts. Home
events are receipt-protected, live checkpoint failures are retryable, editors retain drafts and
enlarged action labels remain visible. All 52 added synthetic regressions pass within full run
`39943912609` (3,478 passed/429 skipped; 137 visual checks/570 captures); eight iOS contract
checks and native run `39942864975` pass. `build-97-audit.md` owns individual contracts and the
unexecuted-device limits. These software results do not establish physical acceptance.

The subsequent `build-98-audit.md` review is complete in Build 99. B98-01–22 have verified
repairs for profile-history rollback, calculation-cache resurrection, refused backup Off,
forgotten-device recovery mirrors, Home persistence/native stop and partial reset/keychain
cleanup, recorded travel-day consistency, restored profile anchors, active lifting windows and
barcode input/opt-in/scrolling. Forty-six added checks have passing targeted groups, alongside
existing settings/cache/nutrient/consent checks. Run voice, reminder/reset cancellation, backup metadata/ordering and
Body read/camera lifecycle, invalid GPS input, elapsed-alarm wording and Food timestamp
preservation and honest unavailable-timeline wording are in the cached Build 99 IPA. Full run
`40003142620` passes 3,524 app tests (429 intentional skips), independent protocol/analytics
suites and 143 visual checks/589 captures; native `40002250844` and local payload checks pass.
Instrumented handwritten root Dart coverage is 75.23%, not every-line or hardware verification.
Reset also holds deletion/mirror cleanup against concurrent self-healing calculation reads,
including legacy preference-only anchors; two concurrency controls and all 16 durability cases
pass. The delivered testing source includes B98-22. Earlier staging IPAs were never delivered.

The coverage-directed follow-up on `build-100` is active in `coverage-audit.md`. Fourteen confirmed
families have source repairs and initial targeted evidence: restoration/gate transport stops,
recoverable diagnostics, concurrent/replay-safe Pushups inbox files, atomic linked Lift edits,
late editor results, acknowledged onboarding, recorded-zone manual workout corrections,
expiry-before-calculation, bounded/coalesced startup, honest Zones read/reflow states and
post-commit Lift refresh outcomes and retries after a failed recent-day rescan.
They are not in the cached Build 99 IPA; full successor verification remains open.

**Symptom:** Pairing works the first time in a session (band off-wrist, double-tap the FRONT of
the sensor until the LED pulses blue — NOT the back, which just shows a battery-level LED and does
nothing for pairing). Once connected, live data works fine.

**But:** after ANY disconnect — closing the app, or just walking out of Bluetooth range and back —
the app shows "Connecting..." then falls back to "Not connected." It never silently recovers. The
only fix is repeating the full off-wrist double-tap-to-blue sequence again, every time.

**Confirmed this is NOT expected/hardware-mandated behavior:** the official WHOOP app reconnects
silently and automatically after a routine disconnect — no physical interaction with the band
needed. WHOOP's own docs only call for the manual tap sequence during initial pairing or genuine
troubleshooting after a full unpair. So this looks like a real gap in `edge`'s reconnection logic,
not a WHOOP 4.0 hardware limitation.

**Leading hypotheses (unverified — secondhand research, confirm against the actual source before
assuming correct):**

1. **Swallowed-exception bug:** reconnection logic may be wrapped in a `try`/`catch` where a single
   dropped frame/thrown error kills the reconnect listener/loop permanently for the rest of the
   app's process lifetime, instead of catching the error and re-arming whatever's listening for
   the peripheral to come back. Look in `lib/ble/` for `try`/`catch` around connection/reconnection
   code — check whether the `catch` actually retries or just logs-and-drops.

2. **`autoConnect` not set correctly:** the standard self-healing Android BLE pattern is
   `BluetoothDevice.connectGatt(context, /* autoConnect = */ true, callback)`. Check whether `edge`
   uses `autoConnect: true` anywhere, or relies solely on `CompanionDeviceManager` (CDM) observation
   (`startObservingDevicePresence` etc., per the original README) — CDM is known to be less
   reliable for this than a properly configured `autoConnect=true` GATT connection.

3. **On the planned personal iPhone build**, the equivalent risk is a broken CoreBluetooth
   restoration/reconnection handoff after suspension, ordinary system termination, memory pressure,
   reboot, or out-of-range return. The accepted build keeps `bluetooth-central`, the native restore
   manager, stable restoration identifier, saved band UUID, and normal Flutter drain handoff. None
   is physically verified yet. Test this separately from Android, and record manual swipe-to-force-
   quit as an iOS lifecycle limitation rather than assuming it is the same defect.

**iPhone goal:** prove silent CoreBluetooth restoration/reconnection across ordinary lifecycle and
range-loss cases. If the iPhone path fails, fix that path or surface an honest recovery prompt.
Do not reopen or patch the Android-specific hypotheses above as part of the iPhone work.

## Calorie semantics and HR/MET fallback (repaired in Build 90 source, algorithm 96)

Found by Codex's independent review of `9170201b` (algorithm 95,
`energy-recovery-independent-review.md`); Akshat approved both repairs. **Repair (`0db6da6e`):**
`computeManualSessionStats` stores `sessionActiveKcal` (the shown method) instead of the legacy
bout scorer; every save path tags `sessions.calories_basis`; a non-active stored figure no
longer competes in the re-score's max rule; `repairSessionCalorieBasis` recalculates older own
rows only where the shown inputs exist and keeps the rest as `legacy`; the Active Energy
workout-gap credit counts `active` rows only. `otherWorkoutActiveKcal` lets heart rate compete
only at or above 57% of Tanaka HRmax. Regressions: `manual_session_test.dart` (Build 90 groups),
`build90_calorie_basis_repair_test.dart`, `daily_energy_consistency_test.dart`. What the review
reproduced:

- **Stored workout gross/net mismatch:** `computeManualSessionStats` calls
  `Calories.estimateBoutCalories`, which includes resting energy below its activity threshold
  and gross HR energy above it. Manual saves and non-movement substrate re-scoring can persist
  this in `sessions.calories`, while the main Train/detail UI generally recomputes net energy
  through `sessionActiveKcal`. Workout-gap credit and health-export code consume stored values;
  Health export is disabled in the personal build. A synthetic ten-minute resting-HR bout
  returns about 12.48 kcal, exactly its resting contribution. The legacy call also supplies
  170 cm when height is unknown. Define provenance and reconcile consumers before any migration;
  do not subtract resting energy indiscriminately from historical rows already containing net kcal.
- **Other-workout near-zero cliff:** `otherWorkoutActiveKcal` falls back to MET at nonpositive
  net HR but selects the smaller estimate as soon as net HR is positive. For a synthetic
  80 kg, 180 cm, 40-year-old male, 30-minute 4-MET session, a 0.02 bpm increase around the
  equation's zero crossing changes 120 kcal to about 0.045 kcal. This is a mathematical
  reproduction, not a personal measurement. A coherent HR validity/fallback policy is required;
  always choosing the smaller positive estimate is not a realistic lower bound.

Evidence: the ignored `build/research-local/calorie-semantics-probe_test.dart` reproduces both
behaviors (one passing probe); 28 existing targeted energy checks also pass, demonstrating that
those arithmetic tests do not validate consistent semantics or physiological accuracy.

## Build 89 day-strain floor never reached the stored day strain (repaired in Build 90 source)

**Found by the Build 90 local measurement (read-only export, two weeks of retained data).**
On algorithm 93, days with a finished walk whose own session strain was about 3.5–5.8 still
store a day strain of 0.0, in `day_result` scalars and `metric_series`. The Build 89 session
net-TRIMP floor (`derivation_engine.dart`, the `strain_session_floor` block) raises
`wake['strain']`, but `_applyWakeDayFeatures` has already copied `wake['strain']` into the
day's scalars a few lines earlier, so Today, Trends, history and exports never see the
floor. The Build 89 regression covered the floor's arithmetic, not the stored value.

**Repair (Build 90 source, algorithm 94):** the floor now runs before
`_applyWakeDayFeatures`, so the scalar every screen reads carries it;
`test/build90_strain_floor_test.dart` reads the stored scalar. Retained days recompute.
Phone check: a day with a finished walk shows at least that walk's strain. The quiet-day baseline form itself
stays as `build-90-research.md` D1 describes.

## iPhone background reconnect: restore wake landing on a parked backoff

**Found by code review. Fixed from source `0.9.33`/`66` and included in accepted build 70;
locked/background restoration still needs its separate device check.**

The failure sequence while backgrounded, after the live link dropped:
1. `_onEngineState` arms the native restore central (`_armRecovery`) and starts `_reconnect()`.
2. `_reconnect()` waits between attempts in a Dart timer. A suspended iOS process runs no Dart
   timers.
3. When the band came back, the restore central's `didConnect` woke the process for a few seconds.
4. The Dart wake handler ran the headless drain. `BandOwnership` refused it the band, because the
   live reconnect loop held foreground intent, so it returned at once and sent `syncDone`.
5. Native then went `idleAfterSync` and cancelled its pending connect.
6. The parked loop never fired inside the wake window. The band was then unwatched, and background
   sync stopped until the app was opened. That matches the reported "never silently recovers"
   pattern above.

**Source fix:**
- A restore wake is offered to the live app first (`IosBleRestore.onWake` → `AppState._onRestoreWake`).
- The wake cuts the reconnect backoff short (`WakeableDelay`, `lib/sync/sync_policy.dart`), so the
  attempt happens inside the wake window.
- If no link lands within about 20 s, the recovery connect is **re-armed** rather than left idle, and
  `syncDone` is not sent over it.
- Re-arming is capped at once per 10 minutes, so a reachable-but-refusing band cannot wake-loop the
  battery.
- The headless drain is unchanged when no live session wants the link.
- `reconnect_supervisor_test.dart` covers the wakeable backoff.

**Still unproven on the phone:**
- out-of-range → return while locked and backgrounded, then data arriving without opening the app;
- a restore relaunch after ordinary system termination.

**Known iOS limits, not defects:**
- ordinary CoreBluetooth force-quit suppression has an iOS 26 AccessorySetupKit exception;
  this app includes ASK, but phone provisioning and force-quit restoration remain unverified;
- after an iPhone reboot, Apple requires first unlock before restoration, not necessarily
  opening WHOOP. A pending preserved Bluetooth operation and its event are still necessary.
  `background-sync-plan.md` links the current Apple contracts and owns the proposed repair.

## Active iPhone pairing crash

**Confirmed on the installed personal candidate:** the app launches, but tapping **Find my band**
terminates the process before the iOS accessory picker appears. The exported report
`Runner-2026-09-09-204522.ips` identifies `EXC_BREAKPOINT`/`SIGTRAP` on the main thread in
`ASAccessorySession _validateDiscoveryDescriptor` → `_validateDisplayItem` →
`_showPickerForDisplayItems`. This is a native AccessorySetupKit validation abort, not the ordinary
not-found or still-connected-to-Android result: Dart's pairing screen catches normal plugin errors
and would render them in place.

**Confirmed cause:** on iOS 18+, `PairingScreen._pair()` routes to `AccessorySetup.showPicker()`.
The Swift bridge currently adds a final `ASPickerDisplayItem` whose descriptor contains only
`bluetoothNameSubstring` and no `bluetoothServiceUUID` or `bluetoothCompanyIdentifier`; Apple
documents the latter as required for every Bluetooth descriptor. The report specifically identifies
that descriptor-validation path, which bypasses Dart's catch and terminates the process exactly at
this tap. The bridge also has a separate activation-order risk: it calls `showPicker(for:)`
immediately after `ASAccessorySession.activate(on:)`, before the asynchronous `.activated` event. The shipped IPA does
contain the declared Bluetooth services, name allow-list, and Bluetooth usage description, so a
missing-key privacy termination is not the leading hypothesis.

**Fix status:** the name-only fallback was removed, picker/provision/remove operations now wait for
the asynchronous `.activated` event, and a regression guard covers the malformed descriptor. The
replacement `0.9.30`/63 IPA built, passed automated macOS/package validation, and is installed. Its
direct-pedometer path is verified, but physical **Find my band** verification is still pending. Keep
the original crash evidence until that picker path is tested on the iPhone.

## Verified iPhone step-source behavior

**Observed and resolved on the installed personal IPA:** Apple Health showed roughly 6,000 steps while
WHOOP showed roughly 200 because **Settings → This phone → Steps** was off. Enabling that setting
verified the direct iPhone `CMPedometer` import. The personal artifact intentionally removes HealthKit
entitlements, Health usage strings, and Health routes (`tool/personal_ios.py` reports `healthKit: false`),
so it still does not query the Apple Health aggregate.

The earlier low number was therefore the band fallback, not a Health total being scaled down. Do not
describe the current personal IPA as importing Apple Health steps: it imports the iPhone motion
coprocessor only. A future HealthKit expansion would need an explicit source/overlap policy rather
than adding its aggregate to the band count and double-counting.

WHOOP 4 band-only all-day steps are not a reliable supported source in this app: the available
historical wrist stream is too low-rate for honest step reconstruction. Keep phone steps enabled for
normal iPhone-carried use. If steps without the iPhone are later required, first prove that the WHOOP
protocol exposes a trustworthy on-band counter; do not fabricate one from 1 Hz historical data.

**Source fix from `0.9.32` build `65`, retained in accepted build 70:** zero-step `CMPedometer` windows are retained as
confirmed-still evidence. When a low-density wrist span overlaps such a phone window, the resolver
voids only that overlap; real gait-density spans survive, and partial overlaps keep their uncovered
share. The focused database/source-ladder tests pass. The current feature phone check passed;
the separate phone-stillness scenario remains useful for verifying this specific guard.

Build 70 also changes personal step resolution to phone-first (`kAlgoVersion` 87): phone-counted
windows use the phone, with band fallback for missed time or qualifying gait. The feature phone
check passed; `metrics-map.md` owns the current step policy.

The secondary-sensor screen provides a separate observation, not a WHOOP-pairing fallback. After
skipping onboarding, **Settings → My Device → Add a Sensor → Bluetooth Heart Rate Sensor** reports
“The phone’s radio is off…”. That screen is for a standard Bluetooth heart-rate chest strap, not the
primary WHOOP, and its pre-scan code maps CoreBluetooth `poweredOff` to that exact sentence; an
app-level denial has different copy. Confirm Bluetooth is on in the iPhone Settings app and WHOOP
is allowed under Privacy & Security → Bluetooth. Also force-quit/relaunch WHOOP after attempting a
secondary-sensor scan: that path creates a global `CBCentralManager`, which the current source says
prevents AccessorySetupKit from presenting the primary-WHOOP picker for the rest of that process.

## UI and food reliability

**Build-85 follow-ups implemented in installed Build 86, pending phone acceptance:**
`build-86-audit.md` owns source evidence
and repair/test contracts for reversed Strain day arrows, average rather than current walking
speed, incomplete cross-midnight sleep signals, automatic open-to-recorded-HR freshness, diary
delete without confirmation, shifting workout trash/chevron and missing summary Delete,
non-atomic session deletion, one-way portion equivalents, fixed-only food categories, typed-
goal calorie warnings, limited activity streaks, weekly protein/coverage denominators and reset
backup-deletion error handling. Sleep-window/freshness paths are confirmed risks, not proof of
the exact recorded gap. They were not fixed by build 85's earlier UI/refresh work; Build 86's
implementation/CI evidence and remaining device checks are in `todo.md`.

**Build 86 UI/presentation findings, repaired in the Build 87 testing IPA:** `build-87-ui-plan.md` owns
the rejected first-viewport/card-heavy design and source-confirmed compressed Progress date axes,
limited food/workout history under All, suppressed partial reviews, mixed comparison windows,
omitted Other subtype, profile-only weight ambiguity, stale completion help and masked read errors.
This is a static source/screenshot audit, not reproduced phone data loss. Repairs and visual
approval are separate: source repairs are implemented, visual/phone acceptance is open;
`todo.md` owns verification and publication gates.

Source `0.9.39`/`72` fixes clipped chart readouts, inconsistent Deep colouring, restored launch
tabs, the indirect Scan flow and unbounded food history. It adds Quick add fibre/editing, optional
macro handling, completed-day weekly coverage and automatic weekly-card rereads. Save guards,
transactional saved meals, historical timestamps, latest-read guards and visible validation/retry
states cover the reviewed failure paths. Widget/database regressions reproduce save/date races,
failed reads/writes, Undo and cold/warm navigation; they are source verification, not reports of
observed phone failures. Release and phone checks are tracked in `todo.md`.

Akshat reports Today pull-to-refresh leaving steps/figures unchanged on installed build 70.
The source trace found band catch-up preceding phone reads, silent refresh timeouts, a guessed
400 ms wait for asynchronous queue persistence, and Today serving cached step scalars instead of
the latest measured coverage. Local build-72 source reads phone steps first, reloads measured
counts independently of derivation, awaits the queued intent and explains unfinished/failed work.
The shared step read serves Today, Steps, Strain detail and today's step-chart point; counter/import
fallbacks remain available, and phone stillness is distinguished from no read. Database/state tests
exercise a blocked band, stale calculated totals, no band records, zero counts and capture/workout
holds (`test/today_refresh_test.dart`). Native phone-sync completion also publishes a screen
revision, covering cold launch/reconnect as well as pull/foreground refresh.
The earlier built `5c00c278` IPA lacks this repair and is superseded. Build-72 local/CI tests,
macOS build, checksum and payload validation pass; Akshat confirms installation, while the feature
phone pass and current-version enrollment remain pending.

## Food-library scanning entry: build-74 replacement repair

The earlier screenshot/source showed that Food → Foods → My foods → New opened only the
manual `FoodEditor`. The scanner is reachable from meal logging, although scanned products and
manual foods share `food_def` and are both returned by `MyFoods.all`. This is a missing library
entry point, not evidence of a broken barcode camera. The built replacement adds Scan beside New,
review before persistence, explicit manual fallback and no library diary writes. Meal scanning
also opens the editable review first and waits for explicit Log on its portion screen. Barcode edits retain
ancillary label data. Source `ba5bb29f` is published and its replacement IPA passes validation.
`todo.md` owns phone gates; `setup.md` records the CI fixture repair with unchanged app inputs.

## Build-73 chart, navigation and notification defects: local build-74 repairs

The installed-build-73 report and source audit confirmed future-time Strain/Steps/Wear selection,
gesture-only daily navigation, static breathing history and generic/stale notification destinations.
Local `0.9.41`/`74` repairs shared pointer/accessibility bounds, measured rendering, day reachability,
dated breathing/readouts and focused notification routes. Paused route HR/cadence now maps through
the saved active clock, preserving the pause gap. Deep sleep uses one colour and units appear once.
Foreground refresh now re-reads session movement after daily steps. The Food deletion/Undo bar
explicitly expires after two seconds: Flutter 3.41 defaults action snackbars to persistent;
queued notices are cleared before a replacement. Undo within the window still restores the entry.
`build-74-audit.md` owns the baseline/research and implemented contract; `todo.md` owns release and
phone checks. Native app/extension compilation passed, while device acceptance remains pending.
The IPA validator permits ZIP's required `PlugIns/` parent for the contract-checked workout
extension and rejects unexpected sibling plugins/files; the realistic archive regression covers
the parent-directory packaging failure. Build-74 source `ba5bb29f`, Linux CI `37397127258`,
macOS build `37395690305` and downloaded checksum/manifest/payload/ZIP checks pass. It is the
superseded candidate, previously installed (Akshat); its open device checks carry forward to
build 85, excluding the Live Activity removed in build 81. Build 70 remains recovery.

## Workout, sync and profile consistency

`workout-sync-audit.md` owns the build-72 reported symptoms, source traces, research and isolated
reproductions: insight retry/rebuild gaps, background voice, gross versus active calorie models,
run-step overlap, cross-midnight/pause windows, hidden macro rows, decimal/round-trip profile input
and stale cached profile calculations. The installed build-72 session-only streak omits step-goal-only days;
the combined rule and dated target policy are documented there. The approved repairs are
implemented in `0.9.40`/`73` (algorithm 89), source `a49d7837`, and pass local regression/release
validation, Linux CI, macOS compilation and downloaded IPA checks. Build 73 is installed;
build 74 supersedes its testing artifact and retains the combined acceptance checklist.
The personal source includes background audio for spoken workout cues; hardware behavior remains
subject to the build-73 phone pass. `todo.md` owns the implementation and release gates.
The added nap repair removes the full-restaging wait from reject/restore and keeps empty-day
entry points; corrected lists, sleep periods and timelines agree before coaching finishes.
Build 73 adds shared Sleep/Strain daily views and a distinct kcal trend. Remaining Today defaults,
daily reachability, future-time limits and other chart/notification gaps are described in
`build-74-audit.md`; they are repaired in local build-74 source. The paused route HR/cadence
lookup uses the saved active clock. Overall phone acceptance remains pending.

Akshat confirms build-72 Today refresh updates step numbers but reports unchanged maintenance
calories. The real-repository Food-card probe recalculates step energy immediately after a saved
count revision; an already-open maintenance sheet keeps its original values. The report maps this
reproduced stale view, cached history/profile dependencies, silent missing-input substitutions and
the separate HR/cadence calorie derivation. Overall phone acceptance remains open.

The old Windows-only failures are repaired: path/newline comparisons and local-date fixtures are
portable; POSIX timezone-switching tests remain explicitly skipped on Windows. Real source fixes
close ZIP inputs even when validation fails and count movement-floor age by calendar dates across
DST. Algorithm 88 permits recomputation. The personal capability profile is unchanged.

## Background sync and slow pull-to-refresh (active investigation)

**Current supplied evidence, with build 85 reported in use:**

- Akshat confirms iPhone 17 / iOS `26.6.2` and expects only two or three minutes of app
  viewing per day. Whether the supplied afternoon gap included force-quit is unknown.
- `openstrap_exits.log` contains MetricKit's window `2026-10-08T05:00:00Z` to
  `2026-10-09T05:00:00Z` (8 Oct midnight to 9 Oct midnight in Chicago): 20 background
  CPU-resource-limit exits, 7 normal background exits and 3 normal foreground exits.
  CPU termination is now confirmed for that reporting window. These are interval totals,
  without individual exit times or build attribution; they do not prove the cause of a
  particular gap or a CPU kill on 9 Oct afternoon.
- The rotated sync logs cover 8 Oct 10:37 to 9 Oct 17:09, using phone-local timestamps.
  On 8 Oct, commits stop at 12:41:09 and resume at 14:33:04 (about 112 minutes); logging
  stops at 12:41:51 and resumes with a foreground launch at 14:31:56. On 9 Oct, commits
  stop at 11:59:58 and resume at 13:27:44 (about 88 minutes); logging stops at 12:03:16
  and resumes with a foreground launch at 13:26:35. Lease counters restart at 1 on those
  launches, consistent with a new AppState/process rather than a healthy connection reclaim.
  These are real gaps in recorded transfer/commit activity, not merely unchanged UI numbers.
- Catch-up commits replay the earlier band timestamps after each gap. Unacknowledged chunks
  are retained and retried; the excerpts demonstrate recovery, not a complete no-data-loss audit.
- Background transfer works elsewhere: on 9 Oct it completes at 11:15, 11:29, 11:59,
  15:32 and 15:47 while backgrounded. Background launches are correctly identified by
  UIKit, so the build-84 launch classification repair is present, but reliability is not accepted.
- Source-level remaining CPU exposure: `AppState._maybeDowngradeLiveForBackground` explicitly
  skips the HR-only downgrade for personal iOS, retaining high-rate motion for passive wrist
  steps. The log measures about 105 Hz. `DeriveScheduler.setBackground(true)` cancels pending
  timers but does not cancel a running pass: on 9 Oct a heavy pass starts at 15:05:39,
  the app backgrounds at 15:05:46, and calculation finishes through 15:06:45. Neither
  exposure is individually proven to cause the reported exits.
- Restoration is already enabled on the live flutter_blue_plus central in `main.dart`,
  and its pinned Darwin implementation restores connected peripherals/subscriptions. The
  separate recovery central intentionally declines a competing connect while live owns the
  band; that alone does not establish absent restoration. The supplied files omit native
  diagnostics needed to distinguish no relaunch from a failed startup/handoff.
- Further source findings: the scheduler arms before UIKit launch state settles; the app's
  first-frame callback can start a foreground session without that check; a queued native
  wake can start headless sync before AppState installs its handler. The fallback still runs
  whole-day "light" derivation with a four-minute worker timeout, and native BLE expiration
  does not cancel Dart. These are repair candidates, not individually attributed gap causes.

No application repair is implemented by this investigation. `background-sync-plan.md` owns the
public Apple research and coordinated capture/calculation/lifecycle/restoration proposal;
`todo.md` owns approval. Preserve wrist-only steps until an explicit policy decision is made.

Report (build 80): data syncs only while the app is open, though it is not swiped away; Status
showed band data 44 min old until the app opened. Every pull-to-refresh takes long.
Source behavior before the build-84 repairs:
- **Background:** `pauseForBackground` keeps the BLE connection and live streams up
  (`bluetooth-central`), so iOS resumes the app per notification. The app's own 5-min drain
  is skipped in the background; offloads are left to the engine's timer, floored at 15 min
  (`BackfillPolicy.periodicFloorSeconds = 900`) with exponential backoff after three empty
  offloads. All calculation is deferred until foreground (`_deriveScheduler.setBackground`), to
  avoid iOS background CPU kills. So even drained data shows no new numbers until the app opens.
- **Known kill evidence:** synced crash reports show repeated `Runner.cpu_resource_fatal` kills on
  build 63 (48 s of CPU in 59 s, 12–14 Sept). A system-killed app that held its connection did
  not arm the restore central (`_armRecovery` runs only when not connected), so iOS may never
  relaunch it until opened. Whether builds 74–80 still get killed is unknown (no reports synced
  since 21 Sept).
- **Pull-to-refresh:** `_pullRefresh` runs phone steps, then the band backlog drain
  (`foregroundCatchUp`, up to 20 sessions), then waits for today's full recalculation, all before
  the spinner stops (60 s cap). Stage timings are not logged.
The earlier Analytics Data check (Akshat, 7 Oct) found `Runner.cpu_resource_fatal` reports only
up to 14 Sept and a `Runner.diskwrites_resource` report on 22 Sept. That absence did not rule
out newer CPU exits; the MetricKit evidence above supersedes the earlier no-CPU-kill inference.
The app log never existed on iPhone: `FileLog` tried Android's
external storage first, which throws on iOS, and the shared handler disabled logging. Fixed in the
local build-82 source (iOS writes `openstrap_sync.log` to Documents, visible in Files → WHOOP), and
pull-to-refresh now logs when phone steps, the band pull and the calculation finish.
First build-82 log (Akshat, 7 Oct, two short opens, not the hour): on first open the band held
~1,500 records, but the reconnect drain pulled 0 and stopped on the 60 s idle timeout twice; a
later foreground refresh then pulled 1,699 records (~28 min of band history, 37 batches). While
backgrounded the app logged "Periodic history refresh skipped — backgrounded" and no background
offload appears before the next open, which reconnected from scratch (new link, clock set; ~9 min
backlog). Pull-to-refresh logged phone steps and band pull both done at 0.1 s (the pull skipped
because a capture was already running) and no calculation line (the app went to the background);
every foreground re-derives 4 days plus a 43-day cross-day pass, the likely slow stage.
The log itself is defective: lines carry no time, and `_log` fires `FileLog.write` unawaited,
each opening the file in Dart's append mode (seek to end, not `O_APPEND`), so overlapping writes
overwrite each other and leave fragments ("drift=0s)."). The empty drains came from
`_runSyncBurst` waiting without sending a history request when the link was reused or the earlier
offload had ended. Both are fixed in build 83 (`todo.md`): a serialized,
time-stamped log writer, and a burst that asks the band whenever no offload is in flight. Next
evidence: that build's log after a backgrounded hour and one pull-to-refresh.
Build-83 log (Akshat, 7-8 Oct, 21:43-07:05, time-stamped):
- **Build-83 fixes work:** reconnect drains now pull data (5-133 records, no 0-record waits),
  "Backfill retry" fired 7 times, and lines are whole and timed.
- **Background sync does run while connected:** the engine's backfill offloaded at 05:32 and
  06:02 (30 min apart, the floored timer with backoff) with the app backgrounded; data reaches the
  phone, but calculation waits for the foreground, which is why numbers look stale.
- **Overnight restart loop (new, most important):** from 02:15 (link timeout) to 03:30 the app
  process started over about 20 times, every 2-4 minutes. Evidence: each start re-acquires
  foreground lease 2 (the token restarts per process), "recovered orphaned steps from a killed
  session" appears 9 times, and every new process ran a full heavy calculation (4 days plus a
  9-day baseline rescan) and one sleep-staging timeout (90 s) while the phone sat locked. The
  restarted process takes the foreground session path (`===== SESSION START =====`, foreground
  5-min refresh) instead of the background one, so it runs foreground-sized work in the
  background. Leading hypothesis: iOS relaunches the app for Bluetooth, the app behaves as if
  opened, the heavy calculation exceeds iOS's background CPU limit, iOS kills it, and the band
  relaunches it again. Akshat's Analytics Data has no `Runner` or `cpu_resource` report for
  7-8 Oct (newest Runner CPU kill 14 Sept, disk-writes 22 Sept); those files did not identify
  the individual exit causes. The newer MetricKit window confirms CPU-limit exits in aggregate.
  The restarts are still real: each one resets the band command sequence (e.g. `24c4…` → `2406…`)
  and the lease counter, with no "Link down" first, and the previous process stops mid-calculation
  with no closing line. Remaining candidates: a memory kill (iOS logs those as `JetsamEvent-*`,
  not under Runner) or silent termination of a backgrounded app followed by a Bluetooth relaunch.
  Akshat found no report of any kind for 8 Oct, Jetsam included; the two 7 Oct reports are
  unrelated (the build-80 Live Activity extension's known code-signing kill, and Apple's own
  `CoreRoutineHelperService`). The later MetricKit window confirms CPU-limit exits despite
  missing individual reports; it cannot assign an exit cause to each earlier restart.
- **Then a 92-minute stall:** at 03:30:07 a new process started a session while a background
  (headless) lease was held and logged nothing until Akshat opened the app at 05:02, so no data
  synced for 1.5 h overnight.
- **Pull-to-refresh timing:** phone steps 0.0-0.2 s and band pull 0.1-0.2 s every time (the pull
  joins the burst already running); calculation 5.9-67 s (50.3 s and 67.0 s on heavy days). The
  slow part is the calculation, not the band.
- Offload record counts in "OFFLOAD SUMMARY"/"Foreground catch-up" are cumulative for the
  connection, not per sync, so they overstate each pull.
Root cause found in source (build 84): the relaunch reaches Flutter as `inactive`, which
`AppState` read as opened; build 84 asks UIKit, keeps background launches light, bumps screens
when today's row lands, ends pull-to-refresh at today, checks offloads every 5 min and records
MetricKit exit reasons (`todo.md`, "Build 84"). These changes are retained in installed build 85;
the supplied logs confirm background classification and successful transfers in some periods,
but persistent stalls and CPU exits keep background reliability unaccepted.
The current proposed repair is in `background-sync-plan.md` and `todo.md`. CPU-limit exits
are now confirmed for the supplied MetricKit interval. Preserve restoration on the live
central; do not arm the separate recovery central against its healthy connection. Brief
daily app use requires bounded background insight opportunities as well as safe capture,
running-worker cancellation and fast foreground catch-up; none is newly implemented here.

## Night of 9–10 Oct split into a short night and two naps (build 85, explained)

Akshat reports sleeping about 10 PM–5 AM. Build 85 shows the night as 9:26 PM–12:44 AM, Band off
your wrist 12:44–4:35 AM, and two naps, 4:39–5:03 AM and 5:20–5:38 AM.

Cause, from Akshat's sync logs: the band's own wear sensor reported it off the wrist.
- The band sent `WRIST_OFF` (event 10) stamped 00:44:02 and `WRIST_ON` (event 9) stamped 04:35:38.
  A WHOOP 4 records no 1 Hz heart rate or motion while it considers itself off the wrist.
- Every history request in between returned packets but zero 1 Hz records (`historical=0,
  recTs=none`), and records resumed at exactly 1791624939 (04:35:39). Nothing was lost in
  transfer: the band never wrote those records.
- No charging, no boot event, and the app was connected throughout.
- A second 28 s `WRIST_OFF`/`WRIST_ON` at 05:08 is consistent with marginal fit. The
  temperature-labelled curve is not corroborating evidence: its WHOOP 4 field is unverified
  as temperature (see the field-integrity issue below).

Sleep detection then did what it is built to do with a four-hour hole: the longest still block
became the night and the later ones naps. Build 85 is not the cause. Its source changes no sleep
detection, staging or recorded data: the analytics package is unchanged since build 74 and
`kAlgoVersion` (91) since build 81. The lost hours cannot be recovered. **Correction (source
audit):** Sleep → Fix sleep times sets the in-bed window, not the duration. A forced window still
needs at least 50% of its span observed (`segment.dart` `kMinObservedFractionForSleep`, no forced
exemption); 10:00 PM–5:00 AM here is about 11,300 of 25,200 seconds observed (≈45%), so that
correction would most likely publish no main sleep at all. Even when accepted, total sleep counts
only observed seconds. The naps can be removed under Naps → Edit.

Repaired in the validated Build 87 testing IPA, pending phone verification: while the band reported off-wrist,
the app treated its silence as a
dead link and bounced the connection 23 times ("No data for >120s — bouncing the link"), costing
battery on both devices. After a `WRIST_OFF` with no `WRIST_ON`, silence should not trigger a
reconnect. Current-connection wear evidence now gates silence reconnect/re-arm/fast polls;
unknown/on-wrist silence and real disconnection/write failures retain recovery. Older history
cannot overwrite newer evidence. Normal polling and history catch-up remain active.

Separate display bug, fixed in build-86 source: the chart's scrub line printed the raw skin-
temperature count relative to the day as "Temp Δ −31.3 °C". That number is not degrees; the
readout no longer shows temperature (the Skin temp row and its chart remain).

## WHOOP 4 Temperature Field Integrity (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** temperature outputs, the anomaly/temp-illness inputs, the glass-box term and the Sleep/Trends/rough-night rows are gated to verified families (`hasVerifiedSkinTemp`, `kShowSkinTemp`); stored history is untouched. The text below is the original finding.

Confirmed source mismatch, not a new firmware or phone observation: the protocol's
`R24.skinTempRaw` (`packages/protocol/lib/src/records.dart`) is explicitly deprecated as
not temperature. Its u16 at inner offset 68 changes too quickly to support that interpretation;
the slower candidate fields are also unconfirmed. The emitted bytes are real, but their physical
meaning is unknown. `derive_prepare.dart` still imports `skin_temp_raw`, and
`onehz_pipeline.dart` averages it, derives a temperature-labelled z-score and passes it to
`tempInput` for readiness when its gates qualify. `_daySkinTempCurve` also charts this channel.
Relative normalization does not make an unknown optical quantity a temperature measurement.

**Reach, confirmed by the second source audit (all active in the personal build):**
- Readiness: `tempInput` (weight .08) is live for `gen4` nights with 14 baseline values, settled
  fraction ≥0.80 and baseline SD ≥1 count. It is fed the plain all-sample mean, not the settled
  mean the v71 changelog promised.
- Cross-day: `crossday_pipeline.dart` passes `skin_temp_z` into `tempIllnessFlag` and
  `multivariateAnomaly`, whose own contracts (`temp_health.dart`, `anomaly.dart`) refuse a
  z-score. That is double standardisation, so their thresholds have no defined meaning even for a
  real temperature. `glassBoxReadiness` takes |z| at .08; the Sleep rough-night card tests z
  against an MDC.
- Alerts: "Skin temperature elevated" is a medical, critical-priority finding that overrides quiet
  hours by default (see Health Alerts below).
- Imports: the WHOOP CSV importer writes absolute °C into `skin_temp_z`, and the cloud importer
  writes its own index there. Cross-day inputs (`recentDayResults(90)`), the Trends row and the
  Sleep row do not filter imported days. This matters only if an import was ever run.
- No retroactive repair: decodable WHOOP 4 frame bytes are not retained (`raw_records` is dropped,
  `rawTail` is never stored). The slower candidates at inner 72/88 were never stored, and inner 88
  is a synthetic zero pad on 88-byte live frames. A Build 88 bump can re-derive only about three
  retained days. Older temperature-influenced `day_result`/`metric_series` values stay served, and
  cross-day reads 90 days of stored `skin_temp_z`, so consumers must refuse WHOOP 4/unknown/imported
  temperature by family and source, not merely recompute.

This remains in installed Build 86 and the validated Build 87 IPA; no app/package output was
changed by documenting it. Do not use the WHOOP 4 temperature deviation as physiological evidence.
Sleep detection/staging uses movement, HR and RR, not this field, so this is separate from stage
accuracy. The proposed repair must abstain for the unverified WHOOP 4 temperature channel without
deleting raw bytes or stored history, assess affected readiness/illness consumers, preserve
independently verified device-family inputs, and make an explicit algorithm-version decision.
Akshat has queued the repair for Build 88 in `todo.md`; implementation is still deferred.
Akshat selected hiding unsupported rows in Trends/Sleep while retaining history. Other unique
removals still require approval. Review the analytics/version/recomputation scope before
implementing. The requested research brief is
`metrics-accuracy-research-prompt.md`; the completed desk review and proposal R01 are in
`metrics-accuracy-research.md`; `build-88-plan.md` consolidates both attached analyses and maps
this repair to B88-01, including the independent RHR-only CUSUM boundary. No new IPA, silent recovery recalculation or historical
rewrite is authorized by this planning request.

## Partly Missing Training Load Becomes Zero (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** load uses net TRIMP over runs of observed days (at least 16 h worn); 1-2 unknown days are skipped, 3 end the run; imported days leave the inputs. Fatigue keeps the 28-observed-day floor (decided): its only reader compares it with fitness, which needs 28, so fatigue alone at 7 days would have no use.

Confirmed from current source, not a new phone reproduction:
`lib/compute/crossday_pipeline.dart::_denseDailyTrimp` returns an empty series when every input
is null, but once any TRIMP value exists it stores null rows as `0.0` and fills missing calendar
days with `0.0`. Its excessive-span fallback also converts nulls to zero. Thus partial missing
history can look like measured rest to `ctlAtlTsb`, potentially affecting downstream load,
target or overreaching context. An observed zero and an unobserved day are different inputs.

Proposal R02 in `metrics-accuracy-research.md` requires a coverage-qualified zero and an explicit
gap policy (including minimum eligible history), not arbitrary interpolation. Add mixed
known/null/skipped-date/genuine-rest and DST regressions, audit all downstream consumers and make
the algorithm-version decision before implementing. No source/output change or reference
validation was performed by this audit; Build 88 selection remains open in `todo.md`
(consolidated work package B88-02). Decaying an EWMA as if a missing input were zero is not
evidence of an observed rest day.

## HRV Headline And Recovery Method Identity (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** the headline and readiness use the qualified primary only; the secondary estimate is stored separately and labelled; the baseline reads `ln_rmssd_v2` nights only.

Confirmed caller difference in `lib/compute/onehz_pipeline.dart`: `rmssdScalar` can fall back
from the sleep-session five-minute mean to robust or whole-window RMSSD, while `lnToday`
is calculated only from the primary sleep-session estimate. Displayed HRV may therefore exist
while readiness's HRV input is absent; cross-day detail can read the fallback scalar. The
estimators/windows are not automatically interchangeable. Allowing every fallback into readiness
would conceal this difference and could mix incompatible baseline histories.

Proposal R04 in `metrics-accuracy-research.md` requires a canonical-method decision, explicit
secondary method/coverage provenance and compatible baselines. Tests must cover every fallback,
gaps/artifacts, repeated derive and version/history handling. This is an open semantic/consumer
consistency issue, not evidence that a particular fallback is more physiologically accurate.
Akshat selected primary-only headlines: unavailable primary remains absent, with labelled
secondary estimates offered in details. This presentation decision is not implemented;
qualification/version/history selection remains open (B88-03 in `build-88-plan.md`).
The attached analysis's NREM-headline claim does not describe the current
primary method and is not authorization to replace it.

## Lean-Gain Waist Rule Overstates Tissue Attribution (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** the rule and its copy are an observation (waist rising faster than about 1 cm per 2 kg), never a tissue claim.

`lib/data/goal_plan.dart::waistFast` qualifies weight gain with waist growth greater than
0.5 cm per kg and can explain this as gaining waist faster than muscle accounts for. The source
already calls the ratio unvalidated; the statement and suggestion branch still convey more
tissue certainty than weight/tape/strength observations support. Circumference can track a useful
trend but does not identify exact fat versus muscle from that ratio.

Proposal R03 in `metrics-accuracy-research.md` preserves qualified waist/strength observations
while removing unsupported tissue attribution from the decision and wording after approval.
It also calls for a distinct intake-eligibility/floor-advice review. Do not substitute another
arbitrary ratio, remove body tracking, or change calorie targets as a documentation repair.
`fitness-goal-research.md` identifies the current rule as policy; Build 88 changes are unimplemented.
`build-88-plan.md` consolidates the observation/decision-branch repair as B88-07, not a new
muscle/fat classifier or automatic calorie-target change.

## Primary HRV Joins Unreported Time And Accepts Sparse Windows (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** pairs must be time-adjacent; windows need 180 s covered, 120 pairs and at most 20% artifacts; nights need 6 windows and 15% of the session. The installed Build 88's 250 ms adjacency left the nightly HRV absent on 6 of 13 real nights and biased low on the rest, because WHOOP 4 beat times carry the 1 Hz record's phase, not the beat's. Build 89 source (algorithm 93) uses one 1000 ms tolerance (`kBeatAdjacencyTolMs`) everywhere; on the same 13 nights all qualify and agree closely with algorithm 91 (`todo.md` Build 89).

Confirmed source behavior with a local synthetic probe, not a personal-data accuracy estimate.
`packages/analytics/lib/src/onehz/clinical/hrv_time.dart::sleepSessionWindowedRmssd` uses
timestamps to assign five-minute buckets, then passes only RR values to `_cleanWindowRuns`.
That helper preserves positions across rejected reported beats but has no timestamps with
which to split sensor dropouts. Unreported time within a bucket can therefore become an
apparently successive RR difference. Any bucket with one surviving difference can contribute
to the nightly mean; no observed-time/beat-coverage minimum is enforced there.

Synthetic inputs `[1000, 1100]` ms inside a 600-second session returned `present=true`,
RMSSD `100.0` ms and confidence `0.3` both when report times were one second apart and when
they were 298 seconds apart within the same bucket. This proves admission/continuity behavior,
not the magnitude of error on the user's nights. The pure-Dart probe ran successfully outside
the Windows sandbox after sandbox-only path failures; it used no personal records or network.

B88-03 must retain report timestamps, split actual dropouts before differencing, respect
multiple intervals sharing a report second, and explicitly qualify window/night coverage.
Do not assume report timestamps are precise ECG beat times. Test rejected runs, sparse windows,
gaps, repeated report seconds and method-specific baseline enrollment. Keep current cleaning
semantics separate from any experiment replacing the cleaner. HRV/readiness output changes
require algorithm/version and compatible-history decisions; the current source is not fixed.

## Strength Review Can Praise Unchanged Or Incomparable Sets (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** one comparator (`compareSet`) for live and Review with an explicit not-comparable state; "stronger" needs at least one lift better.

Confirmed in source and a synthetic local test: `lib/data/progress_review.dart::_compare` returns `0` both for identical
performance and heavier/fewer-rep or lighter/more-rep pairs that its comment calls not
comparable. `review` selects "Consistent with getting stronger" when `better >= worse`,
including `better=0, worse=0` once other data gates qualify. Neutral or incomparable sets
therefore need not demonstrate any improvement for that headline to appear. Identical `40 x 10`
records with sufficient synthetic weight/food observations reproduced that stronger headline.

B88-07/B88-08 must distinguish improved, unchanged, declined and not-comparable states;
only actual qualified improvement may support a getting-stronger statement. Preserve raw
set records and context. Add identical-set, mixed-load/rep, zero-improvement and mixed-direction
tests. This is an interpretation/consumer repair, not permission to invent a muscle score.

## High-Rep Lift Trend Ignores Changed Load (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** without the estimate the trend compares reps at the same load only, or says it cannot compare, and names its date span.

Confirmed in source and a synthetic local test: `lib/data/lift_progress.dart::liftTrend`, if any session lacks an eligible Epley
score, `m` falls back to `best.reps` for every session without requiring a fixed load. A
heavier/fewer-rep high-rep set can be labelled down solely because its rep count fell, despite
the load change making that rep-only comparison ambiguous. It can also affect the plateau
wording and set-to-beat advice. Synthetic `60 x 15` then `65 x 14` reproduced
"Best set down 1 reps over 2 sessions." Both lift diagnostic tests passed using the existing
space-free Windows test workflow in `setup.md`; they assert the current defect, not a fix.

B88-07 should use reps-at-the-same-load/context for this fallback, or declare the pair not
comparable. Keep the existing 1-12-rep score eligibility and do not invent whole-system 1RM
from per-hand/plate/added-load entries. Test changed load above the limit, bodyweight-only sets,
mixed eligible/ineligible sessions and plateau/advice paths. No lift source changed in this audit.

## Second-Pass Source Audit Findings (Mostly Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** each subsection below starts with what Build 88 source repaired and what remains open.

These come from read-only source audits against Build 87 source (`kAlgoVersion` 91, schema 49).
They are verified by reading code, and spot-checked where marked. Additional isolated synthetic
tests reproduce the prior-night freshness, dinner-only completeness and app quiet-hours cases.
None was reproduced on the phone or measured on Akshat's nights; magnitudes are unknown unless stated. "Inference" marks a
source-traced path that still needs a runtime trace. `build-88-plan.md` maps each group to a work
package. `metrics-accuracy-research.md` (Second-Pass Audit) holds per-family verdicts on earlier
claims.

### Health Alerts Use Unsettled Inputs, A Different Score And Critical Priority

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: low readiness reads the headline composite; every health finding is normal priority and respects quiet hours; the anomaly flag is one-sided; RHR-shift evidence restarts after a 7-day gap; irregular rhythm is note-only (C1); each kind can be muted (C8).

- Every aggregated health notification is sent as `NotifPriority.critical`
  (`derivation_engine.dart` `_runNotifications`). That includes "Low readiness", a falling resting
  HR, anomaly, irregular rhythm and temperature. `criticalOverridesQuiet` defaults to true
  (`notification_prefs.dart`), so all of them bypass 22:00–07:00 quiet hours. Spot-checked.
  A synthetic policy test admits an internal critical health event at 23:00. This is the app's
  gate, not Apple's Critical Alert delivery: `notification_service.dart::_details` uses default
  `DarwinNotificationDetails`, ordinary authorization and no personal Critical Alerts entitlement.
  Actual Focus/mute bypass or waking the phone is not established. Akshat selected normal health
  findings that respect quiet hours, leaving the armed band alarm separate; no fix is implemented.
- "Low readiness" fires on `glassBoxReadiness` < 34. The glass box is a deprecated percentile model
  with no minimum input count or weight, needs 7 history values, takes |skin_temp_z| at .08 and is
  not gated on unsettled days. The ring and findings log use `readinessComposite` instead, so the
  `findings.dart` claim that they "cannot disagree" is false.
- Only today's unfinalized row is marked `unsettled`. Yesterday stays unfinalized for 48 h but
  feeds the illness, anomaly and temperature detectors as settled. Inference: today's own
  medical/RHR-shift inputs are nulled for the whole calendar day, while ungated Low readiness can
  still fire from a partial row.
- `multivariateAnomaly` uses an undirected distance, so an unusually good night can raise the
  critical "Unusual overnight physiology" alert.
- The resting-HR shift detector is called without dates (`derivation_engine.dart`,
  `findings.dart`). Its own docs warn that evidence from before a long wear gap can then fire.
- The illness finding says "Elevated resting HR + suppressed HRV", but the CUSUM is RHR-only.
- No cross-day consumer filters imported or foreign-family days: glass box, percentile, CUSUM,
  anomaly, temperature-illness, RHR shift, findings, load, overreaching, session cost. Movers filter
  imports on the outcome but not on strain/steps exposures. The headline readiness baseline is
  clean: past-only, import/family-masked and idempotent.
- The irregular-rhythm screens difference the compacted NN series positionally, so dropouts and
  corrector-removed runs inflate SD1/pNN70. They also drive a critical notification. Despite the
  "opt-in" wording, the health channel defaults on. The pipeline comment claiming gap-aware
  differencing is wrong.

### Readiness Explanation Comes From A Different Model

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: the Readiness breakdown reads the composite's own drivers. Home stores but never rendered glass-box drivers.

The Readiness screen breakdown, Home drivers and driver-breakdown screen render
`readiness_glassbox.breakdown`, a parallel ranking from the deprecated model. Source comments call
it a ranking of "the same four inputs", but the composite now has five. The composite's own
per-driver contributions are stored but never shown, so the explanation under the ring is not the
calculation that produced it. Three band schemes coexist (26/37/61 ring, 34 alert, 40/60/80
elsewhere). "28 nights" is the last 28 stored values with no calendar bound, so after a long wear
gap the baseline can be months old. The RHR whole-bpm quantum is applied to a continuous
30-minute mean; its appropriateness is a noise/quality-policy question, not evidence that the
stored mean is rounded to whole bpm or that a smaller floor is validated.

### Timestamp-Blind Beat Differencing Beyond The Primary HRV

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: one rolling-RMSSD rule (`rollingRmssd`) for the HRV timeline, 24/7 curve and daytime HRV; PRSA needs gap-free windows; RSA window coverage/Nyquist and 6-window nights; BRV uses the real artifact fraction; stress and irregular-rhythm duration gates; labels fixed. The per-night CVHR chart is removed (decided); the across-nights card stays. Build 89 replaces the too-strict 250 ms admission with a shared 1000 ms tolerance for WHOOP 4's record-stamped timing. Open investigations: corrected-NN continuity across actual dropouts, Lomb-Scargle power scaling under gaps and the beat-sum clock. Do not relist the pre-Build-89 adjacency mismatch as an unfixed defect or tighten timing without fixtures that preserve real record cadence.

- These also form successive differences without timestamps, so they can join unreported time:
  - the irregular-rhythm screens (above);
  - PRSA, which also uses L=2, not the documented 64;
  - the sleep `hrv_timeline`, the HRV detail's today chart;
  - the 24/7 `hrv_day` curve, preferred on the Day timeline and Sleep lanes;
  - daytime HRV.
- Even gap-aware `correctRr`/`hrvTime` paths bridge up to about one missing beat (1000 ms
  re-anchor), and Lipponen windows count beats across re-anchored dropouts.
- If headline `rmssd` is absent, the Sleep HRV row shows the mean of `hrv_day`/`hrv_timeline`
  points, a fourth estimator. The fallback-mixed `rmssd` also feeds anomaly, percentile, glass box,
  session cost, the EWMA baseline, rough night, movers and the CSV `hrv` column.
- RSA respiration refuses whole nights through gaps: its Nyquist gate uses
  meanNN = span/(n−1) on a gap-keeping clock (`resp_rate.dart`, spot-checked), so coverage below
  about 80% at HR 60, or sleeping HR under 48, withholds the rate. Readiness then drops the
  breathing input, and the Trends breathing copy blames window disagreement instead.
- BRV windows bypass the 30% artifact gate (`artifactFraction: 0.0`).
- Lomb-Scargle density scales with span/(n−1), so absolute band powers grow with dropouts. If wall
  time is the right clock, the beat-sum clock's ~3.4% shortfall biases spectral rates up by about
  0.5 br/min (unresolved).
- Thin input publishes: stress returns a 0–100 score, level and stored series from ≥30 cleaned
  beats of any scored sleep, with no duration or coverage gate (`stress_si.dart`, spot-checked).
  RSA can publish from roughly 2–10 dense minutes.
- Labels:
  - The `hrv_cv` method text says "Night-to-night coefficient of variation of RMSSD"
    (`metric_detail.dart`, spot-checked); the code computes within-night SDNN/meanNN.
  - Sleep's "Heart rate X average · lowest Y" prints the lowest-30-minute RHR and the 1st
    percentile.
  - The nadir time belongs to the single minimum sample.
  - The stress spec says "resting window" but uses the whole sleep window.
  - A per-night CVHR is rendered although the library says "never per-night".
- Two HRR tau implementations exist; the library result is computed and discarded.

### Sleep Regularity, Breathing Lane And Night-Selection Defects

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: relative stillness (within 0.02 g of the window median on 90%); SRI over observed all-day epochs; 3 h night-time fallback; correction save blocked under 50% recorded; Home bar uses last night's stored need; "In bed at" label. Kept: the approved rule lets a later night with more sleep replace the pick (a later, shorter night does not). Open: the restlessness map's |mag - 1| test, stage cutoffs (experiment), debt/wake-count and smaller items.

Build 90 source supersedes the map/accounting items below: arm-angle restlessness replaces
magnitude-minus-1 g; sleep need adds a quarter of the estimated gap and no strain bonus;
one five-minute wake-run definition serves segmentation and scalar history; cycles are absent
when unqualified or unstaged; Sleep names recording-gap durations as lower bounds. RR reporting
quality is retained without a new nightly-HRV gate. HF, respiration and REM spectral windows
require 90% coverage and exclude clock re-anchors. Eight beat-quality and seven accounting
regressions pass. Stage smoothing/cutoffs retain their existing experimental status; validation
against a reference recording and phone checks remain open.

- **SRI is not the Phillips index.** `_crossDaySri` marks epochs valid only where a hypnogram exists
  (spot-checked), so it compares only minutes inside both nights' windows and moving bedtime barely
  changes it. The audit also found unobserved epochs counted as asleep. Hidden from UI, but stored.
- **Breathing-lane stillness gate.** `dayRespCurve` requires | |a| − 1 g | ≤ 0.02 g on 90% of a
  3-minute window. This band's still magnitudes run about 0.93–1.07 g by posture (plus the ~4.6%
  scale), so breathing points survive only in postures that happen to read near 1 g. This is the
  likely main cause of sparse/early-missing respiration lanes. The restlessness map reuses
  |mag − 1|.
- **Stage cutoffs are tuned to normal proportions.** Weights come from 99 DREAMT PSG nights using
  that dataset's own features. Cutoffs were swept on 11 unlabelled WHOOP captures to land REM
  20–25% and Deep 13–23%. Held-out four-class κ is 0.132 with wake sensitivity 11%; the one WHOOP
  "truth" night is an Apple Watch comparison and was also the tuning night.
- **Fallback nights bypass the 3-hour rule.** The HR-led fallback needs 2 h, has no time-of-day
  limit, and its daytime HR baseline is always empty in live staging, so its threshold is the
  window's own 30th percentile.
- **Night selection and Home ring:** a later, shorter automatic candidate can be blocked by the
  TST-only richer-night guard even if it represents a different night. Same-night protection
  against pruned replay is intentional; explicit overrides already bypass that branch. The
  Home sleep ring divides last night's sleep by tonight's need.
- **Coaching and accounting:** debt is added back in full every night. Two different wake-up counts
  exist.
- **Clock times:** "Fell asleep" and bedtime consistency use the in-bed onset rather than
  first-sleep time, and clock offsets handle DST but not travel.
- **Smaller items:** a 5-minute minimum bout erases short REM; missing cycles show as 0; TST-driven
  consumers (readiness, debt, need, ring) ignore coverage.

### Quiet-Day Strain Inflation And Gross Training Load

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: the strain target is withheld; day zone minutes and the zone label share one `trainingZones` set; strain-dependent sleep need and the strain mover count observed days only. Also repaired (decided): TRIMP uses the zones' max HR (observed ceiling once it reaches the age estimate, else the estimate), and each minute counts for the time it actually recorded, with the quiet baseline over the same covered minutes. Strain values can move slightly on days with gaps or a high observed ceiling.

- All five strain callers pass `quietWakingHrr = 0.20`. The constant's own documentation in
  `load_trimp.dart` (spot-checked) measured that this left a no-activity day at 6.93–12.14 out of
  21 against a personal quiet level of 0.274; `dailyQuietWakingHrr` has no caller. This is a known
  directional bias, not only a deferred experiment. It feeds Today's strain target (whose bands
  assume an inactive day ≈ 0), the "strain 14+" mover tag and the sleep-need strain bonus.
- CTL/ATL use gross TRIMP, including roughly 176 TRIMP in the source's example profile merely being awake, which scales with
  wear minutes. Combined with the zero-filled gaps above, wear coverage alone moves load.
- Strain zones use the observed ceiling while TRIMP stays on the age estimate. Two zone definitions
  exist for the same day. A minute with one sample counts as a full minute, and strain has no
  minimum-wear gate. Imported days enter load as zero-TRIMP rest.

### Energy, Steps, Live Speed And Food/Weight Estimate Edge Cases

Build 90 Codex source implements research G1/G2/G4: general bodyweight resistance is
3.0 MET, functional is explicitly an estimate, and the distance comparison claims ACSM
only within supported measured speed ranges. Other/unknown speeds retain the value as a
Movement estimate. The shorter-than-six-week food/weight display includes the approved
conversion envelope; calculation gates and calorie targets are unchanged. Food quick
weigh-in now delegates to BodyLogDb rather than writing the daily table independently;
first-reading persistence needs Claude's merged Body logic. Resting HR on Sleep, Recovery
and metric detail is labelled lowest 30-minute average while asleep. Device checks remain open.
Build 90 live-speed source additionally requires valid platform speed uncertainty and shows
its ± value in the user's speed units. An invalid speed cannot reappear through the old
position-difference fallback. Distance and moving-time recording remain independent.

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: partial run steps stay known; DST-length BMR; fabricated, over-4 h and overlapping lifts; low-HR lifts by MET; live speed over time (tau 5 s), stop detection, "—" without a fresh fix and moving-time average; Theil-Sen food/weight estimate with Sen's range, 3 weigh-ins per half, hidden past +/-300 kcal. Superseded by Build 89: steps are phone-only and high-rate live streams are off in the personal build. Open: live-speed constants need an outdoor walk and run.

All documented coefficients, gates and worked examples match source. Climb terms are inert:
`runMix`/`motionMix` pass `climbM: 0`. These are policy/coverage edges, not arithmetic errors:
- If a run's step coverage is short by any amount, the day switches to `max(walk, run)`
  (`day_upkeep.dart`, spot-checked). 15,000 steps plus the 5 km worked-example run then gives
  2,451 instead of 2,612 kcal, and the run row vanishes.
- Full-day BMR is not scaled to 23/25-hour DST days (about ±78 kcal).
- `liftingOn` ignores `end_ts_fabricated`, so a stale reconciled lift can be priced for hours in the
  separate lifting line. Overlapping lifts are not de-duplicated. A low-HR non-lift session can
  price at 0, because `min(MET, HR)` lets HR win.
- Steps: any positive phone hour removes all wrist steps in that window. In phone-uncovered time,
  wrist steps are credited at any density.
- Live speed:
  - With the 5 m distance filter, iOS stops sending fixes at a stop, and the stationary-zero branch
    (under 4 m) is nearly unreachable. Inference: the last speed lingers 10 s, then the display
    flips to the labelled workout average.
  - The EMA is per fix, not per second, a lag of about 33 m of travel.
  - A rejected platform speed falls back to position-derived speed with up to 50 m position error.
  - Live average pace uses elapsed rather than moving time.
- Food/weight estimate: raw unweighted OLS over the last 28 days, with no leverage/spread gate and
  no displayed uncertainty. One +1 kg end weigh-in among eight over 14 days moves it by about
  321 kcal/day (OLS arithmetic). Manual weigh-ins dated other than today default to `history_only`
  and leave the slope; that is the settled ownership policy (plan D6), so only its disclosure on
  the card is open. The card says "morning weigh-ins", although only dates are stored,
  and prints "losing 0.00 kg a week" for a flat slope. The estimate is display-only and feeds no
  target or advice.

### Food Completeness, Body Estimates, Strength Comparisons And Goal Advice

Build 90 Codex source freezes closed-day calorie-goal/counting provenance, including first-open
legacy dates, with manual overrides and separate automatic/marked labels. Reads before profile
hydration cannot freeze an unknown target. Food writes retain eaten time separately from the
original logging time; legacy unknown logging times remain NULL. The analysis export includes
historical weigh-ins and provenance, shares bestSet/setScore and equipment/load meaning, and
retains nutrient-specific coverage, partial-total labels and weekly denominators. Export rendering
runs off the UI isolate. Temporary generated copies are cleaned after platform completion,
cancellation or failure; share copy does not claim delivery when the result is unavailable.
Database, encrypted media backup and analysis descriptions state restore support/photo contents;
automatic backups explicitly do not survive container loss. Synthetic checks pass; native share,
restore, photo-count and Food phone acceptance remain open.
Build 90 owned workout mutations now publish the shared insights/Food signal only after
successful persistence; failed-save/retry and repository mutation checks pass. Manual, retimed,
suggestion-confirmed and coach-created sessions now publish in their shared repository writer;
the form no longer increments insights separately. Suggestion-only dismissals refresh after
successful persistence. Health auto-imports use a separate table.
Multi-year synthetic profiling isolated repeated measured-step lookups as a Progress loading cost; the batched
resolver retains the same source policy and old unmeasured series points without a history cap.

Build 90 UI source repairs the shared value-alignment defect: optional history and actions no
longer leave values floating in the middle. Units sit below digits, labels use sentence case,
and large-text comparison groups/detail titles reflow. Today removes duplicate totals while
keeping daily actions and all unique cards; Trends groups related rows and retains missing-day
coverage and both energy estimates. Progress retains one fixed-window verdict and full details.

**Filtered saved-food/meal drag:** a search/category filter previously substituted plain rows
while still advertising hold-drag. Build 90 keeps DragList active in Log Food (My foods/My meals)
and Food → Foods. Reordered matches are placed back into their original slots in the complete
list, preserving hidden items and persistence; swipe-delete confirmation/cancellation remains.
Synthetic gesture/persistence checks cover these paths; the phone drag check remains open.

The selected B calorie/macro component originally lost its ring when Codex copied only the
macro rows. Food now restores remaining calories inside the ring, eaten/fixed goal alongside,
and compact rows below. Missing/partial inputs do not fabricate an exact arc; over-goal copy
remains explicit. The decorative plate/fork and linear calorie bar are replaced. The original
24 merged-view observations have individual dispositions in `build-90-audit.md` under Current Visual
Acceptance. The six approved presentation choices and explicit fixes are implemented: consistent
Today target sub-lines/equal actions, intact Trends coverage and full-width movement context,
anchored pins/Food actions, all-meal totals without singleton duplication, grouped Progress
inputs, an active Add body entry button, full-width Body comparison rows and a single Sleep
correction card. Milestones cannot describe identical rounded values as a decrease: they retain
a second decimal or show the actual difference. Exact stored readings and metric logic are unchanged.
Today's 10-minute/hour/day HR previously allowed selection past the last recorded data; day
detail capped only at the clock. Both now share the latest-real-minute cap, excluding future
samples/trailing gaps, with the same limit for pointer and accessibility input and retained cursors.
Internal gaps stay absent and live bpm remains separate. Targeted checks and device gates are in
todo.md; open observations are not marked repaired merely by this source change.

Build 90 Food source implements the selected calm A overview with B's full calorie/macro card:
remaining calories in the ring, eaten/fixed goal alongside, all four nutrient/target rows with slim
bars, and a visible Add food action. Unknown/partial totals keep their qualifiers; maintenance
comparison is shown in its existing panel. Diary items show calories/protein, meal headings
show energy once, and full meal/group/entry screens retain all nutrients and edit routes.
Meal headings/actions reflow at large text; week marks are smaller with the legend retained.
A failed manual counting-status write now reports its error without changing the visible
status. Existing reviewed whole-day copying remains. Copying is atomic and only the explicit Log action
writes. Past-date Quick add already used meal-clock defaults in the base; the added test
pins that behavior alongside the new separate logging timestamp. Reviewed bottom-tab labels
retain their native-sized, intact text at accessibility sizes; phone acceptance remains open.

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired in Build 88: explicit completion only (D13), subsequently extended by Build 89 automatic counting with manual overrides; "at least" totals and day-state calorie card; unknown protein never 0; Navy male-only, neck within 30 days, 3-50%, both dated; waist/tape from a reading within 7 days of the start; protein advice needs 5 complete days; no step without a calorie goal; Monday weight weeks; recomposition needs waist and a comparable lift.

All documented phase bands, protein ranges, review gates, step sizes, floor formula, streak
constants and per-100/two-way serving scaling match source. No path writes a calorie target.
Defects and corrections:
- **Day completeness.**
  - `foodEntryTime` stamps a past-day dinner at 19:00 by default, past `kEveningLogHour` 17, so a
    dinner-only past day auto-completes.
  - A single late 150 kcal entry also completes a day.
  - An isolated synthetic dinner-only 150 kcal fixture at the default 19:00 reproduces
    `DayLogState.complete` and inclusion in averages. Akshat selected explicit completion for
    advice/food-weight TDEE; existing automatic behavior remains until Build 88 implementation.
  - Quick add stamps the current time even for a past diary date, so `atTs` has two meanings.
  - Weight "latest of day" is really last saved: `putWeight` replaces the date's row and ignores
    `at`.
- **Protein advice** uses a protein mean with no count of protein-complete days, so one
  macro-complete day can drive "raise protein first" or a low g/kg verdict.
- **Floors.**
  - The floor's sex check is exact `user['sex'] == 'f'` (`progress_screen.dart`, spot-checked),
    while Mifflin accepts 'f'/'female'.
  - With no calorie target, no floor check runs and "lower by N kcal" can still show.
  - A goal already below the floor reads "already at its floor".
  - Steps are sized from the typed goal, not observed intake.
  - The "more steps" suggestion at the floor has no adequacy check.
  - The Goal screen copy promises it "never suggests going below your resting energy or 1,500 kcal
    (1,200 for women)", which holds only when a target exists.
- **Navy estimate.**
  - `BodyLogDb.navyBodyFat` is the male inch form with no sex gate (spot-checked) and no hip term.
    It is shown for female, other and unknown sex.
  - It has no plausibility clamp, and no age limit on the neck reading.
  - The screen dates only the waist (neck only if different).
- **Comparison windows.**
  - Waist change compares the later window's last reading with any earlier reading, however old,
    and is set against a weight change over only the window length.
  - Weekly blocks and tape changes use the nearest earlier reading, often undated.
  - `daysOnGoal` uses `difference().inDays`, so the 14-day gate can read 13 across spring-forward.
  - Body weeks start Saturday, while Review weeks run Monday–Sunday.
- **Strength.**
  - The Review picks the heaviest set by load while the live workout picks the best Epley score,
    so the same sessions can read up in one and unchanged in the other (e.g. 105×1 and 100×8,
    then 100×9).
  - `liftTrend` compares only newest against oldest, without showing the span, and its plateau
    rule ignores deloads.
  - Live set comparison is positional, so extra sets misalign it.
  - Epley scores one rep at 1.033× load.
  - Heavier-for-fewer-rep pairs are direction 0, so real regressions never reach the recovery
    priority.
  - Legacy or fabricated-end sessions add unsplit `duration_min` to the activity streak at midnight
    and can double-count with timed sessions.
- **Recomposition verdict.** "On track" depends on the weight rate alone. Waist and lifts appear
  only in the 56-day stall line, which counts absent lift or waist data as "no progress". The
  `waistFast` gap can cut calories even when weight is below the lean-gain band. Red means any
  intake above maintenance, even in lean gain.
- **Presentation.**
  - `CalorieCard` ignores day state, so a partial or in-progress total prints "X left" and a green
    "below estimated maintenance".
  - Meal cards and the meal page sum unknown kcal as zero without "at least", and `_proteinLeft`
    treats unknown protein as 0.
  - The Review "Weight average" appears at "1 → 1 weigh-ins".
  - Copy claiming more than the data supports: "Add muscle with as little fat as possible", "Lose
    fat steadily while keeping your strength", "On track for recomposition", "eight weeks without
    stronger lifts or a smaller waist", "US Navy body fat about X%".
- **Correction to B88-08 check 8.** The Review tab already shows independent weight, waist, calorie
  and strength stats under "Partial evidence" when lifts or food are missing; only `review()`'s
  conclusion and detail sentences are withheld.

### Input Retention And Wear Accounting Limits

These are carried-forward investigation items from the Build 87 source review, not all
reproduced Build 89 defects. Reconfirm current consumers/decoder paths before implementation;
unsupported temperature/oxygen outputs remain withheld by the shipped family gates.
`build-90-audit.md` includes them in the complete backlog without treating absent raw inputs
or unobserved latent record shapes as established device failures.

- Green ADC is decoded but never stored, so no historical RIIV/green respiration path can run.
- Historical R10-lite HR goes only to legacy `samples`, not the substrate (its beats are kept).
  Prevalence is unknown.
- Build 90 source uses one recorded-minute definition for `metric_series` and the day wear
  block, bridging gaps up to 120 seconds. WRIST events establish off-wrist spans, band events
  establish charging, and time after the committed frontier is pending sync. Other recording
  gaps are unknown, including legacy segments; they are not labelled off-wrist.
- Build 90 source caps historical v12/v24 records at four RR values; larger declared counts
  yield no intervals. R10 keeps its separate eight-value bound. Unknown-layout optical fields
  remain NULL through storage and isolate payloads, and old zero sentinels read as absent.
  CSV excludes legacy `odi_per_hour`/`spo2` history without deleting stored rows. Five synthetic
  regressions pass; phone verification remains open.
- Build 90 source stores the observed IANA zone timeline and UTC day seams, including
  westward extended days, eastward skipped labels and 23/25-hour DST days. Derivation workers
  receive that context; SRI uses absolute 24-hour separation and bedtime comparisons exclude
  nights spanning a zone change. Ten pure timezone checks and five schema/recovery checks pass.
  Native notification delivery while open/backgrounded remains a phone gate. Earlier travel
  cannot be reconstructed from legacy exports: before the first observation, the first known
  zone seeds the assignment context; it is not evidence of the zone actually visited.

## Stale Band-Data Age And Repeated Empty Catch-Up

Installed Build 86's later logs show successful durable commits during a window where Status
still displayed a launch-time sample several hours old. This is a confirmed display defect,
not evidence that the entire displayed interval was unsynced. Status and Today's idle freshness
line read `lastSynced`, which was assigned only at initialization/deletion; the advancing durable
frontier already existed separately. Local Build 87 uses that frontier for both readers.
Ephemeral live frames cannot advance it, and the single-record fallback notifies only after storage.

The same diagnostics show cold background connect attempts rejected while CoreBluetooth was
still unknown, repeated empty catch-up rounds, and calculations cancelled/requeued on
backgrounding. Local Build 87 primes the existing bounded adapter-state probe before connect,
stops an unproductive burst even when earlier connection totals are nonzero, connects Today's
HR chart to recent committed samples, and distinguishes queued calculation from running.
A second confirmed display problem was the aggregate calculation timestamp: Today's row commits
and triggers its UI revision before the complete derive pass refreshes aggregate freshness. A
later-day cancellation therefore leaves "Updated" behind the already-committed Today result.
Local Build 87 reads that payload and timestamp together, preserving the served-version ceiling
and separate overnight qualification rather than doing a heavy refresh during cancellation.

New synthetic regressions cover the stale boot sample, empty versus productive stale-timestamp
rounds, recorded-minute gaps and calendar boundaries. Phone cold-wake and short-visit tests
remain open; neither these logs nor source tests guarantee iOS execution or identify why every
process restarted. The supplied MetricKit exit windows do not cover this later incident.

## Overnight Freshness And Sync Lifecycle Gaps (Repaired In Build 88 Source)

**Build 88 source (`0.9.55`/`88`, algorithm 92; previously installed, superseded by installed Build 89; complete phone verification open):** repaired: no-sleep today holds over and says so; today's overnight state refreshes on commit; a lock-refused pass is not marked done; flags reset on every early return; foreground ownership waits at most 20 s and asks the headless drain to stop; BG expiry stops the drain; off-wrist links are bounced after 660 s of silence; the frontier ignores records over 10 min ahead; burst shortfalls are totalled; background lines reach the file log. Open: a BG refresh task still spends most of its ~30 s on transfer; every item needs the phone lifecycle checks.

From a read-only Build 87 source audit; none is reproduced on the phone yet.
- **A prior night can show as today's.** If today's `day_result` is flagged `NO_SLEEP_DETECTED`
  (band unworn overnight, or an early light pass before the backlog lands),
  `refreshComputeFreshness` sets `overnight_day` to today and `showing_prior_overnight` to false.
  Meanwhile `_latestBundle` serves the newest earlier night with sleep, up to 14 rows back.
  `overnightMetric` then prints that night's readiness, HRV, RHR, sleep, breathing and stress as
  today's with no held-over note, on Today, Readiness and Sleep detail. This bypasses the
  deliberate held-over refusal.
  An isolated current-code synthetic DB/repository test stores a previous-night readiness of 66
  and a no-sleep row today: `getToday` returns 66 with `overnight_day=today` and
  `showing_prior_overnight=false`. This reproduces the read contract, not phone behavior.
- **Inference: today's real night can be hidden.** Overnight state comes from the summary freshness
  row, which refreshes only when a whole pass finishes, and background cancellation skips it.
  Today can then say "Last night is still being worked out" after the night committed, possibly
  into the next visit. Build 87 repaired only the activity side.
- **The derive lock drops jobs.** `DerivationEngine.run` returns 0 when another pass holds `_running`
  (spot-checked), and `DeriveScheduler` then calls `completeComputeJob`. Work queued while a
  detached rescan, reanalyze, sleep-override, nap rebuild or BG-task pass runs can be marked done
  without computing.
- **Backgrounding does not cancel everything.** It cancels only scheduler-owned passes. Detached
  rescan/reanalyze/override/nap passes keep running, so Build 86's "cancel in-flight calculation"
  is only partly true. Native BG expiry cancels calculation, but the headless BLE drain continues;
  the 15-minute gate timeout force-releases the band while that orphaned run continues.
- **Latches and ownership:**
  - `openSession` returns early when busy or unpaired, before it clears the background flags it
    alone resets. A slow connect during app switching can hold calculation for the whole visit, and
    pull-to-refresh then waits out its cap.
  - `BandOwnership.acquireForeground` still has no deadline, yet the app awaits it before the
    connect that would preempt a headless drain, which can run 600 s. That contradicts the Build 86
    "bound ownership handoffs" claim.
  - Known off-wrist makes `isLinkStale` false indefinitely, so a dead link while off-wrist may never
    be bounced. Plausible; the battery-poll timeout path was not traced.
- **The newest-data frontier can be pinned.** Records up to 24 h in the future pass `kFutureMargin`
  and raise the monotone `rec_ts_hw`. A decodable record with timestamp ≤0 is admitted untimed, and
  `_recTsFor` falls back to phone capture time. Either can make Status say "just now", silence the
  staleness alert and make the derive debounce treat data as fresh.
- **Short WHOOP 4 bursts are still ACKed.** WHOOP 4 sets `burstCountGateEnforced: false`, so a burst
  the band counted as short is still committed and ACKed ("ADVISORY, gen4"). Commit-before-verbatim
  ACK holds on every drain path, and a failed commit blocks the ACK. "Never ACK a partial chunk" is
  therefore not enforced by packet count on this band; real loss is unmeasured.
- **BG tasks rarely reach calculation.** A BG refresh task's ~30 s is usually spent on the
  600 s-capable transfer. After a headless drain, the native restore central stays idle until the
  app re-arms it.
- **Diagnostics are blind in the background.** Only the app's own `_log` reaches
  `openstrap_sync.log`. Headless, BG-task, restore-gate and background-derive lines, including
  commit checkpoints, go to `debugPrint` only. `openstrap_exits.log` has no size cap.

Confirmed sound: commit-before-verbatim-ACK on foreground, restore, headless and both BG paths;
cancellable derive isolates with requeue; the served-version ceiling; immediate Today refresh
after its row commits; notification dedupe under a lock. Build 88 B88-05 owns the repair and
diagnostics plan.

## Workout Live Activity never drew (builds 74–80): resolved by removal in build 81

Symptom: the Status sample and real walks reported "Started"/"Updated", but the lock screen showed
nothing and the Dynamic Island an empty black pill (iPhone 17, iOS 26.6.2, all switches on).
Evidence: the extension's crash reports (`OpenStrapWidgetExtension-2026-10-07-*.ips`, 0.9.47/80)
show it killed at launch before running any code, `EXC_BAD_ACCESS (SIGKILL)`, namespace
CODESIGNING, indicator "Invalid Page", signed as `com.akshat.personal.whoop.5564K8D4SV.activity`.
The Sideloadly 0.70.1 install log provisions only one App ID ("Using app ID "WHOOP"") in both
bundle-ID modes, so the extension ran under the app's profile. The shipped extension itself was
correct (matching attribute types, widgetkit point, version 80). Build 81 removes the extension
from the personal IPA and stops requesting activities. A future Live Activity needs an installer
that provisions extension App IDs.

## Other known environment quirks (not app bugs)
- Vivo/OriginOS aggressively kills background apps — battery optimization must be "No
  restrictions" for `edge`, app locked in recent-apps view, or background sync gets killed outright.
- Quit/uninstall the official WHOOP app before pairing — only one app can hold the Bluetooth
  connection to the band at a time.

## Documentation synchronization

If reconnection evidence, platform scope, leading hypotheses, or verification state changes, update
this file together with `CLAUDE.md`, `setup.md`, the applicable iOS guide, and any implemented test or
recovery instruction. Keep Android evidence, personal-iPhone plan, and observed iPhone behavior
separate.

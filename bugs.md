# Reconnection Evidence and iPhone Verification Risk

The Android observations below are retained as protocol/implementation evidence only. Akshat's
personal product scope is now iPhone-only, so no Android fix, build, or device validation is planned
unless that scope is explicitly reopened. The active work is proving the separate CoreBluetooth
restoration and reconnection path on the personal iPhone build.

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
- after a manual force-quit, iOS will not relaunch the app for Bluetooth until it is opened again;
- after an iPhone reboot, restoration is not guaranteed until WHOOP is opened once.

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
testing candidate, installed (Akshat), awaiting device acceptance; build 70 remains recovery.

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

## Background sync and slow pull-to-refresh (investigation, build 82 planning)

Report (build 80): data syncs only while the app is open, though it is not swiped away; Status
showed band data 44 min old until the app opened. Every pull-to-refresh takes long.
How it works now (source):
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
Evidence so far (Akshat, 7 Oct): the phone's Analytics Data holds `Runner.cpu_resource_fatal`
kills only up to 14 Sept (build 63) and a `Runner.diskwrites_resource` report on 22 Sept, nothing
since, so recent builds are not being killed for CPU; the stale background data is suspension or
offload spacing, not a crash. The app log never existed on iPhone: `FileLog` tried Android's
external storage first, which throws on iOS, and the shared handler disabled logging. Fixed in the
local build-82 source (iOS writes `openstrap_sync.log` to Documents, visible in Files → WHOOP), and
pull-to-refresh now logs when phone steps, the band pull and the calculation finish. Next
evidence: that log after a backgrounded hour and one pull-to-refresh on build 82.
Candidate fixes (`todo.md`): spinner stops after phone steps + a ~3 s band top-up while the
recalculation finishes on screen; timing lines per refresh stage; keep background offloads at
15 min while connected (no long backoff); arm the restore central while connected so a system
kill can relaunch the app; reduce background CPU if kills are confirmed.

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

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

## Workout, sync and profile consistency

`workout-sync-audit.md` owns the build-72 reported symptoms, source traces, research and isolated
reproductions: insight retry/rebuild gaps, background voice, gross versus active calorie models,
run-step overlap, cross-midnight/pause windows, hidden macro rows, decimal/round-trip profile input
and stale cached profile calculations. The installed build-72 session-only streak omits step-goal-only days;
the combined rule and dated target policy are documented there. The approved repairs are
implemented locally in `0.9.40`/`73` (algorithm 89) and pass local regression/release validation.
The personal source includes background audio for spoken workout cues; hardware behavior remains
subject to the build-73 phone pass. `todo.md` owns the implementation and release gates.
The added nap repair removes the full-restaging wait from reject/restore and keeps empty-day
entry points; corrected lists, sleep periods and timelines agree before coaching finishes.
Trends daily charts and step-calorie routing are also repaired locally, pending phone acceptance.

Akshat confirms build-72 Today refresh updates step numbers but reports unchanged maintenance
calories. The real-repository Food-card probe recalculates step energy immediately after a saved
count revision; an already-open maintenance sheet keeps its original values. The report maps this
reproduced stale view, cached history/profile dependencies, silent missing-input substitutions and
the separate HR/cadence calorie derivation. Overall phone acceptance remains open.

The old Windows-only failures are repaired: path/newline comparisons and local-date fixtures are
portable; POSIX timezone-switching tests remain explicitly skipped on Windows. Real source fixes
close ZIP inputs even when validation fails and count movement-floor age by calendar dates across
DST. Algorithm 88 permits recomputation. The personal capability profile is unchanged.

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

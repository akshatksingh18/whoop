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

**Next implementation:** remove or make the name fallback valid (service/company UUID plus name),
queue picker work until `.activated`, report activation failure through the method channel, and add a
regression test. Do not claim this fix until a replacement IPA passes on the physical iPhone.

The secondary-sensor screen provides a separate observation, not a WHOOP-pairing fallback. After
skipping onboarding, **Settings → My Device → Add a Sensor → Bluetooth Heart Rate Sensor** reports
“The phone’s radio is off…”. That screen is for a standard Bluetooth heart-rate chest strap, not the
primary WHOOP, and its pre-scan code maps CoreBluetooth `poweredOff` to that exact sentence; an
app-level denial has different copy. Confirm Bluetooth is on in the iPhone Settings app and WHOOP
is allowed under Privacy & Security → Bluetooth. Also force-quit/relaunch WHOOP after attempting a
secondary-sensor scan: that path creates a global `CBCentralManager`, which the current source says
prevents AccessorySetupKit from presenting the primary-WHOOP picker for the rest of that process.

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

# Active Bug: Reconnection Failure After Any Disconnect

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

3. **On iOS**, the equivalent risk is CoreBluetooth background restoration getting killed by the OS
   under memory pressure — different root cause, same symptom, worth checking separately once iOS
   builds exist.

**Goal:** either (a) find and fix the actual bug so reconnection is silent and automatic like the
official app, or (b) if a true fix isn't feasible, at minimum improve the UX — detect a failed
reconnect and surface a clear in-app prompt ("Take the band off and double-tap the front until it
pulses blue, then try again") instead of silently sitting at "Not connected."

## Other known environment quirks (not app bugs)
- Vivo/OriginOS aggressively kills background apps — battery optimization must be "No
  restrictions" for `edge`, app locked in recent-apps view, or background sync gets killed outright.
- Quit/uninstall the official WHOOP app before pairing — only one app can hold the Bluetooth
  connection to the band at a time.

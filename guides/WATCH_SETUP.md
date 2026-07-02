# Apple Watch companion — setup

The watch companion is a **read-only mirror** of the phone's derived metrics
(recovery, strain, sleep, HRV, RHR, coach line). The phone computes everything
(the WHOOP band is the sensor); the watch just displays it, plus complications
on the face and Siri/Action-Button intents.

All the Swift + Dart is already written. Two watchOS **targets** must be created
in Xcode (target creation edits the project file, which isn't safe to hand-edit).
This takes ~10 minutes.

## Architecture (already coded)

```
 Flutter app  ──WidgetService.push()──►  App Group (group.wtf.openstrap)   [phone]
        │                                        │
        └── invokeMethod('syncWatch') ───► WatchBridge.swift  (WCSession) ─┐
                                                                            │  WCSession
 Watch App  ◄── WatchStore.swift  ◄─────────────────────────────────────  ┘
        │  writes group.wtf.openstrap                        [watch]
        ├── WatchGlanceView (SwiftUI glance)
        └── WidgetCenter.reloadAllTimelines()
                     │
 Watch Widget Ext ──►  OpenStrapWatchWidgetBundle.swift (complications)     [watch]

 Siri / Shortcuts / Ultra Action Button ──► OpenStrapIntents.swift          [phone]
```

Files written:
- `ios/WatchBridge.swift` — phone WCSession sender (add to **Runner**).
- `ios/OpenStrapIntents.swift` — Siri App Intents (add to **Runner**).
- `ios/OpenStrapWatch/OpenStrapWatchApp.swift`, `WatchStore.swift`, `WatchMetrics.swift` — the Watch App.
- `ios/OpenStrapWatchWidget/OpenStrapWatchWidgetBundle.swift` — the complications.
- Already wired: `AppDelegate.swift` (activates the bridge + `syncWatch` case), `lib/widget/widget_service.dart` (`_syncWatch()`).

## Step 1 — Create the Watch App target

1. Open `ios/Runner.xcworkspace` in Xcode.
2. **File ▸ New ▸ Target… ▸ watchOS ▸ App**. Name it `OpenStrapWatch`.
   - Interface: **SwiftUI**, Language: **Swift**.
   - "Watch App for iOS App" → **Companion to Runner** (bundle id becomes
     `wtf.openstrap.watchkitapp`). Uncheck "Include Notification Scene".
3. Delete the auto-generated `ContentView.swift` / `…App.swift` Xcode made for the
   watch target (we ship our own).
4. Add our files to the **Watch App** target (drag into the group, tick the
   OpenStrapWatch target): `OpenStrapWatchApp.swift`, `WatchStore.swift`,
   `WatchMetrics.swift`.
5. Set the Watch App **Signing team** to `2U62X3RF3R` (same as Runner).
6. Set **Deployment target** watchOS 10.0+ (needed for the Gauge/accessory APIs).

## Step 2 — Create the Watch Widget Extension (complications)

1. **File ▸ New ▸ Target… ▸ watchOS ▸ Widget Extension**. Name it
   `OpenStrapWatchWidget`. **Uncheck** "Include Configuration App Intent" (we use
   a static configuration). Embed it in **OpenStrapWatch**.
2. Delete its auto-generated widget file.
3. Add to the **Watch Widget** target: `OpenStrapWatchWidgetBundle.swift` **and**
   `WatchMetrics.swift` (this file is a member of *both* watch targets).
4. Signing team `2U62X3RF3R`.

## Step 3 — App Groups (the plumbing)

- **Watch App** and **Watch Widget** targets: Signing & Capabilities ▸ **+ App
  Groups** ▸ add `group.wtf.openstrap`. (This is the *watch-side* group so
  the watch app and its complication share the received snapshot. It is NOT the
  phone's group — devices don't share containers.)
- **Runner** already has `group.wtf.openstrap` — nothing to change there.
- Register `group.wtf.openstrap` on your Apple Developer account (Xcode's
  automatic signing will offer to do it).

## Step 4 — Siri App Intents

1. Add `ios/OpenStrapIntents.swift` to the **Runner** target (drag in, tick
   Runner). No capability needed — `AppShortcutsProvider` auto-registers.
2. First launch after install registers the phrases. Test: "Hey Siri, OpenStrap
   recovery".
3. **Ultra Action Button**: Settings ▸ Action Button ▸ Shortcut ▸ pick
   "Recovery" (or Strain / Sleep).

## Step 5 — Build & run

```
# Build the Flutter side once so the embedded frameworks are current:
flutter build ios --config-only
```
Then in Xcode select the **OpenStrapWatch** scheme + your paired Ultra and Run.
On the phone, open the app and pull /today (or sync) once so `WidgetService.push()`
fires `syncWatch` and seeds the watch.

## Notes / gotchas

- **No data on the watch at first** is expected until the phone pushes once
  (open the app / sync). `WatchStore` also pulls on activation.
- Complications refresh on push (WatchStore reloads timelines) plus a 30-min
  safety timeline. watchOS throttles complication updates — don't expect
  second-by-second.
- The watch has **no BLE / no compute** by design. If you later want live HR on
  the wrist, that's the Apple Watch's own sensor (a separate data source from the
  WHOOP band) and a much bigger feature — out of scope for v1.
- Keep the metric keys in `WatchBridge.intKeys/doubleKeys/...`,
  `WidgetService`, and `WatchMetrics.load()` in lockstep if you add fields.

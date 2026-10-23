# WHOOP iPhone build

**State:** The committed Xcode project is the standalone personal release/AOT iPhone app.
Build 99 (`0.9.66+99`, app source `e52d571a`, algorithm 99/schema 50) is the validated unsigned
candidate in `../../final-ipas/whoop/testing/WHOOP-0.9.66-build99-e52d571a`. All 22
`../build-98-audit.md` repairs are implemented, retaining earlier repair contracts. Full cloud
analysis/tests/visuals, the macOS build and downloaded source/version/checksum/ZIP/payload checks
pass. Akshat last reported Build 91 installed; Build 99 is not yet installed or phone-accepted.
Build `0.9.37`/`70` remains accepted recovery in
`../../final-ipas/whoop/backup/WHOOP-0.9.37-build70-accepted`. `../setup.md` owns exact artifact
evidence and `../todo.md` owns phone checks. This state changes on installation and completion
of device/signing gates, not on compilation alone.

The app reads the iPhone's own pedometer when **This phone → Steps** is on and does not use Apple
Health. Earlier builds verified encrypted restore, data/pairing continuity, exact-ID manual refresh
and a controlled forced-due Wi-Fi daemon refresh; both WHOOP bundle-ID modes complete with the same
final ID, and `IOS_SIDELOAD.md` owns install-stall handling. Broader lifecycle,
background/restoration and naturally elapsed signing gates remain in `../CLAUDE.md`.

The accepted model is standalone WHOOP plus the native AkshatOS hub, two installed app slots (see
`../../akshatos/hub-plan.md`). WHOOP stays a separate Flutter app, not an embedded module. No paid
membership or extra capability is needed.

## What the project contains

`ios/Runner.xcodeproj` has two targets, `Runner` and `RunnerTests`. Build 95 removed the widget /
Live Activity extension, the Watch app, Siri intents, HealthKit, Firebase and the alternate icon
(Sideloadly's free signing provisions only the app's own App ID, so an extension was killed at
launch: `../build-81-audit.md`). `tool/personal_ios.py check` refuses any drift:

- `Runner` keeps local BLE, SQLite, analytics, UI, local notifications, Files import/export,
  `bluetooth-central` and CoreBluetooth restoration, with the stable restoration identifier,
  saved band UUID, normal Flutter drain handoff and every commit-before-ACK / resumable-cursor
  invariant.
- `ios/Runner/Info.plist` holds exactly the background modes `bluetooth-central`, `location`,
  `audio`, `fetch` and `processing`, the task identifiers `wtf.openstrap.edge.bgsync` and
  `wtf.openstrap.edge.refresh`, the AccessorySetupKit declarations, and the Bluetooth, motion,
  camera and location usage strings. Route recording asks for While-In-Use; Pushups Home
  auto-pause asks for Always (region monitoring only). No Health or Live Activity key.
- `ios/Runner/Runner.entitlements` is empty.
- `ios/Runner/Assets.xcassets/AppIcon.appiconset` is the black-and-white circular mark, the only
  icon.
- The display and bundle name is `WHOOP`; the permanent bundle ID is `com.akshat.personal.whoop`
  (`ios/Config/Signing.defaults.xcconfig`).

GPS route recording and background tasks are buildable and contract-tested, not yet
device-verified (`../CLAUDE.md`, `../background-sync-plan.md`).

## Building the IPA

New binaries come from the public repository's manual macOS workflow,
`.github/workflows/personal-ios.yml`, never from a laptop (there is no Mac). It checks the contract
(`python3 -m unittest tool/test_personal_ios.py`, `python3 tool/personal_ios.py check`, which also
refuses a version/build already accepted), then runs:

```bash
flutter build ios --release --no-codesign --dart-define=SOURCE_REVISION=<commit>
```

It packages a conventional `Payload/Runner.app`, runs `tool/personal_ios.py validate` (one root
app, no extension, no `Watch/`, no provisioning profile, database or secrets) and uploads the IPA
with a capability/source manifest and SHA-256 for 14 days. `SOURCE_REVISION` is what the in-app
**Status** screen shows as the source; a local build shows "not recorded".

Free-profile refreshes need no new build. Follow `IOS_SIDELOAD.md` for Windows signing,
monitoring, data-safe overwrite and recovery, and keep the accepted build cached on Windows outside
Git (`../../final-ipas/README.md`).

To sign from Xcode with your own account instead, copy `ios/Config/Signing.xcconfig.example` to the
ignored `ios/Config/Signing.xcconfig` and set your team; never commit it.

## Version alignment

`Runner` takes `CFBundleShortVersionString` and `CFBundleVersion` from `pubspec.yaml`'s
version; the project's `MARKETING_VERSION` / `CURRENT_PROJECT_VERSION` lines are kept equal to it.
Every new binary gets a new version/build; `tool/personal_ios_accepted_builds.json` prevents reuse,
and the bundle identity never changes.

## Acceptance

The independent `../build-96-audit.md` reproduces seven additional faults in Build 96.
Build 99 retains those repairs, the eighteen `../build-97-audit.md` contracts and all 22
`../build-98-audit.md` repairs. Full cloud/visual/native checks and replacement IPA validation pass; Builds 96–98
are retained only as historical payload evidence.

Before promotion, inspect the payload, perform a fresh install and a same-ID in-place upgrade,
require the shared signing-health check to print `ENROLLED` for the exact WHOOP signed identity and
current version, pair and drain offline, prove CoreBluetooth background/restoration behaviour,
complete the 72-hour soak, restore an encrypted export, and pass the refresh/expiry gates in
`../CLAUDE.md`. A one-off install that launches is not automatic-refresh coverage, and a successful
compile does not prove BLE restoration, background behaviour, data preservation or recovery. Keep
the official WHOOP app quit while pairing or testing.

## Documentation synchronization

When capabilities, identifiers, build commands, the toolchain, the workflow or the verification
state change, update this guide, `IOS_SIDELOAD.md`, `../setup.md`, `../README.md`, `../CLAUDE.md`
and the affected tests in the same change, keeping what is built separate from what was observed
on the phone.

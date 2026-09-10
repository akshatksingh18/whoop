# WHOOP iOS build and installation profiles

**State:** The repository contains the full upstream-capable iOS targets plus an implemented minimal
personal-sideload build profile and manual private-GitHub workflow. No personal IPA has been built,
signed, installed, or physically verified yet.

The accepted model is standalone WHOOP plus one native hub for Squats, PageVault, and ReelVault:
two free-signing slots. See `../../akshatos/hub-plan.md`. Keep WHOOP as this separate Flutter app,
not an embedded module. Its iPhone-only implementation scope is active, but the minimal personal
artifact remains unbuilt and every verification gate remains; no paid membership or capability
expansion is needed for the chosen packaging. The imported Android target is reference source only
and is not part of this build or acceptance matrix.

This guide separates two different artifacts that must not be conflated:

1. **Personal free-sideload build (selected for Akshat):** standalone phone-only release/AOT IPA,
   deliberately minimal for direct Sideloadly installation.
2. **Full source-signed upstream build:** Runner plus Apple capability targets such as App Groups,
   Widget/Live Activity, Watch, and HealthKit, requiring a signing team/profile that grants them.

## Common prerequisites

- Compatible macOS and Xcode with support for the physical iPhone's iOS version.
- Flutter and CocoaPods; use the pinned/recorded project toolchain when producing a release.
- A physical iPhone and WHOOP band for BLE testing; the simulator cannot validate the product.
- A local ignored `.env`, with optional network features disabled unless deliberately tested.
- The official WHOOP app fully quit before pairing because only one app should own the peripheral.

From the repository root:

```bash
cp .env.example .env
flutter pub get
flutter doctor -v
flutter devices
```

Never commit credentials, Apple signing files, personal health data, databases, captures, or IPAs.

## Profile A: selected personal free-sideload build

### Required build contract

The dedicated profile is implemented with `PERSONAL_SIDELOAD`, `tool/personal_ios.py`,
`ios/Runner/RunnerPersonal.entitlements`, and
`.github/workflows/personal-ios.yml`. It transforms only an ephemeral build checkout rather
than editing the full target ad hoc or expecting Sideloadly to repair entitlements:

- keep `Runner`, local BLE/SQLite/analytics/UI, local notifications, Files import/export,
  `bluetooth-central`, and CoreBluetooth restoration;
- preserve the stable restoration identifier, saved band UUID, normal Flutter drain handoff, and
  every commit-before-ACK/resumable-cursor invariant;
- remove the Watch companion and Widget/Live Activity extension from the packaged IPA;
- remove App Group and HealthKit entitlements and hide/compile out their UI/bridges together;
- remove GPS route recording and location permission keys from the initial profile;
- remove `processing`, `fetch`, and their native/Dart BG task registrations from the
  initial profile;
- default required backend, OTA, health contribution, Firebase Analytics/Performance/Crashlytics,
  and bundled secrets off; BYOK/network features are manual opt-ins only if offline use is complete;
- fail packaging if `Watch/`, widget `PlugIns/*.appex`, unexpected entitlements, signing
  credentials, personal data, injected dylibs, or secrets remain.

The manual workflow applies and tests these exclusions, then runs:

```bash
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

It packages a conventional `Payload/Runner.app`, validates it, and emits a capability/source
manifest plus SHA-256. The iPhone display/bundle name is `WHOOP` and the permanent bundle
ID is `com.akshat.personal.whoop`; its availability to the selected Personal Team remains
a first-signing gate. Cache the accepted unsigned IPA and previous known-good artifact on Windows
outside Git.
The personal configuration selects `AppIconPersonal`, generated from Akshat's supplied
black-and-white circular logo; the upstream `AppIcon` catalog remains unchanged.

New source binaries require macOS/Xcode; free-profile refreshes do not. Follow
`IOS_SIDELOAD.md` for Windows signing, monitoring, data-safe overwrite, and recovery.

### Personal flavor acceptance

Before promotion, inspect the payload/entitlements, perform a fresh install and same-ID in-place
upgrade, pair and drain offline, prove CoreBluetooth background/restoration behavior, complete the
72-hour soak, restore an encrypted export, and pass the refresh/expiry gates in `CLAUDE.md`.

## Profile B: full source-signed upstream build

Use this profile only when the selected Apple team/profile supports the full capability set. It is
not the accepted free-Sideloadly daily artifact.

### Local signing configuration

The committed project uses placeholders. Copy the ignored override:

```bash
cp ios/Config/Signing.xcconfig.example ios/Config/Signing.xcconfig
```

Set identifiers belonging to the selected signing team:

```text
APP_BUNDLE_IDENTIFIER = com.yourname.openstrapEdge
APP_WIDGET_BUNDLE_IDENTIFIER = $(APP_BUNDLE_IDENTIFIER).OpenStrapWidget
APP_GROUP_IDENTIFIER = group.com.yourname.openstrap
APPLE_DEVELOPMENT_TEAM = YOURTEAMID
```

Do not commit `ios/Config/Signing.xcconfig` or personal Xcode project changes.

For the full build, create matching Runner and widget App IDs, one App Group, enable the App Group on
both IDs, and grant every shipped entitlement (including HealthKit when retained). Open the workspace:

```bash
open ios/Runner.xcworkspace
```

Verify signing/capabilities for Runner, Widget, and any included Watch target against the same team
and intended identifiers. Do not assume a free Personal Team profile grants these capabilities.

### Build modes

```bash
# Attached development
flutter run -d <device-id> --dart-define-from-file=.env

# Unsigned release build check
flutter build ios --release --no-codesign --dart-define-from-file=.env

# Signed release-style physical-device run
flutter run --release -d <device-id> --dart-define-from-file=.env
```

Flutter debug builds require Flutter/Xcode tooling to relaunch and are not daily Home Screen builds.
Use Profile/Release for standalone relaunch testing.

## Version alignment

Runner derives `CFBundleShortVersionString` and `CFBundleVersion` from Flutter's build name/number.
The Widget and Watch targets have separate hardcoded `MARKETING_VERSION`/
`CURRENT_PROJECT_VERSION` values in the Xcode project and must be aligned manually when those
targets ship. The personal phone-only artifact excludes them, but its Runner version/build and source
manifest still change for every new binary; bundle identity does not.

## Common failure checks

- Open `ios/Runner.xcworkspace`, not only the Xcode project.
- Update Xcode when it cannot support the physical iPhone's iOS version.
- Treat entitlement/profile mismatch as a build configuration error; do not let Sideloadly strip or
  mutate features unpredictably.
- Keep the official WHOOP app quit while pairing/testing.
- A successful compile/install does not prove BLE restoration, background behavior, database
  preservation, or backup recovery.

## Documentation synchronization

When the personal flavor, capabilities, identifiers, build commands, toolchain, workflow, or
verification state changes, update this guide, `IOS_SIDELOAD.md`, `setup.md`, `README.md`,
`CLAUDE.md`, workflow/configuration notes, and affected tests in the same change. Keep full-source
and minimal-personal profiles explicit, and keep implementation, built artifacts, and observed
device behavior separate.

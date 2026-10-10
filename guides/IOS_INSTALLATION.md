# WHOOP iOS build and installation profiles

**State:** The repository contains full upstream-capable iOS targets plus an implemented minimal
personal-sideload profile and public manual macOS workflow. Akshat reports build `0.9.52`/`85`
currently installed. Source `3c141b7a` passes recorded local validation, Linux CI, macOS compilation
and downloaded artifact checks, with no app extension (removed in build 81).
The single testing candidate remains
`../../final-ipas/whoop/testing/WHOOP-0.9.52-build85-3c141b7a`. Complete phone acceptance,
data/pairing continuity, background behavior and current-version automatic-refresh enrollment
remain open in `../todo.md`; installation alone does not authorize cache promotion.

Build `0.9.37`/`70` remains accepted recovery: its feature phone check and current-version
automatic-refresh registration at the existing signed identity were confirmed with no error.
It is cached in `../../final-ipas/whoop/backup/WHOOP-0.9.37-build70-accepted`.
`../setup.md` owns current and superseded source/hash/workflow evidence; `../build-85-audit.md`
owns the latest approved changes, and earlier audits retain their findings and repair contracts.

The personal profile excludes HealthKit and reads the direct iPhone pedometer when **This phone →
Steps** is enabled. Earlier builds verified encrypted restore, data/pairing continuity, exact-ID
manual refresh and a controlled forced-due Wi-Fi daemon refresh. Both WHOOP bundle-ID modes
complete with the same final ID; `IOS_SIDELOAD.md` owns install-stall handling. Broader lifecycle,
background/restoration and naturally elapsed signing gates remain in `../CLAUDE.md`.

The accepted model is standalone WHOOP plus the native AkshatOS hub:
two installed app slots; the personal IPA carries no app extension (build 81). See `../../akshatos/hub-plan.md`. Keep WHOOP as this separate Flutter app,
not an embedded module. Its iPhone-only implementation scope is active, but installed-identity and
physical-device verification gates remain; no paid membership or capability
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
- remove the Watch companion, general/home/breathing widgets and (from build 81) the workout
  Live Activity extension: Sideloadly's free signing provisions only the app's own App ID, so iOS killed the extension at launch on a code-signing check (CODESIGNING "Invalid Page") and it never drew; `build-81-audit.md` holds the evidence;
- remove App Group and HealthKit entitlements and hide/compile out their UI/bridges together;
  the personal Info.plist carries no `NSSupportsLiveActivities`;
- **keep GPS route recording** — reopened on Akshat's explicit decision. `NSLocationWhenInUseUsageDescription`
  and the `location` background mode are present; route recording asks for While-In-Use only
  (`lib/gps/gps_source.dart`). Build-86 source adds `NSLocationAlwaysAndWhenInUseUsageDescription`
  for Pushups Home auto-pause (region monitoring only, Akshat's approval). Buildable and
  contract-tested, not yet device-verified — `CLAUDE.md` owns the outstanding evidence gate;
- hide the unsupported Oura pairing row in the personal flavor while retaining its direct-BLE
  implementation in the full upstream-capable source;
- `fetch` and `processing`: absent from installed build 85; build-86 source (Akshat's approval)
  keeps exactly `bluetooth-central`, `location`, `audio`, `fetch`, `processing` and the two task
  identifiers `wtf.openstrap.edge.bgsync` / `wtf.openstrap.edge.refresh`, with native
  registration in the personal build. `tool/personal_ios.py` and its tests enforce that exact set.
  Signed-device validation that the tasks actually run is still required
  (`../background-sync-plan.md`);
- the camera usage text covers barcodes and, from build-86 source, optional progress photos
  (taken through a native camera bridge, kept only in the app, without location);
- default required backend, OTA, health contribution, Firebase Analytics/Performance/Crashlytics,
  and bundled secrets off; BYOK/network features are manual opt-ins only if offline use is complete;
- fail packaging if `Watch/`, any app extension, unexpected entitlements, signing credentials,
  personal data, injected dylibs, or secrets remain.

The manual workflow applies and tests these exclusions, then runs:

```bash
flutter build ios --release --no-codesign --dart-define-from-file=.env
```

It packages a conventional `Payload/Runner.app`, validates it, and emits a capability/source
manifest plus SHA-256. The workflow also writes `SOURCE_REVISION=<commit>` into the ephemeral
`.env`, which is what the in-app **Status** screen shows as the source; a local build shows "not
recorded". The iPhone display/bundle name is `WHOOP` and the permanent bundle
ID is `com.akshat.personal.whoop`. The accepted, installed build 70 is cached in `backup\`:
`D:\AI Important Files\personal-project\final-ipas\whoop\backup\WHOOP-0.9.37-build70-accepted`.
Builds 63–69 are no longer cached; all are reproducible from their
workflow runs in `setup.md`.
Keep the accepted build cached on Windows outside Git.
The personal configuration selects `AppIconPersonal`, generated from Akshat's supplied
black-and-white circular logo; the upstream `AppIcon` catalog remains unchanged.

New source binaries require macOS/Xcode; free-profile refreshes do not. Follow
`IOS_SIDELOAD.md` for Windows signing, monitoring, data-safe overwrite, and recovery.

### Personal flavor acceptance

Before promotion, inspect the payload/entitlements, perform a fresh install and same-ID in-place
upgrade, require the shared signing-health check to print `ENROLLED` for the exact WHOOP signed
identity and current version, pair and drain offline, prove CoreBluetooth background/restoration
behavior, complete the 72-hour soak, restore an encrypted export, and pass the refresh/expiry gates
in `CLAUDE.md`. A successful one-off install is not automatic-refresh coverage.

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
targets ship. Runner and Widget/Watch metadata are aligned to `0.9.41+74` in source.
The personal artifact carries no app extension (build 81) and excludes Watch/general widgets.
Runner versions and the source manifest change for every new binary;
the accepted-build ledger prevents reuse and bundle identity does not change.

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

# WHOOP iOS build and installation profiles

**State:** The repository contains full upstream-capable iOS targets plus an implemented minimal
personal-sideload profile and public manual macOS workflow. Build `0.9.37`/`70` is installed over
build 69 and accepted: Akshat confirmed its feature phone check and completed current-version
automatic-refresh registration at the existing signed identity, with no error. It is cached in
`../../final-ipas/whoop/backup/WHOOP-0.9.37-build70-accepted`; `testing` holds validated build 74. `../setup.md` owns
source/hash/workflow evidence and superseded build records.
Build `0.9.39`/`72` was installed, confirmed by Akshat, but was not phone-accepted; its cached IPA
is superseded by build 73. `../workout-sync-audit.md` records its reported issues and approved repairs.
Source `0.9.40`/`73`, commit `a49d7837`, includes background audio for real workout cues and is
published with Akshat's approval. Local checks, Linux CI, the personal macOS build, downloaded
checksum/manifest and payload validation pass. Its testing folder was removed after build 74
validated; its workflow/source/hash evidence remains in `../setup.md`.
Akshat confirms build 73 is installed and initially looks good, with the future-time Strain cursor
defect recorded for build 74. Identity/data/pairing checks, the complete phone pass and
current-version enrollment remain unconfirmed; `../todo.md` owns the combined phone checklist
and build-74 release gates; `../build-74-audit.md` owns the research and implemented contract.
CI `37397127258` validates test-only repair `fa16be3c`; all app/packaging inputs match
compiled IPA source `ba5bb29f`. `setup.md` records the elapsed-window fixture correction.

Source `0.9.41`/`74`, commit `ba5bb29f`, enables one workout-only Live Activity extension without
App Groups. Linux CI `37397127258`, macOS build `37395690305` and downloaded version/source,
checksum, ZIP and payload checks pass. Build 74 is installed (Sideloadly kept the extension at
the exact final ID). Source `0.9.42`/`75` (commit `1c203f17`) is published with Akshat's approval; Linux CI `37514558854` (3,369 tests, 371 intentional skips) and personal macOS build `37514599309` pass. Downloaded source/version, checksum, ZIP integrity and payload/extension checks pass. Build 75 is installed. Build-76 source `0.9.43`/`76` (commit `3f8ada60`) is published with Akshat's approval; Linux CI `37534408576` (3,373 tests, 371 intentional skips) and personal macOS build `37534409412` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. The single testing candidate is
`../../final-ipas/whoop/testing/WHOOP-0.9.45-build78-1eae1fbc`, with the same extension contract;
extension behavior, overwrite/data continuity, background behavior, complete phone
acceptance and current-version automatic-refresh enrollment remain pending. Build 73 is superseded on the phone.
Installation alone does not authorize cache promotion.

The personal profile excludes HealthKit and reads the direct iPhone pedometer when **This phone →
Steps** is enabled. Earlier builds verified encrypted restore, data/pairing continuity, exact-ID
manual refresh and a controlled forced-due Wi-Fi daemon refresh. Both WHOOP bundle-ID modes
complete with the same final ID; `IOS_SIDELOAD.md` owns install-stall handling. Broader lifecycle,
background/restoration and naturally elapsed signing gates remain in `../CLAUDE.md`.

The accepted model is standalone WHOOP plus the native AkshatOS hub:
two installed app slots; the workout extension has its own App ID/signing requirement to verify. See `../../akshatos/hub-plan.md`. Keep WHOOP as this separate Flutter app,
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
- remove the Watch companion and general/home/breathing widgets; build 74 retains exactly one
  version-matched Run/Walk ActivityKit extension, empty entitlements and `.activity` bundle suffix;
- remove App Group and HealthKit entitlements and hide/compile out their UI/bridges together;
  keep only the workout Live Activity bridge/support key and exact-session URL destination;
- **keep GPS route recording** — reopened on Akshat's explicit decision. `NSLocationWhenInUseUsageDescription`
  and the `location` background mode are present; `NSLocationAlwaysAndWhenInUseUsageDescription`
  stays removed, since `lib/gps/gps_source.dart` deliberately never requests Always. Buildable and
  contract-tested, not yet device-verified — `CLAUDE.md` owns the outstanding evidence gate;
- hide the unsupported Oura pairing row in the personal flavor while retaining its direct-BLE
  implementation in the full upstream-capable source;
- remove `processing`, `fetch`, and their native/Dart BG task registrations from the
  initial profile;
- default required backend, OTA, health contribution, Firebase Analytics/Performance/Crashlytics,
  and bundled secrets off; BYOK/network features are manual opt-ins only if offline use is complete;
- fail packaging if `Watch/`, any extension except the single verified version-matched
  workout `.activity` extension, unexpected entitlements, signing credentials, personal data,
  injected dylibs, or secrets remain.

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
The personal artifact includes the single workout ActivityKit extension and excludes Watch/general
widgets. Runner/extension versions and the source manifest change for every new binary;
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

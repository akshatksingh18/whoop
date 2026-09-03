# Local Repository Setup

## Current repository state

This folder is one Git repository on `main`. It preserves the OpenStrap histories and currently
contains:

- edge base `daf6011d3aa0312e22b991713b7af9e5c4433b32`
- protocol `471034cb84b85edb37e72b6f6add79a2d7929294` under `packages/protocol/`
- analytics `1fa8144a5e3b728ce91eeed6ecbc15d482933b44` under `packages/analytics/`

The official sources are named `upstream-edge`, `upstream-protocol`, and `upstream-analytics` and
remain fetch-only. The personal workflow remote is `origin` at the private GitHub repository
<https://github.com/akshatksingh18/whoop>; `main` tracks `origin/main` after the first push. The former
same-machine bare repository at `C:\Users\aksha\git-remotes\whoop.git` is preserved as the
`local-backup` remote. GitHub is the primary collaboration/recovery remote; `local-backup` is an
additional same-machine copy, not an off-device backup.

The app's `pubspec.yaml` uses tracked local paths for both packages, so a checkout of this one
repository is self-contained. Do not restore floating Git refs or create a
`pubspec_overrides.yaml` for the imported packages. `packages/upstream-revisions.yaml` records the
reviewed source revisions and must move with any deliberate package update.

## Local Windows toolchain and build validation

The local Android toolchain is installed and `flutter doctor -v` reports no issues:

- Flutter 3.41.6 at `D:\dev\flutter` with Dart 3.11.4
- Microsoft OpenJDK 17.0.20.1 at `D:\dev\jdk-17`
- Android SDK at `D:\dev\android-sdk`, including platform tools, Android 34–36 platforms,
  build tools 35.0.0 and 36.0.0, NDK 28.2.13676358, and CMake 3.22.1
- Visual Studio Build Tools 2026 and Chrome for the other Flutter desktop/web targets

The Android SDK licenses are accepted for Akshat's Windows user. `JAVA_HOME`, `ANDROID_HOME`,
`ANDROID_SDK_ROOT`, Flutter, Cargo, and Android command-line tool paths are persisted in that
user's environment. From this repository root, the repeatable validation commands are:

```powershell
Copy-Item .env.example .env
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

`flutter pub get` completed. Flutter 3.41.6 resolved four test-tool transitive packages to the
compatible versions now recorded in `pubspec.lock` (`meta` 1.17.0, `test` 1.30.0, `test_api`
0.7.10, and `test_core` 0.6.16).

Because the repository is on `D:` while Flutter's shared Pub cache is on `C:`, Kotlin's
incremental cache cannot relativize plugin sources across drive roots. The checked-in
`android/gradle.properties` disables Kotlin incremental compilation for this project. After
`flutter clean`, the release APK build passed and produced
`build/app/outputs/flutter-apk/app-release.apk` (100.8 MB, SHA-256
`8FA85F92FEF4F5A5B32053A563F2606CD995C28549368E10F02642B7ED92F5E5`). It uses the project's
documented debug-signing fallback because no private release keystore is configured; it is not a
production-signed distribution artifact.

The current imported source baseline is not test-clean:

- `flutter analyze` completes with 35 info-level lint/deprecation findings and no compile errors;
  the command exits nonzero because infos are treated as fatal.
- `flutter test` reports 3,219 passed, 439 skipped, and 13 failed. The failures are in the
  Windows-incompatible POSIX timezone setup (`day_window_dst_test.dart`), ZIP temp-file handling
  (`import_container_test.dart`), the iOS ASK plist check, two movement/import date expectations,
  and repository policy checks in `substrate_admission_test.dart` and `ui2_tokens_test.dart`.

The Android release build is validated on Windows. Runtime behavior, Bluetooth pairing, and
release signing still require physical-device verification. The iOS build remains unexecuted
because it requires macOS/Xcode.

`.env` is ignored. Keep provider keys, signing material, device exports, BLE captures, databases,
health records, and other personal data out of Git. The checked-in analytics CSVs are upstream
test fixtures, not Akshat's personal health exports.

## Updating from OpenStrap

Fetch and review each named upstream independently. Protocol or analytics changes must be merged
into their existing package histories and reviewed together with the app behavior they affect.
Never copy a floating upstream worktree over a package, and never change an algorithm revision
without following `AGENTS.md`'s `kAlgoVersion` requirements.

## Accepted personal iPhone pipeline (planned, not implemented)

Private GitHub hosting and CLI authentication are configured, but no workflow has been activated
for the personal iPhone artifact. GitHub Actions usage is metered, and macOS runners consume
substantially more billed minutes than Linux runners; do not trigger the existing tag workflow as a
personal build until its exclusions, payload checks, and secret handling meet the accepted contract.

The accepted daily-use target is now Akshat's iPhone through a standard unsigned Flutter
**release/AOT** IPA, signed and installed directly from Windows with Sideloadly and the free Apple
Personal Team. This is a plan, not a completed pipeline: no personal-sideload flavor has been
implemented, no iOS IPA has been built in this repository, and the current tag workflow has not
been changed.

The personal artifact must preserve the root phone app, local database/analytics, local
notifications, `bluetooth-central`, CoreBluetooth restoration, and the commit-before-ACK/resumable
drain invariants. Its initial capability profile deliberately excludes the Watch companion, widget/
Live Activity extension, App Groups, and HealthKit. GPS and background processing/fetch remain
explicit test-gated options; required telemetry, health-data contribution, backend, and OTA
dependencies remain off. The full upstream source targets stay in the repository for reference and
possible future source-signed builds.

Creating a new IPA requires one of these deliberately chosen Mac paths:

1. a controlled compatible Mac/Xcode environment; or
2. the private-GitHub macOS workflow after it implements the personal-flavor exclusions,
   payload/entitlement inspection, and source/hash manifest.

Windows then caches the current and previous accepted unsigned IPAs outside Git and performs routine
re-sign/refresh without Flutter, CocoaPods, Xcode, or a source rebuild. The permanent bundle ID,
Windows cache path, encrypted-backup destination, Sideloadly/Local Anisette settings, monitoring,
and alert implementation are intentionally unset until activation and must be recorded here when
chosen. Never commit Apple/GitHub credentials, 2FA codes, signing material, Anisette data, personal
health exports, or IPAs.

See `guides/IOS_INSTALLATION.md` for the personal-versus-full build boundary and
`guides/IOS_SIDELOAD.md` for the accepted Windows install/refresh/recovery workflow. `CLAUDE.md`
owns the complete physical-device, encrypted-backup, expiry, upgrade, and activation gates.

## Documentation synchronization

Any material repository, toolchain, build-hosting, capability, signing, cache, backup, or activation
change must update this file, `CLAUDE.md`, the relevant iOS guide, `README.md`, workflow/configuration
notes, and current verification results in the same change. Keep accepted plan, implemented pipeline,
and executed validation distinct.

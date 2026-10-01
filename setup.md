# Local Repository Setup

## Current repository state

This folder is one Git repository on `main`. It preserves the OpenStrap histories and currently
contains:

- edge base `daf6011d3aa0312e22b991713b7af9e5c4433b32`
- protocol `471034cb84b85edb37e72b6f6add79a2d7929294` under `packages/protocol/`
- analytics `1fa8144a5e3b728ce91eeed6ecbc15d482933b44` under `packages/analytics/`

The official sources are named `upstream-edge`, `upstream-protocol`, and `upstream-analytics` and
remain fetch-only. The personal workflow remote is `origin` at the public GitHub repository
<https://github.com/akshatksingh18/whoop>; `main` tracks `origin/main` after the first push. The former
same-machine bare repository at `C:\Users\aksha\git-remotes\whoop.git` is preserved as the
`local-backup` remote. GitHub is the primary collaboration/recovery remote; `local-backup` is an
additional same-machine copy, not an off-device backup.

The public `main` history was rewritten as a precaution around suspected personal-health content.
The three questioned CSV/test objects were then verified byte-for-byte as the intentionally public,
anonymized OpenStrap analytics fixture introduced by upstream PR #21: timestamps are relative and
the fixture contains no absolute date, device identity, email, UUID, SpO2, temperature, or counter
fields. They are restored from pinned analytics revision
`1fa8144a5e3b728ce91eeed6ecbc15d482933b44`; no GitHub Support object purge is required for them.
The pre-rewrite history remains only in same-machine safety mirrors and must not be pushed wholesale.
Real Akshat exports, databases, BLE captures, credentials, and signing material remain prohibited
from commits, documentation, releases, and artifacts. The repository has no forks or releases;
legacy Actions runs and artifacts were removed after preserving and hashing the accepted IPA.

The app's `pubspec.yaml` uses tracked local paths for both packages, so a checkout of this one
repository is self-contained. Do not restore floating Git refs or create a
`pubspec_overrides.yaml` for the imported packages. `packages/upstream-revisions.yaml` records the
reviewed source revisions and must move with any deliberate package update.

## Local Windows toolchain and build validation

The local Android toolchain is installed and `flutter doctor -v` reports no issues:

- Flutter 3.41.6 at `D:\AI Important Files\personal-project\dev\flutter` with Dart 3.11.4
- Microsoft OpenJDK 17.0.20.1 at `D:\AI Important Files\personal-project\dev\jdk-17`
- Android SDK at `D:\AI Important Files\personal-project\dev\android-sdk`, including platform tools,
  Android 34–36 platforms, build tools 35.0.0 and 36.0.0, NDK 28.2.13676358, and CMake 3.22.1
- Visual Studio Build Tools 2026 and Chrome for the other Flutter desktop/web targets

The Android SDK licenses are accepted for Akshat's Windows user. `JAVA_HOME`, `ANDROID_HOME`,
`ANDROID_SDK_ROOT`, Flutter, Cargo, and Android command-line tool paths are persisted in that
user's environment. This toolchain moved into `personal-project/dev/` from a former standalone
`D:\dev\`; the three user env vars and the three `PATH` entries were updated to match at the same
time, and `android/local.properties`'s `sdk.dir`/`flutter.sdk` (machine-specific, not committed)
were repointed too. Verified afterward by running `java`, `adb` and `flutter --version` directly
from the new location. From this repository root, the repeatable validation commands are:

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
  the command exits nonzero because infos are treated as fatal. Still true after the `dev/` move
  below — confirmed clean of new errors.
- `flutter test` does not run from the space-containing SDK path. Flutter's own SDK now lives at
  `D:\AI Important Files\personal-project\dev\flutter`, and the `objective_c` native-assets build
  hook fails with `'D:\AI' is not recognized as an internal or external command`.
  - **Working local route:**
    1. `subst W: "<this repo>"` and `subst X: "<dev\flutter>"`.
    2. Delete `.dart_tool\hooks_runner` once, because a failed spaced-path attempt leaves a stale
       hook.
    3. Run `X:\bin\flutter.bat test` from `W:\`.
  - **Full suite on source `0.9.33`/`66`, run that way:** everything passes except 13 environment
    failures on this Windows machine:
    - 9 also fail on the unmodified previous commit: `day_window_dst` (its setUp and tearDown),
      `import_container` (3), `ios_ask_plist`, `movement_floor_policy`, `noop_backup_import` and
      `substrate_admission`.
    - 4 are `ui2_tokens_test` allow-list checks that compare forward-slash paths against Windows
      backslashes. They flag only `theme.dart`, `grammar.dart` and `home_screen.dart`, none of which
      changed.
  - GitHub Actions (`ubuntu-latest`) remains the full-suite gate; see `CLAUDE.md`'s "How to review
    this repo".

The Android release build is validated on Windows. The first personal iOS candidate exposed an
AccessorySetupKit discovery-descriptor validation abort; the bridge fix shipped in `0.9.30` build
`63`. `0.9.32` build `65` was installed after a clean same-identity reinstall, and `0.9.33` build
`66` is now installed over it with its device pass open. Before the old
container was removed, its encrypted export was restored successfully into an isolated test install;
the same backup was then restored into build 65, and Akshat confirmed the app works. Data and band
pairing survived an exact-final-ID overwrite, and a controlled forced-due Wi-Fi daemon refresh
advanced signing successfully. The direct iPhone-pedometer path was verified on build 63; exact
About/profile details, retained phone-step setting, GPS/background behavior, and the next naturally
elapsed refresh still need build-65 device verification.

`.env` is ignored. Keep provider keys, signing material, device exports, BLE captures, databases,
health records, and other personal data out of Git. The checked-in analytics CSVs are upstream
test fixtures, not Akshat's personal health exports. The real-night fixture is an anonymized public
OpenStrap regression asset restored byte-for-byte from the pinned analytics revision.

## Updating from OpenStrap

Fetch and review each named upstream independently. Protocol or analytics changes must be merged
into their existing package histories and reviewed together with the app behavior they affect.
Never copy a floating upstream worktree over a package, and never change an algorithm revision
without following `CLAUDE.md`'s `kAlgoVersion` requirements.

## Personal iPhone pipeline

The public GitHub repository and CLI authentication are configured. The manual
`.github/workflows/personal-ios.yml` workflow is the selected build host and refuses to allocate a
macOS runner if the repository is private. Standard GitHub-hosted runners for the public repository
do not consume the private-repository minute allowance. Never use the existing tag workflow as the
personal build.

The accepted daily-use target is now Akshat's iPhone through a standard unsigned Flutter
**release/AOT** IPA, signed and installed directly from Windows with Sideloadly and the free Apple
Personal Team. The deterministic personal flavor, contract tests, payload validator, manifest, and
manual workflow are implemented. Accepted `0.9.30` build `63` passed automated validation and is
cached at `D:\AI Important Files\personal-project\final-ipas\whoop\backup\WHOOP-0.9.30-build63-accepted`
(not in Downloads — see `D:\AI Important Files\personal-project\final-ipas\README.md`); it remains
the accepted rollback. The `0.9.31` build `64` artifact passed the
automated macOS build, payload, manifest, and downloaded-checksum gates but is superseded without
installation. Current `0.9.32` build `65` retains its personal GPS/Oura changes and adds the
confirmed-phone-stillness step guard. Its automated macOS build, payload, manifest, and downloaded
checksum gates pass. It is installed and its encrypted restore/app launch work, but it was never promoted: band,
steps, GPS/background, and same-ID refresh checks were still open when build 66 replaced it as the
one candidate in `testing\`.
The initially low step count came from leaving **This phone → Steps** off; enabling it verified the
direct iPhone-pedometer import. This profile deliberately excludes HealthKit and does not import the
Apple Health aggregate. Keep phone steps enabled for normal iPhone-carried use; WHOOP 4 band-only
historical data is too low-rate for honest all-day step reconstruction. The current tag workflow
remains unchanged.

Personal implementation scope is iPhone only. Do not schedule Android fixes, builds, or device
validation. Keep the imported Android target unchanged as upstream/reference source: it is absent
from the IPA, so deleting it would not simplify signing, installation, runtime, or iPhone testing.

The accepted shared portfolio is standalone WHOOP plus the native AkshatOS hub (two free-signing
slots). See `../akshatos/hub-plan.md`. WHOOP retains its independent
Flutter process, identity, and Bluetooth lifecycle; it is not embedded in the hub. No paid tier,
rotation, WHOOP source move, capability expansion, or activation is implied. The native hub is
owned by `../akshatos/`; consult its build guide for implementation and device evidence.

The personal artifact must preserve the root phone app, local database/analytics, local
notifications, `bluetooth-central`, CoreBluetooth restoration, and the commit-before-ACK/resumable
drain invariants. Installed build 63 excludes the Watch companion, widget/Live Activity extension,
App Groups, HealthKit, GPS, and background processing/fetch. Current build-65 source reopens GPS with
While-In-Use authorization and the location background mode while retaining all other exclusions;
its route behavior and new step guard still need the phone pass. Required telemetry,
health-data contribution, backend, and OTA dependencies
remain off. The full upstream source targets stay for reference and possible source-signed builds.

Creating a new IPA uses the manual public-GitHub macOS workflow. It pins Flutter 3.41.6, derives a
minimal phone-only Runner in its ephemeral checkout, builds with
`flutter build ios --release --no-codesign --dart-define-from-file=.env`, validates the
conventional IPA payload, and uploads the IPA, capability/source manifest, and SHA-256 as an
artifact for 14 days. It injects no companion/backend URL, Firebase configuration, or signing
material.

The accepted rollback is version `0.9.30` build `63`, originally produced by the now-retired
personal-sideload workflow run recorded in its local manifest; its
sanitized-history source equivalent is `7132d2ab29a007da9e650ef802e7340a0cf39677`. Its SHA-256 is
`ff8eb3565ddc97c85163d92b7e1bbafee4ab1e385083b6b99a21f168ef07a5e1`, and the downloaded IPA,
manifest, and checksum are cached at
`../final-ipas/whoop/backup/WHOOP-0.9.30-build63-accepted` — the stable release cache outside
Downloads, excluded from the OneDrive backup archive the same way every `personal-project/`
subfolder is; `../final-ipas/README.md` owns the backup/testing model. The macOS workflow, local
validator, and downloaded checksum all pass. Superseded `0.9.31` build `64` was produced by workflow
run `35376151690` from source `75689dbfd17ccf999231a0bb3d0a92645c62f817`; its SHA-256 is
`d6434cef15ca6860368afb0b1d3a454f0258a8fc80ade6db8ea35e687c1d362f`. It was not installed or
device-verified, must not be promoted, and is no longer cached. Current `0.9.32` build `65` was produced by
workflow run `35382626928` from source `f25fcbd6b9461b70f964738221bd8ea3b8bee22b`;
its SHA-256 is `d936d8819aa2290430ec17ff930135a76787896153564509a327f0a76d07feda`.
Automated validation passed, it is installed, and encrypted restore plus launch are verified. It
was not fully device-accepted and is no longer cached; re-run that workflow to reproduce it.
`testing\` holds exactly one candidate at a time, as `../final-ipas/README.md` requires.
Candidate `0.9.33` build `66` was produced by workflow run `36805031736` from source
`648c1b2e215418e64757b8e711a1b617e0798502` (Linux test run `36804984992` passed); its SHA-256 is
`174bc6001b4efe52de9f39436dd510b6235ad8519eaefcb8e885b71b9af9c31d`. The IPA, manifest, and checksum
are cached at `../final-ipas/whoop/testing/WHOOP-0.9.33-build66-648c1b2e`; the downloaded hash and
payload validation pass. It is not installed yet and supersedes build 65 as the next install.
The accepted-build ledger prevents reuse of `0.9.30+63`.

**Verified Sideloadly identity rule:** build 65 and an isolated temporary-bundle copy both install
and overwrite successfully, including after encrypted history restore and band pairing. The 0% stall
was isolated to Sideloadly v0.60's **Use automatic bundle ID** transformation. For WHOOP refresh or
upgrade, turn that option off and enter the exact installed final ID
`com.akshat.personal.whoop.5564K8D4SV`; keep the separate automatic-refresh control enabled. That
production overwrite reached 100%, advanced the signing time, and preserved data and pairing. Do not
substitute the base ID `com.akshat.personal.whoop` in this path. A controlled forced-due test then
refreshed WHOOP through the real daemon over Wi-Fi with USB disconnected and no GUI/manual refresh
command; the timestamp advanced, expiry reset, the health task recorded `REFRESHED`/`ENROLLED`, and
the subsequent real-app launch confirmed its data and band connection intact. Keep the encrypted
backup and build-63 rollback; the next naturally elapsed cycle remains open.

**A known Sideloadly failure mode, found here first:** its own internal cache of a previously
installed app's IPA can go missing independent of this file — the first wireless refresh attempt
after wireless detection started working found Sideloadly's own cached copy of this build gone, and
it failed with `Install failed: Guru Meditation … __init__() missing 1 required positional argument:
'orig'` instead of a clean error. Fix: reinstall from the file above (USB, to isolate the variable),
which repopulates Sideloadly's cache with a real file. The IPA is installed; enabling **This phone → Steps** verified its
direct iPhone-pedometer import after the initially low band fallback. The personal profile does not
read Apple Health. History/data restore, signed bundle identity, pairing preservation, exact-ID
manual refresh, and a controlled forced-due Wi-Fi daemon cycle are verified. Exact About/profile UI,
retained phone-step behavior, GPS/background behavior, and the next naturally elapsed cycle remain.

The first private-repository build crossed the account's included Actions-minute threshold; the
account notice reports reset on October 1, 2026. The repository was audited and changed to public
before future builds. Do not run this macOS workflow if the repository becomes private again.

Windows caches accepted and candidate unsigned IPAs outside Git and routine re-sign/refresh does not
need Flutter, CocoaPods, Xcode, or a source rebuild. The permanent base bundle ID is
`com.akshat.personal.whoop`; Sideloadly's current signed identity is
`com.akshat.personal.whoop.5564K8D4SV`. The accepted rollback and installed candidate paths are
recorded above. Local Anisette and the sign-in daemon are configured, and
`../akshatos/scripts/check-signing-health.ps1` monitors the exact signed identity and requires a
completed scheduled registration for the current version plus WHOOP's proven `exact` identity mode.
That monitor is deliberately critical
when WHOOP nears expiry without its timestamp advancing. Build 65 is enrolled, exact-final-ID manual
refresh works, and a controlled forced-due daemon cycle reused that identity successfully over Wi-Fi.
The next naturally elapsed cycle remains the long-term proof.
Never commit Apple/GitHub
credentials, 2FA codes, signing material, Anisette data, personal health exports, or IPAs.
The personal build selects the supplied black-and-white circular logo from
`ios/Runner/Assets.xcassets/AppIconPersonal.appiconset`; upstream/reference builds continue using
their existing icon catalog.

Windows is partly ready already: iTunes 12.13.10.3 and Apple Mobile Device Support 19.4.0.10 are
installed, the Apple Mobile Device Service is automatic/running, and the Sideloadly daemon runs
from `C:\Users\aksha\AppData\Local\Sideloadly`. Apple Bonjour 2.0.2 is also installed as an
automatic running service; its signed installer added the UDP 5353 firewall rules, and a local
`_apple-mobdev2._tcp` browse detects the iPhone over Wi-Fi. The installed Sideloadly version and
Local Anisette configuration are not yet verified, and Bonjour discovery alone is not proof of an
actual wireless refresh.

See `guides/IOS_INSTALLATION.md` for the personal-versus-full build boundary and
`guides/IOS_SIDELOAD.md` for the accepted Windows install/refresh/recovery workflow. `CLAUDE.md`
owns the complete physical-device, encrypted-backup, expiry, upgrade, and activation gates.

## Documentation synchronization

Any material repository, toolchain, build-hosting, capability, signing, cache, backup, or activation
change must update this file, `CLAUDE.md`, the relevant iOS guide, `README.md`, workflow/configuration
notes, and current verification results in the same change. Keep accepted plan, implemented pipeline,
and executed validation distinct.

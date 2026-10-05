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

Build-72 local validation passes. The 19 new food/UI flow regressions pass, including
full selected chart text at 320/375/390/430 pt and 1×/1.5×/2× text, optional macros, editing/Undo,
direct Scan/manual fallback, monthly history, automatic weekly rereads, save/date races,
historical saved meals and retryable failures. Representative dark renders were inspected and
generated screenshots removed. The full suite passes 3,274 tests with 368 intentional skips
(unavailable captures/goldens and platform-specific tests). Static analysis succeeds with
`--no-fatal-infos`: 58 info-level findings, no errors or warnings. All 7 personal-iOS contract
tests and `tool/personal_ios.py check` pass. All 9 Today-refresh regressions pass with the
personal build flag, including the native phone-sync write/reload path, absent/zero steps,
stale calculated totals, detail/chart agreement and capture/workout holds.
The initial build-71 Linux CI `37170843509` passed: 3,270 tests, 363 intentional skips and analysis
with no errors/warnings. Build-72 Linux CI `37173914511` passes: 3,279 tests, 363 intentional skips,
analysis with 58 infos and no errors/warnings.

The former 13 Windows failures are repaired in this source: path/newline checks and local-day
fixtures are portable. ZIP validation closes its input on every failure, and movement-floor age
counts calendar dates across DST (algorithm 88). Tests which require changing a POSIX timezone
remain explicitly skipped on Windows; GitHub Linux CI exercises those cases.

Flutter's native-assets hook still needs paths without spaces on Windows:
1. `subst W: "<this repo>"` and `subst X: "<dev\flutter>"`.
2. Delete `.dart_tool\hooks_runner` once if a failed spaced-path attempt left a stale hook.
3. Run `X:\bin\flutter.bat test --concurrency=1` from `W:\`, then remove both mappings.
`flutter analyze --no-fatal-infos` is the CI convention for the imported info-level lint baseline.
GitHub Actions (`ubuntu-latest`) remains the release test gate. Do not leave `test/goldens` after
screenshot checks; its presence enables local golden groups that are not committed.

The Android release build is validated on Windows. The first personal iOS candidate exposed an
AccessorySetupKit discovery-descriptor validation abort; the bridge fix shipped in `0.9.30` build
`63`. Build 70 is installed over build 69 and Akshat reports its phone check passed. Build 67
was the accepted recovery/refresh build until build 70's promotion.
`0.9.32` build `65` was installed after a clean same-identity reinstall, followed by later upgrades. Before the old
container was removed, its encrypted export was restored successfully into an isolated test install;
the same backup was then restored into build 65, and Akshat confirmed the app works. Data and band
pairing survived an exact-final-ID overwrite, and a controlled forced-due Wi-Fi daemon refresh
advanced signing successfully. The direct iPhone-pedometer path was verified on build 63; exact
About/profile details, retained phone-step setting, GPS/background behavior, and the next naturally
elapsed refresh remain broader device/refresh gates; the build-70 feature phone check passed.

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
manual workflow are implemented. The accepted build is `0.9.37` build `70`, cached at
`D:\AI Important Files\personal-project\final-ipas\whoop\backup\WHOOP-0.9.37-build70-accepted`
(not in Downloads — see `D:\AI Important Files\personal-project\final-ipas\README.md`). Build 63
was the first accepted build and is superseded. The `0.9.31` build `64` artifact passed the
automated macOS build, payload, manifest, and downloaded-checksum gates but is superseded without
installation. Superseded `0.9.32` build `65` retains its personal GPS/Oura changes and adds the
confirmed-phone-stillness step guard. Its automated macOS build, payload, manifest, and downloaded
checksum gates pass. It was installed and its encrypted restore/app launch work, but it was never promoted: band,
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

Build-73 source is `0.9.40`/`73`, algorithm 89, with excluded Widget/Watch metadata aligned.
It adds the approved `audio` background mode for actual workout speech; all other personal
exclusions and While-In-Use location authorization remain. Local validation passes; source
`a49d7837c4d2da368a708a1aeb77983fb19e8c1c` is published with Akshat's approval to the public
repository. Linux CI `37252915519` and personal macOS build `37252925924` pass. The downloaded
IPA passes checksum, manifest and payload validation and is the single testing candidate.
Build 72 remains the last confirmed phone installation; accepted build 70 remains the recovery
IPA. Build-73 installation, phone acceptance and current-version enrollment are pending.
`todo.md` owns acceptance gates; artifact evidence appears below.

Build-73 checks: all 3,318 Flutter tests pass with 368 intentional skips, plus 91 focused tests
with `PERSONAL_SIDELOAD=true`. Analysis reports 60 infos and no errors/warnings. All 7 Python
personal-iOS contract tests, `personal_ios.py check`, local dependency/pin guards and `git diff
--check` pass. Representative layouts were inspected; daily details also pass at 320 points and
1.5x text. Windows cannot verify native iOS compilation or locked-screen/background behavior.
The full suite runs serially through temporary `W:`/`X:` paths; generated screenshots are removed.

The personal artifact must preserve the root phone app, local database/analytics, local
notifications, `bluetooth-central`, CoreBluetooth restoration, and the commit-before-ACK/resumable
drain invariants. The build-72 source preserves the personal profile: it excludes the Watch companion, widget/Live
Activity extension, App Groups, HealthKit, and background processing/fetch. GPS was reopened in
build 65 with While-In-Use authorization and the location background mode; the feature phone
check passed, while the broader route/background and restoration matrix remains open. Required telemetry,
health-data contribution, backend, and OTA dependencies
remain off. The full upstream source targets stay for reference and possible source-signed builds.

Creating a new IPA uses the manual public-GitHub macOS workflow. It pins Flutter 3.41.6, derives a
minimal phone-only Runner in its ephemeral checkout, builds with
`flutter build ios --release --no-codesign --dart-define-from-file=.env`, validates the
conventional IPA payload, and uploads the IPA, capability/source manifest, and SHA-256 as an
artifact for 14 days. It injects no companion/backend URL, Firebase configuration, or signing
material.

The former accepted build is version `0.9.30` build `63` (superseded by build 67), originally produced by the now-retired
personal-sideload workflow run recorded in its local manifest; its
sanitized-history source equivalent is `7132d2ab29a007da9e650ef802e7340a0cf39677`. Its SHA-256 is
`ff8eb3565ddc97c85163d92b7e1bbafee4ab1e385083b6b99a21f168ef07a5e1`, and the downloaded IPA,
manifest, and checksum were cached in `../final-ipas/whoop/backup/` until build 67 replaced them
— the stable release cache outside
Downloads, excluded from the OneDrive backup archive the same way every `personal-project/`
subfolder is; `../final-ipas/README.md` owns the backup/testing model. The macOS workflow, local
validator, and downloaded checksum all pass. Superseded `0.9.31` build `64` was produced by workflow
run `35376151690` from source `75689dbfd17ccf999231a0bb3d0a92645c62f817`; its SHA-256 is
`d6434cef15ca6860368afb0b1d3a454f0258a8fc80ade6db8ea35e687c1d362f`. It was not installed or
device-verified, must not be promoted, and is no longer cached. Superseded `0.9.32` build `65` was produced by
workflow run `35382626928` from source `f25fcbd6b9461b70f964738221bd8ea3b8bee22b`;
its SHA-256 is `d936d8819aa2290430ec17ff930135a76787896153564509a327f0a76d07feda`.
Automated validation passed, it was installed, and encrypted restore plus launch are verified. It
was not fully device-accepted and is no longer cached; re-run that workflow to reproduce it.
`testing\` holds exactly one candidate at a time, as `../final-ipas/README.md` requires.
Candidate `0.9.33` build `66` was produced by workflow run `36805031736` from source
`648c1b2e215418e64757b8e711a1b617e0798502` (Linux test run `36804984992` passed); its SHA-256 is
`174bc6001b4efe52de9f39436dd510b6235ad8519eaefcb8e885b71b9af9c31d`. The IPA, manifest, and checksum
were cached at `../final-ipas/whoop/testing/WHOOP-0.9.33-build66-648c1b2e`; the downloaded hash and
payload validation pass. Akshat installed it over build 65; later candidates superseded it, and it
is no longer cached. The accepted-build ledger prevents reuse of `0.9.30+63`, `0.9.34+67` and
`0.9.37+70`.

Build `0.9.34`/`67` (commit `b7414f03e30bdde0974b0f664b9ec9608663abb5`): Linux test run
`36942710724` and personal iPhone workflow run `36943287892` passed. Artifact
`whoop-personal-b7414f03e30b-unsigned.ipa`, SHA-256
`bdb90ee8bf0bdfb363ff1d2c92bb7a8432807b4112c4fd45af5c102eccbdbcae`, matches its checksum file and passes
`tool/personal_ios.py validate`. It was the accepted recovery/refresh build in
`../final-ipas/whoop/backup/WHOOP-0.9.34-build67-accepted`, promoted after Akshat reported it working;
build 70 replaced it and it is no longer cached. Build 66 was never promoted and is
no longer cached. Akshat installed it over build 66 with Sideloadly 0.70.1. WHOOP installs can sit at "Installing 88%" (43 minutes when left alone). The cause is not established. What is observed on build 67: it happens in both automatic and exact bundle-ID mode, with the phone unlocked, and even when the app was swiped away beforehand; opening WHOOP and swiping it away released the stuck install at once, twice. `guides/IOS_SIDELOAD.md` owns the procedure. Sideloadly's record
showed 0.9.34 at `com.akshat.personal.whoop.5564K8D4SV` with a completed automatic-refresh
registration and no error; both exact and automatic mode completed. Its reported sync, GPS run
and layout pass supported promotion; broader lifecycle/refresh gates remain open.

Build `0.9.35`/`68` (commit `284fff83e750c8476f6eef20b13cc80b9407f8e2`): Linux test run
`37138583717` and personal iPhone workflow run `37138914477` passed. Artifact
`whoop-personal-284fff83e750-unsigned.ipa`, SHA-256
`873ba87dd4b56e90ed02b94fd956478e66236c7027ec5fa957c35967e227ae55`, matches its checksum
file and passes `tool/personal_ios.py validate`. It was cached in
`../final-ipas/whoop/testing/WHOOP-0.9.35-build68-284fff83`. Akshat installed it over build 67;
its run screen worked on his first run. It is no longer cached: build 69 replaced it in the
testing slot.

Build `0.9.36`/`69` (commit `5747dd35be2c`): Linux test run `37147798691` and personal iPhone
workflow run `37147823754` passed. Artifact `whoop-personal-5747dd35be2c-unsigned.ipa`
(17.6 MB), SHA-256
`0acf34d2cafabb58e2673994f9ed81cfaab4bb89f7de3cbc778f36a7b85f8ffa`, matches its checksum
file and passes `tool/personal_ios.py validate`. It was cached in
`../final-ipas/whoop/testing/WHOOP-0.9.36-build69-5747dd35` until build 70 replaced it; Akshat's
screenshots show it installed.

Build `0.9.37`/`70` (commit `d8fc8eea6944`): Linux test run `37156185209` and personal iPhone
workflow run `37156191673` passed. Artifact `whoop-personal-d8fc8eea6944-unsigned.ipa`
(17.7 MB), SHA-256
`0008a6aa96f29251fd88f06bf573d8a8660499b0f1b9a23cdf7a2443b2017d17`, matches its checksum
file and passes `tool/personal_ios.py validate`. It is the accepted build in
`../final-ipas/whoop/backup/WHOOP-0.9.37-build70-accepted`. Akshat installed it over build 69,
confirmed the phone check passed and confirmed completed automatic-refresh registration for
version `0.9.37` at `com.akshat.personal.whoop.5564K8D4SV` with no install error. It is promoted;
it remains the accepted backup while build 73 occupies `testing\`. The checksum, manifest and
local payload validator pass at the promoted path;
all 7 `tool.test_personal_ios` contract tests pass, and the accepted-build guard refuses build-70
reuse. Accepted feature verification does not close the broader lifecycle/refresh gates in
`CLAUDE.md`; build 72 now has a separately reported background-voice failure, audited in
`workout-sync-audit.md`.

Superseded build `0.9.38`/`71`: initial UI/food source `5c00c278aa836d12c0dfb54e25e728c67b276d07` was published with Akshat's approval;
Linux CI `37170843509` and macOS workflow `37171288516` passed. That artifact has not been
downloaded/installed and is held before release because it predates the newly reported Today-refresh
fix. It must not be installed and remains reproducible from that workflow.

Superseded build `0.9.39`/`72` combines all approved UI/food changes with the Today-refresh repair, with
algorithm 88 and unchanged schema/capabilities. Local full-suite validation passes (3,274 tests,
368 intentional skips), analysis has no errors/warnings, and all 7 personal-iOS contract tests pass.
Source `05c208c79fe61c35e8df587e7becfd59698cbf02` is published with Akshat's approval.
Linux CI `37173914511` passes (3,279 tests, 363 intentional skips). Personal macOS workflow
`37174063547` passes against that exact revision. Artifact
`whoop-personal-05c208c79fe6-unsigned.ipa` (17,747,901 bytes), SHA-256
`87e2f7a860f5b13130f68394b65952dec43b3db9d4bd28f77f88597517f7183d`, matches the downloaded
checksum and manifest. The manifest confirms version `0.9.39`, build `72`, the full source revision
above and unchanged minimal personal capabilities. `tool/personal_ios.py validate` passes.
The IPA, manifest and checksum were cached in
`../final-ipas/whoop/testing/WHOOP-0.9.39-build72-05c208c7`; that folder was removed after build 73
passed validation and replaced the testing slot. Build 72 remains reproducible from its workflow.
Akshat confirms this build is installed
on the phone used for his screenshots. Reported background voice and sync/calorie/macro/profile
issues are audited in `workout-sync-audit.md`; approved fixes are implemented in build 73.
Akshat confirms Today refresh now updates steps, while maintenance-calorie consistency remains
open. The audit reproduces a stale open breakdown and confirms main-card step recalculation in
an isolated real-repository probe; this is a partial check, not phone acceptance.
Build 70 remains accepted; build 72 was never phone-accepted. The current candidate's phone and
current-version automatic-refresh gates are carried into build 73's checklist.

Build `0.9.40`/`73` implements the approved combined repair, with algorithm 89 and unchanged schema.
Source `a49d7837c4d2da368a708a1aeb77983fb19e8c1c` is published with Akshat's approval.
Linux CI `37252915519` passes (3,323 tests, 363 intentional skips, analysis with 60 infos and no
errors/warnings). Personal macOS workflow `37252925924` passes against that exact source,
including the personal build contract, Dart gates, native compilation and packaged IPA validation.
Artifact `whoop-personal-a49d7837c4d2-unsigned.ipa` (17,848,647 bytes), SHA-256
`b0f5998a00cb13ef105a49869557800186d4503ab2aa8758f9d333c2885f5c3f`, matches the downloaded
checksum and manifest. The manifest confirms version `0.9.40`, build `73` and the full source
revision above. `tool/personal_ios.py validate` and ZIP CRC integrity checks pass at the final path.
The payload retains `bluetooth-central`, `location` and the approved real-workout `audio` mode;
Watch/widgets/Live Activities, HealthKit, App Groups, background fetch/processing and required
Firebase initialization remain excluded. The IPA, manifest and checksum occupy the single folder
`../final-ipas/whoop/testing/WHOOP-0.9.40-build73-a49d7837`.
Installation, phone acceptance and completed current-version automatic-refresh registration for
`0.9.40` at `com.akshat.personal.whoop.5564K8D4SV` are pending. The build-70 recovery IPA and
accepted-build ledger remain unchanged; promote build 73 only after the `todo.md` gates pass.

**Verified Sideloadly identity rule:** build 65 and an isolated temporary-bundle copy both install
and overwrite successfully, including after encrypted history restore and band pairing. The 0% stall
was first attributed to Sideloadly v0.60's **Use automatic bundle ID** transformation; build 67
stalled in both modes, so the mode is not the cause (see `guides/IOS_SIDELOAD.md`). Both modes give
the same final ID and both have completed. The older exact-ID procedure was: turn that option off and enter the exact installed final ID
`com.akshat.personal.whoop.5564K8D4SV`; keep the separate automatic-refresh control enabled. That
production overwrite reached 100%, advanced the signing time, and preserved data and pairing. Do not
substitute the base ID `com.akshat.personal.whoop` in this path. A controlled forced-due test then
refreshed WHOOP through the real daemon over Wi-Fi with USB disconnected and no GUI/manual refresh
command; the timestamp advanced, expiry reset, the health task recorded `REFRESHED`/`ENROLLED`, and
the subsequent real-app launch confirmed its data and band connection intact. Keep the encrypted
backup and accepted build-70 recovery IPA; the next naturally elapsed cycle remains open.

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
`com.akshat.personal.whoop.5564K8D4SV`. The accepted recovery path and superseded build records are
recorded above. Local Anisette and the sign-in daemon are configured, and
`../akshatos/scripts/check-signing-health.ps1` monitors the exact signed identity and requires a
completed scheduled registration for the current version and the same signed identity; WHOOP
accepts `either` bundle-ID mode, as configured in `scripts/signing-apps.json`.
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
Local Anisette configuration should be rechecked after tool changes; build 67 was installed with
Sideloadly 0.70.1. Bonjour discovery alone is not proof of an actual wireless refresh.

See `guides/IOS_INSTALLATION.md` for the personal-versus-full build boundary and
`guides/IOS_SIDELOAD.md` for the accepted Windows install/refresh/recovery workflow. `CLAUDE.md`
owns the complete physical-device, encrypted-backup, expiry, upgrade, and activation gates.

## Documentation synchronization

Any material repository, toolchain, build-hosting, capability, signing, cache, backup, or activation
change must update this file, `CLAUDE.md`, the relevant iOS guide, `README.md`, workflow/configuration
notes, and current verification results in the same change. Keep accepted plan, implemented pipeline,
and executed validation distinct.

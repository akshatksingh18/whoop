# WHOOP BLE Companion

One local Git monorepo, based on OpenStrap, for pairing with a WHOOP 4.0 sensor over Bluetooth
LE, decoding the raw protocol, and computing recovery/strain/sleep metrics locally — no WHOOP
subscription and no app backend.

- The Flutter `edge` app lives at the repository root.
- `packages/protocol/` contains the BLE codecs at the exact revision the imported app used.
- `packages/analytics/` contains the local metric engine at the exact revision the imported app
  used.

The monorepo preserves all three upstream histories. Its personal `origin` is the public
<https://github.com/akshatksingh18/whoop> repository on Akshat's main account. The former local bare
repository remains available as the `local-backup` remote; the three official OpenStrap sources
remain fetch-only named upstreams.

**Status:** Active Android-to-iPhone migration — the deterministic personal IPA from commit
`325a3da7abac893326d45d3f7d3cc2367d60b22c` was built, verified, signed by Sideloadly, and installed
on Akshat's iPhone and launches, but tapping **Find my band** terminates the app before the iOS
picker appears. The crash is confirmed in the report as an AccessorySetupKit discovery-descriptor
validation abort; history import state and exact installed identity/profile still need confirmation,
the bridge fix/replacement IPA remain, and Android development is out of scope.

## Files
- `setup.md` — current public-GitHub/local-backup/upstream remotes, imported revisions, Windows
  validation, installed personal-iPhone candidate, and remaining migration/device decisions.
- `bugs.md` — retained Android reconnection evidence plus the active iPhone CoreBluetooth
  restoration/reconnection verification risk.
- `README.md` — preserved upstream product reference with a personal-fork status banner and clear
  distinctions between upstream distribution/features and the installed but unverified profile.
- `guides/IOS_INSTALLATION.md` — selected minimal personal versus full source-signed iOS build
  profiles, capability boundaries, and build acceptance requirements.
- `guides/IOS_SIDELOAD.md` — accepted Windows Sideloadly installation, refresh monitoring, backup,
  expiry recovery, two-app portfolio, and fallback-signer workflow; not yet executed.
- `.github/workflows/personal-ios.yml` and `tool/personal_ios.py` — manual public-repository macOS
  build plus deterministic personal-profile transformation, payload validation, manifest, and
  checksum.
- `.claude/skills/ponytail/SKILL.md` — upstream implementation discipline; read it before changing
  application or package behavior.
- `pubspec.yaml` and `pubspec.lock` — Flutter dependencies; protocol and analytics resolve through
  tracked paths inside this monorepo.
- `lib/`, `test/`, `android/`, `ios/`, and `assets/` — the imported OpenStrap edge application.
- `packages/protocol/` — imported OpenStrap protocol source, tests, license, and original history.
- `packages/analytics/` — imported OpenStrap analytics source, tests, fixtures, license, and
  original history.
- `packages/upstream-revisions.yaml` — reviewed protocol and analytics source revisions used by
  the algorithm-version guard test.
- `LICENSE` and `NOTICE.md` — OpenStrap edge licensing and attribution; package licenses remain in
  their respective package folders.

## Repo layout
- `lib/ble/` — Bluetooth + sync
- `lib/data/` — local storage + the repository seam the UI reads from
- `lib/compute/` — runs the analytics pipeline, writes results
- `lib/state/` — AppState, the one source of truth
- `lib/ui2/` — every current screen
- `packages/protocol/lib/` — protocol framing and record decoders
- `packages/analytics/lib/` — recovery, strain, sleep, and related formulas

## Environment
- Dev machine: Windows laptop, no local Mac
- Intended primary daily-use device: iPhone via the minimal Sideloadly-sideloaded release IPA; its
  first candidate is installed and launches, but its first pairing attempt crashes at **Find my
  band**; history migration, installed identity, pairing, sync, background behavior, refresh, and
  recovery are not verified yet
- Personal platform scope: iPhone only. Preserve the imported Android source as upstream/reference
  code, but do not spend implementation or validation effort on Android unless Akshat reopens it.

## Personal iPhone deployment plan

This is the durable free-compatible plan for making the iPhone the primary WHOOP device. The
accepted portfolio is standalone WHOOP plus one native hub containing Squats, PageVault, and
ReelVault: two free-signing slots. `../akshatos/hub-plan.md` owns that packaging. WHOOP remains an
independent Flutter app/process, not embedded in the hub; no paid tier, rotation, or identity
migration is required by this decision. Seven-day profiles and the refresh/recovery rules remain.
Akshat has activated iPhone implementation. The personal flavor exists in source, its first
macOS-built candidate passed automated payload/hash verification, and Sideloadly installed it on
the iPhone. Launch is verified, but the first **Find my band** tap terminates the app before a picker
appears. The crash report confirms malformed AccessorySetupKit descriptor validation; daily-use
activation is blocked on fixing that bridge and producing a replacement IPA, and still requires
history import confirmation, exact identity/profile inspection, pairing, sync, recovery, and the other
physical-device evidence below.

### Chosen delivery model and non-negotiable constraints

- Ship WHOOP as a normal, standalone Flutter **release/AOT** iPhone app in a standard unsigned
  `.ipa`, then let Sideloadly sign and install it directly from the Windows laptop with Akshat's
  free Apple Personal Team. Do not use a Flutter debug build for daily use: debug builds require
  Flutter/Xcode to relaunch from the home screen.
- WHOOP uses one slot and the native Squats/PageVault/ReelVault hub uses a second; the third is
  unallocated. Sideloadly has no phone-side host. AltStore/SideStore would use a further slot and
  require an explicit workflow choice; neither is needed. Preserve WHOOP's independent lifecycle,
  minimal personal flavor, encrypted exports, and stable identity rather than embedding it in the hub.
- Do not put the daily app inside LiveContainer and do not add StikDebug, LocalDevVPN, JIT,
  injected tweaks, or a Sideloadly-specific runtime dependency. Those add failure surfaces and
  cannot be trusted to preserve WHOOP's entitlements or CoreBluetooth background restoration.
- Free Personal Team profiles expire after seven days. The installation therefore still depends
  on Apple's signing service, even with Local Anisette; no stock-iPhone build change removes that
  Apple dependency. The reliability goal is early refresh, independent verification, and a tested
  recovery path rather than pretending the profile is permanent.
- Sideloadly is a replaceable installer, not part of the app architecture. Apple can change
  authentication, pairing, or provisioning behavior and temporarily break it. Keep the artifact
  standards-compliant and portable so a maintained replacement signer can install the same IPA.

### Current authoritative references

- Re-check Apple's account documentation before deployment. It currently allows up to ten App IDs
  and three devices, both expiring after seven days, plus three installed apps per device and
  seven-day provisioning profiles:
  <https://developer.apple.com/help/account/basics/about-your-developer-account/>.
- Re-check Sideloadly's official FAQ and changelog before activation and after an iOS, Apple-login,
  or Apple-device-component change. They document current iOS support, background refresh,
  same-bundle overwrite behavior, Wi-Fi/USB caveats, retries, and recent authentication fixes:
  <https://sideloadly.io/faq.html> and <https://sideloadly.io/changelog>.
- Preserve WHOOP's CoreBluetooth design against Apple's documented background/restoration model;
  background wake opportunities are bounded and state restoration must rebuild the real central
  manager rather than assuming continuous execution:
  <https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html>
  and <https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options>.
- Flutter's release-mode AOT behavior, rather than debug/JIT behavior, is the basis for a standalone
  home-screen app:
  <https://docs.flutter.dev/resources/faq>.

### Personal-sideload build contract

The dedicated personal-sideload build/configuration is implemented by `PERSONAL_SIDELOAD`,
`tool/personal_ios.py`, and `.github/workflows/personal-ios.yml`. The script transforms
only the ephemeral build checkout, with drift guards, instead of mutating the general source target
ad hoc or relying on Sideloadly to repair an over-entitled bundle.
The personal artifact must have these properties:

- Keep the root iPhone `Runner` and all local BLE, SQLite, analytics, UI, local-notification,
  import/export, and Files-sharing functionality. Build it with the Flutter version deliberately
  pinned in `.github/workflows/build.yml` (currently 3.41.6), using a release equivalent of
  `flutter build ios --release --no-codesign --dart-define-from-file=.env`.
- Keep `UIBackgroundModes` value `bluetooth-central`, the Bluetooth usage strings, the generated
  AccessorySetupKit service/name declarations, and the `BleRestoreManager` bridge. Preserve the
  stable `openstrap.ble.restore` restoration identifier, the saved band UUID, the deferred
  first-pairing central creation, and the existing handoff to the normal Flutter drain path.
  CoreBluetooth wakes are bounded opportunities, not a promise of continuous execution; every
  drain must retain the commit-before-ACK and resumable-cursor invariants documented below.
- The initial personal profile removes location usage keys/native routes and suppresses route
  tracking. A later GPS experiment requires an explicit decision plus permission, battery,
  background, and stop-semantics evidence; never add location merely to keep the process alive.
- The initial personal profile removes `processing`/`fetch` modes, BG task identifiers,
  native registration, and Dart scheduling. They remain optional future experiments, never
  correctness requirements.
- Default the personal flavor to local-only operation: no health-data contribution, no required
  companion/backend URL, no automatic OTA dependency, and no automatic Firebase Analytics,
  Performance, or Crashlytics collection. In particular, do not carry the current release
  workflow's `ENABLE_HEALTH_DATA_CONTRIBUTION=true` into the personal artifact. BYOK/other network
  features may remain manual opt-ins only if the app works fully with networking disabled and no
  secret is baked into the IPA.
- Strip the Watch companion from the IPA, as the current tag workflow already does. Keep its
  source target for a possible future fully source-signed build, but do not package it for free
  re-signing: its companion bundle-ID cross-reference is not safely rewritten by generic
  sideloaders.
- Strip the widget extension and disable the home-screen widget and Live Activity in the personal
  flavor. Remove the Runner App Group entitlement, the widget App Group entitlement from the
  packaged extension, `NSSupportsLiveActivities`, and app-group bridge calls together. A partially
  working extension is not acceptable for a health app; the current generic workflow's "might not
  work" caveat is replaced by a deterministic phone-only artifact.
- Remove HealthKit entitlements and hide/compile out Apple Health reads and writes in the initial
  personal flavor. Preserve manual profile entry and all band-derived metrics. HealthKit may be
  reintroduced only as a separate, later capability experiment after the exact free Personal Team
  profile produced by Sideloadly is inspected and install, permission, read, write, refresh, and
  upgrade behavior all pass. Never ship `com.apple.developer.healthkit` when the installed profile
  does not grant it.
- Use a minimal Runner entitlement set that exactly matches the profile after the exclusions
  above. Bluetooth background mode and local notifications belong in configuration/permissions;
  do not invent entitlements for them.
- Package a conventional `Payload/Runner.app` IPA with no signing credentials, provisioning
  profile, personal health data, database, BLE capture, API key, injected dylib, or installer
  metadata. Inspect the payload before release and fail packaging if `Watch/`, the widget
  `PlugIns/*.appex`, unexpected entitlements, or personal secrets remain.

### Bundle identity, upgrades, and data continuity

- The personal app's iPhone display/bundle name is `WHOOP`. The permanent bundle identifier
  is `com.akshat.personal.whoop`; Sideloadly signing and installation succeeded, but the installed
  profile/bundle identity must still be inspected to prove that exact identifier was preserved.
  Use that exact identifier, the same Apple
  Account, and the same Sideloadly custom
  bundle-ID behavior for every refresh and upgrade. Never accept a new random identifier merely
  to make an installation succeed.
- The personal iPhone build uses the black-and-white circular mark in
  `ios/Runner/Assets.xcassets/AppIconPersonal.appiconset`; the general upstream target retains its
  existing `AppIcon` artwork.
- Keep the existing source version rules: every new binary gets the correct `pubspec.yaml`
  version/build number and passes the release guards. Code upgrades change the version, never the
  bundle identity. Do not uninstall the existing app for a normal refresh or upgrade; install over
  it with the same Apple Account and bundle ID so iOS retains the app container, pairing state,
  database, and preferences.
- Treat overwrite preservation as a tested behavior, not the only backup. Sideloadly's cached IPA
  and signing state are replaceable; health history is not. An accidental uninstall, changed
  bundle ID, device restore, or failed signing migration can still orphan the container.
- Add a personal-build Settings status that reads the installed provisioning profile when
  feasible and shows its expiration date, last successful band sync, backup state, build version,
  and source revision. Local alerts at 72, 48, and 24 hours before profile expiry are useful but
  supplement, not replace, Windows-side verification.

### Building and caching the IPA

- macOS/Xcode is required only when source changes require a **new** unsigned IPA. Re-signing the
  already-built IPA every few days happens entirely from Windows and must not rerun Flutter,
  Xcode, CocoaPods, or the analytics pipeline.
- The chosen build host is the public GitHub repository's manual macOS workflow,
  `.github/workflows/personal-ios.yml`. It uses Flutter 3.41.6, injects no backend/Firebase
  secrets, applies the personal transform, validates the IPA, and uploads a 14-day artifact
  with a source/capability manifest and SHA-256. The existing tag workflow remains the
  upstream-capable release path and must not supply this personal artifact. GitHub/macOS is a build
  dependency only when code changes, not a runtime or routine refresh dependency.
- Cache the current signed-input IPA on Windows in a stable, non-temporary directory outside Git.
  Keep the current and immediately previous known-good artifacts, each with filename/version,
  SHA-256, source commit, Flutter version, build date, and the feature/capability manifest. Record
  the final cache path in `setup.md` when activated. Do not rely solely on Sideloadly's internal
  cache or a GitHub Actions artifact-retention window.
- A new IPA is promoted only after payload inspection, hash recording, a fresh-device install,
  and an in-place upgrade test. The previous known-good IPA remains available until the new build
  passes the soak and refresh gates.

### Windows signing and refresh automation

- Install Sideloadly only from its official distribution, enable **Local Anisette**, enable Apple
  device Developer Mode/trust, use iTunes to enable **Sync with this iPhone over Wi-Fi**, enroll
  WHOOP for automatic refresh, and run the Sideloadly daemon at Windows sign-in. Sideloadly currently
  warns that wireless discovery can occasionally require iTunes to be open or the iPhone screen to
  be on, and some Windows pairing errors require the web/non-Microsoft-Store Apple components.
  Re-check these transient setup details after tool updates. Local Anisette removes reliance on
  Sideloadly's remote Anisette server but does not remove communication with Apple's signing servers.
- Never place the Apple Account password, a 2FA code, signing material, or an app-specific password
  in this repository, a PowerShell script, task arguments, or plaintext logs. Use the installer's
  supported credential storage and Windows protections. Preserve signing continuity with the same
  account unless a deliberately tested migration is necessary.
- Do not schedule one attempt exactly every seven days. Run a local health check daily (48 hours
  is the maximum acceptable gap) that confirms the daemon is running, the iPhone has recently been
  seen over trusted Wi-Fi or USB, and a successful refresh is recorded. Start the refresh window
  with at least three full days remaining so Apple downtime, a sleeping laptop, travel, or a Wi-Fi
  pairing failure has several retry opportunities.
- Sideloadly describes the daemon as acting when apps are "near expiry" but does not document a
  user-configurable threshold. If the three-day health check has not observed a new expiry, use the
  supported **Refresh All Apps Manually**/normal same-IPA install path. Do not make an unsupported
  GUI script the only recovery mechanism or let it report success without device-install evidence.
- Use proof of success from the installed provisioning expiration and/or Sideloadly's explicit
  success record. A daemon process, opened GUI, cached-file timestamp, or scheduled-task exit code
  alone is not proof that the phone received a new profile. Keep a compact current-state log with
  last success, new expiry, device, bundle ID, and IPA hash; do not store credentials or health
  data in it.
- Raise a persistent local Windows notification when no verified success exists by the
  three-days-remaining threshold, escalate at two days, and require the USB recovery path inside
  the final 24 hours. Test alerts by forcing each threshold; silent monitoring is not monitoring.
  If Sideloadly exposes no supported command interface for a forced early refresh, keep its daemon
  as the refresh mechanism and let the scheduled task verify/alert—do not build brittle blind GUI
  automation that reports success without evidence.
- Keep the trusted USB cable as the deterministic fallback when Wi-Fi discovery fails. After every
  installer or Apple-device-component update, verify one USB refresh and one Wi-Fi refresh before
  relying on unattended operation again.
- Refreshing the unchanged IPA must not change app code or local data. New source builds are a
  separate upgrade workflow and always require the in-place data-preservation test below.

### Backups and recovery

- Before first use, before every new-IPA upgrade, before any bundle/signing migration, and at least
  weekly during daily use, create the app's existing passphrase-encrypted full database export and
  copy it off the iPhone to a local Windows backup location. Record the passphrase safely outside
  the repository; there is intentionally no recovery if it is forgotten.
- Restore-test an encrypted export before making the iPhone authoritative, and repeat after a
  backup-format or schema change. A successfully written file is not a proven backup until the
  current app can decrypt, import, and reconcile it without overwriting measured days incorrectly.
- Do not describe `lib/data/auto_backup.dart` as encrypted: its current foreground-triggered
  `.db.gz` snapshots are plaintext, default off, and retained in the Files-visible Documents
  directory. They may be an additional short-term local safety net, but they do not satisfy the
  encrypted off-device backup requirement. Automating encrypted backups requires a deliberately
  implemented, performant platform-backed encryption/export path and its own restore test.
- Never uninstall WHOOP merely because its profile expired. First preserve an encrypted export if
  the app still opens, then re-sign/install the cached IPA over the existing bundle. If it no
  longer opens, leave it installed and perform the same-ID recovery install; uninstall only after
  a verified backup and an explicit decision that container preservation has failed.

### Physical-device validation matrix

The simulator and a successful build are insufficient for a BLE health app. Run this matrix on
the actual primary iPhone and WHOOP 4.0 band against a release build, with the official WHOOP app
fully quit so it does not own the peripheral:

1. **Artifact/install:** verify the payload exclusions, first Sideloadly install, Developer Mode
   and trust flow, cold launch from the home screen, offline launch, permission prompts, hidden
   HealthKit/widget/Watch surfaces, and exact installed bundle identity/profile expiry.
2. **First pairing:** verify the iOS AccessorySetupKit picker, Bluetooth permission denial and
   recovery, profile entry without HealthKit, full initial drain, correct local computation, and a
   successful encrypted export.
3. **Normal connection:** test foreground sync, screen lock, app backgrounding, Bluetooth
   off/on, airplane mode, Low Power Mode, charging/non-charging, repeated reconnects, and multiple
   drains without duplicate ACK/data or notification re-fire.
4. **Range and restoration:** take the band out of range, wait for disconnect recovery to arm,
   return in range while the app is backgrounded/locked, and prove CoreBluetooth restoration wakes
   the normal resumable drain. Repeat after ordinary system termination if reproducible. Record
   manual swipe-to-force-quit separately: iOS may suppress background relaunch until the user opens
   the app again, which must be documented rather than misdiagnosed as a crash.
5. **Lifecycle:** test app termination and relaunch, iPhone reboot, band reboot, phone storage
   pressure, an overnight background interval, daylight-saving/time-zone changes, and the next
   supported iOS update. After an iOS update, redo pairing/reconnect/restoration and refresh checks
   before declaring compatibility.
6. **Soak:** run at least 72 continuous hours including normal phone use, multiple out-of-range
   events, overnight collection, daily derivation, notifications, and local diagnostics. There
   must be no crash loop, wedged reconnect latch, permanent stale state, UI-isolate stall, data
   loss, or fabricated metric. The active reconnection issue in `bugs.md` must be reproduced and
   resolved or conclusively shown not to affect this iOS path before promotion.
7. **Refresh:** refresh the unchanged cached IPA over Wi-Fi and USB with at least three days left;
   verify the new profile expiry, launch, band pairing, database row counts/key samples, settings,
   and latest sync are preserved. Then exercise all alert thresholds and one failed-network retry.
8. **Expiry recovery:** before live history becomes authoritative, deliberately let a controlled
   profile expire, confirm the expected launch failure, re-sign the same IPA with the same account
   and bundle ID without uninstalling, and verify full data/pairing recovery.
9. **Upgrade:** install a newer versioned IPA over the old one; verify schema migration,
   provisioning, pairing, raw ledger, derived history, encrypted export/restore, background BLE,
   and rollback/recovery using the previous artifact and backup. Never use a downgrade that would
   violate schema or version invariants merely to prove the installer works.
10. **Installer disruption:** simulate the daemon stopped, Windows rebooted, phone unseen on
    Wi-Fi, USB-only recovery, and Sideloadly temporarily unavailable. Confirm alerts arrive early
    and the standard IPA remains usable by the chosen backup signer without changing its bundle
    identity. Activating AltStore/SideStore requires a documented workflow/slot check and verified
    encrypted backup/restore; the selected two-app model does not require removing either app.

### Activation phases and acceptance gates

1. **Scope locked:** target Akshat's iPhone only. Preserve the imported baseline, public origin,
   upstream histories, algorithm/version invariants, Android source as reference, and `bugs.md`
   evidence; Android fixes, builds, and device validation are not part of the personal roadmap.
2. **Lock decisions:** bundle ID `com.akshat.personal.whoop`, no initial GPS, and the
   public-GitHub macOS build source are locked. Before installation, record the Apple Account/team
   continuity choice, Windows artifact-cache path, encrypted-backup destination, and exact alert
   behavior without credentials or personal data. The installed set is standalone WHOOP plus the
   native three-feature hub under free signing.
3. **Build the personal flavor:** the core entitlement/extension/location/network exclusions,
   packaging checks, and tests are implemented. A local installed-profile expiry/status surface
   remains desirable but does not block producing the first controlled candidate.
4. **Produce and inspect one candidate:** build, cache, hash, Sideloadly signing, and installation
   are complete. Import the Android encrypted backup before pairing, then pass exact installed
   identity/profile, pairing, offline, backup, and core BLE tests. Home-screen presence alone is not
   an acceptance gate.
5. **Pilot daily use:** pass the full lifecycle/restoration matrix and 72-hour soak, then pass an
   unchanged-IPA refresh and new-IPA upgrade with data preservation. Android is not an acceptance
   dependency or active fallback for this pilot.
6. **Prove the signing loop:** pass at least two consecutive unattended refresh cycles, alert
   escalation, USB recovery, and the controlled expired-profile recovery. Do not make the iPhone
   authoritative before the encrypted restore test also passes.
7. **Activate daily use:** only after all gates pass may the project status move from active iPhone
   implementation planning to an active iPhone pilot or daily-use status. Keep periodic backups,
   early refresh verification, and regression checks after Sideloadly, Apple-device-component,
   Flutter/Xcode, or iOS changes.

### Documentation and workflow synchronization

`setup.md`, `README.md`, `bugs.md`, and both iOS guides distinguish the personal plan,
the current upstream-capable source, iPhone-only scope, implemented build profile, and unexecuted
verification. The first macOS build, Windows download, Sideloadly signing, and installation are
complete; history migration and the remaining device gates remain.

As implementation proceeds, update all affected sources in the same coherent change:

- Record the artifact/cache/backup paths, exact source/hash manifest, Sideloadly settings,
  monitoring/alerts, and current physical validation in `setup.md` and the guides as they become
  real.
- Keep `.github/workflows/personal-ios.yml` manual, public-repository-only, minimal, and distinct from the
  existing tag release workflow; update the transform and contract tests whenever the Xcode project
  moves.
- Make `ios/Runner/Info.plist`, entitlements, signing configs, Xcode targets, and feature flags enforce
  the chosen capability profile together; remove omitted feature UI/bridges rather than shipping
  misleading controls. Keep generated AccessorySetupKit entries generated and update guard tests.
- Update `CLAUDE.md`, `README.md`, `bugs.md`, setup/guides, workflow/configuration notes, and relevant
  tests whenever a gate becomes implemented or verified. Promote new caveats into their owning
  source of truth and remove superseded planned wording in the same change.

## Working agreement
- Keep this as one repository. Route byte/protocol work to `packages/protocol/`, metric work to
  `packages/analytics/`, and app/flow/storage/UI work to the root app areas.
- Preserve the algorithm-version rules below: any analytics output change must still be
  reviewed with the matching `kAlgoVersion` decision even though no external package pin changes.
- Treat upstream updates as deliberate reviewed imports; never replace a local package with a
  floating branch dependency.
- Personal product work is iPhone-only. Do not delete the imported Android target merely to narrow
  scope: it is not packaged into the IPA, and retaining it avoids an unrelated destructive diff and
  preserves upstream merge/reference value. Do not build, debug, or extend it unless Akshat reopens
  Android scope.
- Any material platform, capability, entitlement, BLE/background, storage, build/signing, status,
  or deployment decision must update this file and every affected current-state supporting
  document—especially `setup.md`, `README.md`, `bugs.md`, the iOS guides, workflow/configuration
  notes, and recovery instructions—in the same change. Preserve the boundary between accepted
  personal-iPhone plan, current upstream-capable source, implemented personal flavor, and verified
  physical-device behavior.
- **Whenever a new project-owned file or top-level source area is added**, add a bullet under
  `## Files` in the same edit. Files inside an already-indexed imported source area do not need
  individual bullets.

## Engineering architecture, invariants, and review guidance

Reviewer context. This doc drifts from code between edits — check
`kAlgoVersion` (`lib/compute/derivation_engine.dart`), `schemaVersion`
(`lib/data/db.dart`), and the `version:` line in `pubspec.yaml` directly
rather than trusting a number written here. Where a source comment disagrees
with an implementation, **the implementation wins** — header comments here go
stale (e.g. `lib/compute/substrate.dart`'s file header still describes a
wake-to-wake day model that `calendarDays()` no longer implements; it walks
local midnight to local midnight). The same drift applies to §2's table and
every line-number citation in §3 below — line numbers move on every edit,
symbol names don't; verify against the source, not this doc.

### Project and source-area boundaries

A Flutter app for a reverse-engineered WHOOP 4.0 band. **Fully on-device,
local-first**: BLE offload → SQLite → on-device analytics → UI. No backend owns
user data. Network use is limited to OTA update pointers, opt-in
telemetry/Crashlytics, and BYOK LLM calls.

One monorepo, strict source-area separation — put work in the right tree:
- `packages/protocol` — bytes: GATT, framing, CRC, opcodes, record decode.
- `packages/analytics` — metrics: HRV, sleep staging, readiness, strain.
- the root app (`lib/`, platform folders, and app config) — flows, BLE link
  management, storage, UI.

New opcode/record → protocol. New metric → analytics. New screen/flow/table →
the root app. A change implementing a metric inside `lib/compute` is in the
wrong source area unless it is pure orchestration.

### Architecture map (`lib/`, well over 200 files — these five are the biggest by far)

Line counts drift constantly; don't trust a number here, `wc -l` the file.

| file | owns |
|---|---|
| `data/db.dart` | `LocalDb`: schema ladder (`onUpgrade`), all CRUD, coach views |
| `compute/derivation_engine.dart` | `DerivationEngine`, `kAlgoVersion`, day scheduling, isolate offload |
| `state/app_state.dart` | `AppState` ChangeNotifier — BLE↔DB↔UI orchestration |
| `ble/ble_engine.dart` | GATT connect/drain/history-sync state machine |
| `data/local_repository_impl.dart` | read seam: `day_result`/`metric_series` → screen shapes; zero compute on read |

- `ble/` — engine + `ble_state.dart` **pure policies**: `ReconnectPolicy`,
  `SeqAllocator`, `DrainStopEvaluator`, `RecordGate`, `CounterRegressionDetector`,
  `AckRetryPolicy`, `ChunkFailureLedger`, `DeriveDebouncer`, `AlarmPayloads`,
  `AlarmConfirmation`.
- `sync/` — `sync_policy.dart` **pure policies**: `ClockRef`/`ClockPolicy`,
  `BackfillPolicy`, `MarginalRadioDetector`, `FrameCorruptionDetector`,
  `PostBondTimeoutLoopDetector`, `BondRefusalGiveUp`, `EmptySyncTracker`,
  `StuckStrapDetector`; plus background/headless entries and OTA.
- `compute/` — `substrate.dart` (**single** raw→`Substrate` decode point +
  `calendarDays()` day model), `onehz_pipeline.dart` (pure, isolate-safe per-day
  pipeline), `crossday_pipeline.dart`, `derivation_engine.dart`.
- `data/` — `db.dart`, read seam, `day_label.dart` (the *only* day-label helper).
- `notify/` — `notification_center.dart` is the **single emitter**;
  `fired_keys.dart` is the persistent fire-once guard.
- `coach/` — read-only SQL over allow-listed `v_*` views behind a deny-list guard.
- `ui2/` — 66 files (`lib/ui` was deleted in the UI rebuild): `ui2/theme.dart`
  and `ui2/grammar.dart` (design system), `ui2/charts.dart`, `ui2/screens/`
  (shared metric/trend IA), plus `ui2/onboarding/`, `ui2/activity/`,
  `ui2/profile/`.
- Also `ai/` (BYOK), `gps/`, `health/` (HealthKit/Health Connect export),
  `telemetry/` (opt-in), `widget/` (App-Group snapshot for WidgetKit/watch).

**Storage.** Durable ledger: `decoded_onehz` (1 Hz, `UNIQUE(rec_ts)`,
INSERT-OR-REPLACE) + `decoded_rr` (beats, cascades on eviction) + `raw_archive`
(never pruned; undecodable/unknown-version records) + `raw_records` (retained as
replay/debug ledger and upgrade fallback) + `events`/`band_events`. Derived
output: versioned **immutable** `day_result` (PK `day_id, algo_version`) and
`metric_series` (PK `date,key`, REPLACE).

**Bug-density hotspots** (fix-titled commit churn, last 300 commits):
`state/app_state.dart` 30 · `data/db.dart` 25 · `compute/derivation_engine.dart`
24 · `data/local_repository_impl.dart` 17 · `ble/ble_engine.dart` 12 ·
`main.dart`+`app.dart` 19. Treat diffs in these with extra scrutiny.
`pubspec.yaml` has high raw churn but most of it is release version bumps — not
a hotspot.

### Hard invariants — violating these is a P0 regression

1. **Commit before ACK.** In the history-sync drain (`ble/ble_engine.dart`)
   decoded rows + cursor commit in one transaction *before*
   `buildHistoryResultOk` echoes the verbatim 8-byte HISTORY_END token. The band
   trims flash on ACK. Reordering, or echoing a regenerated/mangled token, causes
   permanent data loss or an infinite re-flood. Never ACK a partial chunk.
2. **`decoded_onehz` stays INSERT-OR-REPLACE keyed on `rec_ts`.** INSERT-OR-IGNORE
   breaks counter-reset recovery. Evicting a row must delete that counter's
   `decoded_rr` beats in the same batch.
3. **Never fabricate a metric.** Absent input ⇒ null / `Metric.absent` / "—". No
   imputation, no substituted defaults, no deriving one metric from another as a
   fallback. Most-violated rule in the repo (§4.1).
4. **Bump `kAlgoVersion`** (`compute/derivation_engine.dart`) whenever any
   analytics *output* changes, including a change under `packages/analytics`.
   Rows are immutable per version; without a bump nothing recomputes. Add a
   changelog entry above the constant.
5. **A bump citing a package change must include that source change.** Verify the
   monorepo commit actually contains it. v43's changelog described an analytics
   fix its dependency pin never contained; the bug stayed live three releases
   and only shipped at v46.
6. **In-tree packages are reviewed commits, never floating dependencies.**
   `ref: main` on analytics shipped main-thread ANRs into 0.9.13/0.9.14. Keep
   the tracked `packages/` sources, `packages/upstream-revisions.yaml`, and path
   dependencies in the same history.
7. **Day labels are LOCAL.** Always `todayLabel()` / `dayLabelOf()` from
   `data/day_label.dart`; never `DateTime.now().toUtc()...substring(0,10)`. Epoch
   timestamps (rec_ts, session bounds, prune cutoffs) are absolute — do not
   "fix" those to local. Day-length arithmetic must not assume 86400 s (DST).
8. **One source per concern.** One raw decode point (`substrate.dart`), one sleep
   segmentation, one readiness, one frame-ingest path (`RecordGate`), one
   notification emitter (`NotificationCenter.emit`). A second path is the bug.
9. **Never prune raw/decoded for a day that is not fully derived.** `day_result`
   has a `partial` column because days with good headline scalars but a failed
   second-half compute were finalized and pruned — unrecoverable. `raw_archive`
   is never pruned.
10. **Heavy compute never on the UI isolate.** Staging/derivation goes through
    `Isolate.run`; analytics ambient globals do not cross the boundary and must
    be re-armed inside the closure.
11. **Migrations additive and idempotent.** `onUpgrade` is a sequential
    `if (oldV < N)` ladder; `onOpen`'s `_repairOpenSchema` re-runs creators so
    same-version merged builds self-heal. Migrations run inside `openDatabase`
    under iOS's CPU watchdog — keep them cheap. `PRAGMA journal_mode=WAL` must go
    through `rawQuery` (it returns a row; `execute` bricks iOS Darwin sqflite).
12. **Headless/background sync serializes through `HeadlessSyncGate.tryRun`** —
    skip, don't queue.
13. **The coach reads only allow-listed `v_*` views** — never `decoded_*`,
    `raw_*`, or base tables.
14. **Live high-rate streams (0x28/0x2B/0x33) are never persisted** — RAM-only.
15. **Dangerous opcodes are never auto-sent** (`dangerousCmds`, gated in
    `ble/ble_engine.dart` wherever a write checks it): force-trim, reboot,
    power-cycle, firmware load.

### Recurring bug patterns — what actually ships broken here

#### 4.1 Fabricated / non-abstaining metrics ("honesty" violations)
The project has an explicit never-impute rule and keeps breaking it. Instances:
two copies of a `100 - readiness` stress fallback; RHR falling back to daytime HR
("Readiness 100" ten minutes after first wear); literal `"null"` rendered for
oxygen dips; a skin-temp section gated on `spo2` presence; `StageBars` drawing an
*invisible gap* for an absent sleep stage; pace showing absurd numbers instead of
"—"; a false empty state instead of a retryable error; Bluetooth-off reported as
"no strap found". One is still open: stress shows a confident score on ~20 min of
data.
**Ask on any metric diff:** what does this return when the input is missing or
thin? Anything other than null/"—"/an honest low-confidence envelope is a bug.

#### 4.2 Readiness / recompute-idempotence — the largest single cluster
Eight distinct fixes and four sequential attempts at one user-visible symptom.
Readiness recomputes on *every* BLE drain against a moving 28-day baseline, so
any non-idempotent step corrupts it: duplicate-day appends into the baseline
(MAD == 0 ⇒ robust z abstains ⇒ blank ring), rebuilding on persist but not on
read, withholding a score while the overnight builds but not preventing a
ready→ready drift, flashing a stale value before today settles, and saturation
bouncing the ring to 100.
**Ask:** if this runs three more times today with slightly more data, does the
persisted scalar stay stable? Does it append where it should replace?
**Footgun:** `LocalDb.metricSeries(limit: n)` is `ORDER BY date ASC LIMIT n` =
the **oldest** n. For a trailing window use `trailingSeriesValues(key, n)`.

#### 4.3 Sticky boolean latches never reset on the failure path
Self-identified as recurring in the repo's own commit messages ("same shape as
the foregroundActive bug from a couple days ago"). A flag is set, an error path
returns early without clearing it, and sync wedges until force-close. Known
instances: `foregroundActive`, `markForegroundIntent`, `_offloadActive`,
`_drainingOffloadFrames` (no `try/finally`), a sticky standard-HR fallback that
silently zeroed step calibration, and trusting a stale `isConnected`.
**Ask:** every flag set in this diff — is it cleared in `finally`, on timeout, and
on the give-up branch?

#### 4.4 Heavy compute on the main/UI isolate → ANR, jank, stuck launch
Recurred one build apart: `cardioStager`'s per-30s Lomb–Scargle on the main
isolate (Android ANRs every ~30 s), then the *entire second half* of
`_derivePreparedDay` running on the UI isolate for the foreground pass that fires
on every sync. Also: app freezing during backfills, unbounded pre-`runApp` inits
stalling launch, a dark-mode rebuild storm starving background BLE.

#### 4.5 `context` / Provider used after `await` or after unmount
Repeated crash source: `Provider._inheritedElementOf` null in `dispose`,
`context.read` in `dispose`, bare `Navigator.pop()` after an `await`, missing
`mounted` guard on a post-navigation reload.

#### 4.6 Notification re-fire, dedupe race, and gating bypass
Call sites promised "at most once per day" with nothing enforcing it, so
derivation re-runs re-fired them across illness, anomaly, temperature, readiness,
HR-shift, recovery-ready, step-goal and auto-workout alerts. Then the stress
screen called `NotificationService.presentEvent` **directly**, bypassing both the
prefs gate and the new dedupe guard. Then a TOCTOU race let two overlapping
`emit()`s both pass `hasFired`.
**Flag:** any direct call into `NotificationService` that skips
`NotificationCenter.emit`, and any check-then-record without the lock.

#### 4.7 Capability wired into one call path but not all N
The most damaging instance: `FirmwareAwareR24Decoder` existed but was not wired
into all three decode paths (`ble_engine.dart`, `db.dart`, `substrate.dart`), so
a real user's 88-byte v12 records were 100% silently archived — total sync
outage. Also: HealthKit export gated on `day_result` and never session-triggered
(a workout finished offline never exported); auto-detected workouts never
reaching the `sessions` table, invisible to both AI Coach and Health export.
**Ask:** how many call sites exist for this concern, and does the diff cover all
of them?

#### 4.8 UTC-vs-local and day-boundary math
Fixed, then reintroduced *in the same file* (SRI's hypnogram grid used raw UTC
time-of-day right below the fix for that exact mistake), then again in the
`v_sessions` view (AI Coach mis-dated workouts). Also: day math assuming 86400 s
breaking on DST, a briefing greeting "morning" in the afternoon, sleep not
detected in non-UTC timezones, and an alarm armed in the phone's clock frame
instead of the strap's RTC frame so it never fired.

#### 4.9 Package revisions / lockfile / release metadata
Four separate passes. Committed path `dependency_overrides` broke a release;
`pubspec.lock` resolved a package via a stale local path; floating `ref: main`
rode analytics v42 into 0.9.13; a PR bumped `kAlgoVersion` while the lock still
pinned the pre-fix analytics commit, requiring a manual merge-order gate; and
`0.9.17+1` shipped versionCode 1 → `INSTALL_FAILED_VERSION_DOWNGRADE`, making
the release uninstallable.
This monorepo tracks protocol and analytics under `packages/` and resolves both
through paths in `pubspec.yaml`; the package trees and app therefore move in the
same Git history. Do not use `pubspec_overrides.yaml` or restore floating Git
refs for them. Keep `pubspec.lock` consistent with those paths. `version:` must
always keep its `+BUILD` suffix, and the iOS widget/watch
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` are bumped manually and drift.

#### 4.10 Duplicated / inconsistent values across screens
Today showed strain/sleep/stress twice; a week-load wheel duplicated the strain
figure; the steps figure disagreed across screens through three separate
unification attempts and is still being fixed; two different HRV baselines both
labeled "baseline" on one screen.

#### 4.11 Chart / hypnogram render regressions
`Hypnogram.plot` lost its `RepaintBoundary` in a refactor and stayed lost through
three rewrites before being restored. Also recap scrub-marker misalignment,
`GanttPainter` needing restoration, and `RangeError` from unpadded substrate
fields. Rendering regressions here surface as test failures rather than obvious
visual bugs — check whether removed wrapper widgets were load-bearing.

### How to review this repo

**CI does run on PRs.** `.github/workflows/test.yml` runs `flutter analyze` +
`flutter test` on every pull request and on push to `main`.
`.github/workflows/build.yml` (the APK/IPA release) is the one gated to
`push: tags: ['v*']` — it doesn't touch PRs. `test/` is large and not flat
(it has `adapters/`, `support/`, and other subdirectories alongside the
top-level test files). Several regression tests are named for the bug they pin
(`readiness_flash_test`, `readiness_freeze_test`, `readiness_saturation_test`,
`readiness_baseline_pollution_test`). A behavior change with no accompanying
test is a real finding — CI passing doesn't mean the right test exists.

`analysis_options.yaml` is stock `flutter_lints`: no custom rules, no excludes,
no strict language modes.

**Deprioritize:** formatting, import ordering, naming style, `const`
constructors, string-interpolation preference, missing dartdoc, "extract a
widget", and general Flutter/Dart idiom advice not tied to a behavior change.

**Prioritize:** the invariants in §3, the patterns in §4, absent-input handling on
every metric path, idempotence under repeated derivation, flag reset on failure
paths, transaction ordering and durability around BLE sync, isolate boundaries,
migration safety, and anything that could display a number the data does not
support.

# WHOOP BLE Companion

One local Git monorepo, based on OpenStrap, for pairing with a WHOOP 4.0 sensor over Bluetooth
LE, decoding the raw protocol, and computing recovery/strain/sleep metrics locally — no WHOOP
subscription and no app backend.

- The Flutter `edge` app lives at the repository root.
- `packages/protocol/` contains the BLE codecs at the exact revision the imported app used.
- `packages/analytics/` contains the local metric engine at the exact revision the imported app
  used.

The monorepo preserves all three upstream histories. Its personal `origin` is the private
<https://github.com/akshatksingh18/whoop> repository on Akshat's main account. The former local bare
repository remains available as the `local-backup` remote; the three official OpenStrap sources
remain fetch-only named upstreams.

**Status:** Paused/research — source and history are imported and the local Git repository is
ready, but no feature or bug-fix work is expected while paused.

## Files
- `setup.md` — current private-GitHub/local-backup/upstream remotes, imported revisions, Windows
  validation, accepted but unimplemented personal-iPhone pipeline, and deferred Mac build choice.
- `bugs.md` — the active reconnection bug: Android evidence/hypotheses plus the separate planned
  iPhone CoreBluetooth restoration/reconnection verification risk.
- `README.md` — preserved upstream product reference with a personal-fork status banner and clear
  distinctions between upstream distribution/features and the unbuilt minimal personal profile.
- `guides/IOS_INSTALLATION.md` — selected minimal personal versus full source-signed iOS build
  profiles, capability boundaries, and build acceptance requirements.
- `guides/IOS_SIDELOAD.md` — accepted Windows Sideloadly installation, refresh monitoring, backup,
  expiry recovery, three-slot, and fallback-signer workflow; not yet executed.
- `AGENTS.md` — upstream engineering, architecture, safety, testing, and review requirements,
  adjusted only where the one-repository layout replaces sibling repositories.
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
- Intended primary daily-use device: iPhone via the planned minimal Sideloadly-sideloaded release
  IPA; this artifact and pipeline are not implemented or verified yet
- Available fallback/test device: Android phone (Vivo iQOO, OriginOS/Funtouch skin)

## Personal iPhone deployment plan

This is the durable plan for making the iPhone the primary WHOOP device without a paid Apple
Developer Program membership. It records a future implementation path; it does not unpause the
project or authorize behavior changes by itself. Keep the current paused/research status until
Akshat explicitly activates the plan and the acceptance gates below pass.

### Chosen delivery model and non-negotiable constraints

- Ship WHOOP as a normal, standalone Flutter **release/AOT** iPhone app in a standard unsigned
  `.ipa`, then let Sideloadly sign and install it directly from the Windows laptop with Akshat's
  free Apple Personal Team. Do not use a Flutter debug build for daily use: debug builds require
  Flutter/Xcode to relaunch from the home screen.
- WHOOP owns one of the three free Personal Team app slots; the intended allocation is PageVault,
  Squat Reminder, and WHOOP. Sideloadly has no phone-side host app and therefore preserves all
  three slots. AltStore Classic and SideStore each consume a slot themselves and are fallback
  installers only if another personal app is temporarily removed.
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

Create a dedicated personal-sideload build/configuration when this plan is activated. Do not
mutate the general source build ad hoc or rely on Sideloadly to repair an over-entitled bundle.
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
  drain must retain the commit-before-ACK and resumable-cursor invariants from `AGENTS.md`.
- Treat `location` as an explicit optional capability for route recording during a live workout.
  Keep it only if Akshat wants that feature and physical testing proves that permission prompts,
  background behavior, battery use, and stop semantics remain honest. Never request always-on
  location merely to keep the process alive.
- Treat `processing` and `fetch` as best-effort optimizations. They may remain only after the
  personal build registers bundle-appropriate `BGTaskSchedulerPermittedIdentifiers` and tests
  prove they do not interfere with CoreBluetooth restoration. Correctness must never depend on a
  background task running on schedule.
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

- Before the first controlled install, choose and record one permanent personal bundle identifier
  (prefer a stable Akshat-owned form such as `com.akshat.personal.whoop` after verifying it can be
  provisioned). Use that exact identifier, the same Apple Account, and the same Sideloadly custom
  bundle-ID behavior for every refresh and upgrade. Never accept a new random identifier merely
  to make an installation succeed.
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
- The existing tag workflow already has a macOS job that builds an unsigned release IPA and strips
  the Watch app. The private GitHub remote now exists, but activation must still choose between a
  controlled Mac build and adapting that workflow to the personal-sideload contract above. Do not
  run or trust the current tag workflow for the personal artifact until its capability exclusions,
  payload inspection, and secret handling are implemented. GitHub/macOS is a build dependency when
  code changes, not a runtime dependency of the installed app.
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
    identity. Activating AltStore/SideStore requires a documented decision about which of the
    other three personal apps temporarily gives up its slot.

### Activation phases and acceptance gates

1. **Remain paused:** preserve the imported baseline, current local-only Git origin, upstream
   histories, algorithm/version invariants, and `bugs.md` evidence. This documentation change is
   the only authorized work until Akshat explicitly unpauses iPhone implementation.
2. **Lock decisions:** choose the permanent bundle ID, Apple Account, optional GPS route mode,
   macOS build source, Windows artifact-cache path, encrypted-backup destination, and exact alert
   behavior. Record decisions without committing credentials or personal data.
3. **Build the personal flavor:** implement the entitlement/extension/network exclusions, local
   signing-expiry status, packaging checks, and tests. All existing application/package behavior
   changes still follow `.claude/skills/ponytail/SKILL.md` and every `AGENTS.md` invariant.
4. **Produce and inspect one candidate:** build on controlled macOS/Xcode, cache it on Windows,
   record its hash/source, sign with the free Personal Team, and pass artifact, install, pairing,
   offline, backup, and core BLE tests. A successful install alone is not an acceptance gate.
5. **Pilot daily use:** pass the full lifecycle/restoration matrix and 72-hour soak, then pass an
   unchanged-IPA refresh and new-IPA upgrade with data preservation. Keep Android as the fallback
   during this phase.
6. **Prove the signing loop:** pass at least two consecutive unattended refresh cycles, alert
   escalation, USB recovery, and the controlled expired-profile recovery. Do not make the iPhone
   authoritative before the encrypted restore test also passes.
7. **Activate:** only after all gates pass may the project status move from paused/research to an
   active iPhone pilot or daily-use status. Keep periodic backups, early refresh verification, and
   regression checks after Sideloadly, Apple-device-component, Flutter/Xcode, or iOS changes.

### Documentation and workflow synchronization

`setup.md`, `README.md`, `bugs.md`, and both iOS guides now distinguish the accepted personal plan,
the current upstream-capable source, and unexecuted verification. The project remains paused; the
actual personal build flavor, signing configuration, and workflow have deliberately not been changed.

When implementation begins, update all affected sources in the same coherent change:

- Record the permanent bundle ID, chosen controlled-Mac or private-GitHub build path, artifact/cache/backup paths,
  exact build command, source/hash/capability manifest, Sideloadly settings, monitoring/alerts, and
  current physical validation in `setup.md` and the guides.
- Update `.github/workflows/build.yml` (or the selected controlled-Mac equivalent) with the explicit
  personal flavor, health contribution/telemetry off, Watch/widget exclusion, minimal entitlement/
  payload validation, pinned preflight guards, and artifact metadata. The tag workflow is dormant
  until it has been adapted and verified for the personal-sideload artifact.
- Make `ios/Runner/Info.plist`, entitlements, signing configs, Xcode targets, and feature flags enforce
  the chosen capability profile together; remove omitted feature UI/bridges rather than shipping
  misleading controls. Keep generated AccessorySetupKit entries generated and update guard tests.
- Update `CLAUDE.md`, `README.md`, `bugs.md`, setup/guides, workflow/configuration notes, and relevant
  tests whenever a gate becomes implemented or verified. Promote new caveats into their owning
  source of truth and remove superseded planned wording in the same change.

## Working agreement
- Keep this as one repository. Route byte/protocol work to `packages/protocol/`, metric work to
  `packages/analytics/`, and app/flow/storage/UI work to the root app areas.
- Preserve the algorithm-version rules in `AGENTS.md`: any analytics output change must still be
  reviewed with the matching `kAlgoVersion` decision even though no external package pin changes.
- Treat upstream updates as deliberate reviewed imports; never replace a local package with a
  floating branch dependency.
- Any material platform, capability, entitlement, BLE/background, storage, build/signing, status,
  or deployment decision must update this file and every affected current-state supporting
  document—especially `setup.md`, `README.md`, `bugs.md`, the iOS guides, workflow/configuration
  notes, and recovery instructions—in the same change. Preserve the boundary between accepted
  personal-iPhone plan, current upstream-capable source, implemented personal flavor, and verified
  physical-device behavior.
- **Whenever a new project-owned file or top-level source area is added**, add a bullet under
  `## Files` in the same edit. Files inside an already-indexed imported source area do not need
  individual bullets.

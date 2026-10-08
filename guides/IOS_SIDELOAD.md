# WHOOP personal iPhone sideload and refresh plan

**State:** Build `0.9.37`/`70` is the accepted recovery build. Build `0.9.39`/`72` was installed,
but was not phone-accepted and its testing artifact is superseded.
Source `0.9.40`/`73`, commit `a49d7837`, is published with Akshat's approval and passes local
checks, Linux CI/macOS build, downloaded checksum/manifest and payload validation. It is the
previous testing candidate, superseded by build 74. Akshat confirms build 73 is installed; the complete phone pass and
current-version enrollment are pending. Its future-time Strain cursor defect is repaired in local build-74 source;
`../workout-sync-audit.md` records the earlier repairs, `../build-74-audit.md` the newer findings
and implemented Budget/ACSM comparisons and workout Live Activity; `../todo.md` owns release
and phone gates. CI `37397127258` validates test-only repair `fa16be3c`; all app/packaging inputs match
compiled IPA source `ba5bb29f`. `setup.md` records the elapsed-window fixture correction.

Source `0.9.41`/`74`, commit `ba5bb29f`, is published with approval; Linux CI
`37397127258`, macOS build `37395690305` and downloaded version/source, checksum, ZIP and payload
checks pass. Build 74 is installed at the exact final ID with its extension kept. It still requires
extension behavior, overwrite/data continuity, phone behavior and refresh acceptance.
Akshat confirmed build 70's
feature phone check and completed automatic-refresh registration for version `0.9.37` at
`com.akshat.personal.whoop.5564K8D4SV`, with no install error. The accepted IPA is cached under
`D:\AI Important Files\personal-project\final-ipas\whoop\backup\WHOOP-0.9.37-build70-accepted`;
`testing\WHOOP-0.9.50-build83-cbaf93cd` holds the single candidate (not yet installed; build 82
is installed). `../setup.md` owns the
artifact, hash and workflow records.

The minimal profile excludes HealthKit and reads direct iPhone motion data when **This phone →
Steps** is enabled. Encrypted history restore, identity/data/pairing preservation and a controlled
forced-due Wi-Fi daemon refresh were verified on earlier builds. The broader lifecycle,
background/restoration, naturally elapsed refresh and expiry-recovery gates remain open in
`../CLAUDE.md`; Akshat reports build-72 voice cues delayed until foreground. The session/audio
repair is implemented in built source `0.9.40`/`73`, including background audio for spoken
workout cues. Automated build checks pass; locked/background, music/call/headphone behavior needs
the physical-device acceptance pass.

### Current install and refresh procedure

1. Use the accepted build above for routine recovery/refresh. Keep a current encrypted off-phone
   export; install upgrades over the existing app with the same Apple Account and signed identity.
2. WHOOP accepts either bundle-ID mode. In exact mode turn **Use automatic bundle ID** off and
   enter `com.akshat.personal.whoop.5564K8D4SV`; in automatic mode verify it resolves to that same
   final ID. Keep the separate automatic-refresh control enabled.
3. **If a manual install sits at "Installing 88%", open WHOOP on the phone and swipe it away in
   the app switcher.** This released a stuck build-67 install at once, twice. The cause is unknown:
   the stall happened in both modes and once after the app had already been swiped away; one
   untouched install completed after 43 minutes. Phone logs during a stall remain the diagnostic.
4. Require `ENROLLED` for the exact signed identity/current version, no install error, and an
   `IDENTITY` line in either permitted mode. An advanced signing timestamp plus real-app launch
   corroborates refresh; the controlled unattended refresh was observed from exact mode only.
5. New candidates go in the single `testing\` slot and promote only after their phone pass and
   completed current-version enrollment. `backup\` holds only the accepted build.

This is Akshat's selected no-paid-membership path: build a standard unsigned Flutter release/AOT IPA
on a compatible Mac environment when source changes, then sign/install and routinely refresh that
cached artifact from Windows with Sideloadly and a free Apple Personal Team.

## Personal artifact required

Before following installation steps, the candidate IPA must pass the personal-build contract in
`CLAUDE.md` and `IOS_INSTALLATION.md`:

- phone `Runner`, local BLE/database/analytics, local notifications, `bluetooth-central`, and
  CoreBluetooth restoration retained;
- Watch companion, general/home/breathing widgets and every app extension excluded; the
  workout Live Activity (builds 74–80) was dropped in build 81 because Sideloadly's free signing
  provisions only the app's App ID and iOS refused to launch the extension;
- App Group and HealthKit entitlements absent in the initial personal flavor;
- health-data contribution and required telemetry/backend/OTA behavior off;
- conventional `Payload/Runner.app` release/AOT artifact with no injected libraries, JIT,
  credentials, personal data, or installer metadata;
- permanent verified bundle ID plus source version/revision, capability manifest, and SHA-256
  recorded.

The full upstream/TestFlight build can contain more Apple capabilities; it is not the selected
free-sideload artifact.

## Portfolio and prerequisites

- Install standalone WHOOP plus the native AkshatOS hub: two slots under free
  signing, with the third unallocated. `../../akshatos/hub-plan.md` owns the accepted packaging;
  WHOOP stays independent, with active iPhone-only implementation but no daily-use activation until
  its own gates pass. Android is not part of the personal build or acceptance plan. No paid tier or
  rotation.
- Free profiles still expire after seven days; these refresh timings remain applicable. Another
  free account does not bypass the per-device cap, but the two-app model does not exceed it.
- Use direct Windows Sideloadly. AltStore/SideStore would install a phone-side host and require a
  separate workflow decision. They are not required, and neither app should be removed to add one.
- Use the same Apple Account/team and permanent WHOOP bundle ID for every install, refresh, and
  upgrade.
- Install Sideloadly only from <https://sideloadly.io>, configure **Local Anisette**, and use the
  current official Apple Windows components required by its FAQ.
- Have a trusted USB cable and the accepted IPA in the stable Windows cache. Keep the previous
  known-good IPA and a current encrypted database export available before first install/upgrade.

Current external constraints must be rechecked at activation:

- Apple Personal Team limits:
  <https://developer.apple.com/help/account/basics/about-your-developer-account/>
- Sideloadly setup, Wi-Fi, overwrite, refresh, and support caveats:
  <https://sideloadly.io/faq.html> and <https://sideloadly.io/changelog>

## First controlled installation

For migration from an existing Android installation, preserve this order:

1. Let Android finish a final band sync, then export a **passphrase-encrypted backup**. This is the
   same lossless database as the plaintext export; spreadsheets are readable summaries and cannot
   restore the full app history. Keep the Android data and passphrase until the iPhone restore is
   verified.
2. Transfer the `.osbk` file somewhere the iPhone Files picker can reach. On the iPhone welcome
   screen, choose **Bring my history first**, select the backup, enter its passphrase, and wait for
   the import to finish. The importer deliberately skips the source phone's non-portable primary
   BLE identity while merging the raw ledger, derived history, sessions, journal, and other data.
3. Only after the import succeeds, choose **Forget this band** in the Android app, fully close it,
   and turn Android Bluetooth off for the first iPhone pairing. If the band is listed in Android's
   system Bluetooth devices, forget it there too. Do not uninstall or erase Android until iPhone
   history and a fresh encrypted iPhone backup have both been verified.

1. On Windows, connect the iPhone over USB, trust the computer, enable iOS Developer Mode, and use
   iTunes to enable **Sync with this iPhone over Wi-Fi**. Keep Apple's Bonjour service installed,
   automatic, and running; Sideloadly's Windows Wi-Fi path depends on Apple mobile-device discovery.
2. Open Sideloadly, select the accepted personal IPA and iPhone, and choose Local Anisette. Turn
   **Use automatic bundle ID** off and enter exact final ID
   `com.akshat.personal.whoop.5564K8D4SV`; keep the separate automatic-refresh control enabled.
   Disable tweak/dylib injection and other identity changes.
3. Use the selected Apple Account and enroll the app for automatic refresh. Keep credentials/2FA
   out of Git, scripts, task arguments, and plaintext logs.
4. Complete the iOS developer trust flow if prompted, then launch from the Home Screen. Confirm the
   installed bundle identity/profile expiry; HealthKit/general widgets/Watch and app extensions
   stay absent.
5. Pair the WHOOP 4.0 with the official WHOOP app fully quit, complete an initial drain, verify local
   metrics/offline launch, and create/restore-test an encrypted export before making this install
   authoritative.

## Refresh automation and proof

- Start the Sideloadly daemon at Windows sign-in and keep trusted Wi-Fi sync enabled. WHOOP has a
  completed `one_off: 0` registration, exact-final-ID manual refresh evidence, and one controlled
  forced-due Wi-Fi daemon refresh. Keep observing the next naturally elapsed cycle before calling the
  long-term schedule proven. The computer must be available and the phone detected over Wi-Fi or USB.
- Check health daily or at worst every 48 hours. The check can be lightweight, but it must record
  actual WHOOP refresh success/new expiry. A running daemon, opened GUI, scheduled-task exit code,
  or cache timestamp is not device-install proof.
- Target verified refresh while at least three days remain. Sideloadly decides when an app is “near
  expiry”; if its daemon has not refreshed by the portfolio threshold, use **Refresh All Apps
  Manually** or the normal same-IPA install path.
- Raise a persistent Windows alert at the three-day threshold, escalate by two days, and require USB
  recovery inside the final day. Test every alert and one failed-network retry.
- On the phone (from `0.9.33`/`66`, built but not yet device-verified), **Settings → About → Status** shows the installed
  profile's expiry. The app also sets local alerts **48 h and 24 h** before it; tapping one opens
  Status. The alerts re-arm from the installed profile every time WHOOP opens, so a refresh moves
  them. They supplement the Windows health check and do not replace it.
- Wi-Fi discovery may occasionally need iTunes open, the iPhone screen on, current Apple Windows
  components, or re-pairing. If USB works but Wi-Fi does not, verify **Bonjour Service** is running
  and that UDP 5353 rules exist before changing broader firewall settings. A short
  `dns-sd -B _apple-mobdev2._tcp local.` browse can distinguish Apple discovery from a Sideloadly
  UI/daemon problem. USB is the deterministic recovery route.
- After Sideloadly, Apple-device-component, or iOS updates, prove one Wi-Fi and one USB refresh again
  before trusting unattended operation.

## Data-safe refresh, upgrade, and expiry recovery

- Refresh/reinstall over the existing app with the same Apple Account and bundle ID. Never uninstall
  for routine signing; uninstalling can delete the database, pairing state, and preferences.
- Before a new-IPA upgrade, bundle/signing migration, or recovery experiment, create and restore-test
  the app's passphrase-encrypted full database export off the phone.
- From `0.9.33`/`66` (built but not yet device-verified), **Your data → Automatic backup** writes encrypted, verified
  `.osbk` backups on its own once a backup passphrase is set. They sit in the app's `OpenStrap
  Backups` folder and are deleted with the app, so they do not replace the off-phone copy above.
  To make an off-phone copy, copy the newest one to Windows through Files or iTunes File Sharing.
- A same-IPA refresh must preserve pairing, settings, database row counts/key samples, and latest
  sync. A newer IPA additionally must pass schema migration and in-place upgrade gates.
- Sideloadly's proven WHOOP recovery path is an install over the existing app with automatic
  bundle-ID rewriting off and exact final ID `com.akshat.personal.whoop.5564K8D4SV`; it preserves
  data and pairing. Keep a verified encrypted backup anyway. Backup/delete/clean-install/restore is
  the fallback only if the exact-ID container-preserving path fails.
- Keep the accepted build (`backup\`) and at most one candidate (`testing\`) outside Git, with
  hashes, source revisions and capability manifests, so a compatible replacement signer can be used
  if Sideloadly temporarily breaks after an Apple change. Older builds are not kept; they are
  reproducible from their workflow runs.

## Capability and runtime caveats

- Background BLE is best-effort under iOS. Preserve CoreBluetooth state restoration and test locked,
  backgrounded, out-of-range/reconnect, ordinary system termination, reboot, and 72-hour soak
  behavior. Manual swipe-to-force-quit may suppress background relaunch until the app is opened.
- Apple Health, general widgets, App Groups, Watch and app extensions remain excluded. A
  Sideloadly install log shows one App ID ("Using app ID "WHOOP"") in both bundle-ID modes: free
  signing does not provision extensions, which is why the build 74–80 Live Activity never drew.
- Local Anisette avoids dependence on Sideloadly's remote Anisette service, but Apple signing servers
  remain required. Apple can change provisioning/authentication and Sideloadly can require an update.
  Reliability comes from early retries, visible alerts, USB recovery, backups, stable identity, and
  a portable IPA—not permanent installation.

## Fallback installers

A maintained compatible desktop signer or direct Xcode install may replace Sideloadly if it can use
the same Apple Account/team, bundle ID, and standard IPA without uninstalling. AltStore/SideStore are
temporary fallbacks only because their host consumes a slot. LiveContainer/JIT/StikDebug,
enterprise/leaked certificates, DNS revocation blocking, and exploit-specific persistence are not
the daily WHOOP plan.

## Acceptance

Do not call this workflow dependable until WHOOP passes its physical-device matrix, encrypted
restore, same-IPA Wi-Fi/USB refresh, new-IPA upgrade, controlled expiry recovery, two consecutive
unattended portfolio refresh cycles, alert escalation, and USB recovery gates in `CLAUDE.md`.

## Documentation synchronization

When bundle identity, artifact capabilities, Sideloadly behavior, monitoring, backup, recovery, or
verification changes, update this guide, `IOS_INSTALLATION.md`, `setup.md`, `README.md`, and
`CLAUDE.md` together. Keep plan, implementation, and observed device behavior separate.

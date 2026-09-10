# WHOOP personal iPhone sideload and refresh plan

**State:** The matching minimal build profile and private macOS workflow are implemented, but no
personal IPA or Windows refresh automation has been produced or verified yet. Do not substitute an
arbitrary upstream release IPA and claim it matches this capability profile.

This is Akshat's selected no-paid-membership path: build a standard unsigned Flutter release/AOT IPA
on a compatible Mac environment when source changes, then sign/install and routinely refresh that
cached artifact from Windows with Sideloadly and a free Apple Personal Team.

## Personal artifact required

Before following installation steps, the candidate IPA must pass the personal-build contract in
`CLAUDE.md` and `IOS_INSTALLATION.md`:

- phone `Runner`, local BLE/database/analytics, local notifications, `bluetooth-central`, and
  CoreBluetooth restoration retained;
- Watch companion and widget/Live Activity extension removed from the packaged IPA;
- App Group and HealthKit entitlements absent in the initial personal flavor;
- health-data contribution and required telemetry/backend/OTA behavior off;
- conventional `Payload/Runner.app` release/AOT artifact with no injected libraries, JIT,
  credentials, personal data, or installer metadata;
- permanent verified bundle ID plus source version/revision, capability manifest, and SHA-256
  recorded.

The full upstream/TestFlight build can contain more Apple capabilities; it is not the selected
free-sideload artifact.

## Portfolio and prerequisites

- Install standalone WHOOP plus the native Squats/PageVault/ReelVault hub: two slots under free
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

1. On Windows, connect the iPhone over USB, trust the computer, enable iOS Developer Mode, and use
   iTunes to enable **Sync with this iPhone over Wi-Fi**.
2. Open Sideloadly, select the accepted personal IPA and iPhone, choose Local Anisette, and enter the
   permanent custom bundle ID exactly as recorded. Disable tweak/dylib injection and identity
   randomization.
3. Use the selected Apple Account and enroll the app for automatic refresh. Keep credentials/2FA
   out of Git, scripts, task arguments, and plaintext logs.
4. Complete the iOS developer trust flow if prompted, then launch from the Home Screen. Confirm the
   installed bundle identity/profile expiry and that HealthKit/widget/Live Activity/Watch surfaces
   are absent.
5. Pair the WHOOP 4.0 with the official WHOOP app fully quit, complete an initial drain, verify local
   metrics/offline launch, and create/restore-test an encrypted export before making this install
   authoritative.

## Refresh automation and proof

- Start the Sideloadly daemon at Windows sign-in and keep automatic refresh plus trusted Wi-Fi sync
  enabled. The computer must be available and the phone detected over Wi-Fi or USB.
- Check health daily or at worst every 48 hours. The check can be lightweight, but it must record
  actual WHOOP refresh success/new expiry. A running daemon, opened GUI, scheduled-task exit code,
  or cache timestamp is not device-install proof.
- Target verified refresh while at least three days remain. Sideloadly decides when an app is “near
  expiry”; if its daemon has not refreshed by the portfolio threshold, use **Refresh All Apps
  Manually** or the normal same-IPA install path.
- Raise a persistent Windows alert at the three-day threshold, escalate by two days, and require USB
  recovery inside the final day. Test every alert and one failed-network retry.
- Wi-Fi discovery may occasionally need iTunes open, the iPhone screen on, current Apple Windows
  components, or re-pairing. USB is the deterministic recovery route.
- After Sideloadly, Apple-device-component, or iOS updates, prove one Wi-Fi and one USB refresh again
  before trusting unattended operation.

## Data-safe refresh, upgrade, and expiry recovery

- Refresh/reinstall over the existing app with the same Apple Account and bundle ID. Never uninstall
  for routine signing; uninstalling can delete the database, pairing state, and preferences.
- Before a new-IPA upgrade, bundle/signing migration, or recovery experiment, create and restore-test
  the app's passphrase-encrypted full database export off the phone.
- A same-IPA refresh must preserve pairing, settings, database row counts/key samples, and latest
  sync. A newer IPA additionally must pass schema migration and in-place upgrade gates.
- If the profile expires and the app will not launch, leave it installed and sign/install the cached
  same-ID IPA over it. Uninstall only after a verified backup and an explicit conclusion that
  container-preserving recovery failed.
- Keep current and previous known-good unsigned IPAs, hashes, source revisions, and capability
  manifests outside Git so a compatible replacement signer can be used if Sideloadly temporarily
  breaks after an Apple change.

## Capability and runtime caveats

- Background BLE is best-effort under iOS. Preserve CoreBluetooth state restoration and test locked,
  backgrounded, out-of-range/reconnect, ordinary system termination, reboot, and 72-hour soak
  behavior. Manual swipe-to-force-quit may suppress background relaunch until the app is opened.
- The initial personal flavor intentionally has no Apple Health, widget, Live Activity, or Watch
  companion. Do not describe those as “might work”; they are excluded until a separate capability
  experiment passes exact free-profile and upgrade tests.
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

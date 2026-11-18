# Signing, refresh and recovery

**Status:** Sideloadly is the accepted installer; current-version enrollment and physical
renewal/recovery gates remain open. This laptop has no verified signing setup. See `setup.md`.

Sign the standard unsigned release IPA using the established Apple account/team and exact
final bundle ID from the installed phone or private recovery record. Preserve the existing
keychain/container/pairing identity; never guess a suffix or uninstall for profile expiry.
No credentials, provisioning profile, health export or installer logs belong in Git.

Use the supported Sideloadly credential storage, Local Anisette and trusted Apple device
components, Developer Mode and USB/Wi-Fi pairing. Verify current official installer/Apple
guidance before changing setup. A daemon running or task exit code is not an installed refresh.
Observe the phone's actual version/identity/profile expiry and explicit successful renewal.
Begin recovery with at least three days remaining; escalate at two days and use USB inside
the final 24 hours. Test alert thresholds and failure retries. Keep the installer replaceable;
the app has no JIT, container host, VPN or installer-specific runtime dependency.

Before upgrades, identity/schema/format changes and regular daily use, copy a passphrase-
encrypted full export off the phone and prove restore (DB plus photos when applicable).
Automatic in-container backups disappear with an uninstall. Keep the passphrase securely
outside this repo: forgotten passphrases cannot be recovered. Record only non-sensitive
artifact hashes/source and private local acceptance evidence in their appropriate places.

Expiry recovery first re-signs the cached compatible IPA over the existing exact identity,
then verifies DB/history/settings/keychain/band and advanced expiry. Only consider a clean
install after container-preserving recovery fails and a verified restore plan is available.
Test USB/Wi-Fi unchanged-IPA refresh, newer-IPA upgrade and controlled expiry separately;
at least two natural unattended renewals and the soak remain acceptance gates.

The selected portfolio keeps WHOOP standalone beside AkshatOS. If the approved SideStore
pilot continues, retain both stores and Sideloadly until same-ID key/backup parity and two
away-from-PC renewals pass. Changing the refresher is not permission to change app identity.

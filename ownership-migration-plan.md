# Ownership and compatibility

**Status:** Behavior-neutral cleanup is in progress on `ownership-cleanup`; local preservation
is verified, B2 is approved, current full CI and the actual state migration remain pending.
No cleanup history has been pushed and GitHub main has not been replaced.

## Completed scope

App package `whoop_companion`, packages `whoop_protocol`/`whoop_analytics`, their exports/imports,
app/theme/input types, native band labels and both endpoints of eleven method channels now use
owned names. The unused Watch scheme, community/contact and selected attribution files,
real-night fixtures/test and old revision manifest/guard are removed from the proposed tree.
The independent synthetic tied-beat control remains. The internal algorithm/version digest
guard replaces external revision pins; no physiological output, kAlgoVersion or schema changed.
MIT licenses place Akshat's copyright first and retain the required existing line below it.
All three external source remotes/tracking refs were removed after verified all-ref bundles.
Regenerable active-checkout caches were cleared; private recovery evidence is retained.

## Compatibility is not migration

`lib/migration/legacy_names.dart`, native `LegacyNames` in `BleRestoreManager.swift` and
`tool/legacy_identifiers.py` isolate existing on-phone bytes without renaming live state.
Info.plist still permits the two old scheduler IDs because registration still uses them.
Those configuration literals are a temporary exception to the requested final text-search gate;
do not claim the gate or build N migration is complete. Exact old-name inventory and full
earlier design remain in ignored `build/ownership-checkpoint/` and the local-only archive.

| Contract | Build N requirement | Removal gate |
|---|---|---|
| SQLite main/WAL/SHM/recovery families | Quiesce all foreground/headless/backup writers; validated crash-resumable publication to `whoop.db`, preserving originals. Test old-only/new-only/both/neither, corruption/space/refused writes/interruption; never open empty over legacy data or move a live main file alone. | Same-ID phone upgrade and row/key/history/cursor parity; no silent divergent-store merge. |
| OSBK database member and older exports | Review container version and rollback, preserve v1/v2 DB/photo imports and ambiguity rejection; round-trip old/new formats. | Phone N alone does not migrate off-phone exports. Legacy restore must remain supported after N+1. |
| Managed backup folders/names/rotation | Preserve collisions, staging remnants and both folders; verify before retention/prune; retry safely. | Phone confirms migration and independent recovery remains. |
| Dart/native logs and rotations | Preserve both old/new contents and append order; test collisions/refused rename/retry. | Confirm history preserved on phone. |
| Saved BLE UUID preference | Validate/copy/read back the new key; test conflicts, failures, reset and first pairing; do not invent UUID or unpair. | N confirms pairing/reconnect/reset and new authority. |
| OS-held BLE restoration identity | Prototype and test transition to `whoop.ble.restore` without competing managers, lost pending connection or ASK first-pairing regressions. Test generations/leases/cold+scene launch/cancellation. | Real range-loss/background/reboot restoration on N, then explicit phone acceptance before N+1. |
| Background scheduler IDs | Register/drain/cancel old requests while moving to `com.akshat.personal.whoop.bgsync` and `.refresh`; coordinate Info.plist/validator, single completion/expiry and duplicate/late-delivery tests. | Phone N confirms scheduling and safe retirement before old handlers/IDs disappear. |

The installed bundle identity, existing preference/keychain keys, OSBK magic/version, day keys,
notification identities and capability exclusions remain stable. No App Group is used. Native
build N and phone verification are not implemented merely by centralizing constants.

## Preservation and publication

`setup.md` owns the three preservation commits, verified bundles/vault snapshot and original
laptop boundary. Keep `C:\Users\aksha\git-remotes\whoop.git` and `archive/pre-rewrite-main`
local. Exact older technical/personal records remain private; the current TODO retains open
work and does not reopen completed repairs. Refresh preservation before destructive operations.

Full outgoing tree and history must pass the workspace privacy gate. Personal worked examples,
device logs, reference captures, local tools/state and archives do not belong on GitHub.
Any CI candidate must avoid sending private preservation history in its ancestors. The current
privacy boundary and remaining inline captures are listed in `privacy-fixture-review.md`.
The two JSON corpora are now locally preserved, with optional replay and a separate reproducible
synthetic public fixture. Targeted private/public configurations pass with explicit skips.
All nine substitutions were approved and implemented, along with copies in app tests.
`privacy-fixture-review.md` owns the targeted results and completed source-review boundaries.
Review fresh candidate ancestry before a Linux-only CI push; never push this preservation branch.

**B5 STOP:** show the one-root-commit candidate and exact main/branch/tag changes, then obtain
explicit yes before force-pushing main or deleting each remote ref. Existing GitHub main/refs
are untouched. The original laptop must independently archive before re-pointing its clones.

## Approved sequence

Akshat approved completing coverage before build N while keeping the IPA hold. Complete safe
public controls and full Linux verification first, then resume migration and native/phone
acceptance. No early IPA dispatch or metadata bump is authorized. B5's explicit main rewrite
and per-ref deletion approvals remain separate and have not been given.

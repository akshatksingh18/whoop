# WHOOP BLE Companion

One local Git monorepo, based on OpenStrap, for pairing with a WHOOP 4.0 sensor over Bluetooth
LE, decoding the raw protocol, and computing recovery/strain/sleep metrics locally — no WHOOP
subscription and no app backend.

- The Flutter `edge` app lives at the repository root.
- `packages/protocol/` contains the BLE codecs at the exact revision the imported app used.
- `packages/analytics/` contains the local metric engine at the exact revision the imported app
  used.

The monorepo preserves all three upstream histories. A future GitHub repository for this personal
analysis should be private and use Akshat's main account; no alternate identity is needed.

**Status:** Paused/research — source and history are imported and the local Git repository is
ready, but no feature or bug-fix work is expected while paused.

## Files
- `setup.md` — current repository/remotes, imported revisions, local dependency setup, and the
  deferred iOS/GitHub workflow.
- `bugs.md` — the active reconnection bug: symptoms, confirmed-not-hardware evidence, leading
  hypotheses, and where to look in `lib/ble/`.
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
- `lib/ui/` — every screen
- `packages/protocol/lib/` — protocol framing and record decoders
- `packages/analytics/lib/` — recovery, strain, sleep, and related formulas

## Environment
- Dev machine: Windows laptop, no local Mac
- Primary test device: Android phone (Vivo iQOO, OriginOS/Funtouch skin)
- Eventual target: also iPhone via a Sideloadly-sideloaded unsigned `.ipa` (see `setup.md`)

## Working agreement
- Keep this as one repository. Route byte/protocol work to `packages/protocol/`, metric work to
  `packages/analytics/`, and app/flow/storage/UI work to the root app areas.
- Preserve the algorithm-version rules in `AGENTS.md`: any analytics output change must still be
  reviewed with the matching `kAlgoVersion` decision even though no external package pin changes.
- Treat upstream updates as deliberate reviewed imports; never replace a local package with a
  floating branch dependency.
- **Whenever a new project-owned file or top-level source area is added**, add a bullet under
  `## Files` in the same edit. Files inside an already-indexed imported source area do not need
  individual bullets.

# WHOOP companion

Akshat Kumar Singh's personal iPhone Flutter app:BLE → SQLite → on-device analytics → UI.
No app backend,account,telemetry or LLM calls. Optional barcode/Maps requests disclose inputs
to their providers;never imply zero network disclosure.

**Status:** 100% handwritten Dart coverage was verified on main `aacaed47`. Main `27b3d305` holds
the approved 3r app-dead removals at 48,378/48,380 lines; the last two are tested in source and
the next CI candidate re-proves 100%. The large-file split is under way (todo.md), then the
native migration. Use the worktree below; coverage-audit.md owns the proof.

## Files

- `context.md` — read first: what the app is, the data flow, source areas and where to add things.
- `rules.md` — read before any change: data-integrity, versioning, change-gate, test and privacy rules.
- `setup.md` — identity,toolchain,checkout,recovery/release.
- `todo.md` — open A/B/C,coverage3r,STOPs and proposals.
- `coverage-audit.md` — current tree/run,source/LCOV proof and limits.
- `coverage-map.md` — function/caller/purpose audit and removal decisions.
- `bugs.md` — defects and physical acceptance.
- `ownership-migration-plan.md` — ownership cleanup and two-build migration.
- `privacy-fixture-review.md` — synthetic substitutions/capture privacy.
- `README.md` — public overview.
- `metrics-map.md` — metric readers,absence/estimate rules and calorie ownership.
- `build-90-audit.md` — inherited work categories;originals stay private.
- `treadmill-walking-plan.md` — open calculation/flow proposal;review/previews precede implementation.
- `DESIGN.md` — locked kraft/cream A+B composition and tokens;read for UI work.
- `food-undo-preservation-review.md` — approved exact-row Undo repair,pages,regressions and acceptance.
- `lift-rest-expiry-review.md`, `history-end-ownership-review.md`, `session-split-preservation-review.md` — timer/ACK/atomic-session approvals and acceptance.
- `import-sleep-source-review.md`, `home-night-ownership-review.md`, `step-calorie-history-review.md`, `r10-beat-review.md`, `sleep-correction-review.md`, `what-changed-history-review.md` — output/version/page reviews.
- `food-layout-review.md`, `body-history-review.md`, `body-milestone-layout-review.md`, `name-guidance-layout-review.md`, `alarm-write-feedback-review.md`, `journal-layout-review.md`, `text-controller-lifetime-review.md`, `session-band-route-review.md`, `reliability-ui-review.md` — UI/behavior reviews and acceptance.
- `guides/IOS_INSTALLATION.md`, `guides/IOS_SIDELOAD.md` — payload/signing continuity,encrypted restore and phone acceptance.
- `lib/`, `test/`, `ios/`, `assets/` — app,tests and personal Runner-only target.
- `packages/protocol/`, `packages/analytics/` — pure codecs/metrics source and tests;path dependencies stay tracked.
- `packages/algorithm-contract.json`, `tool/algorithm_contract.py` — internal algorithm guard.
- `lib/migration/legacy_names.dart`, `ios/Runner/BleRestoreManager.swift`, `tool/legacy_identifiers.py` — retained compatibility names,not completed migration.
- `lib/migration/store_migration.dart` — the SQLite store's move to `whoop.db`;source-tested,not phone-verified.
- `tool/`, `.github/workflows/` — Linux checks,coverage/caller contracts,synthetic fixtures/pages and held iOS validation;procedures in setup.md.
- `pubspec.yaml`, `pubspec.lock`, `LICENSE` and package licenses — locked metadata/dependencies and required MIT text.
- `product.md`, `.claude/skills/ponytail/SKILL.md`, local Impeccable files/hooks — optional local guidance;no automatic inherited hooks.
- `build/ownership-checkpoint/` (ignored) — private originals,bundles,probes/reviews and migration inventory;never push. setup.md owns recovery.
- Sibling `personal-project/final-ipas/whoop/` — private recovery/testing cache;its README owns promotion.

## Working agreement

- Use `C:\AI Important Files\personal-project\whoop\build\worktrees\build95-repairs`,branch
  `ownership-cleanup`. Preserve historical root `build-90-codex` and newer work;never reset it.
- Root/container privacy and cloud rules apply. GitHub main descends only from fresh root
  `aacaed47`;publish per setup.md. Never push this branch/private ancestors,captures,archives,
  local tooling or recovery.
- Follow A → B → C and every STOP,with the approved coverage-before-buildN sequencing exception.
  Native/IPA stays held until coverage completion. MigrationN,phone confirmation,N+1 alias removal
  and any GitHub ref deletion or main rewrite retain separate approval gates.
- `rules.md` owns the engineering invariants and the removal, UI, calculation and platform
  gates; plan work in todo.md.
- Verify full encrypted off-phone export/restore before upgrades or identity/schema/format
  changes. Container copies do not survive uninstall. Promotion requires payload/source/hash,
  physical matrix/soak,enrollment,natural renewals and recovery;keep the known-good IPA.
- One agent,no subagents/hooks/canvas/overlapping coding sessions. Batch meaningful controls;
  quick few-file probes locally,full suites/analysis/heavy derivation on Actions. Preserve old
  assertions,emitted roles/hits and honest unknowns;never merge old/failed/prototype LCOV.
- Check actual usage at batch boundaries. At5% primary remaining finish preservation/publication/
  handoff only. setup.md/private cov54-current-handoff.md own the single same-chat reset-aware
  occurrence,reserve decisions and recovery. Keep account/reset/scheduler details private;
  never buy/redeem credits,switch accounts,bypass limits or restore periodic polling.
- Preserve required MIT copyright lines;older build records refer to the private archive.

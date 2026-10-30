# WHOOP companion

Akshat Kumar Singh's personal iPhone Flutter app: BLE → SQLite → on-device analytics → UI.
No app backend, account, telemetry or LLM calls. Optional barcode lookup and Maps requests
disclose barcode/route inputs to their providers; never imply zero network disclosure.

**Status:** Ownership cleanup continues on `ownership-cleanup`; fresh main and persisted-state
migration remain pending. Full Linux [41036232608](https://github.com/akshatksingh18/whoop/actions/runs/41036232608)
passes on parentless `fb4635b4`: 5,307 app checks, both packages and 731 synthetic captures.
Handwritten execution is 48,006/50,428 (95.20%; 2,422 unexecuted). Against candidate 45:
14 matching gains/no losses, plus six new/six removed mapped separately; net +15 hits and
unchanged denominator. All 203 source/four unimported hashes match that candidate. Analysis
has zero errors/warnings and 325 retained infos. All first 356 COV-48 controls/four Home
journeys pass, including partial-quarantine rollback and its real file-recovery regressions.
COV-47 met its five-point target. Continue one-agent coverage from matching ranges in
`coverage-audit.md` and scope in `todo.md`. Approved Body A and ancient unknown-record retention
repairs pass locally; 31 unique controls after candidate 45 (24 after candidate 46) pass
targeted checks, with no new analysis notices. Four actual Body pages exactly match approved
A. These DB/Body source changes need fresh combined proof; do not reuse older LCOV positions.
The approved Body milestone A also passes nine local controls and four exact capture matches;
four Food root navigation controls pass. These thirteen later additions need fresh combined
proof. The separate enlarged name helper and native/phone gates remain open.
Full Linux [41041518801](https://github.com/akshatksingh18/whoop/actions/runs/41041518801) is pending on parentless `084d0b18`/candidate 47,
including approved Body A and all 31 additions after candidate 45. Four further ancient
retention controls pass locally; that newer DB repair is outside candidates 46/47.
Full Linux [41044234822](https://github.com/akshatksingh18/whoop/actions/runs/41044234822)
is pending on parentless `a61b4c48`/candidate 48, including that repair and the approved Body A.
Stable calculations, metadata `0.9.69+102`/algorithm 99/schema 50 and persisted identities stay
unchanged. Cached Build 102 is older; installed phone build is unconfirmed. Native/IPA builds
remain held until coverage completion. Enlarged name-helper/native/phone acceptance and
migration N remain open; `ownership-migration-plan.md` owns B5 STOP. The reset-based usage
follow-up is ACTIVE; `setup.md` owns policy and local-only configuration/recovery.

## Files

- `todo.md` — ordered A/B/C work, STOP checkpoints, coverage 3r, Food default investigation,
  treadmill/calorie proposals and inherited acceptance gates.
- `ownership-migration-plan.md` — implemented cleanup versus planned migration, compatibility
  contracts, two-build/phone gates and publication STOP; read before renaming or removing.
- `privacy-fixture-review.md` — exact remaining captured-test boundary, prepared synthetic
  controls and implemented approved substitutions; review final candidate ancestry before CI.
- `setup.md` — correct checkout/branch, toolchain, cached/installed identity, private archives,
  local-only vault and original-laptop recovery boundaries.
- `README.md` — public project/features/build overview.
- `metrics-map.md` — metric readers, absence/estimate rules and calorie ownership.
- `coverage-audit.md`, `tool/coverage_gaps.py` — current CI, remaining ranges/source hashes,
  targeted verification and remaining native/physical limits.
- `build-90-audit.md` — current app-wide work categories; exact original audit/worklist and older
  research/build records remain in the private pre-fresh-start archive.
- `treadmill-walking-plan.md` — open calculation/flow proposal, previews required before code.
- `bugs.md` — current investigations and acceptance; exact private reproductions are archived.
- `DESIGN.md` — locked kraft/cream A+B interface and tokens; read for UI work.
- `food-layout-review.md` — approved Food A composition, complete Before/A/B and actual
  implementation captures, targeted checks and remaining combined/native verification.
- `body-history-review.md` — approved All/Since-start average correction, complete Before/A/B
  synthetic pages, approved A and implemented capture parity; combined/native proof remains open.
- `body-milestone-layout-review.md` — approved milestone A, complete Before/A/B and actual
  matching pages, nine local regressions and remaining combined/native verification.
- `reliability-ui-review.md` - authorized backup-feedback and band-dialog fixes, full-page
  Before/After evidence and remaining large-text helper limitation.
- `product.md` — platform adapter for local Impeccable tooling, no independent product authority.
- `guides/IOS_INSTALLATION.md`, `guides/IOS_SIDELOAD.md` — personal payload, signing continuity,
  encrypted export/restore, upgrades and physical acceptance requirements.
- `lib/`, `test/`, `ios/`, `assets/` — app, synthetic regressions and personal Runner-only target.
  BLE in `lib/ble/`, storage/read seam in `lib/data/`, orchestration in `lib/compute/`, AppState
  in `lib/state/`, screens in `lib/ui2/`, routes/voice in `lib/gps/`, channels in `lib/platform/`.
- `lib/migration/legacy_names.dart` — existing persisted names, not completed migration. Native
  equivalents in `ios/Runner/BleRestoreManager.swift`, validator in `tool/legacy_identifiers.py`.
- `packages/protocol/`, `packages/analytics/` — tracked pure Dart codecs and metric source/tests.
- `packages/algorithm-contract.json`, `tool/algorithm_contract.py` — internal digests, path
  identities and algorithm-version contract; review outputs/version before changing it.
- `tool/generate_protocol_fixture.py` — reproducible public synthetic byte contracts, independent
  of production decoders and private captures; `--check` guards fixture provenance/drift.
- `pubspec.yaml`, `pubspec.lock` — identity, metadata and locked path dependencies.
- `.github/workflows/test.yml`, `.github/workflows/package-tests.yml`, `tool/ui_smoke_gallery.py`
  — full Linux app/package/coverage checks and synthetic complete-page evidence.
- `.github/workflows/personal-ios.yml`, `tool/personal_ios.py`,
  `tool/personal_ios_accepted_builds.json` — manual native payload/source/hash and accepted-build
  ledger. Held until coverage gate resolves; never reuse a published version/build.
- `.claude/skills/ponytail/SKILL.md` — reuse/minimal-change discipline; read before code changes.
- `.claude/skills/impeccable/`, `.codex/hooks.json`, `tool/impeccable-hook.ps1`, `.impeccable/`
  — local-only preserved design tooling/state. Read its skill for UI work; hook trust/automatic
  delivery remain unverified. Never upload local state or bypass executable trust.
- `LICENSE` and package licenses — MIT, owner's line first and required existing line retained.
- `build/ownership-checkpoint/` (ignored) — verified bundles, original docs/worked examples,
  inventories, loose-file hashes and exact old-name migration inventory. Private, never push.
  `setup.md` owns vault copies; a clone does not recover this material.
- Sibling `personal-project/final-ipas/whoop/` — private accepted recovery/testing artifact cache;
  its README owns the model. Promotion requires phone/signing acceptance.

## Working agreement

- Apply workspace root/container instructions and privacy gate. Full suites/analysis/builds
  run on Actions, quick targeted probes locally. No canvas.
- Use `C:\AI Important Files\personal-project\whoop\build\worktrees\build95-repairs`.
  Preserve historical project-root `build-90-codex`; never reset it to become current.
- Follow A → B → C and every explicit STOP. B2's unused scheme removal is approved; B5's
  main force-push and each branch/tag deletion require explicit yes after exact review.
  Archives/preservation branches never leave the laptop; never mirror-push.
- Before removing a feature/screen/tab, list every unique metric/insight/entry point that becomes
  unreachable, core versus redundant, and ask per item. UI deletion does not authorize stopping
  underlying computation/storage. Removed platforms/features stay removed unless reopened.
- Plan multi-feature work in TODO first. Calculation policies require separate review; show
  complete before/after full-page synthetic previews and choices before UI implementation.
  Preserve approved running/walking/lifting/digestion/Recovery methods. The awake 1.2 multiplier
  was withdrawn. Treadmill/Food default proposals are not implementation approval.
- Keep one repo: byte/protocol work in protocol, pure metrics in analytics, orchestration/
  storage/UI in app. Prefer existing shared helpers and Ponytail's reuse ladder.
- Preserve daily iPhone Runner release/AOT, stable signed identity, empty entitlements and
  approved ASK/Bluetooth/GPS/Home-region/voice/scheduler profile. No Watch/Android/extensions/
  HealthKit/App Group/Firebase/OTA/coach, silent audio or installer runtime dependency.
- Verify full encrypted off-phone export/restore before upgrades or identity/schema/format
  changes. Automatic in-container copies do not survive uninstall. Promotion requires payload/
  source/hash, phone matrix/soak, enrollment, natural renewals and recovery; retain known-good IPA.
- Register new private evidence in local-only recovery. Preserve required third-party licenses.
  Older build references resolve to the private pre-fresh-start archive.
- Update affected owning docs together, planned versus verified honestly. Index new project-owned
  files/source areas here; ordinary files within indexed source areas need no individual bullet.
  Parent routing changes only when its own boundary changes. Batch docs with implementation.
- This task authorizes small logical cleanup commits and privacy-reviewed Linux CI, not B5.
- The same-chat `whoop-usage-aware-continuation` automation is ACTIVE again at Akshat's
  explicit request. Keep exactly one absolute occurrence five minutes after the live applicable
  reset, read it back, and preserve completed history. No periodic polling or duplicate wake-ups.
  Check actual usage at useful batch boundaries. Automatic sessions preserve a safe checkpoint
  at 7% remaining; manually started/resumed sessions may use the remaining ordinary allowance
  below 7%. Respect actual account limits and preserve before exhaustion. A weekly block needs
  its applicable later reset; a five-hour reset does not clear it. Never purchase/redeem credits,
  switch accounts or bypass limits. Stop the chain on Akshat's stop request, coverage completion,
  or an approval gate blocking all independent work. Do not overlap another coding session.
  `setup.md` owns the policy and local-only configuration/recovery boundary.

## Engineering invariants

1. Commit decoded rows/cursor atomically before the verbatim 8-byte HISTORY_END ACK. Never ACK
   a partial chunk or regenerate the token; ACK can trim band flash permanently.
2. `decoded_onehz`: INSERT-OR-REPLACE on `(device_id, ts_ms)`; eviction deletes its RR beats
   in the same batch. Never promise raw replay for bytes no longer retained.
3. Missing/thin/invalid input means null, `Metric.absent` or honest reason/estimate; no fabricated
   score, substituted metric or unknown rendered as measured zero.
4. Analytics output changes need reviewed `kAlgoVersion` bump/changelog; rows are immutable
   per version. Pure renames do not justify a bump.
5. A package-output change includes real source and version decision in the same tree.
6. Track both package trees and path lock together, no floating Git refs or
   `pubspec_overrides.yaml`. Review source/output implications before updating digest contracts.
7. Day labels are LOCAL via `todayLabel`/`dayLabelOf`; epochs remain absolute. Do not assume
   86400-second days. Keep effective, recorded and logged provenance distinct.
8. One decode seam (`substrate.dart`), sleep/readiness/ingest path and notification emitter
   (`NotificationCenter.emit`); reuse shared policies before adding caller-specific alternatives.
9. Never prune raw/decoded before full successful derivation. Partial scalars do not finalize a
   day. `raw_archive` is not a full backup.
10. Heavy analytics stays off the UI isolate; re-arm ambient state inside workers.
11. Migrations are additive/idempotent/cheap with sequential upgrades and same-version repair.
    WAL mode uses `rawQuery`. Never move a live SQLite main file without its WAL state.
12. Headless sync serializes through `HeadlessSyncGate.tryRun`: skip, do not queue.
13. Coach/export readers respect allow-listed views, no hidden decoded/raw fallback.
14. High-rate live streams stay RAM-only; phone-only steps and HR-only live-band scope remain.
15. Dangerous opcodes (trim/reboot/power-cycle/firmware) are never auto-sent.
16. Reset uses `CalculationStore.resetWith` through native/preference completion, with capture/
    derive shutdown. Do not re-enter CalculationStore there or restore an anchor after wipe.

Check async latches for `finally`/timeout cleanup, late results for generation ownership,
readiness for idempotence, notifications for atomic dedupe, mutations for cross-tab revision,
and schema/media/backup changes for failure/retry/cancellation. Implementation wins over stale
comments. Synthetic assertions/captures do not certify real BLE, sensors or OS delivery.

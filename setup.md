# WHOOP development and recovery

**Status:** Ownership cleanup continues on `ownership-cleanup`; GitHub main is unchanged.
Full Linux run [40762223691](https://github.com/akshatksingh18/whoop/actions/runs/40762223691)
passes COV-47 at 93.46%, exceeding its five-point target. COV-48 continues toward 100%, with
36 later controls passing targeted checks but awaiting combined CI. Actual persisted-name
migration and phone acceptance stay open; native/IPA builds remain held.

## Correct checkout

On this laptop use `C:\AI Important Files\personal-project\whoop\build\worktrees\build95-repairs`.
Its folder name is historical. The preserved project-root checkout remains on `build-90-codex`.
The cleanup branch starts at `b9f2532d` on `coverage-expansion`; its inherited pre-cleanup
GitHub checkpoint is `050ae04e`. These are historical baselines, not the current CI candidate
recorded below. Preserve newer work rather than resetting to either revision.
Check `git branch --show-current`, `git status` and `pubspec.yaml` before reporting status.

App metadata remains `0.9.69+102`, algorithm 99, schema 50. Cached Build 102 was built from
`fc69b0d3`; later coverage repairs and ownership edits are not in that IPA. Build 91 is the
last reported install; confirm the phone's actual About/version separately. Build 70 remains
the accepted recovery artifact. No cache promotion or signing enrollment is claimed here.

## Toolchain and checks

The workspace development toolchain is under `personal-project/dev/`; resolve it from the
workspace, not relative to this deeply nested checkout. CI pins Flutter 3.41.6. Full suites,
whole-project analysis and native builds run on Actions. Local checks are a few targeted files
or short Python probes. `.github/workflows/test.yml` runs both package suites, app analysis,
instrumented tests and synthetic full-page captures; `personal-ios.yml` is manual only.
The Linux workflow first runs the authored worker/scheduler handoff files for early feedback;
the subsequent complete instrumented suite remains the coverage source.
The internal package digest/version guard is `tool/algorithm_contract.py` and
`packages/algorithm-contract.json`. Review output/version implications before updating digests.
No floating Git dependency, local dependency override or external revision probe is permitted.

On Windows, native hooks can fail under paths with spaces. For targeted probes only, use
temporary unused drive aliases for this checkout and the installed Flutter SDK, remove them
in `finally`, and regenerate package configuration against the real path afterwards. Never
leave a long-running test or temporary drive mapping behind.

Continuation is manual in sessions Akshat starts/resumes; no unattended follow-up automation is
active for this work. Begin by checking the latest run recorded below, then inspect newer source.

Native/IPA builds remain held until coverage work is complete. Akshat approved coverage completion before build N while retaining that hold. Then resume
ownership migration/native verification; the GitHub replacement STOP remains. Do not dispatch a native build or bump metadata to bypass that hold.

## Repository and private recovery

`origin` is `https://github.com/akshatksingh18/whoop.git`; `local-backup` is
`C:\Users\aksha\git-remotes\whoop.git`. Only these remotes remain. Local source cleanup commit: `ce2202d0` (owned identities, preserved runtime aliases and
internal algorithm guard). Documentation/privacy changes are batched separately.
Only reviewed parentless CI candidates have been pushed, using public-safe noreply identity
and no preservation ancestors. GitHub main, existing branches and tags remain untouched.
Read-only GitHub checks confirm the repository belongs to the authenticated account.
The fully verified candidate is parentless `6272ede45179ebf8a97b14d2d3f5019f8e96ee79` on
`ownership-ci-candidate-19`, source `b98a4553`, tree `4fbbca7ed7d3cbaf77d43ae05809c6ac935e1fb7`.
Full Linux run [40762223691](https://github.com/akshatksingh18/whoop/actions/runs/40762223691)
passes 4,951 app checks/429 retained explicit skips, both packages, analysis (325 infos, zero
errors/warnings), the eight early worker checks and 730 synthetic captures. All 343 COV-47
controls pass. Handwritten execution is 47,111/50,410 (93.46%; 3,299 unexecuted). Against
COV-46's 88.01%, 2,746 unchanged lines gain hits and none loses a hit: +5.45 percentage points.
All 203+4 normalized source hashes match. The same existing dirty-state line adds one
instrumented line without a source change; nothing is excluded from the denominator. Exact
coverage/delta and verification are in `build/coverage-continuation/6272ede4/` and
`build/ownership-checkpoint/cov47-ci19-linux-verified/verification.json`.

Candidate 19 preserves all 34 earlier remote refs; only its new branch was added. Its privacy
review covers 919 tracked files, 29 unchanged binaries, 134 original historical/private loose
files and 36 captured originals. Its verified all-ref archive is `cov47-ci19-state-all-refs.bundle`
(42,647,483 bytes; SHA-256
`299d9ed227dc255d8a6cd1f267b3e8fd6b86442135c31463ac7a59228e6533e2`). The pre-push scoped
vault/content check covers 8,199 files with zero differences. Main and tags stay unchanged.
These parentless candidates have no private preservation ancestors. Native/IPA, migration N,
phone acceptance and B5 approval remain separate and open.

The later 28 controls at local source `2d0beb26dcf3816bc79d499bbdaca56cfeeb21a2` are COV-48's
starting cohort, not part of the verified candidate. They pass quick targeted tests and reach
112 matching remaining lines; this is not a combined percentage. The verified
`cov47-post-ci19-copy-controls-all-refs.bundle` protects them (42,670,572 bytes; SHA-256
`9f8a84e0299dd0b5fea4c84b21776012886b218ef55e982eea3c97411f058e41`). Its preservation receipt
re-verifies all 203+4 source hashes, 134 original loose files and 36 captures. The scoped vault
check covers 9,021 files with zero differences through that receipt and downloaded candidate-19
pages. New green-run receipts/documentation require the next verified bundle/vault refresh.

The source/docs checkpoint `a60a0508` is protected by verified `cov48-state-all-refs.bundle`
(42,675,304 bytes; SHA-256
`3fabd7e7397697f5560673851f16c72278079172c697c35169576063e088cf1f`). Its receipt verifies all
203+4 source hashes, 134 original loose files and 36 captures. The scoped vault/content check
verifies 9,034 files with zero differences, including the complete green candidate-19 evidence.
Eight later Recovery/What-changed controls, the new historical-boundary reproduction and owning
document updates require the next verified commit/bundle/vault refresh.

Earlier COV-47 failed and partial runs remain in their own receipts/bundles. The short main-sleep
fixture, async share assertion, route-exit wait and repeated media-container issues are corrected
in tests and pass together in candidate 19. Required RHR, encrypted format/iterations, cleanup,
photo counts and source-data assertions remain. All old media containers are retained. Failed-run
coverage was never promoted. The old root/source identities, exact logs and earlier bundle hashes
remain in `cov47-ci15-*` through `cov47-ci18-*` and their source commits in the verified archives.

COV-46's final-tail refusal/retry, backup failure feedback and band-dialog lifetime repairs and
all re-enabled regressions remain passing. Its existing heart-fixture rollover correction and
aged-snapshot controls remain retained; the separate enlarged name-helper clipping stays open.
No chart implementation, calculation, schema, active identity or metadata changes are made by
COV-47/COV-48. Older COV-44–46 evidence remains in its owning verified receipts.

Approved capture substitutions and copied call sites are implemented; `privacy-fixture-review.md`
owns their provenance and private retention. Two JSON oracles already have
verified local-only copies and optional replay, plus independent public synthetic controls.
This branch also has private preservation ancestors: never push it. A later candidate must
send only reviewed content with fresh ancestry and a public-safe commit identity.

All previous histories are still local. The three preservation commits are:

- `0b3817a8642d3bc495e2c4fb5b20913b845d33e6` on historical `build-90-codex`.
- `f1d5689eca94e4b96149e9e00095fe1806350653` on local-only `preserve/local-design-tooling`.
- `b9f2532d7388605496291ee9f5b4fc6379493ab5` on `coverage-expansion`.

Verified all-ref bundles and loose-file manifests are in ignored `build/ownership-checkpoint/`.
Keep the original repositories as well: bundles do not preserve every reflog-only object.
`archive/pre-rewrite-main` remains in the local bare backup; this clone tracks it as
`refs/remotes/local-backup/archive/pre-rewrite-main`. Never mirror-push archives or preservation refs.
The independently verified local-only vault snapshot is
`C:\AI Local Only\inventories\whoop-pre-fresh-start` (16,124 files, zero check differences).
The later review snapshot is `C:\AI Local Only\inventories\whoop-ownership-review`.
These snapshots precede the source cleanup; refresh preservation before destructive publication.
The original laptop's D:-based checkout and bare backup require their own verified archives.
Current cleanup recovery uses verified all-ref bundles in `build/ownership-checkpoint/`;
`cleanup-final-receipt.json` records the `b53d2f9b` checkpoint; the later verified
`pre-ci-fixture-all-refs.bundle` preserves local source through `2ab7577f` (SHA-256
`f6107e13a9283ad82a1ec5a1849228ebd1f0acf473dffc56469727f268aaef43`).
`ci-candidate*.json` records the separate reviewed public roots. The current verified source/CI
archive receipt for COV-46 is `cov46-session-preservation-receipt.json`; it records exact final head,
all-ref bundle filename/size/SHA-256, run evidence and preserved loose/artifact counts. Earlier
COV-46 source/pending/failed-run receipts and `cov45-session-preservation-receipt.json` remain.
The COV-47 failed-run receipts remain `cov47-ci16-*` through `cov47-ci18-*`; the current verified
receipts are `cov47-ci19-candidate.json` and `cov47-ci19-linux-verified/verification.json`.
Their verified all-ref bundles are recorded there.
`cov47-post-ci14-controls-all-refs.bundle` preserves the later `402c35b8` local commit.
Verify the applicable receipt; an older one does not cover later edits or uncommitted files.

The post-COV-40
checkpoint at `0d8b2e2b` is independently preserved in `post-cov40-state-all-refs.bundle`
(SHA-256 `94d6de093cfab6adc27e58f4249cb745d21f607f3b16a34bc971b62c5df15d7e`).
The isolated vault snapshot `C:\AI Local Only\inventories\whoop-ownership-cleanup` includes
those bundles, exact old docs and captured protocol oracles. Its manifest owns current file
counts; independent collector checks must show zero differences before proceeding. Earlier
snapshots remain unchanged. Refresh the scoped snapshot again before destructive publication.
These archives remain local only.

Exact earlier build/audit/research records, original completed tracker and personal worked
examples remain in the private pre-fresh-start archives. Current edited originals were copied
and SHA-256 verified in `build/ownership-checkpoint/private-reference-docs/manifest.json` before
being removed from the proposed public tree. `pre-cleanup-docs/` retains the earlier bytes too.
These files and local tooling/health captures must not be pushed. The current TODO consolidates
open work without reopening finished repairs. Backup registration/vault collection must include
new private evidence; a Git clone does not recover it.

## Deployment

The personal source ships Runner and RunnerTests only, no extensions, Watch or Android target.
Preserve the bundle/signing identity, encrypted export formats and OS-held restoration state.
The payload validator enforces empty entitlements, capability exclusions and background modes.
See the two iOS guides for signing, backup, upgrade and physical acceptance gates.

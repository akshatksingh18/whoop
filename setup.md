# WHOOP development and recovery

**Status:** Ownership cleanup continues on `ownership-cleanup`; GitHub main is unchanged.
Full Linux run [40630574613](https://github.com/akshatksingh18/whoop/actions/runs/40630574613) passes partial COV-47 and earlier work. Remaining coverage, actual persisted-name
migration and phone acceptance stay open; native/IPA builds remain held.
COV-47's larger test-only cohort remains open: verified coverage is 90.30%, short of its
93.01% minimum. Further targeted probes are development evidence; complete authored-night
orchestration and combined suites run on Linux CI. Candidate 13's unused new-test import is
corrected and candidate 14 passes with matching downloaded evidence.

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
The fully verified candidate is parentless `715b13739f4d416a4942185b5670b6e37772ae2b` on
`ownership-ci-candidate-14`, source `d7624900`, tree `0e50ab55e4fce850cecce5de5a78ebbd4042e567`.
Full Linux run [40630574613](https://github.com/akshatksingh18/whoop/actions/runs/40630574613) passes 4,732 app checks/429 explicit skips, both packages, analysis and
730 synthetic captures. All 124 new controls and retained UI regressions pass. The inventory
is 45,520/50,410 handwritten lines (90.30%; 4,890 unexecuted), with 203 matching imported source
hashes and four matching unimported hashes. Against COV-46, 1,156 unchanged lines gain hits
and one loses its hit: net +1,155. One additional instrumented dirty-state line becomes visible
without a source change; no denominator exclusions. Exact evidence is preserved under
`build/coverage-continuation/715b1373/` and `build/ownership-checkpoint/cov47-ci14-linux-verified/`.

COV-46 repairs current final-tail refusal/retry, backup failure feedback and band-dialog
lifetime. The first combined attempt failed an existing minute-rollover-sensitive heart fixture;
its test-only correction and three aged-snapshot controls pass the corrected full run. No chart
implementation, calculation, schema, active identity or metadata changes. Existing enlarged
name-helper clipping remains open. Full evidence is in `coverage-audit.md` and
`build/ownership-checkpoint/cov46-linux-verified/`; complete UI artifacts/manifests remain local.
COV-45 and COV-44's consolidated 1,450-line gain remain verified in their own preserved receipts.

Only candidates 13 and 14 were added in COV-47 so far. Candidate 14 preserves all 29 earlier
GitHub refs; exact before inventories remain local. Each candidate has one root commit and no
private ancestors. This is not build N migration, a phone install or a main replacement.
Native/IPA and B5 holds remain.

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
The COV-47 CI receipts are `cov47-ci14-candidate.json` and
`cov47-ci14-linux-verified/verification.json`; its verified all-ref bundle is recorded there.
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

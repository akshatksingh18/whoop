# WHOOP development and recovery

**Status:** Ownership cleanup continues on `ownership-cleanup`; GitHub main is unchanged.
Full Linux run [40865029877](https://github.com/akshatksingh18/whoop/actions/runs/40865029877)
passes the first 139 COV-48 cases, four Home journeys and event/clock/import/notification repairs
at 94.34%; COV-47 already exceeded its five-point target. The shared freshness-reader repair
awaits run 40867718870 on parentless `12f4c8ff`. Actual persisted-name migration and phone
acceptance stay open; native/IPA builds remain held.

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

Continuation is allowed in user-started sessions and the explicitly approved same-chat
`whoop-usage-aware-continuation` automation. Periodic polling is removed at Akshat's request.
Exactly one continuation is scheduled five minutes after the live five-hour reset. Each resumed
session rechecks actual limits and schedules the next single occurrence from the new reported
reset, without restoring polling or inventing a reset time. During active work, check usage at
batch boundaries and preserve a safe checkpoint near the authorized reserve. The active absolute
one-occurrence rule is accepted and read back; the first actual reset-time continuation has
arrived and re-armed the next reported reset. Later delivery still depends on the running app/laptop.
The app and laptop must remain running for local work.
No account switching, purchased/redeemed credits, private API or shell-scheduler workaround.
Stop at the existing approval gates, on Akshat's stop request, or when coverage is complete.
The exact local configuration and usage evidence stay local-only; the automation is registered
in the vault item list. Begin by checking the latest run below and preserve newer source.

Native/IPA builds remain held until coverage work is complete. Akshat approved coverage completion before build N while retaining that hold. Then resume
ownership migration/native verification; the GitHub replacement STOP remains. Do not dispatch a native build or bump metadata to bypass that hold.

## Repository and private recovery

`origin` is `https://github.com/akshatksingh18/whoop.git`; `local-backup` is
`C:\Users\aksha\git-remotes\whoop.git`. Only these remotes remain. Local source cleanup commit: `ce2202d0` (owned identities, preserved runtime aliases and
internal algorithm guard). Documentation/privacy changes are batched separately.
Only reviewed parentless CI candidates have been pushed, using public-safe noreply identity
and no preservation ancestors. GitHub main, existing branches and tags remain untouched.
Read-only GitHub checks confirm the repository belongs to the authenticated account.
The fully verified candidate is parentless `5c71cee13b5a48b14d99c9ea70d22c682f2d2986` on
`ownership-ci-candidate-26`, source `57dc6167`, tree `3670a79b511804231650705efe0446f40138036e`.
Full Linux run [40865029877](https://github.com/akshatksingh18/whoop/actions/runs/40865029877)
passes 5,090 app checks/429 retained explicit skips, both packages, analysis (325 infos, zero
errors/warnings), eight early worker checks and 730 synthetic captures. Handwritten execution
is 47,565/50,419 (94.34%; 2,854 unexecuted). Exact mapping against candidate 24 records 77 gains,
no losses and changed instrumentation separately: net +83 executed and +4 denominator. Against
candidate 25, unchanged production sources gain 45 hits with zero losses/denominator change.
All 196 handwritten Git-source hashes, seven generated hashes and four unimported hashes
match the candidate/regeneration evidence. The newer freshness source is outside this proof.
`coverage-audit.md` owns artifact/delta paths and the later repair distinction.
COV-47 remains complete: +2,746 matching lines, 88.01% to 93.46%, exceeding five points.

Candidate 20 preserves all 35 prior remote refs; only its new branch was added. Its privacy
review covers 926 tracked files, 29 unchanged binaries, 134 original historical/private loose
files, 36 captured originals and the five retained negative reproductions. Verified
`cov48-ci20-state-all-refs.bundle` protects source/root (42,669,071 bytes; SHA-256
`578eede63b2b2768b290544ff4d573a0ee6529fd13f3571031f06126b00ddd68`). The pre-push scoped
vault/content check verifies 9,067 files with zero differences. The candidate and verification
receipts are `cov48-ci20-candidate.json` and `cov48-ci20-linux-verified/verification.json`.
The source/docs/expiry checkpoint `61d9eac1` is protected by verified
`cov48-ci20-verified-expiry-state-all-refs.bundle` (42,679,179 bytes; SHA-256
`ad49ec35053c6023f2b75a3636d54e58232593985e1425e136110937951a53fe`). Its receipt re-verifies
all 203+4 source hashes, 134 original loose files and 36 captured originals. Scoped vault and
independent content verification cover 9,821 files, including all green candidate-20 evidence.
The 30 controls after candidate 20, including that expiry case, now pass combined CI in
candidate 21, bringing COV-48's verified cohort to 66. Its full proof is
`cov48-ci21-linux-verified/verification.json`; exact scopes/probes are in `coverage-audit.md`.
The seventeen additions after candidate 21 now pass combined CI: maintenance/HRV, Data imports,
backup status/cadence refusal, Status readers and SQLite event/mirror refusal/retry. The nine
later Today/Train/reminder-reader controls pass locally and reached 45 candidate-22 misses in
that source. A separate event-write error-observation repair changes two orchestration sources;
four new refusal/retry controls pass, and the unchanged original negative source now passes.
Its three-file targeted cohort passes 14 checks; all thirteen additions pass combined candidate 23.
Seven further clock controls and six import-encoding controls pass combined candidate 24,
alongside locally passing unchanged original private failure sources. The
legacy clock augmenter honors the protocol's revision guard; journal UTF-8 decoding now reports
format errors separately from I/O errors so the existing vendor route can run. Both preserve
source data/current policies; candidate 23 predates those repairs. No full suite or encryption worker
runs locally.

Candidate 22's source/root is protected by verified `cov48-ci22-state-all-refs.bundle`
(42,708,917 bytes; SHA-256 `0e6c1e6c59531113ebb3127e54a4c5d5f3203a23cd21ea92c1c31664c615dc28`).
Before push, scoped collection/check and independent content hashes verified 10,700 files;
all 37 prior remote refs are unchanged. Its full green evidence is now downloaded and verified.
The previous local reserve checkpoint is protected by `cov48-ci22-reserve-preservation-receipt.json`
(source `6817ef2c`, verified bundle, all 203+4 hashes, 134 loose originals and 36 captures).
The scoped vault/content check verified 10,761 files before this continuation. Later repair,
tests/docs, green downloads and the re-armed automation require a fresh verified bundle/vault
receipt. Previous checks never cover newer bytes automatically.
Parentless candidate 23 is `134af85f63b972b942c0145e062f5250a0759625`, source `c6eb0659`,
tree `e98360be360a63d50a96ff82629a2de5f73d78e4`. Its full run passes 5,047 app checks.
Its verified all-ref bundle is `cov48-ci23-state-all-refs.bundle`
(42,725,689 bytes; SHA-256 `4479807dab517df68c3e193993877ff33f941cd618ccf8d6510c1e7c97151bad`).
Before push, scoped collection/check and independent content hashes verified 11,522 files,
including candidate 22's green evidence and the re-armed single-occurrence task. All 38 prior
remote refs are unchanged; only candidate 23 was added. Later source/docs/evidence require a
fresh continuation bundle/vault receipt; an old receipt never covers newer bytes automatically.
Parentless candidate 24 is `748043621cd8af6b6fc0cb73e2140886d353214f`, source `9ad6257c`,
tree `c7fab97b8f221975b171bddc3ec4313c7a358d14`, passing Linux run 40858887923 with
5,060 checks. Its verified bundle is `cov48-ci24-state-all-refs.bundle`
(42,743,108 bytes; SHA-256 `26876e45c972c17cf7254d6ba3906537acef86e7135462519a3888948282aa44`).
Scoped collection/check and independent vault hashes verified 11,552 files before that push;
all 39 prior remote refs remain unchanged. Subsequent source/docs/evidence need another receipt.
Candidate 25 is parentless `af64d24729341baed1d5737661eb232340d572ea`, source `c099eec1`,
tree `c993ef80fe81859d0eacdfb4bd7f6a95a8845bdd`, running full Linux run 40862004211. Its
5,075 app checks pass. The verified `cov48-ci25-state-all-refs.bundle`
is 42,750,778 bytes (SHA-256 `ce4033b1879d295ab6bca2ac42bd23554488f8764f3c2d678ac8d2190d960806`).
Pre-push scoped collection/check and independent vault hashes verify 12,336 files, including
the green candidate-23 downloads and original notification failure. All 40 prior refs remain.
Later tests/docs and run receipts require a fresh preservation checkpoint before leaving work.
Candidate 26 is parentless `5c71cee13b5a48b14d99c9ea70d22c682f2d2986`, source `57dc6167`,
tree `3670a79b511804231650705efe0446f40138036e`, passing full Linux run 40865029877 with
5,090 checks. Its verified `cov48-ci26-state-all-refs.bundle` is 42,757,839
bytes (SHA-256 `4121b3d62b8e8a9d55178c818d22ba882cf83845e24c8cbf226039d2a6d595dc`). Pre-push
scoped collection/check and independent vault hashes verify 13,134 files, including the full
green candidate-24 downloads. All 41 prior refs remain unchanged. Later freshness repair,
tests/docs and evidence need a new local-only checkpoint; an old bundle does not cover them.
Candidate 27 is parentless `12f4c8ffb9bd00276e235ace9380424a6c2a7c05`, source `4c497ca8`,
tree `6c5d64a6eaae5080d1e9aacf38e02a32fa4fc371`, running full Linux run 40867718870. Expected
5,102 checks remain unverified. Its verified `cov48-ci27-state-all-refs.bundle` is 42,777,544
bytes (SHA-256 `8ad72e5bf273811be09a7f9b33c78d808810fc51745abc403770afe9a9daf28e`). Pre-push
scoped collection/check and independent vault hashes verify 13,175 files, including the
re-armed single-occurrence follow-up. All 42 earlier remote refs remain unchanged. Later green
candidate-25 downloads, tests/docs and evidence require a new preservation checkpoint.
All prior bundles, failed-run evidence, caches and local preservation refs remain retained.
Main, tags, native/IPA, migration N, phone acceptance and B5 gates remain unchanged/open.

The outgoing gate rejected an invalid Windows-1252 dash in a generated setup document before
candidate 20 was pushed. The corrected document is UTF-8 with LF; an intermediate doubled-CR
conversion was also corrected before publication. All earlier bytes/roots remain in local-only
archives, including `preserve/ci20-text-normalization`; never push that ref. Generate documents
with explicit UTF-8 byte writes and deliberate newline normalization, not Windows defaults.

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
COV-47/COV-48. COV-48's later event-write observation is a scoped reliability repair, not a
coverage-only behavior-neutral change. Older COV-44–46 evidence remains in its owning verified receipts.

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

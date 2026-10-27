# Coverage verification

**Status:** Full Linux verification passes on parentless `6abc7821`, including all nineteen
COV-42 controls. Handwritten execution is 84.45%; 7,827 instrumented lines remain unexecuted
at that checkpoint. COV-43 and approved Food A have targeted verification; combined coverage
and native/phone acceptance remain open. Native/IPA builds remain held.

## Current verified checkpoint

Run [40466294191](https://github.com/akshatksingh18/whoop/actions/runs/40466294191), candidate
`6abc78219555860372d8a4c6a00c200682e75a91` on `ownership-ci-candidate-6`, tree
`06c9fc4b1e18755fdb14ca0b7cb131c6d4d10a23`, local source `72bfaca4`:

- App analysis and all source/personal iOS contracts passed (19 Python checks plus guards).
- App: 4,196 passed, 430 explicit skips. That run includes the known Food large-text skip,
  separate from unavailable goldens/recordings. Approved A now enables and passes that case
  locally; the next combined run must verify it too.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Synthetic pages: 213 checks and 708 captures, passed. These are authored examples.
- Handwritten execution: 42,519/50,346 (84.45%), 7,827 unexecuted. All 203 source hashes were
  verified after CRLF normalization before COV-43/Food implementation. Those two edited sources
  no longer match this inventory; refresh their ranges from the next combined run. COV-42
  executes 60 additional lines versus COV-41; the denominator is unchanged.

The exact LCOV, source hashes and uncovered ranges are in ignored
`build/coverage-continuation/6abc7821/`; verified recovery copies and the result receipt are in
`build/ownership-checkpoint/cov42-complete-linux-verified/`. Generated and unimported sources remain
visible in the inventory. The denominator is not filtered to improve the number. Constant/
export-only files without instrumented lines are reported separately, not counted as executed
by an import.

Only reviewed parentless CI candidates have been published, with public-safe commit identity.
The private preservation branch, archives and original captures remain local. GitHub main,
existing branches and tags have not been replaced or deleted. Prior failed/cancelled run details,
older inventories and exact reference records remain in local recovery evidence.

## Completed coverage batches and storage repair

COV-01–42 have combined Linux verification. COV-36–39's 112 controls cover nested Food, workout
summary/live details, Train, Progress, Body, Pushups and Settings. This closes their combined
verification task, not every remaining branch in those files.

COV-40 adds nine synthetic SQLite regressions for ledger fields/statuses, interrupted copies,
quarantine deduplication, cursor normalization and idempotent reopen. They exposed two existing
repair defects: a current cursor writer could run before repairing an old table, and an
ambiguous quarantine copy could lose uncopied legacy rows. The shared writer now repairs the
cursor first; a populated non-keyed quarantine destination retains its legacy table unchanged.
Both versions survive reopening without a guessed merge or duplicate inserts. The entire
25-case migration-ladder file passes locally and in the full cloud suite. Retained evidence
survives whole-file DB snapshots; automatic reconciliation/import of ambiguous rows is not
claimed. This is separate from build N's still-unimplemented persisted-name migration.

The nine approved private-capture substitutions and copied call sites use independent authored
inputs. `privacy-fixture-review.md` owns their original-file retention, synthetic provenance,
optional private replay and evidence limits. Public synthetic cases do not establish empirical
sensor validity. Algorithm 99, schema 50, approved coefficients and metadata are unchanged.

## COV-41: verified controls and open layout acceptance

Three new files exercise existing Food day/history/library actions, manual activity review and
nap corrections against authored SQLite data: `coverage_food_history_test.dart`,
`coverage_manual_activity_actions_test.dart` and `coverage_nap_actions_test.dart`. They assert
read/retry versus empty state, historical dates, persistence after reopen, filtered reordering,
refused mutations, cancellation, disabled actions, honest unscored workouts, nap overlap/future/
DST rules and saved corrections independently of recalculation. Only repository failure/latency
and recalculation boundaries are substituted. Reorder callbacks do not certify drag gestures.

Targeted execution passes 38 new cases (14 Food, 12 manual activity, 12 nap controls). Targeted
analysis covers just these three files; whole-project analysis and combined tests also pass on CI.
The 3.1x Food day-page case exposed a 150 px meal-heading overflow at 430 px width and
was explicitly skipped in that original batch. Full-page review also found clipped unknown
energy and awkward date wrapping. Akshat has now approved A; the implementation and enabled
regression pass targeted checks below. The old green run alone never established that fix.

The reviewed parentless candidate is `22c733dd87422d2610e31fadafa06b6f1922b5fb` on
`ownership-ci-candidate-4`, tree `104132131c60419c84030f2cf74291e64084e786`, local source
`9e16d54b`. Full run [40455040866](https://github.com/akshatksingh18/whoop/actions/runs/40455040866)
passes all Linux jobs. Its downloaded LCOV/gap inventory and source-hash verification are
preserved in `build/ownership-checkpoint/cov41-linux-verified/`.
The three new files pass targeted analysis with no issues.

No executable Dart implementation or physiological method changes in this batch. Related
source headers now describe current behavior without old private/reference examples. The full
Linux app job gets a 45-minute timeout because setup plus its instrumented suite already takes
about 29 minutes; analysis/full tests still run in the cloud, not on this laptop.

## Remaining work

`todo.md` 3r owns batch sequencing. Work in related groups of about 1,000 remaining executable
lines and retain real assertions for refusal/retry, cancellation, stale results and mutations.
COV-41 covers Food history/diary/library, manual activity review and nap corrections, a group
with 1,013 unexecuted lines across six sources at COV-40. Other branches remain uncovered.
COV-42's nineteen controls pass full Linux verification. Eight refused-write/retry cases in
`coverage_derivation_stop_test.dart` cover ordinary sweeps, selected days, imported days and
recent rescans against real SQLite refusals in `day_result` or `metric_series`: no partly
published transaction, retryable error markers, retained input, released engine and same-engine
retry. Eight in `coverage_ble_durable_boundary_test.dart` drive real frame routing/SQLite with
only GATT replaced: ACK exhaustion/quarantine/recovery, empty-sync escalation/productive clearing,
refused COMPLETE tail retention/retry and gen5 short-count refusal. Three in
`derive_result_protection_test.dart` preserve authoritative fresh null/zero/empty blocks,
independent restored maps and honest absence for missing/malformed old blocks. These cases do
not certify physical BLE delivery or induced worker-crash behavior.

## COV-43: targeted checkpoint preservation and approved Food A

Nine new cases in `coverage_connection_lifecycle_test.dart` exercise actual AppState recovery
with authored checkpoints and real SQLite: local-midnight splitting, current/legacy formats,
invalid spans, replay without duplicate gain, refused first/second segment, reconnect/retry,
empty-stream finalization, replacement by a new counting minute and growing-run ordering.
Two existing data-loss paths were reproduced: empty finalization erased a refused orphan
checkpoint, and a new minute replaced it. Shared clearing/replacement now uses the existing
single-flight idempotent recovery and leaves refused bytes intact. Older recovery runs before
the latest publication/final bank so a shorter snapshot cannot overwrite a longer count.
The synchronous counter reset is retained before finalization I/O to protect a new connection.
No step coefficient, checkpoint key/format, algorithm/schema or metadata changes.

This batch does not close AppState/workout coverage. Follow up the separately identified
current-tail refusal/retry boundary together with disconnect/reconnect generation ownership;
a private draft is retained rather than shipping an unverified reset-after-I/O change.
Then cover typed workout save/retry and pause/finish handoff using existing seams.

Akshat approved Food option A in `food-layout-review.md`. Ordinary headings remain compact;
above the existing 1.3x threshold meal totals stack and the date picker gets its own row.
Unknown-energy text wraps; numeric values, copy, historical dates and all actions remain.
Five historical Food cases pass at 390/1x, 430/1.3x, 430/1.31x, 320/2x and 430/3.1x, including
the retained regression. Two historical navigation/re-read controls pass, at ordinary and 3.1x text. Three actual
complete-page captures are pixel-identical to the approved A previews, including ordinary size.
They use authored data and Manrope instead of native SF; they do not prove phone/VoiceOver.
Targeted analysis reports existing info-only brace notices, no warnings/errors. Full Linux
verification of COV-43/Food A remains pending; no updated combined coverage number is claimed.

Largest current gaps include BLE engine (633), AppState (605), derivation (418), workout screen
(307), nutrition screen (250), food diary (209), Home (220), repository implementation (204),
Progress (199) and live activity (185). Use the exact ranges and matching source hashes above;
do not treat a percentage, an import or a synthetic capture as every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

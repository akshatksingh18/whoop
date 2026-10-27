# Coverage verification

**Status:** Full Linux verification passes on parentless `be12dbbc`, including the first eight
COV-42 controls. Handwritten line execution is 84.38%; 7,866 instrumented lines remain
unexecuted. Coverage and the remaining COV-42 controls stay open; native/IPA builds remain held.

## Current verified checkpoint

Run [40460881603](https://github.com/akshatksingh18/whoop/actions/runs/40460881603), candidate
`be12dbbc795fcdbf4d2f3b206dfd19436a6aaed6` on `ownership-ci-candidate-5`, tree
`f3fb8f1d8b225588b705d1515ddeea92072bbac9`, local source `09f845c6`:

- App analysis and all source/personal iOS contracts passed (19 Python checks plus guards).
- App: 4,185 passed, 430 explicit skips. One skip is the known Food large-text layout defect,
  separate from unavailable goldens/recordings. Passing CI does not resolve that acceptance case.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Synthetic pages: 213 checks and 708 captures, passed. These are authored examples.
- Handwritten execution: 42,480/50,346 (84.38%), 7,866 unexecuted. All 203 inventory source
  hashes match the current production source after CRLF normalization. The first eight COV-42
  controls execute 21 additional lines compared with COV-41; the denominator is unchanged.

The exact LCOV, source hashes and uncovered ranges are in ignored
`build/coverage-continuation/be12dbbc/`; verified recovery copies and the result receipt are in
`build/ownership-checkpoint/cov42-linux-verified/`. Generated and unimported sources remain
visible in the inventory. The denominator is not filtered to improve the number. Constant/
export-only files without instrumented lines are reported separately, not counted as executed
by an import.

Only reviewed parentless CI candidates have been published, with public-safe commit identity.
The private preservation branch, archives and original captures remain local. GitHub main,
existing branches and tags have not been replaced or deleted. Prior failed/cancelled run details,
older inventories and exact reference records remain in local recovery evidence.

## Completed coverage batches and storage repair

COV-01–41 have combined Linux verification. COV-36–39's 112 controls cover nested Food, workout
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
One new 3.1x Food day-page case reproduces a 150 px meal-heading overflow at 430 px width.
It stays explicitly skipped while full-page before/after layout review is open; this is a
known failing acceptance case, not fixed behavior. `food-layout-review.md` has complete Before/A/B
previews and the pending approval gate. Full-page inspection also exposed clipped unknown-energy
text and awkward date wrapping; both are included in the proposal, not changed in production.
Do not hide that skip among unavailable goldens or declare the whole area complete.

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
COV-42 targets BLE state/transfer and derivation refusal/retry boundaries (1,086 unexecuted
lines across the two sources at the current checkpoint). Eight refused-write/retry controls in
`coverage_derivation_stop_test.dart` pass full Linux verification: ordinary sweep, selected
days, imported days and recent rescan, each against a real SQLite refusal in `day_result` or
`metric_series`. They assert no partly published metric transaction, retryable rather than
finalized error markers, retained input, released engine and successful same-engine retry.

Eleven additional targeted controls pass locally in `coverage_ble_durable_boundary_test.dart`
and `derive_result_protection_test.dart`. Eight drive real frame routing, decoding and SQLite
with only GATT substituted: repeated ACK exhaustion, per-token quarantine and later recovery
without deleting evidence or duplicating decoded rows; completed empty-sync escalation and
productive recovery; refused COMPLETE tail retention/retry; and gen5 short-count redelivery or
terminal failure with data retained and no premature trim. Three pin the shared partial-result
recovery contract: fresh null/zero/empty results remain authoritative, restored scalar maps do
not alias the source map, and missing/malformed old blocks do not manufacture recovery.

All eleven additions pass targeted checks, and both changed files pass targeted analysis
with no issues; combined Linux verification remains open. These
are authored inputs, not physical BLE delivery or induced worker-crash proof. They preserve
all production calculations, schema/version and UI. The Food proposal stays separately gated.

Largest current gaps include BLE engine (654), AppState (605), derivation (432), workout screen
(307), nutrition screen (250), food diary (209), Home (220), repository implementation (204),
Progress (199) and live activity (185). Use the exact ranges and matching source hashes above;
do not treat a percentage, an import or a synthetic capture as every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

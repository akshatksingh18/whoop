# Coverage verification

**Status:** Full Linux verification passes through COV-41 on parentless candidate `22c733dd`.
Handwritten line execution is 84.33%; 7,887 instrumented lines remain unexecuted. Remaining
coverage work stays open, and native/IPA builds remain held.

## Current verified checkpoint

Run [40455040866](https://github.com/akshatksingh18/whoop/actions/runs/40455040866), candidate
`22c733dd87422d2610e31fadafa06b6f1922b5fb` on `ownership-ci-candidate-4`, tree
`104132131c60419c84030f2cf74291e64084e786`, local source `9e16d54b`:

- App analysis and all source/personal iOS contracts passed (19 Python checks plus guards).
- App: 4,177 passed, 430 explicit skips. One skip is the known Food large-text layout defect,
  separate from unavailable goldens/recordings. Passing CI does not resolve that acceptance case.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Synthetic pages: 213 checks and 708 captures, passed. These are authored examples.
- Handwritten execution: 42,459/50,346 (84.33%), 7,887 unexecuted. All 203 available inventory
  source hashes match the current checkout after CRLF normalization. Compared with COV-40,
  276 additional lines execute; the denominator increases by one. Use this matching inventory.

The exact LCOV, source hashes and uncovered ranges are in ignored
`build/coverage-continuation/22c733dd/coverage/`; recovery evidence is also retained beneath
`build/ownership-checkpoint/`. Generated and unimported sources remain visible in the inventory.
The denominator is not filtered to improve the number. Constant/export-only files without
instrumented lines are reported separately, not counted as executed by an import.

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
The next group targets BLE state/transfer and derivation refusal/retry boundaries (1,107 current
unexecuted lines across those two sources); inspect actual gaps and reuse existing seams.
COV-42 has begun with eight targeted refused-write/retry controls in
`coverage_derivation_stop_test.dart`: ordinary sweep, selected days, imported days and recent
rescan, each against a real SQLite refusal in `day_result` or `metric_series`. They assert no
partly published metric transaction, retryable rather than finalized error markers, retained
input, released engine and successful retry on the same engine after removing the refusal.
All eight pass locally and the changed test file passes targeted analysis; combined Linux verification and the remaining BLE/derivation gaps stay
open. These extend the existing cancellation tests without changing production calculations.
The UI proposal stays gated while independent coverage continues.

Largest current gaps include BLE engine (654), AppState (605), derivation (453), workout screen
(307), nutrition screen (250), food diary (209), Home (220), repository implementation (204),
Progress (199) and live activity (185). Use the exact ranges and matching source hashes above;
do not treat a percentage, an import or a synthetic capture as every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

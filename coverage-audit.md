# Coverage verification

**Status:** Full Linux verification passes through COV-40 on parentless candidate `48339d48`.
Handwritten line execution is 83.79%; 8,162 instrumented lines remain unexecuted. Remaining
coverage work stays open, and native/IPA builds remain held.

## Current verified checkpoint

Run [40449039544](https://github.com/akshatksingh18/whoop/actions/runs/40449039544), candidate
`48339d4881afc319e938bf4b4ecfa7c65b730f9d` on `ownership-ci-candidate-3`, tree
`1da87695f54a5f30a9b1faa8c28a9b260716ee9b`, local source `c13a2149`:

- App analysis and all source/personal iOS contracts passed (19 Python checks plus guards).
- App: 4,139 passed, 429 explicit skips. The three stale synthetic-profile expectations are
  corrected and pass. Skips remain explicit; unavailable goldens/recordings are not new proof.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Synthetic pages: 213 checks and 708 captures, passed. These are authored examples.
- Handwritten execution: 42,183/50,345 (83.79%), 8,162 unexecuted. Handwritten source hashes
  were verified against the COV-40 checkout. COV-41 adds tests and rewrites comments in three
  source files, so their old line numbers/hashes must not be applied to the new source blindly.

The exact LCOV, source hashes and uncovered ranges are in ignored
`build/coverage-continuation/48339d48/coverage/`; recovery evidence is also retained beneath
`build/ownership-checkpoint/`. Generated and unimported sources remain visible in the inventory.
The denominator is not filtered to improve the number. Constant/export-only files without
instrumented lines are reported separately, not counted as executed by an import.

Only reviewed parentless CI candidates have been published, with public-safe commit identity.
The private preservation branch, archives and original captures remain local. GitHub main,
existing branches and tags have not been replaced or deleted. Prior failed/cancelled run details,
older inventories and exact reference records remain in local recovery evidence.

## Completed coverage batches and storage repair

COV-01–40 have combined Linux verification. COV-36–39's 112 controls cover nested Food, workout
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

## COV-41: current continuation

Three new files exercise existing Food day/history/library actions, manual activity review and
nap corrections against authored SQLite data: `coverage_food_history_test.dart`,
`coverage_manual_activity_actions_test.dart` and `coverage_nap_actions_test.dart`. They assert
read/retry versus empty state, historical dates, persistence after reopen, filtered reordering,
refused mutations, cancellation, disabled actions, honest unscored workouts, nap overlap/future/
DST rules and saved corrections independently of recalculation. Only repository failure/latency
and recalculation boundaries are substituted. Reorder callbacks do not certify drag gestures.

Targeted execution passes 38 new cases (14 Food, 12 manual activity, 12 nap controls). Targeted
analysis covers just these three files; whole-project analysis and combined tests remain on CI.
One new 3.1x Food day-page case reproduces a 150 px meal-heading overflow at 430 px width.
It stays explicitly skipped while full-page before/after layout review is open; this is a
known failing acceptance case, not fixed behavior. `bugs.md` and `todo.md` own the repair gate.
Do not hide that skip among unavailable goldens or declare the whole area complete.

No executable Dart implementation or physiological method changes in this batch. Related
source headers now describe current behavior without old private/reference examples. The full
Linux app job gets a 45-minute timeout because setup plus its instrumented suite already takes
about 29 minutes; analysis/full tests still run in the cloud, not on this laptop.

## Remaining work

`todo.md` 3r owns batch sequencing. Work in related groups of about 1,000 remaining executable
lines and retain real assertions for refusal/retry, cancellation, stale results and mutations.
The current COV-41 group covers Food history/diary/library, manual activity review and nap
corrections: 1,013 unexecuted lines across six sources at the COV-40 checkpoint, not a promised
coverage gain. Its new execution total awaits the next combined Linux inventory.

Largest current gaps include BLE engine (654), AppState (605), derivation (453), workout screen
(307), nutrition screen (301), food diary (292), Home (220), repository implementation (204),
Progress (199) and live activity (185). Use the exact ranges and matching source hashes above;
do not treat a percentage, an import or a synthetic capture as every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

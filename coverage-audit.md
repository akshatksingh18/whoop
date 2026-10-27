# Coverage verification

**Status:** Combined Linux candidate `998d77af` ran completely but failed three stale UI
expectations after the synthetic profile change. Packages, analysis and page captures passed.
A corrected green rerun and remaining coverage work are open; native/IPA builds stay held.

## Current candidate measurement

Run [40426922312](https://github.com/akshatksingh18/whoop/actions/runs/40426922312), parentless
`998d77afa02c1a65c6daf151144697e409546a8b`, tree
`493e6557d62c8b5d63892c9b48a1a8d40a2559e7`, local source `2ab7577f`:

- App: 4,127 passed, 429 explicitly skipped, three failed. The failures expect old profile
  calorie labels in `ui2_food_flow_test.dart` and two `build73_details_test.dart` checks. The
  synthetic 72.5 kg profile expects 237 kcal for 10,000 steps, 154 for 6,500 and 119 for 5,000.
  Production calculations are unchanged. All three corrected checks pass in a 15-second
  targeted local probe; a green full cloud rerun is required.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Analysis and source contracts passed. Synthetic page job: 213 checks, 708 captures, passed.
- Handwritten execution: 42,143/50,345 (83.71%), 8,202 unexecuted. This is a complete inventory
  from a failed run, not a green verification checkpoint. Source hashes/ranges are in ignored
  `build/coverage-continuation/998d77af/coverage/gaps.json`; keep all generated and unimported
  sources visible in the inventory. Renames/source changes alter the denominator, so do not
  report the percentage delta as pure new execution.

The reviewed outgoing tree contained 825 files (13,687,636 bytes), with no preservation-history
ancestors. Only the candidate branch was pushed; main/tags/old branches remain unchanged.

## COV-40: sync-state repair

Nine added synthetic SQLite regressions cover ledger fields/statuses, table-copy interruptions,
quarantine copy/deduplication, cursor normalization and idempotent reopen. They exposed two
pre-existing defects: the body-reading seed could write a current cursor field before repairing
an old table, and a populated quarantine destination caused an ambiguous legacy copy to be
removed even when it was incomplete.

The shared seed now invokes the existing cursor repair first. A non-keyed quarantine copy with
a populated destination retains its legacy table unchanged; it neither guesses a merge nor
duplicates rows. Both old and new tables survive reopening. This preserves evidence in the DB
and its whole-file snapshots; automatic reconciliation/import of ambiguous rows is not claimed.
No physiological formula, algorithm version, schema version or persisted-name identity changed.
The full targeted migration-ladder file passes 25 checks in four seconds, including nine new
cases. The old implementation fails the cursor and ambiguous-copy regressions. Combined Linux
verification and a new coverage inventory are still required; the measurement above predates
these source changes.

## Last green baseline

The following numbers describe the pre-rename tree, not the current source.

At `e88fde29`, run [40189878355](https://github.com/akshatksingh18/whoop/actions/runs/40189878355)
passed 4,018 app tests, both package suites, 13 Python controls and 213 visual checks/709 captures.
Handwritten execution: 41,181/50,310 (81.85%), 9,129 unexecuted. Later COV-36–39 adds 112
targeted controls but still needs combined verification. Earlier COV-01–35 repairs stay complete.
The exact earlier inventories and findings remain in the private pre-fresh-start archive.

Ownership cleanup has passed three targeted Dart files (91 cases: automatic backup, import
container and DB serve/version/read controls) and 14 targeted Python controls (personal iOS
contract and internal algorithm source guard). No full suite or native build ran on this laptop.
A further 61 targeted synthetic calorie/lifting checks pass across five affected files (26
run/walking controls and 35 maintenance/lifting/UI controls). No full suite ran locally.
Three protocol files pass 21 tests with retained local captures; the public configuration
passes 7 and explicitly skips 14 capture-dependent tests. The generated synthetic fixture has
31 byte-contract cases plus 26 named packets and passes its reproducibility check. All nine
approved substitutions, their copied call sites and the remaining recorded nightly/battery/
readiness samples now use authored inputs. `privacy-fixture-review.md` owns targeted results,
retained local original-suite checks and the full content/history review boundary. No new
green Actions result is claimed for the current candidate; its actual failed-run results are
above. Do not combine overlapping checks or private empirical replay with public synthetic
execution coverage.
These checks prove neither migration N nor hardware behavior. `todo.md` 3r owns continuation.

Run `test.yml` on a privacy-reviewed tree for full app analysis/tests/coverage, independent
protocol/analytics tests and synthetic full-page captures. `tool/coverage_gaps.py` inventories
uncovered ranges, source hashes, generated/unimported sources and handwritten execution.
Preserve the full denominator; do not remove inconvenient files or call an import execution.
Review assertions and behavior in related batches rather than optimizing only a percentage.

Native Swift, actual notification delivery, BLE restoration/ACK durability on a real band,
GPS/camera/keyboard/VoiceOver, signing renewal, 72-hour soak and measurement validity require
their own evidence. Mocked channels and synthetic captures do not replace those checks.
Golden baselines and real replay recordings remain private/unavailable to public CI; report
intentional skips honestly. Native/IPA builds remain on hold until coverage completion.

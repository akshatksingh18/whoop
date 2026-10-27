# Coverage verification

**Status:** Ownership renames and the larger coverage batch await combined full Linux CI.
The numbers below are the last measured pre-rename baseline, not a current-tree claim.

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
Actions result is claimed before the candidate run finishes; do not combine overlapping checks
or private empirical replay with public synthetic execution coverage.
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

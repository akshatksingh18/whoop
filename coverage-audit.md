# Coverage-directed audit

**Status:** Active review of the unexecuted and unimported paths in validated Build 99, on
`build-100`. Build 99 remains the testing IPA; no successor behavior or coverage gain is claimed.

## Baseline and reuse

The baseline is app source `e52d571a`, verified by `18324f76` in run `40003142620`.
Root LCOV exercises 37,534/49,891 instrumented handwritten Dart lines (75.23%): **12,357
instrumented lines were not executed**. Five handwritten files were not imported at all.
This is execution coverage, not the proportion of source reviewed. It excludes native iOS
and independent package suites, and does not measure branch correctness or physical delivery.

Reuse the repair contracts and passing tests in `build-98-audit.md`, `build-97-audit.md`,
`build-96-audit.md` and `build-95-repairs.md`. Revisit their implementation only where an
unexecuted sibling/failure path or changed dependency exposes a new question. Do not repeat
the previous broad screen sweep or count a previously passing test as a new regression.

`tool/coverage_gaps.py` records all uncovered line ranges, unimported files and source hashes
from an LCOV artifact. Generated output belongs in ignored `build/coverage-audit/`; unchanged
source hashes allow review evidence to carry forward. A changed hash requires checking the
affected paths again. No exclusions or no-op calls may be added just to improve the percentage.

## Remaining work

- [ ] Entrypoint/error logging and low/zero-coverage host-independent helpers: trace startup
  bounds, handler chaining, failures, retained writes and cold retry.
- [ ] Background/native bridges: exercise shared gate collisions, timeout/error release,
  foreground handoff and expiration through synthetic channels; separately source-review Swift.
- [ ] AppState's uncovered orchestration: initialization, foreground/background transitions,
  connection/save failure, clock/resume and refresh dependencies.
- [ ] Secondary editors/settings/data actions: Lift Log, manual sessions, summary corrections,
  Food/Body/Progress dialogs, cancel/save/retry, late results and native permission return.
- [ ] BLE/derivation/repository uncovered branches: retention/finalization, partial inputs,
  decode/commit failures and publication; preserve scientific coefficients and ACK ordering.
- [ ] Remaining small uncovered regions: map each to existing proof, added proof, dormant
  personal-build code, defensive unreachable input, or a specific physical/private-fixture gate.
- [ ] Run targeted synthetic checks and full cloud coverage; compare against the baseline and
  report denominator changes, remaining gaps and every confirmed finding honestly.

## Confirmed findings and targeted evidence

- **COV-01 — restoration expiry omits the transport stop.** Native sends `expire`, but the
  Dart callback stops only calculation. The synthetic registered headless stop remains
  uncalled before the fix. The callback now requests the same lease-owned transport stop as
  BG-task expiry. Its entrypoint is shared by registration and the synthetic channel checks.
- **COV-02 — the headless ceiling releases ownership without asking transport to stop.**
  The five-millisecond synthetic ceiling reproduces the omitted callback. Request cooperative
  stop before forced lease release; retain token protection against a late old completion.
  This does not prove native disconnect completion or shorten the production ceiling.
- **COV-03 — diagnostics can remain silent after an initialization/handler failure.** A
  temporary path-provider failure latches FileLog unavailable for the process. A throwing prior
  FlutterError handler also prevents the current error from reaching the file. Both failing
  controls now pass: directory lookup retries, and logging precedes the chained handler.
- **COV-04 — concurrent Pushups actions overwrite the shared inbox.** Twelve simultaneous
  background callbacks retain only one action before the fix. Each delivery now publishes its
  own atomic file; legacy arrays remain readable, receipt IDs deduplicate replay, and reset
  clears the owned directory. Malformed input is retained and reported rather than read as
  empty. Lifecycle reconciliation logs its failure; the Pushups screen retains its Retry state.
- **COV-05 — linked Lift edits can commit only their split.** Refusing the workout insert
  after the split write changes the reusable split despite the failure message. Add, remove
  and split-sync controls reproduce all three paths. One transaction now owns both records;
  preference mirrors and controller state change after commit. All three controls pass.
- **COV-06 — a picker returns to a disposed workout editor.** Date, start, end and activity
  pickers all call setState after their editor is removed. Four failing navigation controls
  now pass with mounted guards; suggestion-adjust return and onboarding's file-picker return
  use the same guard. No feature or layout changes.
- **COV-07 — onboarding advances after a refused preference write.** Both New and Imported
  ignore the platform's false acknowledgement. The shared acknowledged preference writer now
  owns the choice before the route advances. Setup reports failure and remains retryable;
  an already-imported history keeps its successful report if only setup continuation fails.
- **COV-08 — historical workout corrections use today's time zone.** The form displays and
  reconstructs saved instants in the current OS zone; date/start/end controls reproduce shifts,
  including a DST seam. It now shares the existing recorded-day wall-clock resolver with Food.
  Untouched instants stay exact, repeated hours use the nearby occurrence, and nonexistent
  clocks are refused without altering the form. This changes explicit edits, not stored history
  or analytics formulas; algorithm 99 remains appropriate.

- **COV-09 — expiry during transfer permits a fresh calculation.** An expired BG wake can
  return from transfer and create an engine with the new cancellation generation. The wake
  now retains its starting generation and checks it after transfer/profile loading and before
  a rescan. A held-transfer/expiry control confirms that no calculation starts afterward.
- **COV-10 — a storage read that never answers leaves startup spinning.** Initialization now
  shares the existing six-second startup bound and presents Retry. A retry joins the same
  pending initialization instead of creating a competing one; late success can recover the
  route. This bounds the UI wait, not the native operation itself. The held-read control and
  existing startup/quarantine controls pass.
- **COV-11 — a Zones read failure masquerades as missing measurements.** The deeper
  Train → Strain → Zones page now shows a retryable read failure rather than empty age/ceiling
  guidance. Retrying a repaired repository displays the measured values.
- **COV-12 — enlarged Zones ranges overflow.** Measured range/unit rows now reflow beneath
  their labels at enlarged text, preserving standard-size composition and the locked palette.
  Full-scroll controls pass at 1× and 3.1×; cloud captures cover both and the read-failure state.
- **COV-13 — an optional Lift refresh falsely reports a committed save as unsaved.** An
  unreadable earlier log reproduces the misleading failure after a new set is durable. The
  controller now distinguishes save failure from refresh failure, retains a saved warning and
  still starts the chosen rest timer. A subsequent clean edit clears the warning. Initial
  history failures remain explicit. Linked split/import cache hydration is best-effort only
  after commit; ordinary startup hydration remains strict and logs the post-commit failure.

Thirteen added Dart files contain **52 targeted cases** for these contracts, real cold-start
routing with an optional notification failure, and GPS service/permission/sample boundaries.
The GPS checks use simulated plugin results, not physical location delivery. Existing manual
workout (11), startup/quarantine (7) and three legacy failure/cancellation cases also pass.
Four Python inventory checks and eight iOS contract checks pass. Fixture/compiler failures
are not counted as app findings. Logs stay in ignored `build/coverage-audit/`.

The first full cloud run, [40015378904](https://github.com/akshatksingh18/whoop/actions/runs/40015378904),
passed analysis, package suites and the original visual job, but the app suite had three old
fixtures without an application-support path provider. The stricter Pushups inbox correctly
surfaced that missing fixture. Those fixtures now supply a synthetic path, retain their
original assertions and pass all three targeted cases. A clean full rerun is still required;
coverage from the failed run is preliminary, not successor verification.

## Limits

Keep the locked A+B interface and all features. No scientific tuning, dependency/capability
change, live-data fault injection or private export is authorized by a coverage target. Native
radio/GPS/audio/permission delivery, signing and soak still need the iPhone. Synthetic native
channel checks establish app reactions, not what iOS or the band physically did. Pure constants,
barrel exports, generated strings and dormant upstream-era screens must not be called tested
user flows. A 100% headline is not a substitute for these distinctions.

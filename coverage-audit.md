# Coverage verification

**Status:** COV-46's authorized three reliability fixes and new coverage controls are implemented;
combined Linux verification and measured delta are pending. COV-45 below remains the verified
baseline: 87.92%, with 6,086 unexecuted instrumented lines. The three known UI regressions are
now enabled locally; the existing enlarged name-helper truncation remains separate. Native/IPA
builds remain held.

## Current verified checkpoint

Run [40585719502](https://github.com/akshatksingh18/whoop/actions/runs/40585719502), candidate
`7ad4687f705cfff205c888e78312c2d3ea5e1c91` on `ownership-ci-candidate-10`, tree
`9e629c7ce8d900d6045041454fa1f55772dba9b2`, local source `1b443349`:

- App analysis and source/personal iOS guards pass: zero warnings/errors, 303 info notices.
- App: 4,549 passed, 432 explicit skips; all 52 new controls pass. At that baseline, three known UI regressions
  were explicitly skipped; the approved Food large-text regression stays enabled and passes.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Synthetic pages: 213 checks and 708 authored captures pass; the complete artifact is local.
- Handwritten execution: 44,285/50,371 (87.92%), 6,086 unexecuted. All 196 tracked and seven
  generated current normalized source hashes match. Against candidate 9's 44,174/50,357:
  94 matching handwritten lines gain execution, none lose it, and 17 new/modified repair lines
  execute. AppState adds 18 instrumented lines and replaces four unexecuted ones: denominator
  +14, net executed +111. Other production source hashes are unchanged. This is execution,
  not proof of every branch, native delivery or scientific validity.

Exact LCOV, source hashes, uncovered ranges and line-identity comparison are preserved in
`build/coverage-continuation/7ad4687f/` and recovery copy
`build/ownership-checkpoint/cov45-linux-verified/`, with `verification.json`.
The verified comparison maps unchanged AppState lines around the minimal startup repair;
new/modified and removed lines are accounted for separately. Earlier exact inventories remain
at `build/coverage-continuation/c640c84e/`, `build/ownership-checkpoint/cov44-linux-verified/`
and the earlier local checkpoints. The COV-44 roughly 1,500-line batch below remains verified.
Generated/unimported sources remain visible; no source is hidden to improve the denominator.
Constant/export-only files without instrumented lines do not count as executed by an import.

Only reviewed parentless CI candidates have been published, with public-safe commit identity.
The private preservation branch, archives and original captures remain local. Only candidate 10
was added; all 25 earlier GitHub refs are unchanged. Main has not been replaced and no branch or
tag has been deleted. Prior probes, inventories and exact reference records remain local.

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

## COV-41: verified controls and layout follow-up

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
regression now pass the full Linux run above. The earlier green run alone did not establish that fix.

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

This batch does not close AppState/workout coverage. COV-46 below implements the separately
identified final-tail refusal/retry boundary while preserving synchronous reset; the older
private reset-after-I/O draft remains archived and is not shipped.
Then cover typed workout save/retry and pause/finish handoff using existing seams.

Fifteen further controls in `coverage_activity_host_test.dart` exercise the shared production
activity host, SQLite and existing live shell. Twelve cover typed-detail refusal/retry, refused
final writes with staged measurements and a fixed finish, identity retained after post-stop
enrichment failure, no invented saved session, existing detail retained for an empty draft,
idempotent repeat finish, paused windows/pinned profile, absent/short/usable phone distance and
measured/missing route altitude/speed. Three cover pause/minimise/reopen/cancel and both typed-
and final-write failures through the live screen and rendered summary retry callback. Callback
execution is separated from gesture hit testing; storage runs in the widget harness's real-I/O
zone. Synthetic route points are an invented equatorial line. This does not claim hardware
GPS/phone motion, native UI acceptance or a changed physiological method.

All fifteen additions have clean targeted analysis and pass combined Linux run [40487773326](https://github.com/akshatksingh18/whoop/actions/runs/40487773326) on parentless
`aaa7c5ce8a14e22d818df4d5d657648393367ab5` (`ownership-ci-candidate-8`), tree
`8736cf280e24e608fddac64b29368d35f9e76848`, local source `99d93af4`. COV-46 separately addresses the current-tail/refused-bank follow-up. Production behavior is unchanged from candidate 7; a logger comment now accurately labels
its legacy fallback. New names and remaining phone/approval gates are reconciled in
`ownership-migration-plan.md`; no persisted identity is renamed by this coverage batch.

Akshat approved Food option A in `food-layout-review.md`. Ordinary headings remain compact;
above the existing 1.3x threshold meal totals stack and the date picker gets its own row.
Unknown-energy text wraps; numeric values, copy, historical dates and all actions remain.
Five historical Food cases pass at 390/1x, 430/1.3x, 430/1.31x, 320/2x and 430/3.1x, including
the retained regression. Two historical navigation/re-read controls pass, at ordinary and 3.1x text. Three actual
complete-page captures are pixel-identical to the approved A previews, including ordinary size.
They use authored data and Manrope instead of native SF; they do not prove phone/VoiceOver.
The first nine checkpoint controls and approved Food A passed original full run 40483497760.
Their targeted four-file analysis reports only twelve existing info-only brace notices. The
fifteen newer host/live controls also pass full run 40487773326.
All earlier remote heads/tags were verified unchanged after publishing candidate 8.

## COV-45: connection ownership and durable state controls

The source batch passes 112 checks across three targeted local files, including 52 new cases,
and all 52 additions pass the full Linux checkpoint above. The new controls span background
startup/periodic transfer,
BLE command framing and preference/history rollback. They reuse the real AppState, isolated
SQLite and existing transport/preference seams; no captured device or profile data is used.

Three startup regressions failed before the repair: a background connect returning after End,
Forget or disposal could still arm HR-only live. Background initialization now captures the
band and reconnect generation and rechecks ownership after the lease, connection, orphan replay
and pending downgrade, including its error path. Foreground takeover retires that startup.
The controls retain committed orphan steps while preventing a retired connection from arming
streams. Healthy success/refusal/error behavior stays covered. No algorithm, schema, calculation,
persisted key/format, metadata or UI changes are included. Physical restoration is not proved.

Periodic controls cover background throttling without history requests, real completion-ledger
writes, enqueue only after actual record progress, contained wake-plan failures, transfer retry,
overlap and late results. BLE controls independently assert bounded ASCII/Gen4/Gen5 opcodes,
wake-mode refusal/retry/idempotence and explicit test-only persistent-flag opt-in. Profile
controls retain previous preferences and absent/existing history on refused writes, then retry;
queued updates preserve prior successful fields. Persistent disk failure is not certified.

At the COV-45 checkpoint, the separate COV-43 current-tail banking limitation remained open: synchronous reset precedes
its immutable run write, so a refused write can lose a tail not present in the old checkpoint.
Do not move that reset behind I/O without proving fresh-session and publication ordering. That
startup repair did not change the contract. COV-46 now implements the refusal/race matrix for first
and later local-midnight segment failures, a banked shorter prefix, preference false/throw,
repeated finalize/retry, a new connection counting while the old final write is held, and
concurrent minute publication. `replaceBandCoverage` identifies rows by device/source/local
day/run start; an older prefix must never replace a longer finalized run. Keep gain applied
exactly once and preserve workout accrual across the synchronous reset. COV-46 implements recovery of refused tails separately; its combined verification is pending. Changed-file analysis and full CI have no
warnings/errors; the full project retains 303 existing info-only notices.
Reviewed parentless `7ad4687f` (candidate 10), tree `9e629c7ce8d900d6045041454fa1f55772dba9b2`,
matches local source `1b443349`. Full Linux run [40585719502](https://github.com/akshatksingh18/whoop/actions/runs/40585719502) passes. The matching-line comparison is
recorded above; exploratory failed local probes
do not count toward verified gains.

## COV-46: final-tail recovery and authorized UI reliability

The implementation preserves synchronous counter reset, existing checkpoint key/runs shape,
gain application, SQLite identity, algorithm 99/schema 50 and app metadata. Immutable snapshots
share one I/O queue for recovery, finalization and minute publication. Acknowledged preferences
hold the final tail before SQLite replay; partial midnight failures retain a restart copy.
Preference false/throw falls back to SQLite, or retains RAM for retry if both stores refuse.
No restart durability is promised while neither store accepts writes. Reset drains the queue
before wiping and clears pending RAM only after acknowledged preference reset.

Controls cover refused first/later midnight writes, current/legacy checkpoints, acknowledged
removal failures, simultaneous store refusal/retry, malformed-copy preservation, a held minute
prefix, an old final save beside a fresh connection, and a full reset with a held writer.
The original nine COV-43 controls remain enabled. The shared backup result guard and form-owned
rename controller repair the two UI defects; three retained regressions are enabled. New
cancel/reopen/retry/late-host cases and complete-page 1x/2x captures retain copy and actions.
`reliability-ui-review.md` owns the reviewed pages and separate existing helper truncation.

Additional authored SQLite/import-finalization controls exercise the real notification
orchestrator: local today/yesterday freshness and fallback dates, benign/missing/malformed
rollups, shared finding text, aggregation, medical escalation/deescalation, muted findings,
quiet/category gates, refused/throwing presentation retry and RHR evidence/date/gap gates.
They use existing methods; they do not validate clinical detection or OS delivery.
The final targeted checks pass 161 unique cases across six files: 131 core/notification/
connection cases, 16 data handoffs and 14 device/review cases. This includes 53 new controls
and three re-enabled regressions. Changed-file analysis has no warnings/errors; three new/
extended test files have no issues. Only existing info-level brace notices remain elsewhere.
A failed test-expectation probe and a Windows native-assets cache collision are preserved
locally and do not count as gains. The corrected UI retry passes without coverage collection;
full instrumentation runs on Linux. Combined Linux results, hashes and delta remain pending.

## COV-44: consolidated coverage-only batch

Consolidated full Linux run [40529212076](https://github.com/akshatksingh18/whoop/actions/runs/40529212076)
passes on parentless `c640c84e`, tree `9ec667747d581824959f83fe0df2203e56040c5f`, local source
`3b8e730c`. The batch meets the requested roughly 1,500-line scale with 1,450 new production
lines across matching sources; it does not close every remaining coverage range.

The new focused matrices reuse shipped localization delegates, existing injection seams and
isolated authored SQLite stores. They exercise core readers, signal gaps/scrubbing, dated
navigation, profile/serving/goal drafts, Food history/library/quick-log/undo and first-reading
weight preservation, Train/session summaries, settings/quiet-time policy, startup/lifecycle,
real engine/GATT subscription and scan flow, isolate preparation, saved-session recovery,
encrypted automatic backup and export/share handoffs. OS/peripheral/share boundaries are
scripted; synthetic data never leaves the test. Rendered callbacks are not gesture proof.

Quick local probes assert values, absence, provenance, write refusal/retry and retained state.
The final count comes from the consolidated Linux LCOV comparison against candidate 8, not the
local union containing exploratory failed probes. All 272 new active controls pass in CI.
Generated translations, test lines and imports are excluded from the target. Production code,
UI, calculation methods, algorithm/schema, metadata and persisted identities are unchanged.

At COV-44, three explicit regression skips preserved two discovered existing defects: backup keychain
failure feedback is overwritten, and device rename disposes its controller during route exit.
`bugs.md` owns both; COV-46 now implements the scoped fixes and enables those regressions. The personal build's removed journal,
manual main-sleep, coach and other unavailable actions are not reopened for coverage.

Largest current gaps at COV-45 include AppState (447), BLE engine (436), derivation (367), food diary
(207), repository implementation (204), Progress (199), live activity (173), workout screen
(125), Home (122) and nutrition screen (97). Use the exact ranges and matching source hashes above;
do not treat a percentage, an import or a synthetic capture as every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

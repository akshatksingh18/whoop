# Coverage verification

**Status:** Partial COV-47 passes full Linux verification. COV-46's three authorized reliability
repairs and retained UI regressions remain passing. Handwritten execution is 91.94%, with
4,063 unexecuted instrumented lines. Remaining coverage, the enlarged name helper and physical
acceptance stay open. Native/IPA builds remain held.

## Current verified checkpoint

COV-47 is an open consolidated coverage-only batch targeting at least 2,521 additional matching
handwritten lines (five percentage points) before it closes. Candidate 15 verifies 221 new controls,
including both cloud-only complete-night cases. Further local controls bring the successful probe
union to 2,369 previously missed matching lines across storage/envelopes, notification handoff,
Body decisions, meal rollback, BLE ownership/debounce, AppState wiring, onboarding and Lift/alarm
controls. Successful probe LCOVs are `cov47-storage-d.lcov`, `cov47-boundaries-b.lcov` and
`cov47-forms-c.lcov`, `cov47-handoff-a.lcov`, `cov47-readers-b.lcov`,
`cov47-operational-a.lcov`, `cov47-routes-ladder-d.lcov`, `cov47-progress-a.lcov`,
`cov47-food-session-a.lcov`, `cov47-home-b.lcov`, `cov47-week-rough-b.lcov`,
`cov47-meal-reclaim-a.lcov`, `cov47-data-edges-b.lcov`, `cov47-localized-naps-a.lcov`,
`cov47-settings-food-f.lcov`, `cov47-pushup-runtime-a.lcov`, `cov47-today-pushup-e.lcov`,
`cov47-sleep-trends-c.lcov`, `cov47-crossday-store-a.lcov`, `cov47-lift-inputs-c.lcov`,
`cov47-shell-banner-c.lcov`, `cov47-live-localized-a.lcov`, `cov47-train-clock-d.lcov`,
`cov47-progress-owned-b.lcov`, `cov47-workout-pause-d.lcov`, `cov47-metric-read-g.lcov`,
`cov47-ble-wire-b.lcov`, `cov47-movement-floor-b.lcov`, `cov47-encrypted-ui-guards-b.lcov`
and `cov47-pull-hold-a.lcov`
under the ignored recovery checkpoint. The additional 171 locally passing controls cover history,
session destinations, Home retries/navigation, weekly/rough-night context, BLE publication,
meal units, nutrient provenance/means, Lift comparability, localized nap/Sleep corrections,
authored photo encoding/retention, explicit historical Food meal/time controls, Settings
reset/refusal/file-cleanup retries, notification replay/mirror/rollover/Home state and Today
Pushups controls, Trends pin/read/observation flows, compact cross-day nap/session rollups,
Lift search/repeat/variation/order, shell session banners, localized swimming/Yoga/breathing/match/
route controls, Train suggestions/history/strain navigation, retained workout-clock traces,
existing movement calorie-basis repair, Progress entry/photo/reminder failures and real workout
pause/resume/gait boundaries, Recovery failure/retry and dated input provenance, localized
metric day doors/percentiles, wire clock/loss diagnostics, frozen movement-floor persistence,
encrypted-export cancellation/missing-media refusal and held-workout refresh reports. These total 293 passing local controls, including one pure detector-input preflight. The two
original full-night cases pass in CI; two real encrypted-export workers and one further complete
night/activity handoff are authored for cloud execution and are not locally verified. The Today Pushups test keeps three named scenarios
in one active widget clock, matching the existing process-wide command Future contract. Failed
fixture probes remain preserved; none replaces a successful LCOV or a retained regression.
Production source, calculations,
metadata and source remain unchanged; the cloud instrumenter exposes one more existing dirty-state
line without a code change. These probes are partial planning evidence, not a combined percentage
or a completed area. Continue against matching remaining ranges toward Akshat's requested 100%,
with one agent, keeping real native/private/unreachable limits explicit and all release gates.

The expanded cohort is on parentless candidate `85ebbd7a143baf15a41a88565416d73e9bfe502c`,
branch `ownership-ci-candidate-15`, tree `f7f6cb650d0d7b1295141651ad129ea86d418fbc`, local
source `aa4be47c`. Linux run [40659144112](https://github.com/akshatksingh18/whoop/actions/runs/40659144112)
passes all jobs: 4,829 app checks/429 explicit skips, both packages, analysis with zero errors or
warnings/320 infos, and 730 synthetic captures. Handwritten execution is 46,347/50,410 (91.94%).
Against COV-46, 1,983 matching lines gain execution and one loses its hit: net +1,982. All
203 imported and four unimported normalized source hashes match. The same single existing
Body dirty-state line is newly instrumented; no source changed or was excluded. The remaining
540 hits needed for 93.01% keep this batch open. All capture names match candidate 14; exact
LCOV/gaps/delta and the full artifact/hash manifest are preserved in `build/coverage-continuation/85ebbd7a/`
and `build/ownership-checkpoint/cov47-ci15-linux-verified/verification.json`.
Its reviewed tree contains 892 files,
29 unchanged binaries and no private ancestors; all 30 previous remote refs are unchanged.
The verified all-ref bundle and preservation/privacy receipt are
`build/ownership-checkpoint/cov47-ci15-state-all-refs.bundle` and `cov47-ci15-candidate.json`.
Main, tags and native/IPA holds are unchanged.

Candidate 15 includes the first 219 local controls and the two cloud-night cases. The further
74 further passing local controls, three newly authored cloud-only cases and a corrected unused
test import await their next combined candidate;
do not attribute them to that verified tree. Targeted analysis of the five continuation files has zero errors/warnings and four info-only
style notices. The earlier unused Lift test import has been removed; the publication checks
also analyze that file and the earlier remaining new controls.

One remaining shell branch is structurally unreachable: `_LiveSessionBar._activityFor` calls
`storedActivity` with a non-null stored string, and that helper always returns an activity,
including the unknown-type fallback. The null-activity finish branch in `app.dart` therefore
cannot run through the current typed path. The authored unknown-type control verifies generic
resume and retained identity without inventing a MET. Its earlier failed null-branch hypothesis
is preserved privately. Do not manufacture an invalid return type or remove the feature to gain
coverage; retain this classification in the remaining-line inventory. The skin-temperature
trend is explicitly suppressed before its loader reaches the imported-unit filter and its
SD formatter. A retained control verifies that suppression; a separate active RHR control
checks algorithm boundaries and localized percentiles. Do not reopen that trend for coverage.
The failed trend hypothesis is preserved privately. A separately reproduced legacy gen5
clock-body guard mismatch remains open in `bugs.md`; no production repair is claimed here.

Run [40630574613](https://github.com/akshatksingh18/whoop/actions/runs/40630574613) passes on
parentless `715b13739f4d416a4942185b5670b6e37772ae2b`, branch `ownership-ci-candidate-14`,
tree `0e50ab55e4fce850cecce5de5a78ebbd4042e567`, local source `d7624900`:

- 4,732 app checks pass, 429 explicit skips; both packages, analysis and synthetic pages pass.
  Analysis has zero errors/warnings and 317 info notices.
- 45,520/50,410 handwritten lines execute (90.30%; 4,890 missed). All 203 instrumented/generated
  source hashes and four unimported hashes match. No executable production change occurs.
- Against COV-46: 1,156 unchanged lines gain execution and one loses execution, net +1,155.
  The lost hit is the Steps metric's unit getter at `progress_review.dart:64`; retain an explicit
  unit-label follow-up. Existing `progress_screen.dart:1604` becomes instrumented
  (+1 denominator); no line is excluded. At least 46,887 hits are needed for 93.01% now.
- The downloaded 730 PNGs and full manifest are preserved. Compared with the prior 731 PNGs,
  only Today's final `b87_today_430w_2.0x_scroll_4.png` is absent; the current full-scroll capture
  finishes one page earlier. This is recorded explicitly, not claimed byte-identical UI evidence.
- Exact LCOV, ranges and delta are in `build/coverage-continuation/715b1373/` and recovery copy
  `build/ownership-checkpoint/cov47-ci14-linux-verified/`, including `verification.json`.

Intermediate run [40629102297](https://github.com/akshatksingh18/whoop/actions/runs/40629102297)
on candidate `74f3694f` stopped at one unused new-test import; candidate 14 corrects it.
The failed run's evidence is preserved. A separate pre-v19 unknown-raw retention
probe failed; its original source/log remain private and the unresolved defect is in `bugs.md`.

Run [40601423011](https://github.com/akshatksingh18/whoop/actions/runs/40601423011), candidate `b3114e224ef768fbf26843d667f4ad9ce9b7912e` on
`ownership-ci-candidate-12`, tree `bdb0e96231775cbff5cd3206ed3159ed7f05d792`, local source
`ffd54bad`:

- Analysis and source/personal iOS guards pass: zero warnings/errors, 303 existing info notices.
- App: 4,608 passed, 429 explicit skips. All 56 new controls and three re-enabled regressions
  pass; no known UI defect is concealed behind those former skips. Other private/native skips
  remain explicit. The approved Food large-text regression stays enabled.
- Protocol: 409 passed, 14 private-corpus skips. Analytics: 643 passed, six skips.
- Pages: 217 checks and 731 authored captures pass. All 23 repair pages exactly match the
  previously inspected Linux pages. The complete artifact and SHA-256 manifest are local.
- Handwritten execution: 44,365/50,409 (88.01%), 6,044 unexecuted. All 203 imported/instrumented
  normalized source hashes and four unimported source hashes match; the latter do not count
  as executed. Only AppState, profile Data and Devices production sources change.
- Against COV-45's 44,285/50,371: 63 matching lines gain execution and 20 previously hit matching
  lines do not execute. New/modified source executes 107/114 instrumented lines; 76 instrumented
  lines are removed/replaced, including 70 previously executed ones. Net execution +80;
  denominator +38. Removed and modified lines are accounted for, rather than counted as old
  newly covered lines. This is execution evidence, not branch/native/scientific proof.

Exact LCOV, hashes, ranges and line-identity comparison are in
`build/coverage-continuation/b3114e22/` and recovery copy
`build/ownership-checkpoint/cov46-linux-verified/`, with `verification.json`.
The comparison maps unchanged lines around all three repairs and accounts for new/removed
source separately. The 20 missing matching hits are explicit follow-ups: overnight battery
(13), native notification presentation (2), closed-handle retry (2), and future-hour masks on
Steps/Wear (3). Their unchanged bodies are sensitive to clock/trigger conditions; add controlled
cases rather than treating an earlier hit as permanent coverage. No denominator/source hiding.

COV-45's exact verified baseline remains in `build/coverage-continuation/7ad4687f/` and
`build/ownership-checkpoint/cov45-linux-verified/`. COV-44's separate consolidated 1,450-line
coverage-only gain remains verified. Earlier inventories, failed probes and original records
are preserved; the failed first COV-46 run is not substituted for the successful result above.

Both COV-46 candidates use reviewed single-root history and public noreply identity. Only
candidates 11 and 12 were added; all 26 pre-batch remote refs remain unchanged. Candidate 12
alone leaves all 27 earlier refs unchanged. Main has not been replaced; no ref was deleted.
The private preservation branch, captures, tooling, archives and probe outputs stay local.

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
checkpoint, and a new minute replaced it. That batch used the existing single-flight idempotent recovery and left refused bytes intact;
COV-46 now orders all recovery/publication/final writers through one immutable-snapshot queue. Older recovery runs before
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
exactly once and preserve workout accrual across the synchronous reset. COV-46 implements and fully verifies refused-tail recovery separately. Changed-file analysis and full CI have no
warnings/errors; the full project retains 303 existing info-only notices.
Reviewed parentless `7ad4687f` (candidate 10), tree `9e629c7ce8d900d6045041454fa1f55772dba9b2`,
matches local source `1b443349`. Full Linux run [40585719502](https://github.com/akshatksingh18/whoop/actions/runs/40585719502) passes. Its matching-line comparison remains in `build/ownership-checkpoint/cov45-linux-verified/`;
exploratory failed local probes
do not count toward verified gains.

## COV-46: final-tail recovery and authorized UI reliability

All 56 additions and three retained UI regressions pass full Linux run [40601423011](https://github.com/akshatksingh18/whoop/actions/runs/40601423011). Targeted local
verification passes 171 unique checks across seven files; changed-file analysis has no warnings
or errors. The added tests include 15 tail/storage/reset cases, 27 notification-orchestration
cases, seven UI cancellation/retry/late-result controls, four full-page reviews and three aged
heart-chart snapshots. Existing checks remain enabled. Calculations, algorithm 99/schema 50,
metadata, active identities, checkpoint keys/shapes and gain application remain unchanged.

Finalization still resets live counters synchronously, then queues immutable snapshots with
orphan recovery and minute publication. Acknowledged preferences hold the final tail before
SQLite replay; failed first/later midnight writes retain a restart copy. Preference false/throw
falls back to SQLite, or keeps RAM for retry if both stores refuse. No process-kill durability
is promised while neither persistent path accepts writes. Reset drains the queue before wiping
and clears pending RAM only after acknowledged preference reset. The tests include current/
legacy checkpoints, removal false/throw, both-store refusal/retry, malformed-copy preservation,
a held minute prefix, a fresh connection beside an old final save and a held writer during reset.

The shared backup result guard preserves existing nested failure feedback across passphrase,
cadence and Back up now. A framework-owned form controller survives band-dialog exit; validation,
copy and actions stay the same. All three former skipped regressions pass. Complete 1x/2x pages
were inspected before implementation; the 23 corrected Linux repair frames match the reviewed
Linux set exactly. `reliability-ui-review.md` retains full Before/After links. The pre-existing
2x name-helper truncation remains a separate open accessibility item.

Notification cases use authored SQLite/rollups through real import finalization: local today/
yesterday and fallback dates, absent/benign/malformed bundles, shared copy, aggregation, severity
escalation/deescalation, muting, quiet/category gates, failed presentation retry and RHR date/
evidence/gap gates. They validate orchestration, not physiological detection or OS delivery.

First run 40596713613 passed the new repairs but failed an old heart fixture across 23:10:59
and 23:11:00 UTC: its one-minute-ahead poison point became current during rendering. The fixture
now keeps the point genuinely future in both inputs and tests immediate/one-minute-aged
snapshots across all three ranges. All original clamp, selection, range and future-poison
assertions remain; production chart code is unchanged. Its failed-run artifact stays separate
at `build/coverage-continuation/46815374/` and `build/ownership-checkpoint/cov46-linux-failed/`.
The corrected run above is the verified checkpoint.

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

Largest current gaps at COV-46 include AppState (465), BLE engine (436), derivation (324),
Food diary (207), repository implementation (204), Progress (199), live activity (173), journal
compose/shared inputs (169), lift-log UI (164) and database (130). Preserve unavailable feature
boundaries: do not reopen a removed surface or execute it merely to inflate coverage. Use the
matching ranges above; imports or captures are not every-line/every-click proof.

Full suites/analysis/builds run on Actions. Local checks remain short targeted files or probes.
Native Swift, physical BLE restoration/ACK durability, notifications, GPS/camera/keyboard,
VoiceOver, signing renewal, the 72-hour soak and measurement validity need separate evidence.
Mocked channels and synthetic captures do not replace those checks. No IPA build or phone
acceptance is claimed by the green Linux run.

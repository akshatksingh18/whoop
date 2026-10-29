# Coverage verification

**Status:** Full Linux verification reaches 94.18%, with 2,933 unexecuted instrumented
handwritten lines. COV-47 exceeded its five-point target; COV-48 continues toward 100%.
The enlarged name helper and physical acceptance remain open. Native/IPA builds remain held.

## Current verified checkpoint

Parentless candidate `748043621cd8af6b6fc0cb73e2140886d353214f`, branch
`ownership-ci-candidate-24`, tree `c7fab97b8f221975b171bddc3ec4313c7a358d14`, source
`9ad6257c939fcf6a0c86e135dbf02fbdaaa8778d`, passes full Linux run
[40858887923](https://github.com/akshatksingh18/whoop/actions/runs/40858887923).

- 5,060 app checks pass, with 429 retained explicit skips; both complete package suites pass.
  Analysis has zero errors/warnings and 325 existing info notices. All eight early authored
  worker/scheduler checks also pass in addition to their complete-suite execution.
- 47,482/50,415 handwritten lines execute (94.18%; 2,933 unexecuted). Against candidate 22's
  47,427/50,410 (94.08%), exact equal-source mapping records 49 gains and one lost declaration
  hit (`lib/app.dart:55`). Eight new/unmapped instrumented lines execute, replacing three lines
  with one prior hit: net +55 executed, +5 denominator. Against candidate 23, net executed
  increases by three and the denominator by one. No source is excluded. Event/clock/import
  repairs and an onboarding comment change five sources; calculations, metadata and UI remain.
  All 196 handwritten Git-source hashes and four unimported hashes match candidate blobs;
  seven ignored generated hashes match regeneration and unchanged localization/toolchain inputs.
  The newer notification source differs and is outside this proof.
- The first 109 COV-48 controls pass together. All 343 COV-47 controls remain passing; that
  completed batch gained 2,746 matching lines from COV-46's 88.01% (+5.45 percentage points).
  Real encryption workers and complete-night derivation stay on Actions.
- All 730 synthetic PNGs are downloaded and hashed; exact filenames match candidate 22.
  This does not certify sensors, OS delivery, signing, an installed build or the helper defect.
- Exact LCOV, remaining ranges and delta are in `build/coverage-continuation/74804362/`;
  `build/ownership-checkpoint/cov48-ci24-linux-verified/verification.json` records assertions,
  log/artifact hashes and limits. All 39 earlier GitHub refs are preserved. Main and tags
  remain unchanged, with B5 still unapproved. Earlier full proofs and LCOVs are retained.
  Candidate 21's two lost database hits remain explicit in its original delta; both have now
  regained execution. The separate current declaration miss stays visible above.

The earlier fixture/harness failures remain preserved in `cov47-ci16-linux-failed/`,
`cov47-ci17-linux-failed/` and `cov47-ci18-linux-failed/`; their percentages were never promoted.
The fixes preserve the existing 3 h sleep minimum by supplying a 4.5 h authored night, use a
synchronous assertion inside the share mock, pump route-exit frames while awaiting worker
cleanup, and isolate repeat media fixtures without deleting their old containers. The green
candidate verifies all of these together. Older partial COV-47 checkpoint receipts and exact
successful/failed local probes remain in the private recovery checkpoint and Git bundles.

## COV-48: current continuation

Continue toward Akshat's requested 100% with one agent. Start from candidate 24's matching
remaining ranges, keeping its entire denominator and all assertions. Batch meaningful active
BLE/state, storage/import, retained-screen and failure/retry controls; keep native-only,
retired/unreachable and private-input limits explicit. Do not reopen a removed feature or
manufacture an invalid typed state to reach a branch. Production methods, approved calculations,
algorithm 99, schema 50, metadata, persisted identities and native/phone gates remain unchanged.

The 36 controls now verified in candidate 20 include:

- Three rolling Strength/waist comparisons and real detail doors; seven actual headless
  GATT/SQLite handoffs including durable ACK, queue refusal, pairing and ownership boundaries.
- Seven foreground/reconnect calculation-intent publication/refusal/throttling cases;
  three waiting-goal actions, five missing zone-anchor cases at 0/13/14 resting days and
  three historical Food copy-picker read/retry/selection cases.
- Four measured-only Recovery-mover store controls and four historical What-changed reader
  controls. The separate future algorithm-break reproduction is an open defect in `bugs.md`.

Thirty later controls pass targeted checks and combined Linux run
[40803053834](https://github.com/akshatksingh18/whoop/actions/runs/40803053834) on
parentless `c59336afa64626aebe22b0a1d79488b55c76da70`, branch `ownership-ci-candidate-21`,
tree `319dae486f1c7af2839bd4e4c032056313d4f905`, source `05884750`. They reach 98
matching candidate-20 misses across fifteen production files in targeted probes; the full
run's measured net gain is recorded above. These controls retain all methods and assertions:

- One headless expired-after-ACK case preserves committed data, cursor, verbatim ACK and
  pairing while queuing the light intent and releasing the link/lease.
- Five retained-finding cases cover original notification wording across day navigation,
  expired reports, decode/retry, the 32-report cap/mirror cleanup and repeated-save identity.
- Seven explicit historical Log-food cases cover read/retry, category selection, refused
  last-portion reads, food/meal reorder rollback/retry, a unit changing after review and a food
  disappearing before Log. A stale unit rolls the entire plate back; zero available foods
  produces the existing honest warning. The general default-meal investigation stays open.
- Three tiny real conversion cases cover a legacy day-only cursor and a competing middle or
  first-resumed row. The newer payload survives, the cursor remains before it, and retry
  converts it losslessly without changing its scalar columns or finalization.
- Three sparse-substrate windows preserve RR endpoints in half-open windows with no 1 Hz
  record, without inventing HR, motion or optical measurements.
- Three import-container cases preserve refused UTF-16/binary sources and all three CSVs
  when a duplicate basename collides with an existing numbered name.
- Three Pushups cases retain no-goal/missed-goal pause history and verify cancel/refusal/retry
  of completed-history deletion while keeping the open day and settings.
- Five barcode library cases cover missing, flagged, unreachable, revoked and partial lookup
  results, with manual-entry/review/cancel and no premature writes. HTTP is mocked, default
  sockets are refused, and request counts are asserted; no service or camera acceptance is
  claimed. The structurally unreachable OK-without-product fallback remains unforced.

Successful evidence is `cov48-headless-expiry-a.lcov`, `cov48-retained-findings-b.lcov`,
`cov48-log-food-recovery-b.lcov`, `cov48-log-food-recovery-c.lcov`,
`cov48-reencode-sparse-a.lcov`, `cov48-container-formats-a.lcov`,
`cov48-pushup-history-a.lcov` and `cov48-barcode-label-a.lcov` under the ignored checkpoint.
`cov48-local-after-ci20-union.json` records matching ranges. New-file analysis is clean after
correcting test imports/style. Earlier failed compile probes remain preserved; no production
failure is relabeled or hidden. No full-night derivation or encryption runs locally.

The verified source/docs/expiry checkpoint `61d9eac1` is protected by
`cov48-ci20-verified-expiry-state-all-refs.bundle` (42,679,179 bytes; SHA-256
`ad49ec35053c6023f2b75a3636d54e58232593985e1425e136110937951a53fe`). The scoped vault and
independent content hashes verify 9,821 files, including the complete green candidate-20
downloads. Later tests/docs require the next commit/bundle/vault refresh; its exact receipt
belongs in the ignored checkpoint. All older bundles, historical/private loose files and
captured originals remain retained. The later candidate/source is protected by verified
`cov48-ci21-state-all-refs.bundle` (42,688,594 bytes; SHA-256
`b098b2c9955d88e77fa54856b876fdbeea5bef2dff456b32d5ea0d8c038a4137`). Before its push, the
scoped vault and independent content hashes verified 9,889 files with zero differences. All
36 earlier remote refs are unchanged; only candidate 21 was added. The later verification and source require the next refresh, recorded by the continuation
receipt; an old vault check never covers later edits automatically. Never push this branch, private ancestors or recovery caches.

Seventeen later controls pass locally and combined Linux run
[40807926057](https://github.com/akshatksingh18/whoop/actions/runs/40807926057) on parentless
`bd8b36ac35c012aa1b452a8045ff0ec6f29698af`, branch `ownership-ci-candidate-22`, source
`5edd0c6689d6a5dff11339610def5780013d0ed0`, tree `19a6cafe403d0fcb2fa29d280c717b391822b325`.
All 5,034 app checks pass, including these seventeen additions:

- One actual maintenance modal retains its last successful running/food breakdown during a
  refused refresh, displays pounds, and replaces the stale answer only after a successful read;
  the typed goal stays fixed. Four HRV cases cover no/prehistory data, imported-outlier exclusion,
  historical windows and an active section's refused-read retention after a day change.
- Five Data actions cover localized failure/skip feedback, a repeated lift import without
  duplicate work, and matching/conflicting same-day body imports without replacing provenance.
- Two real backup-queue controls stop at missing passphrase before snapshot/encryption. A
  refused failure-status write preserves the actual outcome, and refused cadence keeps Off;
  retry preserves unrelated preferences and never claims a backup was written.
- Three actual Status flows cover initial read failure/retry, retention during refused reread,
  refresh after committed record publication and app resume, authored expiry explanations,
  last-successful backup disclosure and the existing Data settings door. Mocked native readers
  and authored signing profiles do not certify an installed signature or physical delivery.
- Two real SQLite trigger refusals cover the first event write and its mirror. Non-closed
  errors remain visible, earlier evidence survives and retry fills the mirror without duplicates.
  These explicitly reach one of the two lost database lines; the closed first-retry condition
  remains uncovered locally. No closed-handle behavior is faked to claim it.

Successful evidence is `cov48-maintenance-hrv-b.lcov`, `cov48-data-repeat-a.lcov`,
`cov48-backup-status-a.lcov`, `cov48-status-health-c.lcov` and `cov48-event-refusal-a.lcov`.
The union reaches 68 matching candidate-21 misses across eight files, not a new cloud
percentage. New-file analysis is clean; the existing Data file retains its eight style infos
with no errors/warnings or new notices. The shared optional units wrapper puts its provider
above the Navigator as in the app, with unchanged default behavior. Earlier failed fixture
probes remain preserved: the units provider had been below the modal Navigator, and the
Status fixture initially used a ledger key the production reader does not read. Neither
fixture issue is claimed as a production repair. These seventeen controls now pass combined CI.

Five further Today/Train controls pass locally outside candidate 22. Today uses its ordinary
reader, marks a newly read night once across reopening/revisions, expires a sync tap without
inventing success and opens both Status doors and Settings. Train recovers a missing repository,
keeps a refused strain chart absent rather than inventing zero, and refreshes after a successful
read. Its saved-session destination retains RPE, timing and every authored route point through
real SQLite enrichment. Production methods and UI remain unchanged. Successful probes are
`cov48-home-current-b.lcov` (three checks) and `cov48-train-current-c.lcov` (two), with clean
analysis. Failed setup probes are retained; the fixture needed the app's units provider and
Scaffold, and must respect the existing absent-chart gate. No production failure is reclassified.
These five controls reach 37 additional misses. Four further controls in `cov48-reminder-rollup-a.lcov` pass with clean analysis: corrupt JSON,
non-object JSON, non-list recent rows and a quiet mixed list preserve the original rollup,
ignore stray entries and cancel stale reminders without inventing a finding. Native cancel/
permission hooks are substituted; no OS delivery or removed feature activation is claimed.
These reach eight additional matching AppState misses. The nine controls outside candidate 22 reach 45 matching misses in its source. That is
local planning evidence, not a combined percentage. The later AppState repair changes source
positions, so do not reuse its old LCOV against those newer bytes.

Verified `cov48-ci22-state-all-refs.bundle` protects the candidate/source (42,708,917 bytes;
SHA-256 `0e6c1e6c59531113ebb3127e54a4c5d5f3203a23cd21ea92c1c31664c615dc28`). Before its
push, scoped collection/check and independent vault hashes verified 10,700 files, including the
full green candidate-21 evidence and corrected single-occurrence automation. All 37 prior
remote refs remain unchanged; only candidate 22 was added. The later source/docs/probes require
the verified `cov48-ci22-reader-preservation-receipt.json` continuation bundle/vault receipt
in the ignored checkpoint. Never push
private ancestors, captures or recovery material.

## Event-write failure observation: combined verification passes

Both production `insertEvent` callers were traced: foreground AppState and headless sync.
Their void event sinks discarded failed asynchronous writes. Both now observe/report the
Future through their existing local diagnostic logger. The database writer still throws
non-closed errors to awaited callers; its contract is unchanged. Alarm effects remain immediate,
and event writes remain best-effort rather than becoming the historical commit/ACK gate.
No automatic replay, durability of refused event bytes, or phone crash prevention is claimed.

Four new controls pass: real SQLite refusal at each foreground event/mirror insert, plus each
headless insert failure through the real scripted GATT/drain. Prior events survive; retry fills
the mirror without duplicates; headless checks retain the exact ACK token, committed row and
cursor, queue/lease cleanup and failure diagnostics. The three targeted files pass 14 checks
in `cov48-event-observation-a.lcov`. The original private failure source is unchanged and now
passes in `cov48-live-event-repair-confirmation`; both old failure and new result remain local.
This repair changes only AppState/background-sync orchestration, with no package, algorithm,
schema, calculation, UI, persisted identity or metadata change. Together with the nine other
local controls, thirteen additions pass full Linux run 40856206198 and remain passing in
40858887923. This verifies the scoped repair, not all BLE/event behavior or phone acceptance.

## Clock/import repairs: combined verification passes

Candidate 23 (`134af85f`, source `c6eb0659`, tree `e98360be360a63d50a96ff82629a2de5f73d78e4`)
passes full Linux verification [40856206198](https://github.com/akshatksingh18/whoop/actions/runs/40856206198)
for its thirteen additions and event-write observation: 5,047 app checks and 96 COV-48 controls.
Its pre-push bundle is `cov48-ci23-state-all-refs.bundle` (42,725,689 bytes; SHA-256
`4479807dab517df68c3e193993877ff33f941cd618ccf8d6510c1e7c97151bad`). Scoped collection/check
and independent vault hashes verified 11,522 files before publishing only that new branch;
all 38 prior remote refs remain unchanged. Later changes require a fresh preservation receipt.

Seven new clock controls pass alongside nine existing cases and the unchanged private revision-7
reproduction (17 checks). The engine fallback now respects the protocol's legacy revision-1
layout guard even for an unset RTC. Unknown revisions cannot trigger clock writes from padding;
current opcode 11, documented revision 1 and gen4 status tolerance remain. Package output,
coefficients and algorithm/schema/metadata are unchanged. Evidence is `cov48-legacy-clock-guard-a`;
analysis has zero errors/warnings and three existing test-style infos.

Six new import controls pass with four existing partial-import cases in `cov48-import-encoding-a`;
the unchanged private Latin-1 reproduction also passes in `cov48-latin1-repair-confirmation`.
Strict byte decoding in the shared journal reader distinguishes malformed UTF-8 from real I/O
failure. The existing router then handles legacy text through its vendor path. Tests retain
Unicode/BOMs, quoted notes, source bytes, and committed groups when vendor handling succeeds
or refuses. They do not claim that the existing lenient vendor decoder reconstructs legacy
characters. The router's binary-container comment is reconciled; no layout or headline method
changes. New importer-file analysis is clean. These thirteen controls/repairs are outside
candidate 23 and pass combined run [40858887923](https://github.com/akshatksingh18/whoop/actions/runs/40858887923)
on parentless `748043621cd8af6b6fc0cb73e2140886d353214f`, source `9ad6257c`, tree
`c7fab97b8f221975b171bddc3ec4313c7a358d14`: 5,060 app checks, both packages, analysis and 730 captures pass. Its verified
bundle is `cov48-ci24-state-all-refs.bundle` (42,743,108 bytes; SHA-256
`26876e45c972c17cf7254d6ba3906537acef86e7135462519a3888948282aa44`); pre-push scoped collection
and independent vault hashes verify 11,552 files. All 39 prior remote refs remain unchanged.
The current verified percentage/ranges are above; no later percentage is accepted.

## Later notification and cached-state controls

The registered foreground notification callback reproduced three real unhandled SQLite errors:
Food completion and Pushups Done/Pause. Its two existing action Futures now report failure
through the notification logger. Routing, awaited/background action contracts, durable state
and retry/deduplication remain unchanged; a refused action is not claimed saved or replayed
automatically. The unchanged original negative source/log remain in the ignored checkpoint.
Four existing callback route/dismiss cases, three refused-write/retry cases and four actual
iOS-plugin permission-handoff cases exercise the public callback registration. Native replies
are scripted; no actual notification or permission delivery is certified.

Four finalized sleep-cache cases use a real store and one authored 1 Hz row. They retain a
valid absent-sleep candidate verbatim, rebuild malformed/non-map/empty cache payloads, retain
source readings, and never invent sleep/profile/scalars. Four additional journeys in the
existing serial Pushups test cover Cancel, dialog dismissal, Start now and Start paused while
Home presence is outside; real stores/mirrors preserve the chosen state and zero completed sets.
These changes await full run [40862004211](https://github.com/akshatksingh18/whoop/actions/runs/40862004211)
on parentless `af64d24729341baed1d5737661eb232340d572ea`, source `c099eec1`, tree
`c993ef80fe81859d0eacdfb4bd7f6a95a8845bdd`. Expected 5,075 checks remain unverified. No full
night runs locally, and no source exclusion, new skip, UI layout or calculation change is made.
The three-file targeted probe `cov48-notification-cache-away-b` passes 16 checks: fifteen new
cases and the existing serial Pushups journey with four added Home choices. Exact equal-line
mapping reaches 32 candidate-22 misses across four sources, with changed lines kept separate;
this is not a combined percentage. Targeted analysis has zero errors/warnings and three
pre-existing brace-style infos. The initial probe's three escaped failures remain preserved
alongside its original source; no failure is skipped or relabeled.
Its verified bundle is `cov48-ci25-state-all-refs.bundle` (42,750,778 bytes; SHA-256
`ce4033b1879d295ab6bca2ac42bd23554488f8764f3c2d678ac8d2190d960806`). Scoped collection/check
and independent vault hashes verify 12,336 files before its push; all 40 earlier remote refs
remain unchanged. Later source/docs/evidence need a fresh preservation receipt.

## Later live-workout and goal-evidence controls

Fifteen controls pass locally outside candidate 25, with production source unchanged:

- Four maintenance readers use real saved/current clocks and authored motion replies. Paused
  minutes stay outside session energy; a finished current run replaces its history entry once.
  Exact workout motion can remain known when daily steps are unavailable. Daily absence stays
  null, while the unchanged conservative estimate retains known running without inventing
  walking. Non-running live work does not create a run or consume motion-window data.
  A separate GPS case with unknown run-step overlap retains the approved maximum of movement
  estimates instead of adding both. Two held history reads prove that an old generation cannot
  overwrite the cache for a newer revision or repository.
- Five goal cases distinguish unavailable old coverage from measured zero/below-threshold
  correction and an earned threshold retained after a target increase. A refused authoritative
  ledger correction releases a queued read, preserves both prior state and retry capability.
- Three route callbacks flow through the real GPS-source/tracker/AppState readers. Supported
  running/walking speeds retain qualified estimates; fast walking keeps the labeled movement
  estimate while qualified ACSM abstains. No pulse/steps/workout finish is fabricated, and the
  seven authored equatorial fixes persist. These tests do not validate GPS or calorie accuracy.

All three changed files pass 36 targeted checks in `cov48-live-ownership-batch-f`: fifteen new
cases and 21 retained route controls. Exact source-line mapping reaches 45 candidate-23 misses
across four sources; this remains a local range count, not a combined percentage. Existing
formulas, approval gates, UI and version metadata are
unchanged; changed-file analysis is clean. These do not implement treadmill or parked calorie proposals. The initial reader
probe's test-only record-field typo is preserved, corrected, and is not an app defect.

## Remaining reachability and repair boundaries

The actual remaining inventory includes active branches, native/physical behavior and retained
unused/removed surfaces. Keep all of them visible rather than claiming the remaining 5.82% is
one homogeneous, executable Linux test target.

- `_LiveSessionBar._activityFor` always gets an activity from `storedActivity`, including the
  unknown-type fallback; its null-activity finish branch cannot run through the typed path.
- The skin-temperature trend is suppressed before its imported-unit filter/SD formatter.
  The retained suppression control and separate active RHR boundary/percentile cases pass.
- `TodayPlanCard` has one production caller, always `overviewHasTotals: true`; the old duplicate
  totals/workout branches are retained but are not activated solely to count their lines.
  `DashedRing` has no production call site. Gallery-backed painters have actual preview doors.
- Removed Journal/cycle/spot-check/breathing surfaces, abstract fallback stubs, theme compatibility
  and platform-only branches remain explicit limits. Do not remove/reopen them for a percentage;
  any feature removal needs a per-item unreachable inventory and approval.
- Three authored negative reproductions still require source repairs: pre-v19 unknown-raw
  retention, historical R10 eight-beat handling and a future algorithm break erasing an earlier
  What-changed comparison history. Their exact sources/logs stay local. Event-write observation
  passes combined CI, as do legacy clock and Latin-1 routing. Notification-action handling has
  passing targeted proof with combined verification pending. All original sources/logs remain preserved. No
  failure is hidden by a new skip; output/version/migration decisions retain their own gates.

## Preserved earlier verification

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

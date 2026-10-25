# Coverage-directed audit

**Status:** COV-01–35 are repaired in source through `e88fde29`; full Linux run
`40189878355` passes. Cached Build 102 (`fc69b0d3`) contains COV-01–29 and remains the single
validated testing IPA. Further native/IPA builds are held until the coverage work is complete.
Current handwritten execution is **41,181/50,310 (81.85%)**, with **9,129 unexecuted**.
These are software execution counts, not every-click or physical-device certification.
The larger continuation batch adds COV-36–39 and 112 passing targeted controls; its combined cloud
checkpoint is pending, so the percentage above remains the last full-run measurement.
`setup.md` owns cache/source/hash evidence; `todo.md` owns the open execution and phone gates.

## Build 101 baseline

The extension adds 96 passing synthetic cases. Full root suite: **3,685 pass/429 intentional
skips**, including 408 absent golden baselines. Analysis has zero errors/warnings and 243 infos.
Protocol passes 433/skip four; analytics passes 645/skip six. All 13 Python controls and
152 visual checks pass, producing 607 synthetic captures with substituted fonts.

Final root LCOV is 39,277/57,659 (68.12%, 203 imported files). Excluding the same seven generated
localization files, handwritten execution is **39,226/50,058 (78.36%, 196 files)**, up from
76.57%. That is 902 more executed lines; the instrumented denominator grows by 10, leaving
**10,832 unexecuted lines**, 892 fewer. No exclusions, skipped-test changes or dormant imports
were added. The exact inventory is ignored `build/coverage-audit/build101-final.json`.

Largest gains are Lift UI (+384 executed lines), actual analysis export (+126), Your data
actions (+110), Food diary (+103) and retained phone motion (+78). These are execution-count
differences, not claims of the same number of newly proven old branches. Remaining misses
include AppState (1,034), BLE engine (709), derivation (523), Train (513), repository (462)
and Progress (410). Many remain suitable for further automated work; they are not all hardware
blocked. Constants/barrel exports remain the same three unimported files.

## Remaining execution work

Checkpoints now aim for roughly 1,000 remaining executable lines across related flows before
another full cloud coverage run. This is a batching target, not a quota of tests, a claim that
every reached line is proven correct, or permission to pad/exclude paths. Small targeted local
checks and coherent source commits continue inside the batch. Further IPA builds remain held.

**COV-36 — the promised empty-label rename cannot save.** Food → Foods → Manage labels →
Rename says "Label (empty removes it)", but the shared text prompt rejects an empty value
after that caller's validator accepts it. The rename alone now explicitly permits empty input;
other callers retain required-text validation. Eleven real-sheet/SQLite controls pass for
rename, case-insensitive merge, clearing, bin cancel/remove, length validation, atomic rollback
on write refusal and retry, 2x/3.1x access, and the shared prompt's required-field default.
Saved foods and historical diary entries remain intact. No layout, wording, metric or schema
changes accompany this repair.

The larger batch also has 29 passing workout-summary view controls, seven saved-meal editor
controls and fourteen Settings controls. They follow real reachable tabs/sheets, partial
distance splits, recorded HR gaps, legacy/mile splits, heat/cold no-signal explanations,
template validation/portion/grouping/persistence/retry, unit independence, barcode consent,
notification preferences, muted kinds, thresholds and permission refresh. Food and template
tests use synthetic SQLite; Settings uses a preference-store substitute and scheduler counters,
and system permission delivery is substituted. Workout views use synthetic ActivityResult
records rather than a band or native GPS. Screens are scrolled at narrow phone widths, with
selected 2x/3.1x controls and substituted fonts.

**COV-37 — a replacement summary retains the previous result's state.** Three failing controls
select an HR point beyond a replacement trace, retain a third tab when only two remain, or
retry a failed save with a shorter trace. The first and third throw a cursor RangeError; the
second throws a tab RangeError. Result replacement now resets selections and result-owned
caches, end time, lift markers and earlier-run data. Each asynchronous read/retry/rating completion
keeps its result generation, so an older completion cannot overwrite a newer record. A rating
copy within the same result retains valid pending metadata. Controls also hold real SQLite
reads/writes through replacement and verify that committed old ratings stay on their own row.

**COV-38 — effort rating can report success for a removed workout.** A failing real-store control
deletes a summary's session before selecting a rating. UPDATE affects no rows, but the caller
publishes a change and shows the rating as saved. The shared database method now requires one
updated row, matching session-type editing; refusal keeps the prompt unrated. Ordinary saves,
skip, missing-row refusal, write refusal/retry, deletion/cancellation and type correction pass
through the actual repository. No rating, energy or physiological formula changes.

**COV-39 — HIIT rounds disappear while Finish opens the summary.** A restored paused interval
has two completed rounds on screen. The result shares the live state's mutable list; after the
draft clears, a timer tick during route removal clears that list, leaving no rounds in the
summary. The finished result now takes a copy. Its two rounds, work/rest seconds, nullable HR
and active duration survive the actual finish transition. Swimming lap times, yoga poses and
match sets already construct independent lists. Five live typed-detail controls follow swim
lap Undo/pool/stroke/reopen, rowing's unmeasured distance, yoga pose progress, breathing's
unmeasured rate and interval finish. There is no metric calibration or schema change.

The same batch adds 15 saved-summary action controls, 11 Progress explanation controls, eight
Body-history controls, one Pushups scripted test covering eight named journeys, five live-detail
controls and 11 Train destination/history controls. Progress tests distinguish missing goal
evidence from missing context, expose the fixed-week explanation and return from Change goal.
Body tests retain related records on tape/weight deletion, roll back refused writes and preserve
first-reading/edit/unit semantics. Pushups tests exercise Start/Done/Undo/Pause/Resume/End,
blocked-notification manual logging, refusal/retry, settings, old-month recap and empty history.
Train tests reach Run/Walk/Gym/Home/Other setup without starting a session, cancel past entry,
select the running week in km/mi, retain private history while excluding it from running records,
and open missing/interrupted/saved-session destinations. These use synthetic SQLite and route
rows; the profile write in Body, platform paths, preference storage, permission delivery and
schedulers are explicit substitutes. They are not GPS/radio/notification or phone acceptance.

All **112** cases pass targeted checks. The local union reaches at least **939** previously
missed executable lines, mapped only through identical source blocks against hash-checked
`e88fde29`; this is provisional and not a new full-run percentage or branch proof. The next
full cloud run and exact combined inventory remain pending. Layout/copy, scientific coefficients,
algorithm 99/schema 50, dependencies, release metadata and ACK ordering are unchanged. No IPA.

The next continuation is active on `coverage-expansion`; further IPA builds are held until
the requested coverage work is complete. Build 102 remains the cached candidate. New source
controls below are verified in Linux checkpoint `40189878355` at `e88fde29`, but are not in
a replacement IPA. All 101 added cases pass within **4,018 app tests/429 intentional skips**
(408 absent golden baselines). Analysis has zero errors/warnings and 258 infos; protocol passes
433/skip four, analytics 645/skip six, 13 Python controls and **213 visual checks/709 captures**.
Handwritten execution is **41,181/50,310 (81.85%)**, up from Build 102's 81.44%: 293 more executed
and 101 more instrumented lines, with **9,129 unexecuted**, a net reduction of 192. Raw root LCOV
is 41,232/57,923 (71.19%) across the same 203 imported files; the same seven generated files
are separate from the 196 handwritten files, and the same three constants/barrels remain
unimported. No exclusions, skip rules or denominator filters changed. Every handwritten and
unimported source hash matches the downloaded artifact. The next exact inventory is ignored
`build/coverage-continuation/e88fde29/coverage/gaps.json`, with current discovery ranges in
`build/coverage-remainder/next-inventory.json`. The screenshots use substituted fonts; no new
native compilation or device delivery is claimed. Earlier superseded checkpoint runs are not
used as passing full-suite or coverage evidence.

**COV-30 — retired connection attempts keep configuring a band.** Four failing synthetic
controls show a reconnect sending wake-window/live/battery/name commands after End session,
Unpair or disposal, and a retired backoff connecting to a newly selected band. The retry
checked its generation only at the loop boundary, then continued after asynchronous waits.
Foreground setup has the same interrupted-wait shape. Both paths now recheck lifecycle,
generation and paired identity before continuing; stopped backoffs wake to exit. A foreground
lease arriving after cancellation is released without releasing a token adopted by a current
session. Forty-seven targeted controls pass locally, including interruption at connect,
battery/name polling, wake-window and live arming, held headless ownership, retryable refusal/
exception and the repair pause. A fifth failing control shows that a repair pause arriving
during backoff still allowed one connect; the pause is now rechecked after delay/ownership waits.
Storage and ownership policies are real; the band transport
is substituted and its callbacks are not wired as native delivery. Full cloud verification
and a refreshed coverage inventory pass in checkpoint `40189878355`. No UI, metric, schema or ACK-order change.

**COV-31 — an old history wait can continue on a replacement connection.** A failing
held-transfer control ends the session, establishes a replacement transport, then releases
the old report. Its caller requests another history burst and overwrites the current capture
status. The burst now retains its connection generation and paired identity across cursor reads,
requests and transport waits. Foreground and forced catch-up also retire their deferred requests,
single-flight waits and calculation callbacks when their session ends. Already committed rows
are retained. Nineteen real-store/substituted-transport controls pass locally, covering archived/
R10 cursor progress independently of decoded rows, stale-timestamp continuation, the 20-session
bound, cumulative-counter spin prevention, throttle refusal, overlapping wakes and failure/retry.
The active clock, scientific definitions and BLE transfer/ACK implementation are unchanged.
Two additional failing sibling controls reproduce a periodic backfill acting after cancellation,
both behind an actual SQLite-held wake-plan read and a held transport write. The periodic caller
and shared wake-window helper now keep/check their original generation across those waits.

Ten additional integration controls pass through the real BLE frame queue, decoder and SQLite
transaction with GATT writes substituted, for both supported families. They verify exact-token
ACK only after durable decoded/archive rows, transaction rollback when archive or cursor writes
fail, no ACK on failure, and preserved committed rows without a stale ACK after disconnect during
commit. Unknown-revision archives deliberately do not invent a decoded frontier. These extend
the existing pure-policy/commit controls; no new BLE defect or physical delivery claim follows.
These 76 controls pass in the combined full checkpoint above; native builds remain held.

**COV-32 — AppState disposal leaves route resources running.** A failing armed-route
control retains a GPS subscription after disposal; the display-awake flag is also unreleased.
Disposal now cancels tracking, attempts the buffered tail save through the existing bounded
stop path and releases the display without finalizing or deleting the live workout/clock.
A failed tail save is contained and logged; it is not reported as successful persistence.
Disposed callers cannot re-prompt permissions, and failed stream setup releases its tracker.

**COV-33 — the live route's Try again action opens Settings.** The existing error card says
Try again, but its feed callback handles only plain permission denial as a retry. A failing
callback control opens Settings after a transient platform error. Error now retries the same
route-arming flow; service-off, permanent denial and reduced accuracy retain Settings. The
page's wording, layout, colors and actions are unchanged.

**COV-34 — saved-route read failure escapes unawaited arming.** A failing repository-read
control throws from the post-permission preparation, leaving no tracker or retry state.
The error is contained and logged, the existing route-error/retry state is used, and no new
recording starts against unknown saved history. A later retry keeps the same live workout.
Twenty-one route controls pass locally for these repairs and neighboring permissions,
concurrent arming, retained history, paused tracking, refused final persistence, and successful/
failed permission/storage returns after finish/delete/disposal. SQLite, AppState, route tracking
and the actual live-feed callbacks are real; geolocation delivery and the injected read fault
are substitutes. These do not prove device permissions, background GPS or native wake behavior.
**COV-35 — cold workout recovery resumes after its owner is disposed.** Two held real-store
read controls dispose AppState before recent/stale live rows return. Recovery then re-arms a
live workout/timer or finalizes a stale row after disposal. It now checks disposal/reset at
entry, after the read and before continuing the row loop or re-arming cadence. Both controls
pass without mutating the saved live row or inventing a finish. These are host lifecycle
controls, not process-termination or actual iOS restoration proof.

All 101 added controls pass in full combined checkpoint `40189878355`. No new IPA, release metadata, metric output, schema or scientific definition change.

The requested continuation began with all 10,832 Build 101 missed lines. Final full run
`40141173339` at `fc69b0d3` verifies COV-18–29 and all **232 added cases**:
**3,917 app tests/429 intentional skips** (408 absent golden baselines), zero analysis errors/
warnings and 257 infos, protocol 433/skip four, analytics 645/skip six, 13 Python controls and
**213 visual checks/708 synthetic full-scroll captures** with substituted fonts.
Handwritten execution is **40,888/50,209 (81.44%)**: 1,662 more executed lines and 151 more
instrumented than Build 101, leaving **9,321 unexecuted** (1,511 fewer). Raw root LCOV is
40,939/57,822 (70.80%) across the same 203 imported files; the handwritten view excludes the
same seven generated files. The same three constant/barrel files remain unimported. No
exclusions, skip rules or denominator filters changed. The exact next inventory is ignored
`build/release102/coverage/gaps.json`; discovery/context helpers remain under
`build/coverage-remainder/` and refuse stale source hashes. These are execution counts,
not manual review or branch/hardware proof. Native `40141175245` and full downloaded
manifest/source/version/checksum/ZIP/payload/AOT validation pass at the same source.
Build 102 is the single testing candidate; Build 101 was superseded without reported installation.

The six additional packs pass **84 synthetic cases**: AppState commands/device callbacks (31),
stored metric readers (13), derivation stop/resume/status (14), live transport (7), workout
history actions (8) and Food label boundaries (11). They use real synthetic SQLite stores;
radio, permission and platform boundaries are substitutes. History filters, destructive-action
confirmation/refusal, stored-summary navigation and the Food serving/provenance/retry outcomes
are asserted. Material calendar fonts are substituted explicitly; the history fixture uses
in-process SQLite to avoid simulated-clock/FFI-isolate teardown races. This batch is verified in
the full cloud run above, along with the later Recovery/Journal/match/goal/backup controls.
Build 102 (`0.9.69+102`) is the validated cached candidate. All later controls described below
are included in its final full run; physical acceptance and the remaining execution work stay open.

**COV-18 — calculation entry points can revive stopped work.** Selected-day recalculation and
raw import captured a new cancellation generation after an asynchronous read, so a stop that
already arrived could be ignored and a result written. Two failing first-read controls reproduce
the defect. Every day now carries its pass's generation into preparation/compute; the second
compute-stage fallback propagates cancellation instead of treating it as an optional-detail
failure and persisting a partial headline. Selected work skips housekeeping after a stop and
releases its process lock. Fourteen real-store controls cover four day entry points, stops before
compute and between stages, a fresh successful pass after an earlier stop, and the independent
rollup's first-read/status-write boundaries. Two more negative controls reproduce the rollup
stamping a history result after a stop; it now retains the previous status. Existing committed
transactions are retained; this does not claim rollback of writes committed before cancellation.
Algorithm 99 and the scientific definitions are unchanged.

**COV-19 — a refused live command reports the stream enabled.** The essential realtime-HR write
returned false on refusal or transport error, but its caller discarded that result and set the
live flags anyway. Both band generations reproduce the false-success path. Flags are now set
only after that write succeeds; refusal leaves the stream unarmed for retry and is logged,
without introducing a new thrown error into fire-and-forget callers. Seven transport-substitute
controls cover refusal, exception, successful retry, disabling/clearing and a fresh connection.
This proves Dart command/state behavior, not physical radio delivery or a received live sample.

**COV-20 — Recovery can explain a different score from the pinned headline.**
A real-store synthetic counterexample pins a morning score, then serves a later day's composite
with different driver contributions. `ReadinessData.load` reads the pinned number through
`getToday`, but `_compositeBreakdown` reads the overwritten day bundle and current baseline
series. Its points therefore add to the later calculation, despite the caption saying they add
to the shown score. The reproducer is ignored `build/coverage-remainder/recovery_probe_test.dart`.
Akshat approved the full-page correction preview. The first completed morning pin now archives
its existing composite, input values, comparison histories, missing-input notes and dated HRV
series in the same cursor write as the score. Later calculations still update normal metrics;
Recovery's points, usual ranges and recent-HRV card read the saved morning evidence, explicitly
captioned as the saved morning score. This archival copy changes no score/formula, algorithm
output or schema, so algorithm 99/schema 50 remain. The cursor already participates in whole-DB
export, restore, salvage and wipe. Legacy or malformed pins retain their score/history with
"Morning breakdown unavailable"; they never reconstruct the original from later inputs.
The approved kraft/cream composition is retained. All **18 new controls** and 15 existing
freeze/explanation controls pass locally. Synthetic controls cover later recalculation,
dated-history gaps, held-over unscored days, restart, next-day replacement, malformed snapshots,
database export/wipe/restore and the saved/legacy states at 1x, 2x and 3.1x text. Full cloud
verification is included in checkpoint `40141173339`. The six saved/legacy enlarged-text
states are included in the cloud visual job, with full-scroll synthetic captures and substituted fonts.

**COV-21 — older Journal entries disappear from an editor or lose their note/tags.**
The retained Journal editor and tag-answer pathways accept historical nights, but their reads
searched only the recent 30-day list. The retained rough-night answer read the same bounded list, then
replaced that older row using an empty note/tag baseline. Two failing real-store controls show
the hidden note and its deletion after logging a tag. Selected-day reads now use an exact-date
query, separate from the unchanged recent-list window. Rough-night answers merge tags in one
transaction with the current note, retaining concurrent answers and unrelated numeric entries.
The new repository methods are additive; list ranges and whole-entry replacement keep their
existing meaning. These editor/tag routes are not current personal navigation: Sleep passes
`ask: never`, as the dormant-path inventory below records. Their tests exercise retained code
and compatibility/data-preservation contracts, not a newly exposed personal flow. No page
composition, scoring formula or schema changes.

**COV-22 — adding a custom Journal field discards the unsaved day draft.**
After the definition committed, the editor reloaded the entire day, replacing unsaved note,
ratings, doses and tags with the stored versions. A failing modal round-trip control reproduces
the loss. It now adds only the committed definition to the editor; the draft and conflict
baselines remain intact. A full modal/create/edit/Save round trip verifies the original note,
rating, tags and new field value reach storage together. Thirteen new synthetic controls pass
for COV-21/22, including older-day conflict refresh, concurrent tag additions, refused definition
write/retry, time-picker cancellation and custom-field validation/kind changes. Seventeen existing
save/conflict and neighboring controls also pass. Full cloud verification is included in
checkpoint `40141173339`.

**COV-23 — one match-score decrement can remove many points above 100.**
The live match screen allows point increments above 100, but its decrement clamped the result
to 99. Four failing controls reproduce the jump for both sides at two valid larger scores.
Decrement now removes exactly one point while retaining the zero floor. The existing display,
draft shape, scoring feature and all physiological/calorie calculations stay unchanged. Nine
live-match controls pass for the correction, zero/point controls, closed-set append/reset,
restart, Finish cancellation and transfer of closed/partial sets into the summary.

Fourteen additional goal-picker controls pass for all phases, all fat-loss paces and training
ages, measured/absent holding weights, failed-save retry, Back/Keep editing/Discard and full
navigation at 2x/3.1x text. They found no new goal-calculation defect. These 23 cases are included
in full checkpoint `40141173339`; they have no separate execution-percentage claim.

**COV-24 — backup passphrase dialogs overflow at enlarged text.**
With readable substitute fonts, both creating and opening a backup overflow at 3.1x text.
The keyboard-open baseline works; the earlier keyboard overflow was a block-font test artifact.
Akshat approved the complete before/after preview in ignored
`build/coverage-remainder/backup-preview/index.html`. The existing AlertDialog now uses its
built-in scrolling content; all wording, obscured fields, exact passphrase bytes, creation
minimum, older-backup unlock rules, encryption/container format and cancellation remain.
Ten synthetic prompt controls pass, covering short/mismatched/empty entries, exact spaces,
older short passphrases, Cancel and keyboard/large-text creation/restore. No cryptographic work
or real backup data runs in these UI checks. The four full-scroll pressure states join the cloud
visual job. The common render helper now supplies readable fonts for Material's Roboto family,
as well as the existing app families, preventing false block-font reports.

All 148 cases and seven repair families COV-18–24 are verified by the full checkpoint above.
The remaining inventory is still active and is not all hardware blocked. Build 102 is the
validated cached candidate; installation and physical acceptance remain open.

**COV-25 — shared confirmations clip messages/actions at enlarged text.**
The shared sheet's height ceiling and non-scrollable column overflow for Finish/Delete/Discard
at 3.1x, and for a longer import-link message at 2x. Ten failing matrix controls reproduce it.
Akshat approved the full modal preview; the same sheet can now grow to its available height
and scroll. Messages, colours, labels and true/false choices remain. All 24 matrix controls
pass across four actual caller messages, three text sizes and both choices, checking that the
message's final rendered line is reachable as well as the selected action. Full-scroll captures
are included; layout exceptions alone are not the visibility check.

**COV-26 — Reset silently clips the deletion disclosure.**
The initial reset AlertDialog constrains its Text without a scrolling viewport: at 2x/3.1x its
last lines are outside the text box, despite no RenderFlex exception and the full string being
present in the widget tree. Rendered selection-box geometry reproduces the missing disclosure.
Akshat approved every scroll view of the full reset preview. The existing dialog now uses
built-in scrolling; wording, Keep my data, Delete everything and actual reset behavior remain.
Three real Settings-entry controls verify full-text geometry/reachability and cancellation;
the destructive callback is substituted and must stay uncalled. These 27 controls are verified
in full run `40141173339`, with native `40141175245`. The combined COV-18–29 checkpoint above
reaches 81.44%/9,321; no physical reset/confirmation delivery is inferred.

**COV-27 — a settled workout can keep the previous activity/window's score.**
The recent-session sweep cached only `id@end`, although changing an activity changes its energy
method and retiming can move only the start. A real-store control first settles a lift, uses the
same narrow type writer as Change activity, then reproduces a sweep that leaves the old calories
unchanged. The cache now keys id, both bounds and activity type; unchanged sessions still avoid
redundant writes. No equation, coefficient or day-result output changes, so algorithm 99 remains.
Nine synthetic sweep controls cover type correction, start-only retiming with later imported
coverage, a moving frontier, live-to-finished state, retry after a substrate-read failure, honest
absence, fabricated ends and retention of privacy/effort/HR-recovery fields. Nineteen existing
manual-workout/calorie-repair neighbors also pass. All are verified in full run `40141173339`;
native `40141175245` passes. Physical edit/sync delivery remains open.

Fifteen further step-goal editor controls verify invalid/non-finite and boundary inputs,
write refusal/retry, disposal during successful/refused writes and usable actions at 2x/3.1x.
Nine Sleep-page controls cover fallback confirmation, manual reversion, selected-night rejection,
write failure versus an unapplied saved correction, both picker cancellations, overnight instants
and disabled duplicate writes/disposal. These use the real widgets and substitute the command/
post-write calculation boundary; they are not new proof of native time-picker or engine delivery.
Those controls brought the continuation to 208 cases; the final total below is 232. The remaining
execution inventory stays open.

**COV-28 — analysis export ranges overflow at enlarged text.**
The range picker used a non-scrolling column under the default short-sheet ceiling. Both
2x/3.1x before controls reproduce the overflow; the actual Your data button reproduces it too.
Akshat approved the full-scroll preview. The same five ranges and complete explanation now grow
within the viewport and scroll, retaining selection, cancellation and export semantics.

**COV-29 — Your data's working message exceeds the screen width.**
The actual export flow also exposed an unbounded status Text beside its spinner. At 2x/3.1x it
runs past the right edge during imports, exports and rebuilds. Akshat approved the complete
before/after page. The existing message now wraps in the remaining row width; the spinner,
action lock and operation behavior are unchanged. All twenty-four new real-screen controls pass in the final full run, covering
all five range selections at three text sizes, picker cancellation without file creation,
share outcomes/failure/retry and temporary report cleanup, plus working-state layout/action
gates. The OS share sheet and rebuild callback are substitutes. Six pressure states join the
cloud capture job. The continuation totals 232 targeted cases. Final full run `40141173339`,
native `40141175245` and downloaded-artifact checks pass at `fc69b0d3`; the remaining execution
inventory and physical-device acceptance stay open.

## Build 100 baseline

All 16 earlier families passed full run `40046857679` at fixture revision `40f9fee6`, whose
app source is identical to `1277cd3a`. Native `40044650218` and downloaded validation passed.
Its testing folder is superseded by Build 101; its exact fingerprint remains in `setup.md`.

## Baseline and reuse

The baseline is app source `e52d571a`, verified by `18324f76` in run `40003142620`.
Root LCOV exercises 37,534/49,891 instrumented handwritten Dart lines (75.23%): **12,357
instrumented lines were not executed**. Five handwritten files were not imported at all.
This is execution coverage, not the proportion of source reviewed. It excludes native iOS
and independent package suites, and does not measure branch correctness or physical delivery.

## Verified result

The clean full run passes **3,589 app tests / 429 intentional skips**, including all 65 new
cases. Of the skips, 408 need absent golden baselines. Analysis has zero errors/warnings and
235 informational lints. Protocol passes 433/skip four; analytics passes 645/skip six. The
visual jobs pass 152 checks and produce 607 synthetic captures. Eight iOS contract checks
and the four original inventory controls pass in CI; all five inventory controls pass locally.

Root LCOV records 38,375/57,649 lines (66.57%) across 203 imported Dart files. Excluding seven
generated localization files, handwritten execution is **38,324/50,048 (76.57%)** in 196 files,
up from 75.23%. There are 790 more executed lines; the instrumented denominator also grew by
157, so this is not a claim that 790 old missed lines were all exercised. **11,724 instrumented
handwritten lines were then unexecuted.** The production entrypoint and error logger became
imported/exercised. The three unimported files are the build-profile constant and two UI barrel
exports; importing them would not establish another user flow.

That baseline inventory is ignored `build/coverage-audit/build100-final.json`, alongside the
canonicalized Build 99 baseline. No denominator filters or exclusions were added to raise the
percentage. Native iOS, independent package suites, branch correctness and physical delivery
remain outside this root line-coverage measure.

## Build 101 execution extension

**Status:** Complete on `coverage-expansion`; baseline is the verified Build 100 result above.
Add meaningful outcomes for missed deep Lift/Food/settings/history and state/storage boundaries,
with real synthetic ledger writes and failure/retry/restart checks where applicable. Keep the
same denominator and retain earlier tests. Do not import dormant screens, assert only widget
existence or call private helpers solely to raise a percentage. New gains require a clean full
cloud coverage artifact. The incline-walking proposal remains separate and unimplemented.

The extension adds 96 passing targeted cases in five files:
`coverage_deep_lift_test.dart` (27), `coverage_data_actions_test.dart` (28),
`coverage_motion_retention_test.dart` (27), `coverage_meal_actions_test.dart` (8) and
`coverage_analysis_pipeline_test.dart` (6). All data are synthetic. Real SQLite writes cover
split/load identity, history-preserving edits, finished-set correction/deletion, refused-write
retry, meal copy/save, import review/commit and analysis-file provenance/privacy/denominators.
Share/picker/native-motion substitutes check Dart outcomes and cleanup; backup/profile/rebuild
substitutes check the data screen's responses, not native delivery or the underlying engines.
Existing independent storage/crypto/engine regressions remain required.

**COV-17 — split/exercise sheets return into disposed owners.** Three negative navigation
controls reproduced `setState() called after dispose()` on rename, exercise edit and exercise
add. Mounted guards now reject the late result before mutation. The sibling live set,
variation, add/remove, rest-setting and recent-exercise callbacks also check their owner before
applying a returned result or touching disposed text controllers. Successful persistence already
in flight remains durable; the fix does not undo a committed workout. All 27 Lift checks pass
with the real bundled font substitute. No layout, metric, ACK, schema or dependency change.

Build 101 (`0.9.68+101`, algorithm 99/schema 50) contains this lifecycle repair. Full cloud
analysis/app/package/visual coverage and native compilation pass. Downloaded manifest/source,
checksum, embedded version, complete ZIP CRC and compiled Runner/App AOT checks pass, including
the source-revision literal in AOT. The one-slot testing folder is
`WHOOP-0.9.68-build101-9a92656f`; SHA-256
`f0dfcd247f47644ced3f88268e312c9671d81b35d022df8a0d96b501f25818bd`.
Build 100's folder went to the Recycle Bin. Build 70 recovery is unchanged. No installation,
signing enrollment or native-device acceptance is inferred from the successful software checks.

Reuse the repair contracts and passing tests in `build-98-audit.md`, `build-97-audit.md`,
`build-96-audit.md` and `build-95-repairs.md`. Revisit their implementation only where an
unexecuted sibling/failure path or changed dependency exposes a new question. Do not repeat
the previous broad screen sweep or count a previously passing test as a new regression.

`tool/coverage_gaps.py` records all uncovered line ranges, unimported files and source hashes
from an LCOV artifact. Generated output belongs in ignored `build/coverage-audit/`; unchanged
source hashes allow review evidence to carry forward. A changed hash requires checking the
affected paths again. No exclusions or no-op calls may be added just to improve the percentage.
Hashes normalize CRLF to LF so Windows/Linux checkout formatting does not invalidate unchanged
source evidence. Every handwritten baseline hash is checked against the `e52d571a` Git blob;
generated checkout files are excluded from source-review carryover. The five inventory controls
include equivalent LF/CRLF content and a real-edit counterexample.

## Review coverage and remaining execution

- [x] Inventory every baseline LCOV miss/unimported file with source hashes; preserve the
  complete raw ranges in ignored `build/coverage-audit/build99-baseline.json`.
- [x] Exercise formerly absent entrypoint/error-log and zero/low-coverage GPS, BG-task,
  restoration/gate and cold-retry boundaries with meaningful outcomes and retained writes.
- [x] Trace uncovered AppState initialization, import/publication, foreground/background,
  band-owner/reconnect, active-clock/route and calculation scheduling branches. New contracts
  are COV-01/02/07/09/10; retained session/reset/phone-step contracts remain in Build 98's map.
- [x] Review deeper editor/settings callbacks and their storage/read seams, using the prior
  full flow map rather than duplicating the main-screen sweep. COV-05/06/08/11–13/15/16 add
  previously absent failure/retry, disposed-caller, route-refresh and accessibility evidence.
- [x] Trace the BLE/derivation/repository misses against commit-before-ACK, cancellation,
  retention/finalization, absent input and versioned publication. COV-14 adds the failed-rescan
  retry control; no decoder, coefficient, ACK or scientific definition changes.
- [x] Complete full cloud analysis, app/package suites, final coverage and full-scroll capture
  review for the final implementation in `40046857679`; earlier failed/cancelled runs are not release proof.
- [ ] Physical iPhone/band acceptance remains separate: permissions, radio/restoration,
  real GPS/background/audio/notifications, camera/share gestures, signing and soak.

This completes a coverage-directed **software review pass**, not execution of every missed
line. The remaining LCOV regions retain their exact file/range inventory; they are not erased,
excluded or declared unreachable to improve a percentage. Evidence is carried by concern:

- **Executable host paths:** startup/onboarding, diagnostic chaining, settings, Food/Body/Lift
  saves, recorded-zone edits, background callback reactions and cache publication now have
  the new controls below. Existing `startup_and_rebuild_recovery_test`, `app_state_regressions_test`,
  `workout_stop_durability_test`, `workout_reliability_test`, `route_tracker_test`,
  `ui2_food_flow_test`, `db_paged_import_export_test`, `import_data_safety_test` and Build 98/99
  nested/durability/secondary controls retain their prior evidence. They do not prove every
  exception branch in each containing file.
- **Storage/calculation/protocol defenses:** DB repair ladders, archive/quarantine, incomplete-day
  preservation, isolate failure/cancellation, baseline gates, unknown signal families and native
  GATT outcomes are source-traced alongside the existing ACK, migration, result-protection,
  readiness/baseline, decode and independent package tests. Rare corrupt-page/low-space/process
  loss combinations and absent private replay fixtures remain execution gaps; no real record was
  used to manufacture those cases.
- **Concrete iOS delivery:** GATT, ASK, zone/pedometer/home bridges, precise GPS, MapKit, camera,
  notifications and audio have host adapters or source contracts, not a physical certification.
  Swift BG-task completion/expiry and BLE-restore handoff were source-reviewed; compilation and
  synthetic callbacks cannot establish OS scheduling, native UI behavior or band receipt.
- **Retained dormant/developer branches:** manual Journal/custom fields and appearance settings
  are not current personal navigation. Sleep's sole RoughNightCard uses `ask: 'never'`; shared
  Journal input widgets remain live and are not classified dormant. Gallery fixture controls,
  default abstract repository throws, older import/schema compatibility and non-iOS plugin
  branches remain in the source. A dormant screen is not an exercised user flow, and legacy
  import/migration code is still a real recovery concern covered by its own contracts.
- **Non-executable/absent baselines:** build-profile constants and two UI barrel files do not
  become meaningful flows just by importing them. Generated localization is reported separately.
  Missing golden baselines remain explicit skips; synthetic screenshots are not pixel-baseline
  tests or native SF-font/VoiceOver evidence.

The context extracts under ignored `build/coverage-audit/` identify the reviewed gap clusters;
`build-98-audit.md` owns the complete retained end-to-end flow map. Neither static action counts
nor source context extraction is counted as new runtime verification.

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
  use the same guard. The Food calendar and metric-day/quiet-hour pickers also refuse results
  after their caller closes; Food meal selection and late workout-detail navigation check their
  owner before updating. A fifth real-navigation control confirms the Food callback. No feature
  or layout changes.
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
  Full-scroll controls pass at 1× and 3.1×; the cloud capture job includes both and the read-failure state.
- **COV-13 — an optional Lift refresh falsely reports a committed save as unsaved.** An
  unreadable earlier log reproduces the misleading failure after a new set is durable. The
  controller now distinguishes save failure from refresh failure, retains a saved warning and
  still starts the chosen rest timer. A subsequent clean edit clears the warning. Initial
  history failures remain explicit. Linked split/import cache hydration is best-effort only
  after commit; ordinary startup hydration remains strict and logs the post-commit failure.

- **COV-14 — a failed recent-day refresh consumes its retry.** A real refused `day_result`
  insert reproduces a stored baseline signature despite the failed day. The rescan now
  acknowledges the signature only when every prepared day succeeds; failed/null preparations
  retain the pending change and existing results. Retry with unchanged baseline succeeds, then
  the subsequent clean rescan becomes a no-op. This repairs scheduling, not a scientific output
  definition; algorithm 99 and every formula remain unchanged.

- **COV-15 — a corrected route reuses its earlier map/projection.** The snapshot cache used
  only session ID/size, despite correction changing the track. It now matches immutable copies
  of the coordinates, retains newer requests after an older failure, rejects malformed projected
  point counts/values and safely handles empty thinning input. The actual map widget uses its
  plain-route fallback while a new image is pending rather than retaining an earlier projection.
  Five synthetic channel/widget controls pass; no map service or location request was used.
- **COV-16 — secondary settings have silent read/write failure paths.** Notification and
  Pushups settings can spin or show no feedback after a failed read/save. Body settings also
  expose initial defaults before its saved configuration loads, and Journey start lacks save
  error handling. These screens now withhold editable defaults until reading succeeds, offer
  Retry and retain prior choices after a refused save. Six actual-widget controls cover all
  three readers and Pushups goal/interval plus Journey start refusal/retry. Failure captures
  at standard/enlarged text are included in the cloud visual job.

Sixteen added Dart files contain **65 targeted cases** for these contracts, real cold-start
routing with an optional notification failure, and GPS service/permission/sample boundaries.
The GPS checks use simulated plugin results, not physical location delivery. Existing manual
workout (11), startup/quarantine (7), baseline-rescan (3) and three legacy failure/cancellation
cases also pass.
Five Python inventory checks and eight iOS contract checks pass locally. The four original
inventory controls also pass in the cloud; the fifth checks cross-host source-hash equivalence.
Fixture/compiler failures
are not counted as app findings. Logs stay in ignored `build/coverage-audit/`.

The first full cloud run, [40015378904](https://github.com/akshatksingh18/whoop/actions/runs/40015378904),
passed analysis, package suites and the original visual job, but the app suite had three old
fixtures without an application-support path provider. The stricter Pushups inbox correctly
surfaced that missing fixture. Those fixtures now supply a synthetic path, retain their
original assertions and pass all three targeted cases. A clean full rerun is still required;
coverage from the failed run is preliminary, not successor verification. Intermediate runs `40042565354`, `40043039909` and native
`40043061254` were cancelled as superseded while the remaining source review found additional
repairs; cancellation is not a failing test or a release result.

Full app/package/visual/coverage run `40044648006` at source `1277cd3a` passes analysis,
packages and visuals, with 3,588 app cases passing, 429 skips and one old fixture failure.
The pairing source-row fixture started platform initialization without awaiting it, leaving
the six-second startup timeout pending at test teardown. It now uses `AppState.forTesting`;
all pairing assertions remain. All 39 router cases and both separate real startup controls
pass together. The clean full rerun `40046857679` passes; the earlier run's interim coverage is not release proof.
Native run `40044650218` passes, and the cached unsigned `0.9.67+100` IPA passes downloaded
manifest/source/version/checksum, full ZIP CRC and compiled Runner/AOT payload checks. Its
SHA-256 is `3251c08089021f18af9d551e6b1738fb46e02294f01dc796ac7dbcb078f1d183`.
Those checks validated the then-cached Build 100; Builds 101 and 102 subsequently superseded it.
Phone acceptance and signing gates remain open; Build 70 recovery is unchanged.

The final cloud visual job in `40046857679` passes **152 checks and 607 synthetic captures**,
including 19 focused phone-width captures. Review of the earlier job found its new settings
failure captures used the default wide test window; the two fixtures now use a
390-logical-pixel phone viewport. A focused nine-case local run also passes. Standard/3.1×
read failures and every enlarged Zones scroll position were inspected; Retry remains reachable
through the enlarged Pushups page. Existing Today/Trends/Food/Train/Progress/Body samples retain
their composition. These are test-fixture corrections only: app source remains identical to
`1277cd3a`. One earlier Today scroll frame is no longer required to reach the bottom; the final
viewport still contains the maintenance card and navigation. Captures use substituted fonts,
not physical iPhone typography, and are not comparisons with absent golden baselines.

## Limits

Keep the locked A+B interface and all features. No scientific tuning, dependency/capability
change, live-data fault injection or private export is authorized by a coverage target. Native
radio/GPS/audio/permission delivery, signing and soak still need the iPhone. Synthetic native
channel checks establish app reactions, not what iOS or the band physically did. Pure constants,
barrel exports, generated strings and dormant upstream-era screens must not be called tested
user flows. A 100% headline is not a substitute for these distinctions.

## Focused phone acceptance

Use the existing encrypted database/photo recovery and same-ID upgrade procedure before installing
the candidate. Keep Build 70 recovery until current-version device/signing acceptance is reported.
Do not corrupt live storage, alter the phone clock or force database failures to repeat synthetic tests.

- **Closed-app Pushups:** take separate Done/Pause notification actions, reopen, inspect the
  session history, then reopen again. Each real delivery must appear once and reminders must
  follow the saved session. Actual iOS delivery remains unproved by the file/receipt tests.
- **Train and Lift:** log a set with rest enabled, change a linked split, return through history
  and relaunch. The saved set/split and timer must agree; initial history failure must retain Retry.
- **Historical workout editing:** inspect an existing recorded travel day if available. An
  untouched start/end must remain exact, and an explicit edit must display in that day's zone.
- **Run/Walk maps:** record a short safe route, inspect its cursor, correct the saved route if
  that flow is used, and revisit it. Real GPS accuracy, native snapshots and background voice
  need the phone; the automated map check substitutes the channel response.
- **Deeper pages:** open Train → Strain → Zones, Settings → Notifications, Pushups settings and
  Progress → Body settings at normal/enlarged text. Reach the last section and every action.
  Saved choices must survive returning to the page; Retry must remain available if a read fails.
- **Startup/background/signing:** cold-open and resume after ordinary background use, then
  complete the existing BLE-restoration, notification/permission, data-preserving upgrade,
  current-version refresh enrollment and 72-hour matrix in `todo.md` and the iOS guides.

The 17 repaired families are software contracts, not a substitute for those physical outcomes.

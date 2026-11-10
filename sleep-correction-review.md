# Sleep correction during recalculation

**Status:** The approved algorithm101 Sleep preservation and reviewed Sleep/Recovery pages pass full110;
ordinary/rescan rehoming preserves their assertion values and recovery contracts. Native
acceptance remains separate. Current algorithm102 adds the separately approved restored-scalar
reader guard;31 local controls/actual-page parity pass and combined cloud verification remains.
That guard changes none of this review's Sleep correction code. The original detailed82 evidence
below remains retained.

Algorithm101 preservation, approved explanations and later restore/edit/pin-only/
reset protections pass fully green82:5,674 app checks/429 retained skips, both packages,
analysis and743 gallery PNGs;101 focused checks pass.24 layouts/53 complete-scroll captures
retain five input names, history and approved actions;34 preview pairs have small platform
rasterization differences. No pixel/native parity claim.

All35 storage preservation controls pass full cloud verification. Accepted windows/pin
absence survive old backups; committed counts and disjoint retry remain. Runtime reset
ownership/admission prevents older restores recreating rows, including post-merge writes/
day zones; existing CalculationStore ordering remains. Originals/backups are local.
No formula/persistent-key/schema change:algorithm101/protocol1.0.1/schema50. Broader physical
interruption/space/phone acceptance remains open. `coverage-audit.md` owns exact evidence.

## Confirmed failure

The [cloud diagnostic](https://github.com/akshatksingh18/whoop/actions/runs/41195062255)
fails on parentless candidate 58, `93139775ee709ad1c31edc131c40540c1b85a9bb`.
It uses the already verified three-hour authored night, an older sparse day, actual SQLite
and `AppState.reanalyzeAll()` / `setSleepOverride()`. No busy flag or result is fabricated.
The two real day calculations run concurrently, so first-day progress can arrive while
the other day is already computing from its old input snapshot.

The check proves, in order:

1. The actual two-day reanalysis completes and the edit was accepted while it was busy.
2. Both new boundaries are durable in the override table: start +1,200 / end +9,600 seconds.
3. The sleep reader reports a present manual window, but its onset is still start +900.
   Expected onset is `1617672000`; actual is `1617671700`, five minutes earlier.

The test stops at that assertion; later wake/raw-frontier assertions are not claimed passing.
The existing serial correction/read-refusal/explicit-retry controls pass full candidates 56/57.
The complete failure output, original test and hashes stay in local recovery. This separate
red diagnostic remains an open blocker even if the combined candidate-58 suite passes.

## Shared cause and proposed repair

`setSleepOverride`, `confirmSleep`, `rejectSleep` and `clearSleepOverride` all persist first,
then call `_reanalyzeForOverride`. Its `if (reanalyzing) return` drops that recalculation
request. The durable edit survives; the already running calculation can finish with older
boundaries. `reanalyzeAll` releases the busy flag but does not replay this accepted edit.
Phone-step permission/removal also use this helper; review those callers in the same fix.

Reuse the existing coalesced-drain pattern used by nap edits and the existing deferred-override
state. The one shared helper should retain a pending request, wait for the real calculation
owner, and derive from the latest durable inputs. Edits arriving during that pass request one
more pass, rather than competing workers. Callers share the completion Future. Keep the
existing notifications/revision refresh and force-derive semantics. Release ownership in
`finally`; contain failure, retain the existing explicit retry/foreground cancellation policy,
and stop queued work after disposal/reset. Do not add a second derivation engine or timer job.

This changes when an already accepted user edit is recomputed. It adds no new measurement,
sleep detector, coefficient, calorie method, field, schema or persisted identity. A corrected
window can legitimately change its dependent sleep/HRV/readiness results, just as the same
serial manual edit already does. It cannot rebuild detailed inputs that retention has removed.

## Version and validation decision

Approved: keep protocol **1.0.1**, algorithm **100**, schema **50** and app **0.9.69+102**.
The accepted input and existing calculation method are unchanged; this repairs scheduling of
the user's correction. It is not a new physiological model. The output/version rule in
`CLAUDE.md` required this separate review. Akshat answered “Approve shared repair/version plan”
to the linked proposal before the production change.

The exact original failing diagnostic is retained locally. Its behavior is promoted into
`test/coverage_sleep_override_overlap_test.dart`, in normal cloud regression discovery, with
nine real-night cases: edit/repeated edit, confirmation/rejection/clear, read refusal/retry,
background/foreground, disposal and reset. The original assertion measured acceptance when
the edit Future completed; completion now waits for recalculation. The promoted check instead
observes the actual durable change while the real engine remains busy. It retains the overlap
premise and exact expected boundaries rather than weakening either. None has run locally.
The separate diagnostic workflow targets this same file for early feedback on candidate 59;
its result cannot replace combined verification. Original candidate 58 stays immutable.

The [candidate-59 early run](https://github.com/akshatksingh18/whoop/actions/runs/41196382307)
passes edit, repeated edit, confirm, read-refusal/retry, disposal, background return and reset.
It fails Reject (`has_sleep` stays true) and Clear (source stays manual). Their new durable
intent assertions pass and a recalculation actually runs. Logs identify the existing
`nightSubstrateRegressed` preservation guard: it treats the missing new night physiology as
pruned input and keeps the old complete manual result. No preservation rule is changed yet.
The two assertions remain in normal discovery and their exact failed source/log stay local.
Full candidate 59 (41196382278) has 5,428 passing/429 skipped checks and exactly these two
failures; its packages, analysis and 732 captures pass. Its LCOV/gaps are retained, not promoted.

`test/diagnostics/sleep_intent_serial_probe.dart` uses the same adequate night and fully awaited
serial commands, verifies the new intent plus retained raw frontier, then asks the same output
questions. Its bounded cloud workflow tests whether these failures predate the queue repair.
The [serial cloud run](https://github.com/akshatksingh18/whoop/actions/runs/41197092882)
fails both despite fully awaited commands and retained raw frontier. Both failures reach
the same older night-preservation guard, independently of overlap. This is a diagnostic
outside default discovery, not an excluded old regression. A genuine
preservation-policy change requires a concrete separately reviewed output/version decision;
never disable the richer-night guard globally or erase retained night baselines to get green.

The helper retains pending work behind AppState and the process-wide engine, coalesces shared
completion and drains again if another edit arrives during its pass. Background holds leave
the existing foreground retry flag; cancellation does not spin. Reset clears pending work and
waits for the owned Future before wiping. Disposed/reset owners cannot start queued work.
The redundant phone-permission wait is replaced by this shared queue; permissions and step
source policies remain. No new engine, persistent table, native job or calculation method.

Check the other shared callers without changing their permission or step-source policies.
Run quick targeted analysis locally, adequate-night controls and the full suite on Linux Actions.
Do not infer coverage from the diagnostic or weaken its real-overlap premise.

The scheduling repair proposes no UI layout, copy, navigation or control change. The separate
Reject/Clear preservation proposal must show complete Sleep/Recovery Before/Proposed pages,
dependent-output and version effects, recovery ownership and retry/restart behavior. Clear's
accepted algorithm-101 plan governs the working preservation repair; the amended
breathing-link UI is authorized and implemented for verification.
Never globally disable richer-night preservation or erase old night/baseline evidence.

The scheduling-only repair did not change UI. The later authorized correction pages now read
the corrected saved result through their existing revision notification. Any additional UI
change requires its own complete-page previews and approval. Native/IPA, migration N,
phone acceptance and exact-ref B5 approval remain held.

## Approved Reject/Clear preservation contract

The queue repair above is already approved and implemented. This is a separate proposal.
Akshat chose **unknown current output when Clear cannot produce a usable automatic
replacement**, while retaining the old result for recovery. Akshat subsequently approved the calculation/preservation plan below and algorithm 101.
The approved implementation passes full106. He accepted Fix sleep times being unavailable for the unknown day
and approved keeping the breathing report linked through the amended complete-page review.

### Proposed contract and version

- **Reject:** honor the durable rejection for the selected main night. Its old duration,
  stages, overnight HRV/RHR/breathing and Recovery must not remain current measured values.
  Reject does not mean zero hours slept or zero HRV. Naps and independent daytime data remain.
- **Clear:** remove the manual/confirmed/rejected override and request fresh automatic analysis.
  A usable replacement becomes current; no usable replacement means unknown, with the stated
  reason. Do not silently relabel the old manual result as automatic or reuse its cached candidate.
- **Preserve:** before accepting the command, atomically retain the affected prior result,
  original override/candidate, night-series/provenance and any matching frozen morning
  score/explanation, together with the new intent. Reuse the existing `baselines` JSON store
  and its transaction/update pattern for a versioned per-day intent/recovery record. Keep
  prior generations; never overwrite the only recovery copy. No new table or schema change.
  Failure of this transaction must leave the old intent and current result unchanged.
- **One current intent:** a durable request generation identifies the current action. A late
  worker may publish only for the inputs/generation it actually read. New edits supersede
  stale completions; restart, background return and explicit retry retain the same intent.
  Clear needs this marker because deleting `sleep_override` alone erases its provenance.
- **One shared read policy:** current Sleep/Recovery/Home, metric details, charts, baseline
  reads and exports must agree about the affected night. An outstanding accepted intent masks
  stale main-night values even when no raw remains and the derivation loop cannot run.
  A read/worker failure remains a failed/pending calculation, not evidence of zero sleep.
  Keep original explanations attached to their original score; do not reconstruct them.
- **Morning-score exception:** an explicit correction invalidates the affected night's old
  frozen headline as a *current* answer. Keep the original pin/explanation unchanged for
  recovery. A usable corrected result supplies current output; otherwise it is unknown.
  Ordinary syncs still cannot rewrite a settled morning score. Unaffected nights are unchanged.
- **Baseline safety:** a rejected/unresolved main night cannot keep training current night
  baselines through stale `metric_series`. Retain its old values/provenance for recovery and
  exclude them through the same shared policy until a usable replacement exists. This can
  change the available-night count and later newly calculated Recovery, without new weights
  or formulas. Do not rewrite unrelated historical results or existing pinned explanations.
- **Guard boundary:** the raw-pruning/richer-night guards stay in force for ordinary reanalysis.
  Only a matching accepted explicit correction may supersede its own old night. No invented
  substrate, blanket guard removal, old-row deletion or success/finalization claim for an
  absent replacement. Unknown output must not enable raw pruning.
- **Proposed version:** algorithm **101**, protocol **1.0.1**, schema **50**, app **0.9.69+102**.
  This changes accepted intent/output and baseline membership, so it needs the separate
  algorithm-version decision even though the physiological formulas and package source do not
  change. Algorithm101 and its owning version contract are implemented and verified in full106.
  The physiological formulas and package source remain unchanged by this correction. Native/IPA and persisted-name migration remain held.

The complete database backup must retain the intent/recovery record; structured import/export,
same-day conflicts, reset and rollback need explicit tests. Do not offer to recover signals
that retention had already removed. Older builds cannot enforce this new intent contract;
rollback must use the preserved full backup and its known version, never erase newer rows.

### Complete Before/Proposed pages

These are authored data prototypes using the complete existing production Sleep/Recovery
views, not a repaired derivation. Only the proposed Sleep absence wording is substituted in
the local localization delegate; Recovery uses the existing metric-note/diagnostic reader.
The old fixture has a 2h30 main night, an independent 30-minute nap and a retained score of 72.
The proposed Recovery history retains the earlier four points and shows a gap for this night.
No actual recordings, personal measurements, native fonts or phone acceptance are implied.

| Page / width / text | Before | Proposed Reject | Proposed Clear without replacement |
| --- | --- | --- | --- |
| Sleep / 390 / 1.0× | [Before](build/ownership-checkpoint/sleep-intent-review/sleep_before_390_1.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/sleep_reject_390_1.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/sleep_clear_390_1.0x.png) |
| Sleep / 320 / 2.0× | [Before](build/ownership-checkpoint/sleep-intent-review/sleep_before_320_2.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/sleep_reject_320_2.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/sleep_clear_320_2.0x.png) |
| Sleep / 430 / 3.1× | [Before](build/ownership-checkpoint/sleep-intent-review/sleep_before_430_3.1x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/sleep_reject_430_3.1x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/sleep_clear_430_3.1x.png) |
| Recovery / 390 / 1.0× | [Before](build/ownership-checkpoint/sleep-intent-review/recovery_before_390_1.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/recovery_reject_390_1.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/recovery_clear_390_1.0x.png) |
| Recovery / 320 / 2.0× | [Before](build/ownership-checkpoint/sleep-intent-review/recovery_before_320_2.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/recovery_reject_320_2.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/recovery_clear_320_2.0x.png) |
| Recovery / 430 / 3.1× | [Before](build/ownership-checkpoint/sleep-intent-review/recovery_before_430_3.1x.png) | [Reject](build/ownership-checkpoint/sleep-intent-review/recovery_reject_430_3.1x.png) | [Clear](build/ownership-checkpoint/sleep-intent-review/recovery_clear_430_3.1x.png) |

Eighteen checks render eighteen complete pages plus eighteen 844px viewports. The first
generic-absence prototype is preserved separately; the proposed copy now names the actual
correction reason instead of claiming no explanation exists. Existing enlarged-text date/chart
axis ellipses remain visible and are not claimed fixed. This proposal introduces no layout
redesign. Actual implementation captures and cloud regressions are required after approval.

### Selected-day reachability decisions

The current no-night branch keeps day navigation, Naps and Reject's Undo action. It does not
show the following two controls. They are shown in the Before pages and absent in the proposed
no-night pages; the per-item decisions are now recorded below:

1. **Fix sleep times — accepted unavailable on this unknown day:** it currently needs a usable main window. Leaving it unavailable on
   this unknown day prevents an old cleared window from being treated as current. The old
   window remains in recovery and the control remains on other usable nights. If explicit
   re-entry from an unknown day is wanted, prepare that flow/preview separately; do not reopen
   the removed manual-main-sleep surface incidentally.
2. **Breathing pattern in sleep — keep linked in the approved implementation:** this opens an across-night report. Its existing link is
   inside the usable-night branch, so it would be unreachable from this unknown day's page,
   and potentially from Sleep entirely if no other usable night exists. Akshat chose to keep that existing
   report linked from the no-night page; prepare and approve the amended complete page
   before implementation. The report's computations/history are never deleted.

These are conditional navigation consequences, not permission to delete either feature or its
data. No tab, metric history or computation is authorized for removal by the Clear preference.

### Amended complete Sleep pages — breathing report remains reachable

Akshat approved the calculation/preservation plan and both per-item decisions. The local
prototype now adds the existing breathing-report row to the no-night branch, with identical
copy, target and shared helper. Day navigation, Naps, Reject Undo, uncertainty and the proposed
absence reason remain. Fix sleep times stays unavailable on the unknown day as accepted.
Akshat has now released the previous UI hold and authorized these amended pages.
The working implementation retains the approved reachability decisions below.
Do not ask the same approval question repeatedly.

| Width / text | Before | Proposed Reject with link | Proposed Clear with link |
| --- | --- | --- | --- |
| 390 / 1.0× | [Before](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_before_390_1.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_reject_390_1.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_clear_390_1.0x.png) |
| 320 / 2.0× | [Before](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_before_320_2.0x.png) | [Reject](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_reject_320_2.0x.png) | [Clear](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_clear_320_2.0x.png) |
| 430 / 3.1× | [Before](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_before_430_3.1x.png) | [Reject](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_reject_430_3.1x.png) | [Clear](build/ownership-checkpoint/sleep-intent-breathing-review/sleep_clear_430_3.1x.png) |

Nine focused rendering checks pass, with nine complete pages/nine actual-size viewports.
The reviewed correction copy and breathing row wrap at enlarged text. The existing date
ellipsis remains explicit. The prototype is a private source copy with rewritten imports and
one added row; its first import-resolution failure is retained separately and is not an app
failure. Recovery's complete proposed pages above are unchanged. No feature is deleted.

### Approved UI implementation plan

Akshat explicitly released the UI hold and authorized this reviewed plan. Implementation
and actual complete-page evidence pass full106;native/phone acceptance remains separate.

1. Use the approved durable-intent contract to distinguish rejected main sleep, cleared sleep
   without a usable replacement, usable automatic replacement, and failed/pending calculation.
   Never relabel an old manual night as current automatic sleep or render unknown as zero.
2. Keep `SleepDetail`'s layout, tokens and day navigation. Reuse its no-night status card,
   Naps link and Reject Undo. Add the existing `detailLinkRow` for **Breathing pattern in
   sleep**, with identical subtitle and `SleepBreathingScreen` target, to the no-night branch.
   Fix sleep times remains unavailable for that unknown day as accepted; do not reopen the
   removed manual-main-sleep surface.
3. Use reviewed localized absence wording tied to the actual persisted reason. Clear names
   the unusable automatic replacement; Reject names the user's rejection. Both explain that
   the previous result is kept for recovery. Preserve retry/uncertainty states and never
   claim an implemented recovery UI or measurements that do not exist.
4. Reuse Recovery's existing metric-note and diagnostic paths. Through the approved shared
   policy, withhold invalid current-night values and the affected current frozen headline,
   retaining the original pin/explanation for recovery. Keep earlier dated chart points and
   a gap for this absent night; do not reconstruct a different score's explanation.
5. Retain Naps, day navigation, Undo and the breathing-report door. Delete no tab, metric
   history, computation or feature. Existing date/chart ellipses are outside this scoped plan.
6. After approval, verify the states and actual navigation, enlarged-text wrapping, Undo,
   clear/retry/restart, unavailable manual entry and retained nap/breathing data. Keep both
   existing red calculation assertions. Adequate-night derivations and full analysis/suites
   run on Actions; local checks remain bounded. The current publication task adds no tests.
7. Capture actual implemented complete pages and 844px viewports at 390/1×, 320/2× and
   430/3.1×. Compare with the approved prototypes and retain manifests. Synthetic fonts/pages
   do not prove phone acceptance. Synchronize owning docs with implemented versus verified
   scope and retain native/IPA, migration N/phone and B5 gates.

### Required regression proof

Keep both existing red assertions and the original failed source/logs. Extend the real serial
and overlapping night controls for usable auto replacement, honest unknown/rejection, a prior
frozen score, full absence of raw, unrelated-night preservation, repeated edits and stale worker
completion, transaction refusal/retry, restart, background/reset and backup/export/restore.
Verify old recovery payloads/series/pins byte-for-byte and normal richer-night protection.
Run adequate-night derivations/full analysis/full suites only on Linux Actions. Targeted
synthetic pages are review evidence; they cannot certify the repaired calculation or phone.

### Approved additional correction explanation

Actual candidate-68 captures reveal that a correction-only diagnostic falls through to
“Everything above was present” under What was missing. That is false for a rejected or
unresolved night. Its unknown copy also says automatic when the accepted correction was
manual/confirmed. The storage repair must retain the intent provenance; no new physiology
or headline method is proposed.

[Complete Before/Proposed Sleep and Recovery sequences](build/ownership-checkpoint/sleep-explanation-review/review.md)
cover Clear, Reject and unresolved manual correction at 390/1×, 320/2× and 430/3.1×. All
36 prototype cases pass, including every scroll position. Proposed Recovery retains all
five input names, says Not used for this night, and gives the actual correction reason;
unknown Sleep/Recovery copy uses Analysis without inventing an automatic origin. No baseline
count is invented. Earlier history/current gap and all approved Sleep actions remain.
Akshat approved this additional copy/diagnostic repair. The working implementation matches
the reviewed five-input rows and generic Analysis wording; 24 targeted actual-widget checks
pass, including Clear/Reject/pending/manual/confirmed Sleep states and corrected Recovery.
Candidate 71 passes 79 focused checks and 24 targeted layouts.53 actual captures and 34
matched-frame comparisons are retained; all actions/inputs remain, with cross-platform
rasterization differences explicitly recorded. Full later verification and native acceptance
remain separate requirements.
Candidate-68 font-block captures are retained; adding the missing Material Roboto alias to
the authored capture fixture makes Undo readable without changing production typography.

### Restore boundary preservation

The original source/logs are retained under `cov51-import-race-negative` and the pin-only
original probe. The source-read wrapper pauses the actual backup reader; the accepted command
uses real SQLite and the unchanged transactional correction method. No production test hook
or replacement database is introduced. A new correction during a merge now refuses the next
page inside its exclusive SQLite transaction, before an old override/pin can overwrite it.
An imported revision advances the expected generation only after that page commits. Pin-only
source history participates in preflight conflicts. Both stores and original results remain.
Four new cases plus26 retained preservation cases pass locally; wider cloud proof is pending.

# Sleep correction during recalculation

**Status:** Akshat approved the shared repair/version plan. The implemented helper passes seven
of nine early cloud cases, including the original overlap. Reject/Clear remain red through
an older preservation guard; the serial counterfactual also fails both, and combined Linux verification is pending.

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

There is no proposed UI layout, copy, navigation or control change. Existing pages should read
the corrected saved result through their existing revision notification. Any additional UI
change requires its own complete-page previews and approval. Native/IPA, migration N,
phone acceptance and exact-ref B5 approval remain held.

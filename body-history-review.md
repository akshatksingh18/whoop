# Body history average review

**Status:** Akshat approved A. The shared average correction passes full Linux
[41041518801](https://github.com/akshatksingh18/whoop/actions/runs/41041518801) on parentless `084d0b18`/candidate 47.
Original negatives, fifteen range/units/gap/future/short/single-day controls and two absence
controls pass. Four actual complete pages match approved A. Later milestone A is separately
owned by `body-milestone-layout-review.md`; its newer combined candidate-49 run also passes.
Native/IPA, migration, phone and B5 gates remain.

## What was wrong

All and Since start label the selected row as the average of the chosen range. The old row used
the last-seven-day window intended for the separate first/last-week comparison. In the
authored 61-day example, it showed 70.1 kg from seven days; the full-range mean is 70.6 kg
from 61 daily weights. Original failing tests/logs are retained locally; no public skip hides it.

`DESIGN.md` already calls for latest individual reading, seven-day average and selected-period
average. The existing daily-weight series and `weightWindow` mean remain the approved basis;
this does not introduce a new physiological model or reweight individual same-day entries.

## Approved choice

**A — approved and implemented locally:** show the whole selected range's average and count. Keep the current
first/last-week comparison, including its dates, count and change, as a separately named line
in the same selected row. Latest reading, daily weight, seven-day average, chart and controls
remain. All uses earliest retained day; Since start uses the existing baseline/fallback rules.

**B:** keep the existing seven-day value/count/comparison and rename that row to
“Last 7 days · comparison.” This makes its current number honest but leaves no separate
whole-range average in that row. It changes the earlier selected-period design contract.

No metric, uncertainty label, retained comparison or navigation action becomes unreachable
under either proposal. A adds the correctly scoped full-range mean; B retains today's value.
Back, Add body entry, range controls, More periods, all measurement chips, Readings/trend,
Body settings, All history, Photos, dated entries and Milestones are retained.

## Complete pages

Every link is a local full-page Flutter raster under the registered recovery checkpoint.
All includes every section through the last milestone. Since start has an additional ordinary
size comparison because the same selected row and reflow are shared by both ranges.

| Range / width / text | Before | A | B |
|---|---|---|---|
| All / 390 / 1x | [Before](build/ownership-checkpoint/body-mean-preview/all_before_390_1.0x.png) | [A](build/ownership-checkpoint/body-mean-preview/all_a_390_1.0x.png) | [B](build/ownership-checkpoint/body-mean-preview/all_b_390_1.0x.png) |
| All / 320 / 2x | [Before](build/ownership-checkpoint/body-mean-preview/all_before_320_2.0x.png) | [A](build/ownership-checkpoint/body-mean-preview/all_a_320_2.0x.png) | [B](build/ownership-checkpoint/body-mean-preview/all_b_320_2.0x.png) |
| All / 430 / 3.1x | [Before](build/ownership-checkpoint/body-mean-preview/all_before_430_3.1x.png) | [A](build/ownership-checkpoint/body-mean-preview/all_a_430_3.1x.png) | [B](build/ownership-checkpoint/body-mean-preview/all_b_430_3.1x.png) |
| Since start / 390 / 1x | [Before](build/ownership-checkpoint/body-mean-preview/sinceStart_before_390_1.0x.png) | [A](build/ownership-checkpoint/body-mean-preview/sinceStart_a_390_1.0x.png) | [B](build/ownership-checkpoint/body-mean-preview/sinceStart_b_390_1.0x.png) |

### A, complete ordinary page

![Proposed A, whole Body page](build/ownership-checkpoint/body-mean-preview/all_a_390_1.0x.png)

## Evidence and implementation gate

Twelve bounded preview cases pass. The private preview mounts the actual Body page with
authored daily weights, tape, food and steps, then substitutes only its selected summary row.
It reuses the actual row layout, fonts, decoration and other page children. Viewport growth
verifies the entire vertical scroll extent, and checks retain all sections and major actions.
One batched inspection and one confirmation retain the locked palette and composition.

The enlarged Before/A/B pages also expose character wrapping in milestone dates. That
separate defect now has its own approved A reflow and locally passing regressions/captures
in `body-milestone-layout-review.md`; these original average-proposal pages retain the older
milestone layout as evidence. No new Flutter overflow was observed. Full-page images do not certify native SF, safe areas, gestures,
VoiceOver, callback execution after implementation, or a phone build. Manrope substitutes
for SF; no native build was run. The local Impeccable binary was not executed because its
trust remains unverified; existing product/design/native guidance was read directly.

The shared `_bodySummary` now selects the existing daily-weight mean over the whole chosen
range while keeping its old first/last-week comparison separately. `progressPeriod`, charts,
stored weights, goal/maintenance/calorie methods, algorithm, schema and metadata are unchanged.
This applies to all Body destinations that share the summary; Food/Strength review windows
retain their existing contracts. No metric or action is removed.

Both original measured negatives pass without changing their 61-reading expectation; the
exact original four-case file (including absence/preferences controls) is restored and passes.
Fifteen new controls cover distinct baseline/earliest boundaries, sparse observations, future
exclusion, kg/lb, unchanged 7/30/90-day means, short and single-day history, retained comparison
counts/changes, and no invented/written weights. The two missing-day controls stay enabled.

Four complete captures use actual production widgets with no prototype substitution:

| Range / width / text | Actual implemented page |
|---|---|
| All / 390 / 1x | [Implemented](build/ownership-checkpoint/body-mean-implemented/all_implemented_390_1.0x.png) |
| All / 320 / 2x | [Implemented](build/ownership-checkpoint/body-mean-implemented/all_implemented_320_2.0x.png) |
| All / 430 / 3.1x | [Implemented](build/ownership-checkpoint/body-mean-implemented/all_implemented_430_3.1x.png) |
| Since start / 390 / 1x | [Implemented](build/ownership-checkpoint/body-mean-implemented/sinceStart_implemented_390_1.0x.png) |

All four are pixel-identical to approved A, with dimensions/hashes in each local verified
manifest. Targeted analysis has no errors/warnings or new infos; full Linux candidate 47
verifies the average correction. Native/phone acceptance remains required. These original
average pages preserve the old milestone wrapping; the separate approved milestone A and
its actual matching pages are in `body-milestone-layout-review.md`, passing candidate 49.

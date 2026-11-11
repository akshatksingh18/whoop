# Current-night correction ownership

**Status:** Approved and implemented shared-reader repair;targeted checks/page parity pass.
Full combined Linux and native/phone acceptance remain open.
Eight original accepted-correction regressions failed locally for rejected,clear,manual and
confirmed actions,in pending and completed-unknown states. Original source/logs remain
private and are excluded from passing coverage. The amended private prototype passes all
eight unchanged regressions,additional Sleep-reason assertions and20 complete-page controls.
Akshat approved the reviewed repair/pages and retaining algorithm102/protocol1.0.1/schema50.
Nine actual reader regressions and ten complete-page controls now pass;37 implementation
viewports exactly match the approved proposal.

## Repaired behavior and original cause

The correction transaction preserves the old result/pin for recovery and withholds the
current night's measurements. getToday now returns its corrected_unknown-aware
showingPriorOvernight value. Previously its returned status copied the raw freshness flag
even after computing showingPriorOvernight=false.

heldOverNightOf and staleOvernightNote consume that returned flag. The repaired value retains
the explicit correction reason,opens the current corrected unknown Sleep day by default,
and removes the contradictory prior-night Recovery caption. The prior result is legitimate history,but it is not this corrected result.

## Implemented narrow repair and approved version decision

The implementation returns the already computed showingPriorOvernight value in getToday's status,and carries
the existing correction reason in an absent sleep.duration_min envelope. Without that
envelope,Home's Sleep tile falls through to an unsupported insufficient-night explanation
after the stale flag is corrected. The value remains absent;the existing shared explanation
is reused for rejected,pending and no-replacement outcomes. Keep the
freshness record,stored prior-night metadata,original measurements,pins,recovery generations,
all history and ordinary pre-sync fallback unchanged. Change no formula,writer,schema,
protocol,app metadata or persisted identifier. The explicit approved read-side version decision retains algorithm102,protocol1.0.1 and
schema50 for this ownership correction;no analytics formula or writer changes.

Current unknown-night Sleep pages and their correction explanations are already approved.
Opening the current corrected night must retain Naps,day navigation,Reject Undo where
applicable and the breathing report. Fix sleep times remains unavailable on this unknown
day under Akshat's existing decision;earlier usable nights and their controls stay reachable
through date navigation. No functional entry point or historical measurement is deleted.

## Complete-page review and verification plan

The [complete local Before/Proposed pages](build/ownership-checkpoint/home-night-ownership-review/full-pages.html)
contain20 complete states and84 scroll viewports:Home,Sleep and Recovery at390px/1x,
320px/2x and430px/3.1x,plus the complete390px Health/Trends pair. All viewports were inspected;
67 remain pixel-identical to the initial review outside the removed SDK debug banner,and
the17 amended Home viewports were inspected separately. Both Health viewports are pixel-
identical Before/Proposed. The original one-field previews and interrupted capture stay local.

The same authored store and actual loaders show the wrongly opened earlier Sleep page
beside the current unknown page. The private prototype changes only the two returned fields;
the implemented reader now matches that proposal. All navigation,history,recovery/report
links and uncertainty remain.
The existing large-text Today heading wraps across lines in both versions;that typography
is outside this ownership/explanation proposal. Native rendering/phone acceptance remains separate.

Both returned-field expressions are implemented and all eight original failures are
promoted unchanged,with the additional absent-Sleep explanation assertions. The ninth
regression retains ordinary uncorrected prior-night fallback. Actual Home/Sleep/Recovery/
Health pages use the real reader;all37 viewports exactly match the approved proposal.
Saved-row,series,pin and correction preservation checks pass. Targeted analysis has zero errors/warnings and one unchanged reader style info. One
privacy-reviewed combined Linux run must verify the final tree;native/IPA/phone gates remain.

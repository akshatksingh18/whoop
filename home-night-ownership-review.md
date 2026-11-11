# Current-night correction ownership

**Status:** Confirmed reader/routing defect; repair proposal only. Production is unchanged.
Eight real accepted-correction regressions fail locally for rejected,clear,manual and
confirmed actions,in pending and completed-unknown states. Original source/logs remain
private and are excluded from passing coverage. The amended private prototype passes all
eight unchanged regressions,additional Sleep-reason assertions and20 complete-page controls.
Implementation and the read-side/version decision remain pending approval.

## Actual behavior and cause

The correction transaction correctly preserves the old result/pin for recovery and withholds
the current night's measurements. getToday correctly computes corrected_unknown and a local
showingPriorOvernight=false. Its returned status instead copies showing_prior_overnight from
the raw freshness record,where the prior scored night remains available.

heldOverNightOf and staleOvernightNote consume that returned flag. Home can therefore replace
the explicit correction reason with a missing-sync explanation;SleepData's default opening
chooses the earlier scored night;Recovery carries a prior-night caption beside the current
unknown result. The prior result is legitimate history,but it is not this corrected result.

## Proposed narrow repair and version decision

Return the already computed showingPriorOvernight value in getToday's status,and carry
the existing correction reason in an absent sleep.duration_min envelope. Without that
envelope,Home's Sleep tile falls through to an unsupported insufficient-night explanation
after the stale flag is corrected. The value remains absent;the existing shared explanation
is reused for rejected,pending and no-replacement outcomes. Keep the
freshness record,stored prior-night metadata,original measurements,pins,recovery generations,
all history and ordinary pre-sync fallback unchanged. Change no formula,writer,schema,
protocol,app metadata or persisted identifier. Request a separate decision to retain algorithm102,
protocol1.0.1 and schema50 for this read-side ownership correction;do not infer that decision.

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
production is untouched. All navigation,history,recovery/report links and uncertainty remain.
The existing large-text Today heading wraps across lines in both versions;that typography
is outside this ownership/explanation proposal. Native rendering/phone acceptance remains separate.

After approval,apply only the two returned-field expressions and promote all eight unchanged failures.
Add an ordinary uncorrected prior-night fallback control so real pre-sync history still opens
the correct earlier night. Verify current Home/Sleep/Recovery agreement and exact saved-row,
series,pin and correction preservation. Run targeted checks locally and include the change
with the next privacy-reviewed combined Linux verification;native/IPA/phone gates remain.

# Current-night correction ownership

**Status:** Confirmed reader/routing defect; repair proposal only. Production is unchanged.
Eight real accepted-correction regressions fail locally for rejected,clear,manual and
confirmed actions,in pending and completed-unknown states. Original source/logs remain
private and are excluded from passing coverage. Complete Before/Proposed pages are pending;
no implementation or new version decision is approved by this plan.

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

Return the already computed showingPriorOvernight value in getToday's status. Keep the
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

Prepare complete current/proposed Home,Sleep and Recovery pages at ordinary,2x and3.1x text
from the same real authored store. Use a private read-result prototype for the single flag;
do not edit production to make previews. Show the actual wrongly opened prior Sleep page
beside the current unknown page. Inspect every scroll segment and preserve all navigation,
uncertainty labels and recovery/report links. Confirm indirect Health consumers remain unchanged.

After approval,apply only the metadata expression and promote all eight unchanged failures.
Add an ordinary uncorrected prior-night fallback control so real pre-sync history still opens
the correct earlier night. Verify current Home/Sleep/Recovery agreement and exact saved-row,
series,pin and correction preservation. Run targeted checks locally and include the change
with the next privacy-reviewed combined Linux verification;native/IPA/phone gates remain.

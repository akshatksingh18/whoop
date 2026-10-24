# Treadmill walking: speed, incline and calorie ownership

**Status:** Requested feature; source review and research proposal only. The current app does not
record treadmill settings. The calculation choice and full-page UI previews need review before
implementation. No metric, schema, version, dependency or installed artifact changes here.

## Current behavior

- Ordinary Walk calories use the recorded active-window phone steps. The same steps already
  contribute to daily maintenance, so another full Walk calorie total is not added there.
- The generic `treadmill` type belongs to `isRunType` in `lib/gps/run_history.dart`. It uses the
  existing distance/run-walk mix rather than explicit walking speed and grade settings. Do not
  recommend it as an incline-aware walking mode or silently relabel its existing history.
- `lib/compute/profile.dart` already distinguishes the walking vertical term (1.8) from the
  running vertical term (0.9) in the movement comparison. Current GPS climb does not supply an
  added calorie bonus, and pedometer step/distance data do not supply a treadmill's grade.
- `DayUpkeep` is the common daily-calorie reader used by Today, Food, historical summaries,
  Weekly and Steps/Trends. Any addition must propagate through that reader and post-commit
  revisions, not be a live-screen-only calculator.

## Recommended user flow

1. **Train → Walk → Treadmill:** retain Outdoor Walk and the existing generic Treadmill history.
   Indoor walking records phone steps/HR and the session clock without asking GPS for a route.
2. **Setup:** enter treadmill speed (km/h or mph) and incline **%**. A previous setting may be a
   prefill, but is confirmed before it becomes this workout's recorded setting. Zero grade is
   explicit; an omitted grade is unknown, not silently flat.
3. **Live:** show current speed/grade in one compact section, steps and active-calorie estimate.
   **Change settings** closes the current timed segment and begins a new one at the saved
   change time. Earlier minutes retain their actual settings. Without treadmill integration,
   changes must be entered; the app cannot detect a belt adjustment automatically.
4. **Pause/resume:** paused time contributes no incline energy. Resume preserves the saved
   setting with a visible way to change it. Unreported belt stops/setting changes cannot be
   reconstructed from elapsed time; a step discrepancy is not proof that the user stopped.
5. **Finish/history:** review a compact timeline of speed/grade segments; correct values and
   change times, then recalculate. A small stepped incline plot can summarize the session.
   Identify entered belt distance and equivalent climb separately from GPS distance/elevation;
   do not create an outdoor route, actual altitude gain, floors climbed or running best efforts.

Full-page before/after previews cover setup, the complete live page and change-settings sheet,
summary/history editing, and the affected daily maintenance breakdown. Preserve the locked A+B
visual system. Production UI follows review of those previews.

## Calculation proposal

For a segment, let `v` be entered belt speed in m/min, `g = incline_percent / 100`, `t` its
active minutes, `d = v*t` its entered belt distance, and `w` its recorded weight in kg.

- ACSM walking oxygen demand: `3.5 + 0.1*v + 1.8*v*g` mL/kg/min.
- Full **active** walking comparison: `0.005*w*(0.1*d + 1.8*d*g)` kcal. The resting 3.5 term
  is excluded; daily BMR must not be subtracted a second time.
- Incline-only increment: `0.005*w*1.8*d*g` kcal for an uphill segment.
- Recommended **Budget**: keep the existing phone-step walking contribution and add only this
  incline increment. Daily step count, goal and streak remain unchanged. This is an app budget
  combining two methods, not a separately validated ACSM total or a guaranteed lower bound.
- Retain the full ACSM walking estimate as the existing alternative comparison. Do not sum
  that full estimate with the unreduced step contribution. Its belt distance replaces the
  covered window's phone-estimated distance where overlap evidence supports that replacement.
- Apply each speed/grade pair to its own duration; multiplying separate session-average speed
  and average grade can give a different answer when both change. Use existing shared movement
  helpers and one persisted segment ledger rather than new formulas in individual screens.

## Accuracy and scope

The method estimates energy from entered workload, not from measured respiratory gases. Steady
unsupported walking, accurate belt settings and accurate weight fit its assumptions better than
rail-assisted walking or unreported setting changes. No arbitrary discount makes it a proven
personal minimum. The app's existing ACSM walking speed qualification is 50–100 m/min; retain
clear estimate/out-of-domain wording. Short transitions are approximations, not instantaneous
measurements of metabolic response. Very steep grades need separate evidence/model review;
do not invent a validated grade cutoff from a single study or generalize an extreme-grade result
to every treadmill session. Decline walking is outside this initial uphill feature proposal.

## Implementation and verification gates

- Explicit walking identity/environment; no retrospective conversion of generic Treadmill runs.
- Additive/idempotent persistence with segments, settings provenance and active times included
  in snapshot/import/export/restore/salvage/wipe paths and cold-resume state.
- A refused settings/segment write retains the previous committed segment and a retryable draft.
  Editing, deleting, retiming or restoring a workout republishes all calorie dependencies.
- Daily ownership unions duplicate/overlapping active windows. Midnight/DST/travel splits use
  recorded day boundaries; pauses and edited end times clip segments. Retain captured profile
  semantics and do not reprice old workouts with an arbitrary current weight.
- Missing speed/grade/weight/time/steps stays unknown or explicitly partial; never fill absent
  steps with a synthetic count. Provenance distinguishes phone steps from entered workload.
- Steps counted by the phone stay counted once. Test zero grade, incline-only increments,
  changing both settings, unit conversion, missing data, pauses, sub-minute tails, write refusal,
  cold retry, overlap, midnight/DST, edits/delete, restore and every live/history/daily consumer.
- Analytics-output versioning and any schema bump occur with implementation, not this plan.
  New scientific settings require an explicit decision; no coefficient changes now.

## Primary sources

Public sources checked 2026-10-24; no personal workout data was submitted.

- [Moore et al., cadence/ACSM validation](https://pubmed.ncbi.nlm.nih.gov/32555022/): evaluates
  walking predictions against indirect calorimetry and reports prediction error; it does not
  establish an individual minimum. The [full article](https://pmc.ncbi.nlm.nih.gov/articles/PMC7896743/)
  explains the speed domain and steady-state sampling.
- [ACSM walking/running equation in the BEST study](https://www.frontiersin.org/journals/physiology/articles/10.3389/fphys.2019.01517/full):
  walking uses the 1.8 speed-by-fractional-grade term, distinct from running's 0.9.
- [Hofmann et al., handrail/posture experiment](https://intjexersci.com/ijes/vol7/iss4/10/):
  support/posture changes measured energy demand; rail holding is not one universal discount.
- [Lankford et al., steep incline/decline validation](https://pubmed.ncbi.nlm.nih.gov/32656608/):
  compares several models over a broad grade range and reports biomechanical changes at steep
  grades; this does not validate unrestricted extrapolation of the simpler ACSM equation.
- [Apple CMPedometerData](https://developer.apple.com/documentation/coremotion/cmpedometerdata):
  step count and estimated pedestrian distance are inputs, not a treadmill incline setting.

# Workout, sync, food and streak audit

**Status:** Build-72 evidence and approved build-73 repair contract. The audited installed build is `0.9.39`/`72`, source
`05c208c79fe61c35e8df587e7becfd59698cbf02`. Akshat confirms this is the phone build used for
the screenshots, reports background voice failure and confirms Today refresh now updates steps.
He reports maintenance calories appearing unchanged. The approved repair is implemented locally in
`0.9.40`/`73` (algorithm 89) and passes local validation. Akshat approved publication and the
single personal IPA; source `a49d7837` is published and Linux CI/macOS compilation pass.
The downloaded IPA passes checksum, manifest and payload checks; its testing artifact is superseded
by build 74. Akshat confirms build 73 is installed and initially looks good, but reports chart,
navigation and notification issues; `build-74-audit.md` owns that newer source/research audit and
`todo.md` the build-74 release/device gates. Published/built source `0.9.41`/`74` implements the coordinated
repairs, persistent Budget/ACSM pair and narrow workout Live Activity. Native and downloaded IPA
checks pass; build 74 is installed but superseded by build 75 (`build-75-audit.md`), the sole
testing candidate awaiting installation, its complete phone pass and current-version enrollment. Build 70 remains accepted;
build 72 was installed without acceptance and has been replaced on the phone by build 73.
The evidence sections below describe build 72; `todo.md` owns current implementation and phone gates.

## Evidence and limits

The phone reports establish missing background voice, the confusing cross-day warning/action,
the differing walking calorie presentation, hidden macro rows and the missing profile decimal key.
The source explains these symptoms. Today's measured-step refresh works on the phone; the reported
unchanged Food maintenance total was not reproduced in the main card with synthetic step updates,
while its already-open breakdown was reproduced as stale. The disappearance of the warning alone
cannot establish which
cross-day computations succeeded: no phone database or diagnostic export was available.

139 existing focused tests pass: run calculations/analysis, live versus stored HR-calorie parity,
calorie anchors, cross-day freshness/pipeline, retained-result protection, units, profile editing,
food flows and the existing streak rule. All nine Today-refresh regressions also pass with the
personal build flag, including native step persistence, revision publication and held/error states.
The expanded step suite passes 99 tests in its normal
configuration. Forcing its legacy source-ladder tests into the personal profile yields four failures:
they expect band-first overlap semantics rather than the personal phone-first policy. This is a
test-configuration gap to fix with explicit policy selection, not four observed phone failures.
Fifteen temporary synthetic probes also pass, reproducing
the current defects rather than claiming fixes. The probes and logs are ignored under `.dart_tool/`;
their SQLite database was isolated and deleted. These tests cannot verify iOS background execution.

Reproduced cases:

- A voice update from 0.1 km to 3.8 km at 38 minutes says "last kilometre 38 minutes" and skips
  the intervening kilometre announcements. A newly created voice controller primes at the current
  distance and does not recover earlier milestones.
- Saving unchanged imperial prefills converts 80.5 kg to 80.28584949 kg and 186.69 cm to
  187.96 cm. Metric height prefill rounds 186.69 to 186.7 before an unchanged save.
- An empty macro card hides Carbs, Fat and Fibre; explicit zero makes them visible.
- A synthetic 5 km run at 80.5 kg with unavailable session steps adds 287.79 run kcal while all
  5,000 daily steps still contribute 131.79 step kcal. If those steps came from the same run,
  the movement has been counted twice.
- A cross-midnight run contributes all its energy to its start day and none to the next day.
- Three retained current-version day results with no decoded raw data do not repair an old
  cross-day artifact even when a forced heavy derivation is requested.
- 12,000 stored steps and a step-goal change do not qualify a day for the session-only streak.
- A profile save issues an AppState notification but does not change `insightsRevision`.
- With identical synthetic profile/HR input over 10 minutes, live workout calories are 13.42
  at 60 bpm versus summary Method 2's zero; at 151 bpm they are 145.34 versus 132.41.
- A positive phone count can lose to the band under the phone-left-behind heuristic; a positive
  hourly phone bucket can also suppress a different wrist-only walk later in that hour.
- Passive live gait needs no started workout, but a synthetic minute publishes zero daily band
  steps until banking, then 119. A continuous two-minute wrist walk crossing midnight is banked
  entirely on its start day instead of being split by calendar date.
- Without derivation, a real repository/SQLite update from 5,000 to 9,000 phone steps reloads
  Food's main card and changes step energy from 131.79 to 237.23 kcal at 80.5 kg. An open
  maintenance breakdown keeps its original 5,000-step explanation and calories while that
  underlying card has already updated to 9,000.

## Band sync and cross-day insights

The button is wired, but it does not specifically request or await a local insight rebuild.
`home_screen.dart:134` binds it to `AppState.syncNow`, which calls `openSession`. A healthy
existing connection takes the fast catch-up path. That catch-up can be throttled by the
90-second foreground-sync floor, can return while another burst is active, and marks new stored
data for derivation only when records arrive. The full new-connection path requests a heavy pass.
Tapping the warning therefore does not guarantee a rollup rebuild or explain a no-op.

Individual sleep/recovery data come from day results. Cross-day families come from a separately
stored `baselines.crossday` artifact. `LocalRepositoryImpl.crossDayStaleReason` withholds a
different algorithm version, an unstamped artifact or one more than seven calendar days away.
Build 72 uses algorithm 88, so an older 87 artifact can produce the exact warning while sleep and
recovery remain available. This is a freshness guard, not evidence that history was deleted.

The warning is conditional content rather than a permanent tab. It normally disappears when the
reader sees an acceptable rollup. A valid rollup can still abstain on individual metrics that lack
their own baseline. Missing/malformed artifact reads can also return an empty map without a stale
reason, and the bare-Today rendering branch uses another status card. The screenshot alone cannot
distinguish those cases.

Recovery gaps in `derivation_engine.dart`:

- `run` returns early without decoded data or without work to derive. Its main path invokes
  cross-day computation only after computing at least one day. Retained compact day results can
  therefore exist without any way for this path to repair a stale rollup independently.
- `_runCrossDay` requires at least three usable day records; that is a bundle input minimum,
  not sufficient baseline for every output. A lack of history needs a distinct explanation.
- Its exception handler logs a dropped bundle but returns normally. The scheduler can consider
  the job finished without persisting a cross-day failure/retry state for the warning to display.
- The stale-insights card says rebuilding regardless of queue/connection/error state and does not
  use the tap feedback applied to the separate bare-Today status card. Heavy computation also
  waits during capture, iOS background periods and active workouts; the screen should explain that.

Proposed repair: a durable independent cross-day rebuild using retained compact inputs, preserving
pruned historical results; a retry action that does not require fresh BLE data; and explicit
connecting, syncing, calculating, waiting for history, held and failed states. Keep stale numbers
withheld. Report completion after the artifact is persisted and reload Today then. Do not erase
history or fabricate missing insight families to make the warning disappear.

## Today refresh and dependent calories

Build 72 refresh reads/persists today's phone pedometer windows first. `syncPhoneSteps` updates
the phone-count state and emits `insightsRevision` after a successful read; `_pullRefresh` also
emits a revision before band catch-up and after waiting for the durable derive queue. The Today,
Food day, Food history and Weekly readers subscribe to that revision. Routine foreground return
and the foreground refresh timer use the same phone sync and queue a light derive. A pull is not
required to invalidate Food after a committed phone update.

The immediate dependency path is: native phone windows → `live_coverage` → the shared
`getDaySteps` resolver → `getToday.daily.steps` → Food's `stepsOn` / Today's `HomeData` →
`DayUpkeep` / `maintenance`. The step term is calculated directly, not persisted as a calorie
result waiting on sleep or HR. With unchanged weight, completed-run deductions and food, more
accepted walking steps must increase it on that reread. The 5,000→9,000-step probe confirms this
path through the real repository/database and mounted Food card without invoking derivation.
It does not establish which values were shown in Akshat's before/after phone comparison.

Specific stale/error paths and legitimate unchanged values:

- `showMaintenance` computes `m` and its explanation rows once before opening the sheet. It
  never subscribes to later data/profile revisions. The open breakdown is a fixed snapshot,
  even when its parent updates; reopen is currently required. This is a reproduced UI defect.
- Expanded monthly history caches maintenance totals in `_maintenance`. It reloads on durable
  revisions, but does not react directly to changed profile/run props. A profile save currently
  emits no durable revision, and parent/child asynchronous loads can use different run snapshots.
  The plan needs dependency invalidation, not just another general widget rebuild.
- `stepsOn`, `_monthSteps` and `_allRuns` swallow read failures into null/empty results. Maintenance
  can then quietly drop movement or treat completed-run steps as walking rather than identify
  unavailable inputs. Preserve last known inputs with a visible stale/retry state.
- The UI rounds to whole kcal. Small additional counts can leave a displayed figure unchanged.
  Steps already priced as part of a completed run must be removed from the walking step term;
  correcting those counts need not increase total movement energy a second time.
- Food's "Calories" card is intake versus the user's fixed target. Walking intentionally does
  not alter logged intake or add exercise back to the target.

Calculated daily active/total energy and strain are another dependency path: stored band HR,
baseline/profile anchors and resolved per-minute cadence → the queued day derivation → saved
scalars → screen revision. Its walking component uses CADENCE-Adults MET thresholds (at least
100 steps/min), not the Weyand per-step maintenance formula. Hourly phone counts spread into
minute cadence can remain below that threshold; an increased daily count does not imply an
increased HR/cadence estimate. `wakeDayEnergy` also removes minutes without valid HR alongside
their cadence, so some measured movement cannot contribute there. These are different estimates,
not interchangeable numbers that can be made identical by waiting longer.

Manual refresh waits for eligible queued derivation, with an eight-second light settling window,
and is capped at 60 seconds. Capture/offload, a live workout or iOS background can hold it; missing
raw HR/baseline inputs can leave no eligible result to recompute. Existing feedback describes
held/ongoing/error states, but queue completion alone does not prove every metric changed. New
data cannot be obtained by recalculation alone. Sleep/recovery/HR insights should only change when
their own inputs change, while local step-based maintenance should never wait behind those jobs.

Proposed repair: one date-aware maintenance reader shared by Today/Food/history/breakdown, reactive
to committed steps, food, run-window and profile/goal changes. Reload an open breakdown in place;
keep the latest complete input snapshot rather than silently substituting failed reads. Publish
step-derived energy immediately while separately showing outstanding HR/insight work. Refresh
completion should confirm consumer reloads at the committed revision and explain held/unavailable
dependencies. Test the actual gesture and automatic refresh while Food is cached or its breakdown
is open, with disconnected/slow band, active workout, failed reads, rounding, run deductions and
midnight. Preserve the fixed food goal and the distinct HR estimate rather than add both to the
maintenance budget.

## Voice, timing, distance and heart rate

`_VoiceCueState` in `ui2/activity/live.dart:1142` owns `KmVoice` and feeds it from
`didUpdateWidget`. A visible widget update is the trigger. While the view is not being updated in
the background, distance milestones do not reach this controller; reopening can issue a delayed
cue or prime a replacement controller. The controller is not owned by the durable workout session.

The native `SpeechBridge` uses a retained `AVSpeechSynthesizer`, playback/voice-prompt audio,
music ducking and deactivation after speech. The personal build contract in `tool/personal_ios.py`
permits only `bluetooth-central` and `location` background modes, not `audio`. Adding a plist value
alone would conflict with preparation/validation. Audio activation errors are ignored and there
is no explicit interruption/cancellation/route-change handling.

Apple documents background audio and location as separate execution modes. Playback while locked
requires the appropriate audio configuration; setting the playback category alone is insufficient.
Spoken prompts should activate audio when needed and release it afterward. This supports a
session-driven implementation, not a promise that arbitrary Dart timers execute indefinitely.
[Apple background modes](https://developer.apple.com/documentation/xcode/configuring-background-execution-modes),
[playback category](https://developer.apple.com/documentation/avfaudio/avaudiosession/category-swift.struct/playback),
[spoken-prompt guidance](https://developer.apple.com/library/archive/documentation/Audio/Conceptual/AudioSessionProgrammingGuide/AudioGuidelinesByAppType/AudioGuidelinesByAppType.html).

Proposed repair: move milestone tracking to the session's accepted location/motion events, derive
the actual kilometre crossing times, preserve the last announced boundary, and handle interruption,
minimise, pause and stop. A jump across several boundaries must not mislabel a whole gap as one
kilometre. The approved build-73 source includes audio in the personal build contract and validator.
Location already requests background updates. GPS denied/phone-motion-only operation needs a
separate honest availability policy; its current fallback distance is recovered after finishing,
not supplied to the live distance getter. No silent audio keepalive is proposed.

Additional timing defect: Pause changes `LiveDraft.pausedSec/pausedAt` and freezes the visible
clock, but `AppState._tickWorkout` still uses wall time and continues HR, zone and calorie accrual.
Route collection is not paused by that control. `_withPhone` and `_withMotion` query
`start + active duration`, shortening the sensor window instead of using the actual end after a
pause. A ten-minute pause can drop the final ten minutes of phone data. This is source-confirmed,
not a separately observed phone failure. Use one session clock with pause intervals and retain
actual start/end separately from active duration, including reload and interrupted sessions.

Live pace is average elapsed time divided by distance; finished route pace uses moving time and
excludes stops. Live and finished distance also undergo different amounts of smoothing. Label the
pace basis and share a coherent route/pause policy rather than promising identical instantaneous
and final values. Current HR uses a freshness check and stored curves preserve missing minutes;
keep those safeguards and the zone anchor provenance.

## Calorie map: current implementation

1. **Activity picker and welcome:** `Activity.kcal` and `setup.dart` use
   `MET × 3.5 × kg / 200 × minutes`. Walking has 3.5 MET. This is a generic gross estimate,
   including resting energy, for a hypothetical 30 minutes. It is not the maintenance movement
   method and does not know the future distance or steps.
2. **Live run, walk and most other activities:** `_kcal` prefers `LiveFeed.calories`, otherwise
   falls back to the activity's gross MET estimate with elapsed minutes rounded. The feed uses
   `LiveWorkoutState._scoreCalories`: gross Keytel above 40% HR reserve, Harris–Benedict resting
   energy below that gate. It needs HR/profile anchors. The model can silently change when HR
   becomes available. It is not distance Method 1 or net summary Method 2.
3. **Stored session, workout history totals and share:** `sessions.calories` stores the live/
   manual-session gross HR estimate. Rescoring uses the same estimator; existing parity tests
   prove that agreement. Workout list and share values can still differ from the run detail.
4. **Finished run detail:** `RunCaloriesCard` uses Method 1 from route or phone-motion distance,
   and Method 2 from minute HR minus Mifflin resting energy. Within 50 kcal, it displays the
   distance value with an agreement explanation; otherwise both values. This is the intended
   comparison and should remain.
5. **Finished walk/hike detail:** the same card uses the same distance/gait split as a run,
   with 0.1 on walking metres. The split helper has no activity-type argument; speeds at least
   2.0 m/s or phone cadence at least 140/min are classed as running even inside a Walking activity.
   Thus fast walking can receive the running coefficient. It is not the step-based walking floor.
6. **Today/Food/History/Weekly maintenance:** full-day Mifflin BMR + Weyand energy on steps
   outside completed runs + run Method 1 + 10% of logged food. A walk contributes through its
   steps, never as an extra workout calorie row. Lifts/other activities and HR Method 2 are not
   added. An unfinished run remains in steps until a completed distance is available.

The accepted equations in `compute/profile.dart` are:

- Step movement: `2.74 × steps × kg / 8368` kcal. 8368 converts joules to kcal and strides to
  two steps; this is not a second kcal-per-step factor.
- Run Method 1: `0.005 × kg × (0.143 × run metres + 0.1 × walk metres + 0.9 × climb metres)`.
- Method 2: sex-specific Keytel gross kcal/min, minus `Mifflin BMR / 1440`, integrated over
  measured HR slots, with negative contributions clamped to zero.

At 80 kg, illustrative flat 4 km movement is 228.8 kcal if all running or 160 kcal using the
walk-distance coefficient. 6,000 steps yield 157.17 kcal with the step method. The welcome's
30-minute 3.5-MET estimate is 147 kcal gross. These are different inputs and definitions; the
screenshots' 147/201/149 numbers alone cannot isolate an arithmetic error. The source does prove
that the screens do not consistently follow the desired maintenance method. The existing worked
example, 80.5 kg and 5.06 km all running = 291.24 kcal, still passes.

Proposed presentation: running's primary live/detail/history/share value uses Method 1 throughout,
with net Method 2 as the secondary comparison. Walking's primary value uses the same Weyand
session-step calculation as maintenance, with net HR as a secondary estimate and an explanation
that its energy is already in the Steps row. Keep distance/pace/HR data visible. Remove the generic
30-minute MET calorie promise from Run/Walk welcome screens; describe their actual method and
input availability. Other activities may retain an explicitly labelled estimate but must distinguish
gross from active energy and remain excluded from the maintenance floor.

Build-73 calorie terminology and display contract: Walking Method 1 is exactly
`(2.74 * session_steps * weight_kg) / 8368`; Running Method 1 retains the accepted distance/
walk-break/climb equation. Method 2 uses the same sex-specific Keytel equation for both activities,
then removes resting energy: sum `max(0, gross_kcal_per_min(HR) - BMR / 1440)` over measured slot
durations. The male equation supplied by Akshat returns gross kcal per minute, not a session total;
age, weight and measured HR still affect its answer. Missing HR does not become a fabricated slot.
Using one regression for both activities is not evidence of equal accuracy across all modes or
intensities, and Weyand is an empirical metabolic estimate rather than a universal mechanical bound.

Use an "Active calories" heading with this explanation on Run/Walk welcome, live and summary:
"Energy above your estimated resting burn. Resting calories are already included in your daily BMR."
Label Method 1 "From steps" for Walking and "From distance" for Running, and Method 2 "From heart
rate"; explain that the HR estimate has resting energy removed. Both methods estimate the same
session's active component, so never add them together. Keep the existing within-50-kcal comparison
rule while showing the appropriate Method 1 value. Do not subtract resting energy again from the
already-net Method 1 estimates. Daily maintenance continues to use only Method 1 movement, with
run-window steps removed and a walking workout included once through its steps. BMR and the 10%
logged-food digestion term remain separate components. Akshat subsequently approved implementing
this contract in build 73 and separately approved its public source and personal IPA.

## Conservative-estimate limitations and accounting defects

The equations are useful budgeting estimates, not guaranteed physiological lower bounds. Weyand's
2.74 J/kg/stride was an observed average at the most economical measured speeds, with variation,
not a proof that every person's every step costs at least that amount.
[Weyand 2010](https://pubmed.ncbi.nlm.nih.gov/21075938/).

The run coefficient 0.143 deliberately produces less energy than the standard 0.2 running
coefficient. Its arithmetic matches Akshat's chosen example, but the consulted primary sources do
not establish 0.143 as a universal minimum. Walking/running equations have measured prediction
error and depend on conditions; downhill cost is not necessarily flat cost. Keep this as the
chosen conservative estimate, not a verified minimum physical cost.
[Measured walk/run comparison](https://pubmed.ncbi.nlm.nih.gov/15570150/).

Keytel was fitted to exercising participants at steady exercise stages, with residual prediction
error and effects of fitness and exercise mode. It should remain a comparison, especially for easy
walking; selecting it or the larger of two methods would undermine the intended conservative
budget. Mifflin also predicts rather than measures individual resting expenditure.
[Keytel 2005](https://pubmed.ncbi.nlm.nih.gov/15966347/),
[Mifflin 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/).

Food thermogenesis varies with composition and individual response. A fixed 10% of logged energy
is not a guaranteed minimum, particularly for fatty meals. Retain the currently accepted 10% only
as an explicit estimate unless Akshat chooses a stricter movement-only/resting budget; do not
silently revise the equation in this planning pass.
[Meal-response experiment](https://pmc.ncbi.nlm.nih.gov/articles/PMC2221871/).

Accounting fixes matter before changing physiological coefficients:

- Unknown run-window steps currently deduct zero while the whole run distance is added. Prefer
  exact non-overlapping phone windows. When overlap cannot be measured, do not sum two possibly
  overlapping movement estimates; use a conservative documented overlap policy and disclose it.
- Phone-first daily totals can be combined with a band fallback for run-window steps. Source
  mismatch can under-deduct. Track provenance and use compatible windows/counts.
- Split energy and step deductions by actual local-day boundaries for cross-midnight workouts.
- Run-history caches retain a missing motion answer for the process lifetime. A later available
  phone answer needs retry/invalidation rather than a permanently missing result until relaunch.
- Elevation gain is smoothed with a deadband but lacks a trustworthy vertical-quality gate; noise
  can add climb energy. Gate uncertain climbing or omit it from the strict estimate. Downhill-as-flat
  and speed/cadence-only gait classification also prevent a guaranteed minimum claim.
- Past maintenance/run detail uses current profile weight, while an active workout captures the
  profile at start and older stored HR energy may reflect prior anchors. Decide date-appropriate
  weights/snapshots and show their basis; body-weight history already exists but is not used here.
- "Maintenance so far" includes the whole day's BMR even in the morning. Keep the full-day budget
  arithmetic and label it as daily resting plus movement/food logged so far, not calories already
  burned by the current clock time.

## Accepted maintenance-estimation recommendations

Keep the accepted Method 1 daily budget as the primary conservative estimate: full-day Mifflin
BMR + Weyand steps outside runs + run Method 1 + 10% of logged food. First fix source coverage,
overlap, pause bounds, day allocation, weight precision and dependency refresh. Adding HR energy
to the same walking/running movement would count that activity twice. Keep net Keytel Method 2
as a comparison; neither averaging the methods nor selecting their maximum/minimum establishes
a calibrated estimate or a guaranteed lower bound. Missing HR must not erase measured movement.

An individually calibrated HR-plus-movement model can improve expenditure precision, but the
studied combined model is not a simple sum of our two equations and is not validated for this app.
An optional broader expenditure estimate would need time-aligned inputs, one active-energy
answer per interval, net resting subtraction, signal-quality checks and independent validation.
It must remain separate from the accepted conservative budget unless Akshat changes that policy.
[Brage 2015](https://pubmed.ncbi.nlm.nih.gov/26349056/).
Heat can raise heart rate without a proportional increase in work-related energy, so HR alone
is not a dependable way to enforce a conservative movement estimate.
[Brode and Kampmann 2019](https://pubmed.ncbi.nlm.nih.gov/30606899/).

The existing Food weight card is a separate inferred maintenance estimate, not a direct metabolic
measurement. `measuredMaintenance` averages an undated list of eligible food-day calories and
subtracts raw-weight regression slope times 7,700 kcal/kg. Its caller selects both inputs from the
trailing 28 days, but food dates need not match the actual first-to-last weight interval; missing
food days are excluded while the weight slope still spans those calendar days. Eight weigh-ins,
ten heuristic-complete food days and a 14-day span cannot establish complete intake for that span.
The after-5-pm-entry heuristic also cannot detect a forgotten meal. These are source-level risks,
not a reproduced phone failure or evidence of any particular user's incomplete logging.

Proposed improvement: pass dated intake, align food and weight to the same exact interval, disclose
coverage and withhold inference when intake coverage is inadequate rather than treating missing
days as zero or silently dropping them. Prefer a sustained multiweek trend (4-6 weeks is a practical
recommendation, not a validated universal threshold), and label the result "Estimated maintenance
from food and weight". Weight changes include water and composition effects; a fixed 7,700 factor
is an approximation, not an exact conversion for each kilogram or short interval.
[Hall 2011](https://pubmed.ncbi.nlm.nih.gov/21872751/).
Stable trend weight with complete representative intake can check average maintenance for that
period. This inferred total already includes resting, activity and digestion; never add those
components to it again or automatically raise the conservative budget. Any explicit day-complete
control, inference-window change, dynamic model or calibrated HR hybrid remains an optional product
decision. None is approved or implemented by this recommendation.

## Macro visibility and profile precision

`MacroCard` filters away Carbs/Fat/Fibre when both logged value and target are absent. That explains
the screenshot and was an overinterpretation of prioritising calories/protein. The database and
food forms still retain all nutrients, explicit zero and missing-value provenance. Food detail
lists Calories/Protein/Carbs/Fat/Fibre even when absent; Quick add's optional macros are folded.

Restore all four daily macro rows/icons and retain all existing nutrient fields in saved foods,
barcode review and editing. For Akshat's requested presentation, show zero logged for an omitted
macro, with a small logged-values explanation; retain null internally so this does not fabricate
known complete nutrient intake or penalise a calories/protein day. Never infer energy from omitted
macros, overwrite untracked fields, or require fat/carbs/fibre to include known calorie entries.
The current evening-entry completeness heuristic cannot detect a forgotten earlier meal; it is
already disclosed, and an explicit day-complete control would be a separate product decision.

Settings and onboarding both request `TextInputType.number` for height/weight. The parser/store and
calorie equations already accept fractional values; the iOS keyboard is the immediate UI defect.
Food's weight log already requests a decimal keyboard. Additional profile issues are rounded edit
prefills, missing positive/range validation, and profile saves not invalidating cached metric
screens. A food weight log writes the weight history and profile separately; failures can leave
two different current values.

Proposed repair: decimal keyboards for measurements everywhere, integer age, lossless edit
round-trips, shared finite/range validation, preserved underlying precision, explicit save feedback,
and a committed profile revision that reloads Today, Food, Weekly and Train without a pull. Use a
consistent weight authority/snapshot policy; a plain profile notification is not sufficient.

## Run/walk/step-goal streak

`loadMoveStreak` reads sessions only. A day qualifies after ten recorded run/walk/hike minutes,
including several short sessions; other workouts do not qualify. Today remains open until midnight
and does not break yesterday's streak yet. No workout started from Train means no session to count
unless some other import/manual/confirmed source supplied one. Steps alone never qualify today.
The source also attributes a cross-midnight session wholly to its start day.

Train and Today's Weekly card share this loader. Neither uses `step_goal`, so changing that goal
currently cannot affect the streak. The goal defaults to 8,000 in repository/UI reads, is editable
in Steps with a 500–100,000 bound, and is stored as one profile value without effective dates.
Changing the goal changes the ring/percentage; it does not change steps, distance or calorie math.
Profile save does not emit the durable revision used by the other cached screens.

The separate step-goal notification reads the explicit profile goal and latest derived steps,
unlike the phone-first measured Today read. It has no UI-default goal when that field is absent and
does not explicitly require the latest series day to be today. It is fire-once-per-day and is not
a streak ledger. Do not use notification state to establish a streak achievement.

Proposed rule: a local day counts with either at least ten completed run/walk minutes **or** the
day's measured step goal reached. Count once, preserve run/walk distinctions and show a separate
step-goal reason; steps must not fabricate a workout, distance, pace or calories. Use the same
phone-first read as Today and update both streak displays after sensor commits, profile/goal
changes, session edits and local midnight without requiring a recorded workout.

Accepted goal-change policy: keep a dated goal history and earned-day evidence.
Before today's goal is earned, a change applies immediately; reducing it below steps already
measured qualifies today. Increasing it raises the remaining target. Once earned, a goal edit alone
does not revoke that day, and never rewrites past days; the UI should show the goal under which it
was earned. Corrections/deletions of source data need separate reconciliation, not blind latching.
Past step goals cannot be reconstructed from the current profile: retain historical workout-based
days and make any retroactive step-only backfill an explicit choice rather than silently applying
today's goal to all history. Late-arriving steps use the saved goal for their original local date.

## Phone-first steps and WHOOP fallback

Akshat's required behavior is phone steps whenever he carries the phone, supplemented by genuine
band steps only for separate phone-absent periods. Step-goal completion should use that same total
without requiring Start in Train. This is an automatic source-resolution requirement, not a reason
to add both complete daily totals or infer workout distance.

The existing `resolveDaySteps` policy is already per span rather than per whole day:

- Positive phone windows normally exclude overlapping band counts outright. A phone-recorded run
  is therefore counted once even when the band also recorded it.
- Valid band windows outside phone coverage are retained. A confirmed-zero phone window permits
  sufficiently dense band gait; low-density wrist counts below 40 steps/min are vetoed there to
  reduce chores/driving false positives.
- A band span at least 40 steps/min can override a positive phone window when its overlap count
  is at least three times the phone count and exceeds it by at least 300 steps. That is a heuristic
  for a phone left behind, not measured knowledge that the phone was absent.
- Accepted sources are resolved and summed; source/provenance is exposed to Today/Steps. A missing
  phone interval differs from a measured zero. Phone replacement is transactional and repeatable;
  an all-zero reread cannot erase a previously banked positive phone day.

That covers the simple fallback cases, but not the full requirement. Phone data is queried/stored
in hourly buckets. A phone-carried walk early in an hour and a phone-absent walk later can share one
positive phone bucket, suppressing the later band walk. Conversely, a wrist false positive can
trigger the ratio rule and replace an accurate positive phone count. Counts alone cannot prove
phone carriage; BLE connection only proves proximity, and phone zero can mean a stationary phone
on a desk or a stationary person. Do not label the heuristic as certainty.

For the existing WHOOP 4 path, the custom pedometer needs live high-rate IMU frames delivered to
the phone. It accepts passive gait without an active workout, rejects unsuitable active workout
types and refuses a stream below the measured 50 Hz rate floor. Gain is currently 1.00, not a
blanket uplift. The low-rate historical stream is not used to invent steps. There is no gen4
on-chip cumulative step counter in the decoded path; the gen5 counter is a separate whole-day
fallback and is not safely added to phone totals.

Two operational gaps reduce passive coverage:

- iOS downgrades live streaming to HR-only when backgrounded with no workout/breathing consumer.
  Thus forgetting Start can also remove the high-rate band signal needed for passive steps.
- Completed live gait chunks are checkpointed to preferences, but daily coverage is banked on
  disconnect or orphan recovery. Today's resolver reads the database, so a connected band-only
  walk can remain absent from Today/maintenance/streak reads until that banking occurs. A stable
  connection is not evidence that no steps were measured. `_bankGaitRuns` also assigns an entire
  continuous run to its start day, including one that crosses midnight.

Once the wearer leaves Bluetooth range with the phone behind, those live frames do not reach the
app. Later sync can recover other WHOOP 4 history without enough gait-rate information to count
that missing walk accurately. A UI/source-ladder fix cannot manufacture an accurate offline step
count from that history. This boundary must remain explicit in the plan and product copy.

Wrist algorithms also have false positives and missed steps depending on motion and placement;
the app's sample-rate/type/density gates reduce some failures but do not establish this wearer's
accuracy. Existing source comments cite corpus validation; this audit did not rerun the labelled
OxWalk corpus or collect new hand-counted WHOOP measurements. An independent device study confirms
that non-stepping daily activities can produce false steps in wrist monitors; it does not validate
this WHOOP algorithm specifically.
[O'Connell 2017 specificity experiment](https://pmc.ncbi.nlm.nih.gov/articles/PMC5234787/).

Proposed repair: use finer, targeted phone intervals around observed band gait and give positive
phone movement priority for the same interval; avoid replacing it merely from a ratio. Keep a
clearly explained band-only fallback for accepted uncovered/phone-stationary intervals, with gait
quality and source labels. Persist growing band runs idempotently while connected, publish a durable
revision and split at local midnight/DST. Consider a bounded passive gait consumer/background stream
policy so connected band steps do not require Start, with battery and iOS testing before acceptance.
Keep unrelated workout HR/live data and the no-double-count rule intact. Missing band-only coverage
must remain unmeasured, not zero or a fabricated all-day estimate. Test counted walks, slow walks,
run/walk transitions, chores/driving, phone-carried/desk/absent, BLE range loss, locked/background,
reconnect and source handoff against a hand-counted reference before calling the fallback accurate.

## Approved implementation and acceptance scope

The approved local implementation covers: independent insight rebuild/state feedback; session-owned
background voice; coherent pause/time/window handling; common Run/Walk calorie presentation and
non-overlapping maintenance accounting; all macro rows restored; decimal/lossless profile inputs
and immediate profile refresh; immediate, consistent step-based maintenance and reactive breakdowns;
shared step-or-workout streak with dated goal policy; finer phone-first
source resolution and prompt, idempotent band-only publication. Keep existing
worked-example equations unless a formula change is explicitly approved. Other-activity estimates
must remain labelled and excluded from the maintenance floor.

The same build also implements the subsequently approved food conveniences (custom fractional
servings, headings at log time, picker deletion, haptics and keyboard-safe cancellation) and daily
detail repairs. Naps saves/rejects/restores through one durable correction ledger, immediately
updating its list, Sleep periods/totals and the timeline. Empty/no-main-night days retain the Naps
entry. A retained-input coaching rebuild runs independently in the background, survives restart
and exposes retry state; it does not restage main sleep. Nap credit affects sleep need, while the
existing cross-night debt model remains unchanged. New unjudged detections cannot resurrect stale
cached proposals, and legacy lost proposals restore as user reports without invented stages.
Trends defaults to Week; Sleep/Strain Today share full daily charts, and measured HR/HRV/wear
charts retain their actual dates. Steps includes the hourly source chart; Step calories has a
separate kcal trend using daily maintenance's walking term.

Local release checks pass: 3,318 Flutter tests with 368 intentional skips; 91 focused tests with
the personal build flag; all 7 personal-iOS contract tests; project/path/pin guards; analysis with
60 infos and no errors/warnings. Representative food, nap, Steps and Trends layouts were inspected,
and daily details pass at 320 points with 1.5x text. These checks do not verify native speech,
background execution, wrist accuracy or signing on the phone.

Required regression cases: retained-only/empty/history cross-day retry and failure; correct split
crossings and duplicate prevention; pause/minimise/resume windows; missing/mixed-source run steps;
cross-midnight/DST allocation; live/detail/history/share calorie parity; absent HR/GPS/motion data;
explicit zero and partial macro preservation; unchanged metric/imperial profile saves and failures;
step-only goal days, threshold equality, goal raise/lower before/after completion, late data,
historical goal migration, restart, midnight, missing steps, and session/step corrections. Add policy-
explicit overlap tests, phone movement before/after an independent wrist-only walk in the same hour,
passive live publication, continuous band-walk midnight splitting and background/range coverage.
Exercise native phone commit → Today/Food/Weekly/breakdown reload, maintenance read failures,
profile/run dependency changes and the separate held HR calculation without a stale-success claim.
Also exercise rapid nap reject/restore, last removal, relaunch, stale legacy bundles, manual-only
days, immediate period/timeline agreement and retained-only coaching credit; Trends route/default
and chart reuse; and a Today maintenance sheet whose initial snapshot belongs to the prior date.

Required phone gates before acceptance: multiple kilometre cues while locked and while another app
is foreground; music/podcast/call/Bluetooth interruption; minimise/resume/pause; GPS-denied behavior;
insight retry with a connected/disconnected band and no new records; calories across live/detail/
history/Food; decimal entry and unchanged saves; all macro rows; step-only streak and target edits.
Measure wrist fallback against counted steps with the phone carried, left nearby and out of range;
offline WHOOP 4 coverage is a documented limitation, not an acceptance promise of accurate steps.
Only after the phone pass and current-version refresh enrollment should the resulting candidate
replace accepted build 70. `setup.md` owns subsequent publication/build evidence; this audit
does not constitute phone acceptance or cache promotion.

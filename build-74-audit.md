# Build 74 audit and implementation contract

**Status:** Build `0.9.41`/`74` (algorithm 90) is published and built on Akshat's
approval of the combined repairs and useful audit/Gemini additions. Local release validation
passes: 3,343 full-suite tests (376 intentional skips), 107 personal-profile tests and eight
personal-iOS contract tests. Analysis has 113 infos and no errors/warnings; rendered layouts were
inspected and generated screenshots removed. Source `ba5bb29f` is published with approval;
Linux CI `37397127258` and personal macOS build `37395690305` pass. Downloaded version/source,
checksum, ZIP integrity and personal payload/extension checks pass. The corrected validator accepts
the required `PlugIns/` parent only and retains other extension/file exclusions.
Build 74 is the sole cached testing IPA and is not installed yet; build 73 remains installed.
Phone acceptance and current-version enrollment remain pending; accepted build 70 remains recovery.
`todo.md` owns release and device gates; `setup.md` owns build evidence.

CI `37397127258` validates test-only repair `fa16be3c`; all app/packaging inputs match
compiled IPA source `ba5bb29f`. `setup.md` records the elapsed-window fixture correction.

## Implemented build-74 behavior

- Food → Foods exposes Scan beside My foods → New. Both library and meal scans open an editable
  serving/nutrition review before Save to My foods; meal logging then requires explicit Log on
  the portion screen. Cancel adds nothing, rescans update the same barcode food, optional values
  stay absent and saved barcode foods work offline. Unknown/flagged/unreachable scans offer manual
  label entry. Brand and ancillary label nutrients survive editing and unit conversion.

- Budget/ACSM values stay side by side on Today, Food/history/Weekly, Trends/Steps, live and
  finished run/walk screens, workout history and share cards. Budget coefficients are unchanged;
  ACSM uses net walking/running distance coefficients on the same dated movement ledger.
  HR/Keytel is expandable analysis, never an extra maintenance term or an automatic HR switch.
- Daily iPhone motion distance is retained with accepted step windows. Valid recorded walking
  routes replace their overlapping phone distance; run windows are removed once. Remaining
  steps use a labelled height-based distance estimate when possible. Unknown distance stays
  unavailable. Calories remain estimates, particularly for household start/stop walking.
- Current-day Strain, heart-rate, hourly Steps/calories and Wear scrubbing/rendering stop at now,
  including accessibility actions. Completed overnight records and workouts retain their range.
  Historical day browsing is permanent, Step calories opens Today, and useful breathing/workout
  HR series have dated readouts. Deep sleep consistently uses purple. Units have one owner.
- Paused route charts map wall timestamps to active-minute HR/cadence slots. Session pause
  excludes session movement, while accepted daily steps continue. Missing signals remain gaps.
- Calorie-history reads use the requested range and shared run inputs, cached by repository,
  input revision and day/range. Foreground/manual refresh also re-reads ongoing-workout movement
  after daily phone steps, so live energy cannot retain an older session snapshot. Food navigation can load
  before background history estimates; refresh awaits both, with separate retryable status.
- Notification taps carry date/session/finding identifiers, clear a prior detail route and wait
  for an open input sheet to close. Recovery, health, device and workout alerts open focused
  destinations. Weekly wording and training evidence are retained; missing evidence is explicit.
- Training review is local and opt-in for notifications. Separate run/walk comparisons require
  three matched sessions in each fortnight, sufficient route/HR coverage and similar pace or HR.
  Live cadence prefers fresh phone steps/minute and otherwise accepted wrist measurements;
  measured zero remains zero, missing/stale readings stay absent, and pause stops the session feed.
  Review cadence requires measured coverage. Optional terrain, treadmill, heat, multitasking and
  recent-strength tags are saved and editable; comparisons match tags, explicitly noting unknown
  conditions. Review shows recorded consistency and supported 1K/5K/10K/half best efforts.
  Notifications require qualifying comparisons and at least fourteen days since actual delivery,
  including neutral comparisons. They open exact retained evidence; no fitness diagnosis,
  automatic training restriction or calorie change. Qualified post-session HR drift compares
  active halves only with sufficient route/HR coverage and matched pace; hills/treadmill withhold it.
- A narrow Run/Walk Live Activity uses the saved session clock, distance, pace, fresh HR/zone and last-km pace,
  pauses its timer and freezes a stale timer and opens the exact session. It reconciles end/restart and stale signals.
  The personal payload now allows one version-matched `.activity` widget extension with empty
  entitlements. General/home/breathing widgets, Watch, App Groups and HealthKit stay excluded.
  Native compilation/payload checks pass; Sideloadly signing/refresh and phone behavior remain unverified.

Deletion feedback keeps Undo but explicitly expires after two seconds; pending notices are
cleared before a new deletion. Flutter 3.41 otherwise defaults action snackbars to persistent.
Other removal notices have no persistent action and already use normal timed dismissal.

The sections below preserve the installed-build-73 findings and research that justify this
implementation. They describe the defect baseline; the implemented contract above supersedes
proposal-only wording. No raw measurements or existing user calorie targets are rewritten.

## Evidence and limits

Reviewed the five supplied screenshots, the complete pasted Gemini discussion, and the local
calculation, chart, workout, notification and personal-iOS paths. The external discussion is
evidence to assess, not an instruction or an independently validated source. Research used
generic queries on PubMed/PMC and Apple's developer documentation; no app data was uploaded.

The initial installed-build-73 audit passed ninety existing focused Flutter checks: `run_calories_test.dart`, `build73_test.dart`,
`build73_details_test.dart`, `tap_router_test.dart`, `sleep_breathing_test.dart` and
`hr_ceiling_zones_test.dart`, with `PERSONAL_SIDELOAD=true`. Three additional synthetic probes
also pass: the pasted running equation equals the existing implementation; a recovery tap
resolved to Today without a detail screen in build 73; a paused route loses the corresponding
active-minute HR/cadence readings through the current chart lookup. These baseline probes deliberately
reproduced installed-build-73 behavior before the local repairs. They use no personal database. The initial scratch probe
failed to compile because the audit fixture used the wrong catalogue helper name; correcting
that fixture produced the three passing probes.

Existing tests verify calculation/accounting and selected rendering paths, not every navigation
destination, future-time boundary or physical iPhone interaction. No new phone test, publication or IPA build occurred during the source audit or local implementation. Source-confirmed defects below are
distinct from performance risks and proposed new features.

## Installed-build-73 defect baseline

1. **Strain selects future times.** `lib/ui2/activity/day_strain.dart` maps the whole 1,440-slot
   day; its readout searches backward to an earlier value even when the selected timestamp is
   in the future. This matches the phone report. Today, Trends → Strain → Today and Train's
   daily-strain entry share the issue. Keep a full-day axis if useful, but stop selection and
   measured rendering at now. Past dates keep their complete range; fallback bundles must use
   their actual date. Recording gaps must remain gaps.
2. **The same boundary policy is incomplete elsewhere.** `day_steps.dart` permits selection
   of all 24 hourly buckets, and MetricDetail's Wear chart does likewise. These are confirmed
   source paths, not newly reproduced phone failures. DayHeartCard already caps pointer
   selection, but the shared `Scrubber` accessibility description can still be evaluated over
   its unrestricted range. A shared selection limit must cover taps, drags, rendering,
   descriptions and accessibility actions. Do not truncate a completed overnight sleep record
   or a finished workout merely because its date crosses midnight.
3. **Step calories opens 7 days.** `MetricDetail.initState` explicitly sets `_range = 1` for
   `step_kcal`, while other metric details start at Today. Remove that exception. The outer
   Trends page already opens Week; preserve that separate choice.
4. **Daily Steps is hidden behind a chart gesture.** The date/value action exists only while
   `_pick != null`. The two screenshots show the before/after states. Show a permanent selected
   day row, initially Today/latest available, and an always-visible daily list or Browse days
   action. Today detail should have date arrows/picker immediately. Tapping any retained day
   should open its hourly detail in one step, including from Trends. Retain the 7/30-day view.
5. **Step calories has a distinct series but an incomplete daily destination.** It already
   computes walking kcal rather than reusing step counts, so the old identical-series defect
   should not be reported as still unfixed. However, it lacks the Steps day-screen route and
   hourly calorie presentation. Provide daily kcal, the dated weight and run-step exclusions,
   with a clear path to source steps; hourly allocations must reconcile with the daily ledger.
6. **Breathing history is static.** `sleep_breathing.dart` draws bars without a Scrubber or
   selected-night date/value. It loads once instead of observing metric revisions, and a read
   failure can resemble insufficient nights. Add night selection, date, cycles per observed
   hour, analysed coverage and quality/withheld reason where available. Preserve the aggregate
   explanation: this is a pattern in heart rate, not measured breaths or an apnoea diagnosis.
   Reload while open when results change; distinguish loading, insufficient data and retryable
   failure. Keep missing nights at their real dates instead of compressing the calendar.
7. **Units can be duplicated.** MetricDetail's `_slotSays` includes the unit, then ChartFrame
   appends its unit again. The selected Steps screenshot shows `steps steps`; the shared
   contract can also duplicate bpm/kcal. Give the readout one owner for units and test all
   callers, wrapping and enlarged text.
8. **Paused workout charts mix two clocks.** `activeTrack` retains real timestamps and route
   gaps. `ActivityResult.hr` and `_perMinute(sessionMotionWindow)` use compact active-minute
   slots, while `RunView.hrAt/cadenceAt` index them using wall-time route offsets. A synthetic
   two-active-minute session with a ten-minute pause reproduces missing later HR/cadence.
   Use timestamped samples or an explicit wall-time-to-active-time mapping, preserving the
   pause gap and aligning route, pace, HR, cadence and readout. This is a chart mismatch;
   it does not by itself prove that the integrated calorie total is wrong.
9. **Some related charts are still static or inconsistent.** Non-route workout summary HR
   uses a LineChart without a Scrubber; deep sleep is purple in the hypnogram/stage rows but
   blue in MetricDetail and a sleep-comparison tile. Add readouts to useful historical/time
   series and use one stage colour. Compact decorative zone/progress bars need not become
   interactive if they already expose their values and open the full detail where relevant.
10. **Step-calorie history does unnecessary work.** `stepCaloriePoints` serially calls
    `DayUpkeep.read` over the available step series before the visible range is applied.
    Each daily read traverses run accounting. This is a source-level performance risk, not a
    measured phone latency. Bound reads to the chosen range, batch shared history inputs and
    cache by input revision, date, profile and model version; retain latest-request guards.
11. **Notification destinations are too generic.** Recovery resolves to Today with no focused
    recovery screen. Health exceptions open the Trends domain through `/heart`; band alerts
    open general settings through `/profile`; idle-workout taps choose Train. Several payloads
    do not identify the event date or session. On a warm tap the shell changes its domain but
    does not clear an already-pushed detail route, so that screen can remain above the intended
    destination. The latter is confirmed routing structure, with the complete warm/cold/modal
    flow still needing reproduction tests during implementation.

## Installed-build-73 calorie baseline: what is already consistent

`lib/compute/profile.dart`, `compute/day_upkeep.dart`, `gps/workout_measurements.dart`,
`gps/run_history.dart` and `data/profile_history.dart` are the shared calculation path.

- Walking budget: `2.74 * accepted_walking_steps * weight_kg / 8368`.
- Running budget: `0.005 * weight_kg * (0.143 * run_metres + 0.1 * walk_break_metres
  + 0.9 * trusted_climb_metres)`. Flat running is `0.000715 * metres * weight_kg`.
  The user's speed → VO2 → kcal/hour → session calculation is already algebraically identical:
  speed multiplied by time becomes distance. A zero-duration workout must not require division
  by zero merely to obtain this distance result. Untrusted GPS climb adds no calorie bonus.
- Daily budget: whole-day Mifflin BMR + walking energy outside covered runs + running budget
  + 10% of logged food. A walking workout's steps are already included; its calories are not
  added again. Run steps are deducted once. Unknown overlap uses the larger movement estimate
  instead of summing both unreduced terms. Lifting/other workout estimates are not added.
- Pausing excludes movement/HR/time from that session. Daily accepted steps continue, including
  paused walking/running movement; those steps remain daily walking energy. This is intentional.
- HR comparison: sex-specific Keytel gross kcal/min, minus `BMR / 1440` over measured active
  minutes, with missing slots unfilled and fractional minutes respected. It is not an extra
  maintenance term. There is no automatic HR-above-100 switch to this method.
- Dated/snapshotted weight, overlap handling, midnight allocation and revision-driven reloads
  were implemented in build 73. The focused checks pass; the outstanding phone matrix still
  matters. Do not silently rewrite history with today's weight or reuse obsolete model caches.
- The food/weight estimate already aligns its weight interval with complete food days and
  requires coverage. That earlier defect was repaired in build 73; do not list it as still
  present. Its fixed 7,700 kcal/kg conversion remains an approximation.

**Active calories** means estimated energy above resting expenditure for the relevant measured
movement/workout period. Resting expenditure is already represented by daily BMR. “Maintenance
so far” currently includes the entire day's BMR plus activity/food recorded so far; it is not
calories burned since midnight, nor a complete estimate of every component of actual TDEE.

## Research assessment and model recommendation

### The “mechanical floor” claim needs correction

Weyand's reported 2.74 is metabolic joules per kilogram **per stride**, at the most economical
walking speeds measured. A stride is two steps; `8368 = 2 * 4184` supplies that conversion.
It is not a universal per-step mechanical-work constant. The abstract supports the efficient
walking relationship, not a guaranteed minimum for all speeds, slopes, loads or individuals.
The original full-methods resting-baseline convention was not independently established from
the available abstract; retain the existing budget convention without claiming that this
alone proves an exact net physiological floor. [Weyand et al., 2010](https://pubmed.ncbi.nlm.nih.gov/21075938/).
Baseline choice itself matters: standing and resting subtraction yield different net walking
costs. [Weyand et al., baseline study](https://pubmed.ncbi.nlm.nih.gov/19964188/).

The audit found no traceable primary validation for the app's running coefficient `0.143` as an
individual lower bound, elite-runner calibration or universal kinematic law. It can remain an
explicitly chosen lower budgeting coefficient, but those stronger descriptions should go.
“Conservative estimate” describes a budgeting choice, not certainty that actual expenditure
must exceed it. The earlier “true floor” wording was too strong.

### ACSM is a useful comparison, not a second guaranteed truth

ACSM's gross VO2 equations are resting + `0.1*v + 1.8*v*G` for walking and resting +
`0.2*v + 0.9*v*G` for running, with speed in metres/minute and grade as a decimal. Removing
the resting term and using approximately 5 kcal/litre oxygen gives flat net estimates of
`0.0005 * walking_metres * kg` and `0.001 * running_metres * kg`. Do not subtract BMR again
from those already-net expressions. Walking's grade coefficient is 1.8, not running's 0.9.
[Primary model paper documenting ACSM equations](https://pmc.ncbi.nlm.nih.gov/articles/PMC5919631/).

At a hypothetical 80 kg and 5 km flat run, current running budget is 286 kcal versus ACSM
400 kcal. Current is 28.5% below ACSM; ACSM is about 39.9% above current. Those percentages
have different denominators and must not be interchanged.

Walking does not have a fixed ordering: 10,000 steps at 80 kg gives about 262 kcal through
Weyand; ACSM gives 200 kcal if those steps cover 5 km, or 300 kcal if they cover 7.5 km.
The crossover is about 0.655 metres per step. Therefore these numbers do not define a lower
and upper safety range. A large treadmill-walking validation found ACSM underprediction on
average; this supports treating it as an imperfect model rather than “true maintenance.”
[CADENCE-Adults validation](https://pmc.ncbi.nlm.nih.gov/articles/PMC7896743/).

Use steady-state/gait context and expose input quality. The traditional running equation's
intended speed range does not justify treating every very slow jog, sprint, hill or GPS gap as
equally validated. Validation of VO2max predictions is also not interchangeable with validation
of submaximal session calories. [Running equation limitations](https://pmc.ncbi.nlm.nih.gov/articles/PMC3743617/).

### Keep HR as a comparison

Keytel is a population regression, not a direct oxygen measurement. The original study used
115 exercising adults and steady-state treadmill/cycle stages; the version without a fitness
measure explained less variance than the fitness-aware version. The app uses that simpler
version. It can be displayed for walking and running, but a complete HR trace does not make
it personally calibrated. [Keytel et al.](https://pubmed.ncbi.nlm.nih.gov/15966347/).

Heat can raise HR without an equivalent increase in work. A heat study of a different HR-based
model supports that general limitation; its error percentage is not a correction factor for
our Keytel implementation. Do not replace Weyand merely because HR exceeds 100/120, average
the methods, add them, or assume true burn lies between them. [Heat/HR validation](https://pubmed.ncbi.nlm.nih.gov/30606899/).

### Recommended product structure

1. Keep **Budget estimate** as the primary continuity model: the existing walking/running
   terms, full-day BMR and logged-food allowance. Explain deliberately excluded movement
   types and incomplete coverage. Keep the user's calorie target/deficit as a separate decision.
2. Add **ACSM distance estimate** alongside it in a maintenance comparison only when the same
   day's movement has adequate comparable distance coverage. Otherwise show a session/covered
   movement comparison marked partial, not a complete second daily maintenance number.
   The current all-day phone bridge retains steps, not distance. Full-day ACSM requires a
   dated native motion-distance ledger with source/coverage and run exclusion, or explicitly
   estimated walking distance; wrist-only steps do not supply precise metres. Never silently
   treat unknown distance as zero or label height-derived distance as measured.
3. Retain **Heart-rate analysis** in the workout analysis/details, showing measured-minute
   coverage and the resting subtraction. It is not a third main calorie column, a maintenance
   input or an automatic substitute for either main estimate. Preserve the legacy calculation
   and stored measurements; the old code's Method 2 name remains Keytel until descriptive labels
   replace numeric names. Use the same active windows/weight snapshot for every model.
4. Use **Estimated maintenance from food and weight** as the longer-term reality check, with
   aligned complete logs, coverage and multi-week weight trend. It is not an extra term to
   add to either daily estimate. Fluid changes and adaptation limit exact inference from
   short intervals and the fixed conversion. [Hall's dynamic energy-balance model](https://pubmed.ncbi.nlm.nih.gov/21872751/).

Do not call the columns “fat loss” versus “true maintenance” or promise that eating between
them ensures a deficit. A lower model plus an explicit deficit can unintentionally combine
two reductions. Keep the 10% logged-food allowance visibly approximate; omitted optional
macros are a reason not to pretend a precise protein/fat-specific thermic calculation.
Diet composition affects that thermic response. [Diet-composition experiment](https://pubmed.ncbi.nlm.nih.gov/10193874/).

More elaborate cadence/height/speed walking models and calibrated HR-plus-motion models are
possible later. They require model-specific validation and reliable inputs, not an average
of the current numbers. The basic shared movement ledger remains the first priority.

### Accepted two-estimate presentation and reconciliation

Show **Budget estimate** and **ACSM estimate** in consistent side-by-side positions on every
walking/running calorie and daily-maintenance surface: setup/live, finished summary, retained
history, sharing, Today/Food maintenance and their breakdowns, Weekly and relevant Trends/day
details. Do not collapse them when close together. Missing/partial inputs retain the labelled
position and coverage explanation instead of a fabricated zero. Calories eaten and the user's
food target remain single independent values; these movement models do not recalculate foods.
Other sports are not silently priced with a walking/running equation.

The two daily totals share the same BMR and 10% logged-food allowance; only the movement model
differs. Both exclude duplicate walking-workout additions and covered run steps/distance. Both
exclude paused movement from the workout while allowing it into ordinary daily movement. Neither
uses Keytel to increase the total. All pages read one versioned pair of calculation results;
do not implement a new formula separately in each widget or reinterpret stored Method 2 values.

The existing `walkingEnergy` distance helper uses `steps * 0.413–0.415 * height` as a height-based
step-length estimate, not a measured distance. Its comment calls that a stride, which should be
corrected. For ACSM, prefer reliable measured walking distance; a height-based fallback may be
used only with a visible **Estimated distance** label and dated profile inputs. Without enough
inputs, keep the ACSM column unavailable/partial. The build-73 helper required height before
returning its calorie/distance pair; independent step-calorie availability must not be lost merely
because distance cannot be estimated. This is a source-level edge case, not a reported phone bug.

For household walking, the selected input is Apple's `CMPedometerData.distance`. The
existing native `motionWindow` already reads this per-session field; the daily `stepsInInterval`
path returns steps only. Extend the daily ledger to retain phone motion-distance estimates over
the same dated/source windows as accepted steps, without requiring Start or continuous app GPS.
Apple explicitly calls this distance estimated and permits a missing value; do not describe it
as a ground-truth indoor measurement or promise an accuracy percentage.
[Apple distance property](https://developer.apple.com/documentation/coremotion/cmpedometerdata/distance).
Use validated route distance for recorded outdoor segments where appropriate, phone motion
distance for supported phone-carried periods, and a clearly labelled step-length fallback for
remaining accepted steps only. Never sum overlapping route and motion distances. Check house
walking with repeated turns, very short/slow bouts and carrying positions on the actual phone;
phone-left-behind periods need accepted wrist steps and cannot acquire measured phone distance.

Even perfect distance would not make ACSM exact for household movement: steady-state equations
do not fully represent short start/stop bouts. A controlled study found bout duration changes
walking's metabolic cost. Keep ACSM labelled an estimate; do not apply that study's group effect
as an automatic household calorie multiplier.
[Short-bout walking research](https://pmc.ncbi.nlm.nih.gov/articles/PMC11521144/).

## Notifications and lock-screen session presentation

### Existing personal notification inventory

- Recovery ready; unusual-physiology/health exceptions; detected-workout review and idle-workout
  prompt; band battery/charging/gone-quiet/charge forecast; conditional weekly physiological
  lookback; signing-expiry warnings; and the report of a user-armed band alarm.
- Delivery depends on permission, category/feature switches, quiet hours, event classification
  and deduplication. The weekly lookback already exists, but is not a fortnightly run-progress
  feature. An emitted event is not proof of OS delivery on a phone.
- Step-goal, movement and wind-down notifications are explicitly disabled by personal
  `NotificationPrefs.load`. Water, medication and journal prompts are also disabled because
  their personal destinations were removed. Do not accidentally revive them by widening a
  category allowlist. Step-only streak qualification still works independently of OS alerts.

Introduce a destination carrying screen, date, session/finding id and reason. Recovery opens
that day's recovery detail; health opens the relevant finding/day; device alerts open the band
status; workout prompts open that session/review; recap opens its retained period. Queue taps
until app/database/navigation are ready, consume once, and handle warm foreground routes and
forms without silently losing unsaved input. Expired/missing records get a clear fallback.
Apple provides notification-response callbacks; the exact navigation is the app's responsibility.
[Apple notification actions](https://developer.apple.com/documentation/usernotifications/handling-notifications-and-notification-related-actions?changes=_8_4).

Recommended additions: an opt-in fortnightly training review, and optionally an opted-in
personal step-goal achievement. Prefer one useful retained finding over routine notification
volume. The fortnightly review can compare pace at similar HR, HR at similar pace, consistency
or a supported best effort. Require separate run/walk comparisons, adequate HR/route coverage,
comparable conditions and enough sessions in both periods; otherwise remain silent. Proposed
engineering thresholds (such as at least three comparable sessions in each fortnight) are
quality gates to test, not scientific proof of improvement. Match observed data and wording:
“Lower recorded HR at a similar pace in these runs,” not “your heart grew stronger.” Tap opens
the exact evidence. Keep everything local, opt-in, quiet-hour aware and deduplicated.

### Live Activity architecture and remaining native gates

Build 73 deliberately excluded the Live Activity bridge/extension/support key. Build 74 enables
one workout-only extension and replaces its fields with the shared distance/pace/paused clock
contract; it does not revive general widgets or App Group bridges.

Implemented initial design: a compact dark card with Run/Walk and a clear active/paused state; active
timer, distance and pace as the main row; fresh HR as secondary information. Expanded Dynamic Island shows timer/distance/pace; its
compact form shows activity and distance. Fresh HR zone and last-kilometre pace are included. Tap opens the exact live session;
finish/pause can initially stay in the app. Avoid exposing a route/name on the lock screen.
Show missing/stale HR honestly; pause freezes its active timer. End, crash recovery and
restart must reconcile the same session id and saved clock. No new calorie algorithm belongs
inside the widget.

Apple requires a widget extension and ActivityKit support. Local app updates need no push
server; a Live Activity itself does not receive location or grant extra execution time.
It has a maximum active lifetime of eight hours. [Apple Live Activities](https://developer.apple.com/documentation/activitykit/displaying-live-data-with-live-activities?changes=_6).
The current background location/audio collection remains a separate device check.

Reintroducing this narrowly scoped extension changes the personal signing/payload contract.
Akshat's build-74 implementation approval includes this local capability change. It still needs
macOS compilation, payload validation and real Sideloadly extension signing,
overwrite/data retention, current-version refresh enrollment and unattended-refresh checks.
Do not claim free signing is impossible or guaranteed before those checks. Build 70 stays
the recovery IPA. Do not promote the candidate before its extension and background checks pass.

## Assessment of the other Gemini topics

- **HR maximum and zones:** do not infer an exact maximum of 198/200/210 from age, RPE or
  gasping. The app already combines an observed ceiling or Tanaka fallback with its shared
  resting anchor; it does not just use `220-age`. Individual age-prediction errors are large.
  Label an estimated ceiling and its source; allow a valid measured override only as a
  deliberate later feature. No unsupervised exhaustion test or automatic zone recalibration
  from one hard run. [HRmax prediction validation](https://pubmed.ncbi.nlm.nih.gov/23913510/).
- **Zone 2/3 and progression:** reject “grey-zone waste,” exact fat-burning switches, guaranteed
  four-to-six-month HR reductions, or diagnosing ventricular growth from pace/HR. Zone
  conventions differ; use understandable effort descriptions and trends, not deterministic
  training promises. Optional pace/zone targets should preserve user control.
- **Cadence:** retain the metric and expose matched-session history. A change from 145 to
  160 does not prove good posture, reduced joint impact or elite economy. Studies of relative
  cadence changes do not establish one universal cadence target. [Cadence/loading study](https://pmc.ncbi.nlm.nih.gov/articles/PMC6088121/),
  [cadence/economy study](https://pmc.ncbi.nlm.nih.gov/articles/PMC6317050/).
- **Cardiac drift:** a post-session first/second-half comparison can be useful only after
  matching pace, active windows, terrain and HR coverage. Heat and other conditions can
  affect drift; a ten-bpm rise alone is not a breathing fault or injury warning.
  [Heat/HR drift experiment](https://pubmed.ncbi.nlm.nih.gov/37348014/).
- **Recovery/HRV:** keep contextual suggestions rather than locking hard workouts or claiming
  CNS damage. HRV-guided training has research support in specific protocols, not a universal
  safety rule for this score. [HRV-guided training trial](https://pubmed.ncbi.nlm.nih.gov/26909534/).
- **Long-term fitness insights:** pace at matched HR and HR at matched pace are worth adding,
  with sample count, dates and route/conditions. Closing the calorie-model gap is not an
  independently validated fitness score. Phone cadence does not measure ground-contact time.
- **Audio/haptics/motivation:** existing km speech and its call/music interruption handling
  need device acceptance. Optional target cues should debounce and use sustained measurements.
  A user-controlled encouragement button may be useful later; harsh automatic coaching or
  accidental double-tap triggers are not a priority. Keep planned-rest days and avoid shame
  or claiming a binary daily target determines biological progress.
- **Ghost comparisons:** a matched prior route/distance overlay is a later feature, dependent
  on GPS quality and comparable sessions. Do not compare arbitrary coordinates/time offsets.
- **Weather and tags:** start with optional manual terrain, treadmill, heat, attention and
  recent-strength-session tags, now implemented; wrist temperature is not ambient weather. An
  external weather service/location transmission would be a new integration needing separate
  destination approval. Tag associations are not causal diagnoses or quantified CNS fatigue.
- **Official WHOOP APIs/sleep need:** this app owns local BLE/SQLite computations. The pasted
  backend/OAuth design does not describe the current architecture or supply official raw
  historical step data. Do not silently add a cloud backend, subscription score or Gemini
  integration. Local sleep need/insights must name their own data coverage and model.

## UI wording and reachability contract

- Walking: **From steps — estimated active energy from accepted steps and your weight.**
- Running: **From distance — the chosen lower distance estimate, using your weight; walk
  breaks are separated.** Details name coefficients without claiming a physical guarantee.
- HR: **From heart rate — an exercise estimate using HR, age, weight and sex, with resting
  energy removed.** Show measured minutes; BMR subtraction is not the prediction itself.
- ACSM: **Standard distance estimate — a walking/running oxygen-cost equation; distance and
  grade quality limit accuracy.** Use “estimated distance” or “partial coverage” when relevant.
- Daily energy: **Estimated daily budget — full-day resting energy plus recorded movement
  and a food-digestion allowance.** Avoid a misleading elapsed-burn headline.
- Explain Strain (cardiovascular load, not kcal), Recovery (comparison with personal baseline),
  HRV (variation between beat intervals), usual range (personal observed range, not a clinical
  target), zone (estimated effort band), cadence (steps/minute), active versus moving pace,
  CVHR (heart-rate cycling during sleep), missing coverage and rebuilding states.
- Primary values/actions remain visible without hovering. Use concise one/two-line definitions
  and optional More detail, consistent units/colours and a direct date selector. Compact
  previews should open the corresponding full chart rather than a generic page. Retain all
  existing metrics; no feature removal is authorized by this audit.
- Replace the current within-50-kcal merged primary display with the accepted persistent
  Budget/ACSM pair. HR remains reachable in analysis/details. Numerical agreement between
  estimates is not proof of accuracy and must not be described as validation.

## Release verification contract

**Repair core:** shared chart boundaries/readouts/accessibility, permanent daily navigation,
Step calories Today and daily detail, breathing selection/reload/error states, paused HR/cadence
alignment, deep-stage colour, bounded history reads, exact notification routing and descriptive
labels. These are implemented together in the local build-74 source.

**Implemented presentation:** persistent Budget/ACSM pair using the
same movement ledger and explicit distance coverage, with HR analysis separate. Keep current
budget coefficients unless Akshat explicitly changes the primary model. Each model must have
a cache identity; model changes invalidate/rebuild all affected
daily, historical, Weekly, live, summary and share values. Never alter stored raw measurements.

**Implemented additions:** narrow Run/Walk Live Activity capability and opt-in
fortnightly local training review, live cadence, context tags and qualified HR drift. More coaching, ghost routes, weather services and personal
zone calibration can follow later; they are not prerequisites for dependable basic navigation.

Required implementation checks:

- Fixed-clock charts before midnight, at rollover, on a past/fallback date, local DST days,
  sparse/gapped/absent measurements, current partial hour, stale future points and enlarged text.
  Exercise pointer and accessibility selection from every Today/Trends/Train entry.
- Permanent day navigation before touching the chart; selected-day persistence; future arrows
  disabled; steps/kcal rows show the correct units and open the correct dated detail.
- Pauses/resumes/late first GPS fix/missing HR/irregular motion chunks: route, HR, cadence,
  splits and readouts align without inventing samples. Session pauses preserve daily movement.
- Arithmetic fixtures for metres/km, steps/strides, decimal grade, weight precision, zero/invalid
  inputs, run/walk breaks, trusted versus uncertain climb, net/gross resting removal, midnight,
  overlapping windows, source handoffs and missing distance. Every page agrees within rounding.
- Refresh and saved food/profile/workout changes update visible details and history caches;
  date races, read failure, retry, partial logs and old-build cached values remain explicit.
- Notification taps on cold/warm/foreground launch, above a modal/form, before data is ready,
  for historical dates/finished or deleted sessions, repeated responses and unknown old routes.
  Verify exact destination and no duplicate push or lost unsaved input. Confirm personal gates.
- Optional Live Activity: lock/unlock, pause/resume, music/call/Bluetooth changes, GPS/HR loss,
  app termination/recovery, final dismissal and matching session metrics. Native build success
  alone does not establish refresh/signing or background correctness.
- Run focused regressions, the full release suite and personal payload-contract tests after
  implementation; inspect small/normal widths and large text. One combined IPA only after the
  approved scope passes. Promotion still requires phone acceptance and refresh enrollment.

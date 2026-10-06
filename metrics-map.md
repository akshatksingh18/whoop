# WHOOP personal app: metrics map

Everything the app stores and where each item appears in the approved local build. This file is the
reference for keeping the personal build focused on lifting, running, sleep and recovery. It covers
the built personal source `0.9.41`/`74` (algorithm 90); physical-device validation is pending.

**Status:** Build 74 source `ba5bb29f` is published with Akshat's approval and passes local
regression/release validation, Linux CI, macOS IPA compilation and downloaded artifact checks.
Build 74 is installed but superseded: Source `0.9.42`/`75` (commit `1c203f17`) is published with Akshat's approval; Linux CI `37514558854` (3,369 tests, 371 intentional skips) and personal macOS build `37514599309` pass. Downloaded source/version, checksum, ZIP integrity and payload/extension checks pass. Build 75 is installed. Build-76 source `0.9.43`/`76` (commit `3f8ada60`) is published with Akshat's approval; Linux CI `37534408576` (3,373 tests, 371 intentional skips) and personal macOS build `37534409412` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Build 76 is the single testing candidate,
awaiting installation, complete phone acceptance and current-version enrollment. Build 73 was replaced on the phone and was not accepted; its testing artifact
is superseded. Build 70 remains the accepted recovery. `build-74-audit.md`
records chart/navigation/notification findings and implemented calorie comparisons; `todo.md` owns
the implemented build-74 contract and release gates. Budget coefficients are unchanged; ACSM is
now a separate distance comparison using the same ledger. `setup.md` owns the artifact/workflow evidence.
CI `37397127258` validates test-only repair `fa16be3c`; all app/packaging inputs match
compiled IPA source `ba5bb29f`. `setup.md` records the elapsed-window fixture correction.

Stored metrics remain intact; any removal
still needs Akshat's per-item approval.

## What is stored

### 1. Raw band data (short-lived)

| Store | What it holds | Kept |
|---|---|---|
| `decoded_onehz` | 1-second heart rate, motion, skin temperature, per-second steps | about 3 days after a day is fully analysed |
| `decoded_rr` | every beat-to-beat interval (the HRV input) | same as above |
| `raw_records` / `raw_archive` | undecoded band frames kept for replay and recovery | same as above; unknown formats archived longer |

Nothing a screen shows depends on raw data once a day is analysed.

### 2. Per-day scalars (`metric_series`, kept forever)

One number per day. These drive every trend, baseline and "against your usual" comparison.

**Recovery and heart**
- `readiness` = recovery score
- `rhr` = resting heart rate
- `rmssd` = HRV. Also `ln_rmssd`, `sdnn` and `hrv_cv` (night-to-night swing)
- `lf_hf` = HRV frequency balance
- `prsa_dc` = deceleration capacity
- `dip_pct` = how far heart rate falls in sleep
- `hrr_bpm` and `hrr_tau_s` = heart-rate recovery after efforts
- `hr_ceiling_bpm` = highest heart rate observed
- `irregular_rhythm_flag` = screen, not a diagnosis

**Sleep**
- `tst_min` = total sleep
- `deep_min`, `rem_min`, `light_min` = stage minutes (they sum to `tst_min`)
- `efficiency` = asleep while in bed
- `sol_min` = time to fall asleep
- `awakenings` and `longest_sleep_min`
- `unobserved_min` = band gaps in the night
- `sleep_onset_sec` and `midsleep_sec` = bedtime and midpoint consistency
- `nap_min`

**Breathing and temperature**
- `resp_rate` = breaths per minute in sleep
- `brv_cv` = breathing variability
- `skin_temp_z`, `skin_temp_adc` and `skin_temp_coverage_frac`

**Load and activity**
- `strain` (0–21) and `trimp` = cardio load
- `calories` (active) and `calories_total`
- `steps`
- `active_min`
- `dyn_p90` = movement intensity

**Other**
- `stress` = overnight autonomic stress, 0–100
- `worn_min` = wear time

### 3. Per-day bundle (`day_result`, kept forever)

The full analysis of each day, including curves:
- **`hr_curve`:** heart rate every minute of the whole day. This powers the new all-day heart-rate
  chart.
- **Other day curves:** `strain_curve`, `activity_curve` (5-minute movement), and the daytime HRV
  timeline.
- **Night:** hypnogram (stage per moment); the overnight heart rate, HRV, breathing and
  skin-temperature lanes; sleep window, cycles and wake-ups; nocturnal HR (average and lowest).
  Also the breathing-disturbance screen (heart-rate cycling, CVHR), oxygen-dip proxy fields,
  personal baselines (robust centre and spread per metric), and the illness watch.
- **Sleep Coach** (in the cross-day rollup): sleep need, debt, minutes added for training load,
  minutes credited from naps, and target bedtime/wake.

### 4. Training

| Store | What it holds |
|---|---|
| `sessions` | every workout: type, start/end, strain, Method 1 active calories for run/walk, estimated HR/MET calories for other types, max HR, time in each HR zone, steps, cadence, device |
| `workout_route` / `workout_split` | GPS route points and per-kilometre splits (runs, rides, walks) |
| `baselines` calculation anchors (preferences mirrored) | retained `motion.<session>` answers, active workout windows/pauses, captured profiles, voice milestones, dated profile and step-goal history; included in backup/import |
| `strength_set` / `exercise_def` | lifting sets: exercise, weight, reps |
| `workout_suggestions` | auto-detected efforts waiting for confirmation |

### 5. Manual logs

These are still stored but no longer entered in the personal build:
- **Removed from the UI:** `journal_metric`/`journal` (the journal), `med_*` (medications),
  `cycle_log`, and water (a journal field).
- **Removed from the UI as well:** `lab_result` (Health → Labs), `breathing_session` (the paced
  breathing screen), `strength_set` entry (lifting sets; a Lift is now a timed session, and old sets
  stay stored for a later migration), and `imported_measurement` (phone imports).
- **Still in the UI:** meals under Food (see below).

### 6. Nutrition

| Store | What it holds |
|---|---|
| `food_entry` | each logged item: date, meal (breakfast/lunch/dinner/snack), quantity/unit, kcal, protein, carbs, fat, fibre, food key |
| `food_def` | your foods, stored per 100 units (grams by default, or links/slices/cups/ml/custom units): typed from a label ("50 g oats = 200 kcal…") or cached from a barcode scan |
| `meal_template` | saved meals: a name, a usual meal slot, and foods at fixed quantities and units |
| profile `kcal_target`, `protein_target`, `carbs_target`, `fat_target`, `fibre_target` | typed daily targets |
| `food_entry.grp` | a sub-heading inside a meal ("Oatmeal", "Omelette"); logging a saved meal fills it with the meal's name |
| `body_weight` | one weight per day (latest wins); logging one also sets profile `weight_kg` |

## Where each core metric appears now

Four tabs, each one scrolling page: **Today · Trends · Food · Train**.

| Metric | Today | Trends row | Detail screen |
|---|---|---|---|
| Recovery | ring with the score, verdict, HRV and resting HR | yes | Readiness: drivers and 90-day history |
| Sleep | card with a bar against sleep need | yes | Sleep: chart, stages, against your usual, overnight signals, naps |
| Strain | card with a bar and today's target | yes | Day strain: any day (arrows), draggable curve, zones, three-line method |
| Heart rate, all day | live bpm, then the day's line and range | — | Scrubbable minute-by-minute chart (stops at the current time) |
| HRV, resting HR | inside the recovery card | yes | metric detail with measured nightly HRV / daily HR charts |
| Steps, walking kcal | card | separate Steps and Step calories rows | Steps with inline hourly source graph; separate kcal trend |
| Maintenance estimate | card: resting · steps · run · food; tap for the detail sheet | step calories row | Food → Today (card and sheet) and History |
| Breathing rate | — | only when measured on at least half the nights of the last 30 | metric detail; Sleep overnight row when measured; Readiness says why it was not counted |
| Skin temperature | — | once 7 of the last 30 nights have one | metric detail (this band's nights only, as a difference from usual); Sleep overnight row |
| Wear time | — | yes | metric detail, with recorded hourly wear and unmeasured gaps |
| Breathing pattern in sleep | — | — | one tap below Sleep |
| Bedtime and sleep need | — | — | not shown (still computed); the wind-down reminder is off and hidden |
| Illness watch, past findings | card when amber/red | "Noticed" section | resting HR chart, findings log |
| Naps | — | — | Sleep → Naps section on a day with one; Naps screen to edit |
| Workouts, GPS | — | — | Train: Run / Walk / Lift / Other, run-or-walk streak, draggable 7-day strain (tap opens that day), running trends (draggable weekly distance, predicted 5K/10K, best 1K/5K/10K/half), recent sessions; a run opens the run screen (Apple Maps route, calories by distance and by heart rate, best efforts, verdict, splits, linked pace/HR/elevation charts, pace zones); a walk opens the same screen without the running-only parts |
| Food, calories left, macros | — | — | Build-75 source: Maintenance → Calories (opens the whole day) → Macros; meal cards show kcal and P/C/F; one dragged order for My foods and saved meals shared with the log screen (no sort); + opens the portion screen or saved-meal review; − / + amounts; up to two named measures per food; saved meals keep sub-headings; swipe either way deletes. Food → Today: ‹ day › with calendar and swipe, calorie and macro cards, maintenance, evening protein-left line, meal cards (Log; ⋯ copy from / copy to / save meal). Meal page: sub-groups, editable quick-add entries, swipe-to-delete with Undo. Log screen: search, My foods (default) / My meals, sort, direct Scan and product review, food detail with % of goals and "often eaten with", named quick add with optional fibre; decimal servings and heading selection before logging; saved-food/meal deletion directly in the picker |
| Maintenance history, weight | weekly card | — | Food → History: weight card (7-day trend, estimated maintenance from food and weight), completed-day weekly deficit, trailing 31-day maintenance-vs-eaten chart with range caption, lazy calendar-month accordions (current open, older closed), logged-day rows that open for editing |

Build-75 source: Trends opens on 7 days, with the same Today / 7 days / 30 days / 3 months
switch every metric screen uses. Each row shows today's value (Today) or the range's daily
average, with a small line; tapping opens the metric at the same range. Every metric shows its
newest day with ‹ › arrows and opens that day (night signals open Sleep, Wear the breakdown);
7 days lists days, 30 days weekly and 3 months monthly averages with a 7-day average line.
Build 74 and earlier opened Trends on Week and showed the newest reading in every range. Sleep and Strain's Today sections reuse their full
daily detail charts. Step calories opens its own kcal trend rather than the Steps dashboard;
it uses the same dated walking contribution as daily maintenance.
Build 73's Step calories detail still defaults to 7 days and lacks a direct daily breakdown;
Steps' dated action appears only after chart selection. These remaining navigation gaps, static
breathing history and shared readout/time limits are implemented in build 74;
`build-74-audit.md` and `todo.md` own the validation limits.

**Readiness:** history is a line (build-75 source; coloured bars before), opened from Trends
through the shared metric screen with the same ranges; its inputs open their own metric.
Dragging an empty day reads its stored reason (14-night baseline building, no sleep heart data, HRV or resting HR not measured, held back).

The end-to-end readiness audit found no bug. Each night writes HRV (`ln_rmssd`), resting HR,
breathing and skin temperature into `metric_series`. `_BaselineHistoryCache` reads the last 28
earlier values per input, excluding imported days and other band families. `readinessComposite`
requires at least 14 earlier nights per input, at least two usable inputs and at least half the
weight; robust z-scores are combined with weights renormalised over available inputs. Missing
scores store `readiness_absent_diag`; `readinessGap` exposes the per-day reason. The sparse history
before 30 September reflects those baseline/missing-input/import rules, not a broken read path.

**Steps (phone first, personal build):** positive phone measurements own overlapping time, even
when the band counts more. Accepted wrist-only spans supplement uncovered time; dense walking
cadence is required to override a measured phone-zero span. Hour/source/day boundaries preserve
measured counts. Fine phone windows around source handoffs and session pauses avoid subtracting
whole-hour totals from part-hour sessions. Growing live wrist windows replace their earlier partial
rows rather than accumulating duplicates. Personal builds request the live IMU passively while
connected, subject to device battery/background acceptance. Source provenance stays visible.
WHOOP 4 recorded history cannot accurately reconstruct offline steps beyond Bluetooth range.
`resolveDaySteps` in `lib/data/live_coverage_policy.dart` is the common counter.

**Charts:** every trend chart takes a finger: a line and a ring mark the point, and the date and
value show in the chart's header (metric detail at every range, Readiness history, Train's strain
and weekly distance, day strain, hourly steps). Titles and selected values have their own
full-width rows; selected text wraps without ellipsis. Every tab refreshes on a pull: today's phone
steps first, then band sync and today's queued calculation. Measured steps publish immediately via
the shared coverage resolver, even without new band records; Today, Steps, Strain detail and today's
step-chart point agree. Stored counter/imported/interim counts remain fallbacks when no fresh source
covered the date. Explicit phone stillness is zero; an unread day stays absent. The calculation
enqueue is awaited, and read failures, holds and the 60-second refresh cap show a status message.
Today/food cards also reread after committed food writes, derived changes, foreground return,
and the five-minute foreground refresh (including local day rollover and fresh phone counts). No pull is needed and
workout voice also enables the approved iOS audio background mode. A fresh launch opens Today; warm resume retains position.

**Food coverage:** calories/protein are primary. Optional omitted macros remain null/untracked;
explicit zero is retained. Weekly energy summaries exclude today, unknown-calorie entries and
past days without an evening entry on that local date. Missing optional macros do not exclude a
day. Logged protein is averaged only over qualifying days with protein values. Coverage/exclusions
are shown; this heuristic cannot detect every forgotten food or prove a complete diary.
All four macro rows/icons remain visible, with zero logged when nothing supplied that nutrient;
null is preserved internally. Run/walk streaks accept ten active recorded minutes OR reaching the
dated measured step goal. Displayed targets change immediately; raising an earned goal
cannot revoke that day's saved qualification threshold. Overlapping recorded run/walk windows
count only once toward ten minutes. A measured count correction can revoke unsupported
completion. No historical step-only days are invented before dated goals were recorded.

### Computed and stored, but shown on no screen

Still calculated every day and kept in `metric_series`, so a screen can be added back with its
history intact: stress score, LF/HF, HRV night-to-night swing, deceleration capacity, heart-rate
dip, heart-rate recovery, breathing variability, TRIMP, active minutes, sleep efficiency / deep /
REM as their own trend charts, chronotype, social jetlag and sleep regularity, fitness / fatigue /
form (training load), next-morning session cost, and the beat-by-beat night data.

## Sleep screen: what each section shows

1. **Total sleep:** time asleep, in bed, bedtime → wake, and % asleep while in bed.
2. **Through the night:** stage chart (deep in the sleep violet) with the stage names only in the
   colour key and five clock marks. Drag it: time · stage · heart rate · HRV · skin temperature
   (against the night's average, °C) show in two wrapping header rows. Deep uses the same violet in
   Stages. A compact wake-up/stretch summary stays visible; full caveats are under Night details.
3. **Stages:** Deep, REM, Light (minutes and % of sleep, summing to total sleep) and Awake.
4. **Against your usual:** your last 28 nights for time asleep, deep sleep, % asleep while in bed,
   and when you fell asleep.
5. **Unusual:** one card only when something stood out, e.g. sleeping heart rate high or a rough
   night naming which measurements moved.
6. **Overnight signals:** one row each with a small line: heart rate (average and lowest), HRV,
   skin temperature (difference from usual), and breathing only on a night it was measured.
7. **Naps:** always reachable, including an empty or nap-only day; log, reject or restore.
   Saved corrections update this list, Sleep periods and the timeline immediately. Sleep coaching
   rebuilds in the background from retained results; it does not restage the whole main night.
8. **Occasional rows:** "Fix sleep times" (folded), and breathing pattern across nights (one card:
   within/above your usual, a small nightly chart, caveats folded).

There is no Tonight section: Akshat sleeps on his own schedule, so the target bedtime, sleep need
and debt are not shown (the Sleep Coach still computes them).

## How calories are estimated

**Daily maintenance** (Akshat's chosen conservative budgeting estimate):
maintenance = BMR + step calories (steps outside runs) + running (Method 1) + 10% of the food logged.

- **BMR:** Mifflin–St Jeor for the whole day: 10 × kg + 6.25 × cm − 5 × age, + 5 for men, − 161
  for women (the midpoint otherwise). `bmrMifflin` in `lib/compute/profile.dart`.
- **Step calories:** 2.74 × steps × kg ÷ 8,368 (Weyand et al. 2010 form), energy above resting
  only, on the day's steps **minus the steps taken during that day's runs**. `stepCalories`.
  This is the app's chosen active-energy budget convention. The reported constant is metabolic
  J/kg per stride at economical walking speeds; a stride is two steps and 8,368 is 2 × 4,184.
  It is not a universal per-step mechanical minimum. `build-74-audit.md` owns the source limits
  and comparison/wording contract; no Budget coefficient or resting subtraction changed.
- **Running (Method 1, the accepted distance estimate):** 0.005 × kg × (0.143 × metres run + 0.1 × metres
  walked inside the run + 0.9 × metres climbed). This is Akshat's four steps folded together (speed ×
  time = distance, speed × incline × time = climb, 0.3 ÷ 60 = 0.005). `runFloorKcal`.
  - Running vs walking inside a run: by GPS speed over ±15 s, 2.0 m/s and up is running, below it
    walking (ACSM walking cost 0.1, so a walk break never counts as running), below 0.5 m/s
    standing (nothing). Without GPS, from the phone per minute: 140 steps/min and up is running.
    `runMix` / `motionMix` in `lib/gps/run_analysis.dart`.
  - Unverified GPS elevation adds no calorie bonus; smoothed elevation remains visible. The climb coefficient is retained for trusted climb input; downhill never subtracts movement.
  - Run steps: the shared phone/wrist resolver over active windows, with retained phone motion
    or recorded session counts as legacy fallbacks. Paused movement remains daily walking steps.
    Midnight allocates distance and steps to each local day. Overlapping sessions contribute once
    to maintenance. Without reliable overlap coverage, use the larger of run Method 1 and full
    walking energy rather than adding both unreduced. A run without distance adds nothing and its
    steps remain walking steps.
  - Walks are never in this row; their steps stay in Steps.
- **Food (thermic effect):** 10% of the kcal logged that day; 0 until something is logged.
- **Lifts and other workouts are not added.**
- Checked: 23 y, 80.5 kg, 186.69 cm, 15,000 steps, 2,500 kcal eaten → 1,862 + 395 + 250 = 2,507
  with no run; with a 5 km run that took 4,835 steps → 1,862 + 268 + 288 + 250 = 2,668
  (`test/walking_energy_test.dart`, `test/run_calories_test.dart`).
- **Where it shows:** the Maintenance card on Today, the Maintenance card on Food → Today (tap
  either for a sheet with one plain line per part and its numbers), and "Maintenance N · M
  under/over" on completed Food → History days; unfinished rows say So far or Partial log.
  Trends has a Step calories row.
- **The calorie goal never changes:** Akshat types it once (Food → target button); maintenance is
  shown beside it, not used to move it.

These are estimates, not guaranteed individual physiological minima. The card includes the
whole day's BMR plus movement and food recorded so far; it is not burn elapsed since midnight.
ACSM uses `0.005 * kg * (0.2 * run_metres + 0.1 * walk_metres + 0.9 * trusted_run_climb
+ 1.8 * trusted_walk_climb)`, excluding resting already. Daily ACSM maintenance uses the same
full-day BMR and 10% logged-food allowance, with the same run ownership and step exclusions.
Current GPS climb is not trusted for additions. A recorded walking route replaces overlapping
phone distance; no walking-workout calorie addition exists. iPhone `CMPedometerData.distance`
is saved beside its accepted step coverage. Remaining steps use an explicit height-based distance
estimate when possible; absent distance/profile stays unavailable, never zero or an invented burn.

Budget/ACSM are persistent paired values on Today/Food/history/Weekly, Trends/daily Steps,
live/summary/history/share. HR is separate expandable analysis. No within-50-kcal merging or
claim of a guaranteed upper/lower range remains. Neither model measures true individual TDEE.
Calories eaten and fixed food targets are independent of exercise. `build-74-audit.md` owns the
research and quality limits. Algorithm 90 invalidates old derived values; raw movement/profile
records remain intact. Notification/training snapshots are retained evidence, not calorie caches.
`DayUpkeep` is shared by Today, Food, history, Weekly, Trends, Steps detail and open maintenance
sheets. The displayed step-calorie contribution already accounts for running, and historical
points use dated weight. Step charts prefer retained measured counts on every covered date,
including days without a derived result, instead of leaving older build totals in place. Measured
steps and their calories reload immediately after the saved input revision, independently of HR
calculation. Food/profile/workout changes, foreground return and the foreground timer invalidate
dependent views. Foreground/manual refresh also re-reads current session movement after daily
phone coverage. Run/walk history recalculates Method 1 rather than retaining old gross estimates.
Build-73 release checks, CI/macOS and downloaded IPA validation pass. Build-74 local release
checks pass: 3,343 full-suite tests (376 intentional skips), 107 personal-profile tests and eight
personal-iOS contract tests; analysis has no errors/warnings. Source `ba5bb29f` is published
with approval; Linux CI `37397127258` and macOS build `37395690305` pass. Downloaded checksum,
source/version, ZIP and payload/extension checks pass; `setup.md` owns complete evidence.
Build 73 installation is confirmed; build 74 installation and calculation/refresh phone checks remain before calling these
fixes verified on iPhone.

**A run's or walk's own calories** (setup/live/summary/history/share):
- Walking Method 1: exactly `(2.74 * active_session_steps * weight_kg) / 8368`, labelled From steps.
- Running Method 1: the accepted distance equation, labelled From distance.
- Method 2: sex-specific Keytel gross kcal/min (men: (−55.0969 + 0.6309 × HR + 0.1988 × kg +
  0.2017 × age) ÷ 4.184; women: (−20.4022 + 0.4472 × HR − 0.1263 × kg + 0.074 × age) ÷ 4.184)
  minus resting `BMR / 1440` for each measured active minute, floored at zero. Missing HR minutes
  are not filled from the average; a partial final minute uses its actual duration. Method 2 is a
  comparison, never an extra maintenance term and never switched in merely because HR exceeds 100.
- Budget and ACSM are both labelled estimates of Active calories: energy above estimated resting
  burn, already included in daily BMR. HR/Keytel remains in analysis with measured-minute coverage.
- Walking is already included by daily steps and contributes no extra workout addition. Running
  substitutes its Method 1 for the Weyand energy of its covered active steps.
- Live cadence is measured steps/minute: fresh phone data first, then accepted recent wrist
  cadence; zero is measured stillness, absent/stale is unavailable. It does not change calorie
  coefficients or impose a universal target. Session pause stops its cadence feed. Optional
  terrain/treadmill/heat/multitasking/recent-strength tags are captured and editable. Qualified
  post-session HR drift compares active halves with adequate HR/route coverage and matched pace.
- Training review compares separate run/walk fortnights with matched tags and measured coverage,
  shows recorded consistency and supported best efforts, and optionally notifies no more often
  than fourteen days between deliveries. Missing comparable evidence stays silent.
- Pausing freezes session duration, route distance, HR, zones and steps. Daily steps keep counting.
  Kilometre voice is owned by session events, with saved milestones and the actual kilometre pace;
  iOS audio mode and interruption handling require locked-screen/calls/music device acceptance.
- A captured workout profile preserves its weight basis; dated profile/scale records anchor days.
  Older sessions without those records use the available dated fallback; old missing weights
  cannot be reconstructed. Decimal metric/imperial inputs preserve precision across saves.
  Metric prefills and food quantity/nutrient editors retain all supplied decimals.
  Sub-minute movement allocation from older minute-level records remains proportional; the
  app cannot reconstruct an exact step timestamp that was never recorded.
- Other workouts retain estimated HR/MET calories and remain excluded from this maintenance budget.
  Stored daily HR/cadence `calories` and `calories_total` are separate analytics, not Method 1.

**Apple Health:** not used. Steps come from the iPhone's own motion sensor when **This phone →
Steps** is on; HealthKit stays excluded from the personal build.

**Food/weight maintenance inference:** labelled Estimated maintenance from food and weight.
It requires at least eight weigh-ins and fourteen fully covered food days aligned to the interval
from the first morning weight (inclusive) to the last morning weight (exclusive). Any missing or
heuristically incomplete day withholds the estimate; visible coverage explains why. Optional
omitted macros do not disqualify calorie coverage. Least-squares weight slope and 7,700 kcal/kg
remain approximations. This estimates total expenditure for that interval: do not add BMR,
movement or food digestion again. No automatic HR hybrid or coefficient adjustment is adopted.

## Layout decisions (local source `0.9.41`/`74`)

| Item | Decision |
|---|---|
| Tabs | Today · Trends · Food · Train; no sub-tabs except Food's Today/History/Foods |
| Look | Flat rounded cards on a near-black page, floating tab bar, short labels, no paragraphs on main screens |
| Health → Explore, Beats, Body clock, Stress row, Consistency cards | Removed (data still stored) |
| Home greeting and "Today's plan" | Removed; the strain target moved into the Today cards |
| Bedtime / sleep need | Removed from Today and Sleep (Tonight section) at Akshat's request; still computed |
| Steps screen | The per-stretch list is removed; the hourly bars are draggable and the totals line stays |
| Metric detail (personal build) | No algorithm-version dotted lines, no locked-range line, no Worn bars under the chart |
| Today | Weekly card: deficit at the floor, logged protein vs target, km run, streak, average sleep; completed-day coverage and exclusions |
| AI coach, AI briefings, language picker, paced breathing | Removed |
| Train | One page. Removed the activity library tab, mascot card, fitness/fatigue/form, kg-lifted chart, morning-after and overreach cards, and the share poster button |
| Lifting sets | Removed. A Lift is a timed session scored from heart rate |
| Settings | One list (band, profile, alarm, steps, notifications, units, data, privacy, status). Removed Tasker/Shortcuts, double-tap, app icon, add-a-sensor, phone import |
| Notifications | Personal movement nudge, wind-down and step-goal alerts stay hidden/off. In the upstream-capable profile the step-goal action uses the measured total and configured target; earning the streak does not require alerts |
| Band alarm, barcode scanning, Sleep screen, Nutrition | Kept |

Built build-74 food-library addition: Food → Foods → My foods exposes Scan beside New.
Scanning reviews serving/nutrition before Save to My foods, without a meal or diary entry.
Cancel adds nothing; barcode-key updates preserve ancillary label data and missing macros.
Meal scanning shares the editable review, then waits for explicit portion/meal Log.
Manual fallback and saved-product offline lookup reuse the existing paths. `todo.md` owns
phone gates; the cached `ba5bb29f` replacement includes this addition. CI passes with test-only
fixture repair `fa16be3c`; its app/packaging inputs match the compiled IPA source.

Common press actions use light selection haptics. Entry sheets keep a close/drag header above the
scrolling form, respect the top safe area, and dismiss the keyboard on drag; cancellation never
requires saving. Food forms use the same wrapper. Failed saves/read actions show retry status.
Cross-day insight rebuilding is a local action independent of band sync, with busy/history/error
states and a warning that clears only after a confirmed result. Neither a pending warning nor
missing retained inputs is presented as a successful rebuild.

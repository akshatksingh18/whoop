# WHOOP personal app: metrics map

Everything the app stores and where each item appears, plus the proposed layout. This file is the
reference for keeping the personal build focused on lifting, running, sleep and recovery. It covers
the personal build from source `0.9.36`/`69`.

**Status:** Current map of stored data and screens for source `0.9.36`/`69`. Everything in
"What is stored" keeps being recorded whether or not a screen shows it; any further removal still
needs Akshat's per-item yes.

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
| `sessions` | every workout: type, start/end, strain, active calories, max HR, time in each HR zone, steps, cadence, device |
| `workout_route` / `workout_split` | GPS route points and per-kilometre splits (runs, rides, walks) |
| app preferences `motion.<session>` | the phone's per-minute steps and distance over a run or walk, saved the first time it is read (the phone keeps only 7 days): run steps for maintenance, and distance/splits/cadence for a session with no GPS |
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
| `food_entry` | each logged item: date, meal (breakfast/lunch/dinner/snack), grams, kcal, protein, carbs, fat, fibre, food key |
| `food_def` | your foods, stored per 100 g: typed from a label ("50 g oats = 200 kcal…") or cached from a barcode scan |
| `meal_template` | saved meals: a name, a usual meal slot, and foods at fixed grams |
| profile `kcal_target`, `protein_target`, `carbs_target`, `fat_target`, `fibre_target` | typed daily targets |

## Where each core metric appears now

Four tabs, each one scrolling page: **Today · Trends · Food · Train**.

| Metric | Today | Trends row | Detail screen |
|---|---|---|---|
| Recovery | ring with the score, verdict, HRV and resting HR | yes | Readiness: drivers and 90-day history |
| Sleep | card with a bar against sleep need | yes | Sleep: chart, stages, against your usual, overnight signals |
| Strain | card with a bar and today's target | yes | Day strain: any day (arrows), draggable curve, zones, three-line method |
| Heart rate, all day | live bpm, then the day's line and range | — | Scrubbable minute-by-minute chart (stops at the current time) |
| HRV, resting HR | inside the recovery card | yes | metric detail |
| Steps, walking kcal | card | yes | metric detail, steps breakdown |
| Maintenance (floor) | card: resting · steps · run · food; tap for the detail sheet | step calories row | Food → Today (card and sheet) and History |
| Breathing rate | — | only when measured on at least half the nights of the last 30 | metric detail; Sleep overnight lanes when measured |
| Skin temperature, wear time | — | yes | metric detail; Sleep overnight lanes |
| Breathing pattern in sleep | — | — | one tap below Sleep |
| Bedtime and sleep need | — | — | not shown (still computed); the wind-down reminder is off and hidden |
| Illness watch, past findings | card when amber/red | "Noticed" section | resting HR chart, findings log |
| Naps | — | section on a day with one | Naps |
| Workouts, GPS | — | — | Train: Run / Walk / Lift / Other, run-or-walk streak, draggable 7-day strain (tap opens that day), running trends (draggable weekly distance, predicted 5K/10K, best 1K/5K/10K/half), recent sessions; a run opens the run screen (Apple Maps route, calories by distance and by heart rate, best efforts, verdict, splits, linked pace/HR/elevation charts, pace zones); a walk opens the same screen without the running-only parts |
| Food, calories left, macros | — | — | Food: Today, History (month), Foods |

Trends has a Week / Month / 3 months switch. Each row shows the average for the range, a small
line, and the newest reading.

**Charts:** every trend chart takes a finger: a line and a ring mark the point, and the date and
value show in the chart's header (metric detail at every range, Readiness history, Train's strain
and weekly distance, day strain, hourly steps). Every tab refreshes on a pull: band sync, phone
steps, then today's derive, with the spinner held until it finishes (60 s cap).

### Computed and stored, but shown on no screen

Still calculated every day and kept in `metric_series`, so a screen can be added back with its
history intact: stress score, LF/HF, HRV night-to-night swing, deceleration capacity, heart-rate
dip, heart-rate recovery, breathing variability, TRIMP, active minutes, sleep efficiency / deep /
REM as their own trend charts, chronotype, social jetlag and sleep regularity, fitness / fatigue /
form (training load), next-morning session cost, and the beat-by-beat night data.

## Sleep screen: what each section shows

1. **Total sleep:** time asleep, in bed, bedtime → wake, and % asleep while in bed.
2. **Through the night:** stage chart with each lane named (deep in the sleep violet) and five
   clock marks. Drag it: the time and stage show in the header, and heart rate, HRV and breathing
   at that moment show underneath.
3. **Stages:** Deep, REM, Light (minutes and % of sleep, summing to total sleep) and Awake.
4. **Against your usual:** your last 28 nights for time asleep, deep sleep, % asleep while in bed,
   and when you fell asleep.
5. **Unusual:** one card only when something stood out, e.g. sleeping heart rate high or a rough
   night naming which measurements moved.
6. **Overnight signals:**
   - Headline numbers: sleeping heart rate, lowest heart rate and breathing rate.
   - Four lanes through the night: heart rate, HRV, breathing rate and skin temperature.
7. **Occasional rows:** correct the sleep window, and breathing pattern across nights.

There is no Tonight section: Akshat sleeps on his own schedule, so the target bedtime, sleep need
and debt are not shown (the Sleep Coach still computes them).

## How calories are estimated

**Daily maintenance** (Akshat's formula, a floor, never a ceiling):
maintenance = BMR + step calories (steps outside runs) + running (Method 1) + 10% of the food logged.

- **BMR:** Mifflin–St Jeor for the whole day: 10 × kg + 6.25 × cm − 5 × age, + 5 for men, − 161
  for women (the midpoint otherwise). `bmrMifflin` in `lib/compute/profile.dart`.
- **Step calories:** 2.74 × steps × kg ÷ 8,368 (Weyand et al. 2010 form), energy above resting
  only, on the day's steps **minus the steps taken during that day's runs**. `stepCalories`.
- **Running (Method 1, the kinematic floor):** 0.005 × kg × (0.143 × metres run + 0.1 × metres
  walked inside the run + 0.9 × metres climbed). This is Akshat's four steps folded together (speed ×
  time = distance, speed × incline × time = climb, 0.3 ÷ 60 = 0.005). `runFloorKcal`.
  - Running vs walking inside a run: by GPS speed over ±15 s, 2.0 m/s and up is running, below it
    walking (ACSM walking cost 0.1, so a walk break never counts as running), below 0.5 m/s
    standing (nothing). Without GPS, from the phone per minute: 140 steps/min and up is running.
    `runMix` / `motionMix` in `lib/gps/run_analysis.dart`.
  - Climb: smoothed elevation gain with a 3 m deadband; downhill counts as flat.
  - Run steps: the phone's steps over the exact run window (`motionWindow`), else the band's
    session steps. A run with no distance adds nothing and its steps stay walking steps.
  - Walks are never in this row; their steps stay in Steps.
- **Food (thermic effect):** 10% of the kcal logged that day; 0 until something is logged.
- **Lifts and other workouts are not added.**
- Checked: 23 y, 80.5 kg, 186.69 cm, 15,000 steps, 2,500 kcal eaten → 1,862 + 395 + 250 = 2,507
  with no run; with a 5 km run that took 4,835 steps → 1,862 + 268 + 288 + 250 = 2,668
  (`test/walking_energy_test.dart`, `test/run_calories_test.dart`).
- **Where it shows:** the Maintenance card on Today, the Maintenance card on Food → Today (tap
  either for a sheet with one plain line per part and its numbers), and "Maintenance N · M
  under/over" on every Food → History day. Trends has a Step calories row.
- **The calorie goal never changes:** Akshat types it once (Food → target button); maintenance is
  shown beside it, not used to move it.

**A run's or walk's own calories** (its screen, `RunCaloriesCard`):
- **From distance:** Method 1 above, for that session.
- **From heart rate (Method 2, Keytel 2005):** gross kcal/min (men: (−55.0969 + 0.6309 × HR +
  0.1988 × kg + 0.2017 × age) ÷ 4.184; women: (−20.4022 + 0.4472 × HR − 0.1263 × kg + 0.074 × age)
  ÷ 4.184) minus resting (BMR ÷ 1,440), per minute of the band's heart rate; a minute below zero
  counts as zero. `keytelActiveKcal`.
- Within 50 kcal of each other they show as one number (the distance one); further apart both
  show. Maintenance counts only the distance number for a run.
- Other workouts keep the band's heart-rate calories (`calories`, Keytel above 40% of heart-rate
  reserve), which the analytics still store with `calories_total`.

**Apple Health:** not used. Steps come from the iPhone's own motion sensor when **This phone →
Steps** is on; HealthKit stays excluded from the personal build.

## Layout decisions (source `0.9.36`/`69`)

| Item | Decision |
|---|---|
| Tabs | Today · Trends · Food · Train; no sub-tabs except Food's Today/History/Foods |
| Look | Flat rounded cards on a near-black page, floating tab bar, short labels, no paragraphs on main screens |
| Health → Explore, Beats, Body clock, Stress row, Consistency cards | Removed (data still stored) |
| Home greeting and "Today's plan" | Removed; the strain target moved into the Today cards |
| Bedtime / sleep need | Removed from Today and Sleep (Tonight section) at Akshat's request; still computed |
| Steps screen | The per-stretch list is removed; the hourly bars are draggable and the totals line stays |
| AI coach, AI briefings, language picker, paced breathing | Removed |
| Train | One page. Removed the activity library tab, mascot card, fitness/fatigue/form, kg-lifted chart, morning-after and overreach cards, and the share poster button |
| Lifting sets | Removed. A Lift is a timed session scored from heart rate |
| Settings | One list (band, profile, alarm, steps, notifications, units, data, privacy, status). Removed Tasker/Shortcuts, double-tap, app icon, add-a-sensor, phone import |
| Notifications | Movement nudge, step-goal alert and wind-down reminder removed (read as off) |
| Band alarm, barcode scanning, Sleep screen, Nutrition | Kept |

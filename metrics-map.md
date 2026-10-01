# WHOOP personal app: metrics map

Everything the app stores and where each item appears, plus the proposed layout. This file is the
reference for keeping the personal build focused on lifting, running, sleep and recovery. It covers
the personal build from source `0.9.33`/`66`.

**Status:** Current map of stored data and screens. The layout decisions at the bottom are
applied in unbuilt source; any further removal still needs Akshat's per-item yes.

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
| `strength_set` / `exercise_def` | lifting sets: exercise, weight, reps |
| `workout_suggestions` | auto-detected efforts waiting for confirmation |

### 5. Manual logs

These are still stored but no longer entered in the personal build:
- **Removed from the UI:** `journal_metric`/`journal` (the journal), `med_*` (medications),
  `cycle_log`, and water (a journal field).
- **Removed from the UI as well:** `lab_result` (Health → Labs).
- **Still in the UI:** meals under Nutrition (see below), `imported_measurement` (phone imports),
  and `breathing_session`.

### 6. Nutrition

| Store | What it holds |
|---|---|
| `food_entry` | each logged item: date, meal (breakfast/lunch/dinner/snack), grams, kcal, protein, carbs, fat, fibre, food key |
| `food_def` | your foods, stored per 100 g: typed from a label ("50 g oats = 200 kcal…") or cached from a barcode scan |
| `meal_template` | saved meals: a name, a usual meal slot, and foods at fixed grams |
| profile `kcal_target`, `protein_target`, `carbs_target`, `fat_target`, `fibre_target` | typed daily targets |

## Where each core metric appears now

| Metric | Home | Health | Detail screen |
|---|---|---|---|
| Recovery | ring | — | Readiness: drivers and 90-day history |
| Strain | ring | trend | Day strain: curve and zones |
| Sleep | ring | overview row | Sleep: chart, stages, against your usual, overnight signals, tonight |
| Heart rate, all day | "Heart rate, all day" row | Overview → Heart rate range | Scrubbable minute-by-minute chart and moments |
| Resting HR, HRV | resting HR tile | overview rows | metric detail, Beats (HRV) |
| Stress | — | overview row | metric detail |
| Breathing rate | — | overview row | metric detail; Sleep overnight lane |
| Breathing pattern in sleep | — | — | one tap below Sleep |
| Steps, active energy | tiles | trends | steps detail |
| Workouts, GPS, lifting | — | — | Workout tab |
| Food, calories left, macros | — | — | Nutrition tab: Today, History (month), Foods |
| Skin temperature, wear time | — | Overview (former Vitals rows) | metric detail |

## Sleep screen: what each section shows

1. **Total sleep:** time asleep, in bed, bedtime → wake, and % asleep while in bed.
2. **Through the night:** stage chart. Touch it to read the stage plus heart rate, HRV and
   breathing at that moment.
3. **Stages:** Deep, REM, Light (minutes and % of sleep, summing to total sleep) and Awake.
4. **Against your usual:** your last 28 nights for time asleep, deep sleep, % asleep while in bed,
   and when you fell asleep.
5. **Unusual:** one card only when something stood out, e.g. sleeping heart rate high or a rough
   night naming which measurements moved.
6. **Overnight signals:**
   - Headline numbers: sleeping heart rate, lowest heart rate and breathing rate.
   - Four lanes through the night: heart rate, HRV, breathing rate and skin temperature.
7. **Tonight:** target bedtime, sleep need (including the part added for training load) and debt.
8. **Occasional rows:** correct the sleep window, and breathing pattern across nights.

## How calories are estimated

- **Resting (BMR):** calculated from weight, height, age and sex with the Mifflin–St Jeor formula,
  spread across the whole day.
- **Active:** calculated from heart rate with the Keytel 2005 formula. It only counts minutes when
  heart rate is above 40% of heart-rate reserve (resting + 0.4 × (max − resting)). Every other minute
  counts as resting.
- **Total** = resting + active (`calories_total`). **Active** = the active part only (`calories`).
- **Steps do not add energy to these totals, by Akshat's decision.** Easy walking below the
  heart-rate threshold counts as resting. Lifting reads from heart rate alone, which a wrist sensor
  tracks loosely.
- **Walking energy is shown separately:** "≈N kcal walking" on the Home steps tile, and calories
  plus distance on the Steps breakdown. It never adds to active, total or the nutrition goal.
  - **Formula** (`walkingEnergy` in `lib/compute/profile.dart`): distance = steps × a height-based
    stride (0.415 × height for men, 0.413 for women), costed at about 0.5 kcal per kg per km net
    (ACSM level walking).
  - It needs height and weight in the profile.
- **Nutrition:** the calorie goal is whatever Akshat types and never grows with exercise. The Goals
  sheet shows the 14-day average of total burn as a reference only.
- **Apple Health:** decided against adding it. Without an Apple Watch, Apple's active energy comes
  only from the iPhone's own motion: the same steps the app already reads, which the walking
  estimate covers. HealthKit would also add a capability that free signing may refuse at install.
  The personal build keeps HealthKit excluded.
  - **Steps:** already come directly from the iPhone's motion sensor (the same source Apple Health
    uses), when **This phone → Steps** is on.

## Layout decisions (applied in source `0.9.33`/`66`, unbuilt)

| Item | Decision |
|---|---|
| Home: rings, at-a-glance tiles, today's plan, heart rate all day | Kept |
| Health: Overview (now including the former Vitals rows), Explore, Trends | Kept; three tabs |
| Health → Labs | Removed |
| Health → Vitals | Merged into Overview, without the duplicate breathing row |
| Naps card | Shown only on a day with a nap |
| Nutrition | Kept and rebuilt; see section 6 |
| Workout tab | Kept |

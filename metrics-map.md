# WHOOP personal app: metrics map

Everything the app stores and where each item appears, plus the proposed layout. This file is the
reference for keeping the personal build focused on lifting, running, sleep and recovery. It covers
the personal build from source `0.9.35`/`68`.

**Status:** Current map of stored data and screens for source `0.9.34`/`67`. Everything in
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
| Sleep | card with a bar against sleep need | yes | Sleep: chart, stages, against your usual, overnight signals, tonight |
| Strain | card with a bar and today's target | yes | Day strain: curve and zones |
| Heart rate, all day | live bpm, then the day's line and range | — | Scrubbable minute-by-minute chart (stops at the current time) |
| HRV, resting HR | inside the recovery card | yes | metric detail |
| Steps, walking kcal | card | yes | metric detail, steps breakdown |
| Maintenance (floor) | card: resting · steps · food | step calories row | Food → Today and History |
| Breathing rate, skin temperature, wear time | — | yes | metric detail; Sleep overnight lanes |
| Breathing pattern in sleep | — | — | one tap below Sleep |
| Tonight's bedtime and sleep need | row | — | Sleep → Tonight |
| Illness watch, past findings | card when amber/red | "Noticed" section | resting HR chart, findings log |
| Naps | — | section on a day with one | Naps |
| Workouts, GPS | — | — | Train: Run / Lift / Other, 7-day strain, running trends, recent sessions; a run opens the run screen (Apple Maps route, best efforts, verdict, splits, linked pace/HR/elevation charts, pace zones) |
| Food, calories left, macros | — | — | Food: Today, History (month), Foods |

Trends has a Week / Month / 3 months switch. Each row shows the average for the range, a small
line, and the newest reading.

### Computed and stored, but shown on no screen

Still calculated every day and kept in `metric_series`, so a screen can be added back with its
history intact: stress score, LF/HF, HRV night-to-night swing, deceleration capacity, heart-rate
dip, heart-rate recovery, breathing variability, TRIMP, active minutes, sleep efficiency / deep /
REM as their own trend charts, chronotype, social jetlag and sleep regularity, fitness / fatigue /
form (training load), next-morning session cost, and the beat-by-beat night data.

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

**Daily maintenance** (Akshat's formula, a floor, never a ceiling):
maintenance = BMR + step calories + 10% of the food logged that day.

- **BMR:** Mifflin–St Jeor for the whole day: 10 × kg + 6.25 × cm − 5 × age, + 5 for men, − 161
  for women (the midpoint otherwise). `bmrMifflin` in `lib/compute/profile.dart`.
- **Step calories:** 2.74 × steps × kg ÷ 8,368 (Weyand et al. 2010 form), energy above resting
  only. Running steps are costed as walking steps, which keeps it a floor. `stepCalories`.
- **Food (thermic effect):** 10% of the kcal logged that day; 0 until something is logged.
- **No workout calories are added.**
- Checked against the agreed case: 23 y, 80.5 kg, 186.69 cm, 15,000 steps, 2,500 kcal eaten →
  BMR 1,862 + steps 395 + food 250 = 2,507 (`test/walking_energy_test.dart`).
- **Where it shows:** the Maintenance card on Today (so far today), the Maintenance card on Food →
  Today, and "Maintenance N · M under/over" on every Food → History day. Trends has a Step
  calories row.
- **The calorie goal never changes:** Akshat types it once (Food → target button); maintenance is
  shown beside it, not used to move it.
- **Heart-rate calories still exist but are not on the main screens:** the analytics still store
  `calories` (active, Keytel 2005 above 40% of heart-rate reserve) and `calories_total`; a
  workout's own screen still shows its calories.
- **Apple Health:** not used. Steps come from the iPhone's own motion sensor when **This phone →
  Steps** is on; HealthKit stays excluded from the personal build.

## Layout decisions (source `0.9.34`/`67`)

| Item | Decision |
|---|---|
| Tabs | Today · Trends · Food · Train; no sub-tabs except Food's Today/History/Foods |
| Look | Flat rounded cards on a near-black page, floating tab bar, short labels, no paragraphs on main screens |
| Health → Explore, Beats, Body clock, Stress row, Consistency cards | Removed (data still stored) |
| Home greeting and "Today's plan" | Removed; strain target and bedtime moved into the Today cards |
| AI coach, AI briefings, language picker, paced breathing | Removed |
| Train | One page. Removed the activity library tab, mascot card, fitness/fatigue/form, kg-lifted chart, morning-after and overreach cards, and the share poster button |
| Lifting sets | Removed. A Lift is a timed session scored from heart rate |
| Settings | One list (band, profile, alarm, steps, notifications, units, data, privacy, status). Removed Tasker/Shortcuts, double-tap, app icon, add-a-sensor, phone import |
| Notifications | Movement nudge and step-goal alert removed |
| Band alarm, barcode scanning, Sleep screen, Nutrition | Kept |

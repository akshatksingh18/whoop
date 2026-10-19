# WHOOP personal app: metrics map

Everything the app stores and where each item appears in the approved local build. This file is the
reference for keeping the personal build focused on lifting, running, sleep and recovery. It covers
the Build 86 feature contracts, subsequent Build 87/88 repairs and installed Build `0.9.56`/`89`;
complete physical-device acceptance is pending.

**Status:** Akshat reports Build 89 installed and being tested. Recorded Linux/macOS and artifact
checks pass; full physical acceptance remains open. He rejects Progress's information overload;
`build-90-audit.md` retains the all-tab findings. The accepted A + compact B interface is
implemented in Build 90 local source; `todo.md` records checks and outstanding integration/device gates. Build 89 still occupies testing; its recovery promotion
is requested after the review. Build 70 remains cached recovery. `build-85-audit.md` owns earlier approved changes;
`build-74-audit.md` owns the Budget/ACSM research and comparison contract. Budget coefficients
moved to 0.17 mL/kg/m for running in Build 90 (Akshat's decision); the distance comparison uses ACSM only at supported measured speeds,
otherwise it is labelled Movement estimate using the same ledger. `todo.md` owns
current phone gates; `setup.md` owns source/hash/workflow evidence for current and superseded builds.

Build 88 (`0.9.55`/`88`, algorithm 92) was installed before Build 89 (algorithm 93). Historical
sections below describe the originating build; Build 89 retains those changes except where stated.
Stored metrics remain intact; any removal still needs Akshat's per-item approval.

## What is stored

### 1. Raw band data (short-lived)

| Store | What it holds | Kept |
|---|---|---|
| `decoded_onehz` | timestamped heart rate/motion and family-specific raw fields; WHOOP 4 has no historical step counter or verified temperature field | about 3 days after a day is fully analysed |
| `decoded_rr` | decoded reported beat intervals (variable coverage; HRV input) | same as above |
| `raw_archive` | undecodable/unknown-format frames, not a complete raw backup | retained, except old `undecodable_rec_v20` frames selectively thinned to one in 60 |
| `raw_records` | legacy raw-frame store | dropped by the current open-schema path; not available as a permanent replay ledger |

The usual decoded cutoff is three days behind the newest committed data edge, with bounded
protection for unfinished derivation. Inspect actual retained inputs before promising historical
recalculation; immutable derived results do not recreate pruned sensor observations.

Nothing a screen shows depends on raw data once a day is analysed.

### Sleep inputs and WHOOP comparison

The personal app reads the WHOOP 4 band's historical Bluetooth records, not WHOOP cloud sleep
results. `packages/protocol/lib/src/records.dart` decodes timestamps, heart rate, beat-to-beat
intervals (0-4 observed per record; the historical decoder accepts up to 8) and a three-axis
gravity/motion vector. The green optical count is decoded but not stored. Wear events qualify recording
gaps; they are not sleep-stage labels. The optical-block counts are not a continuous PPG waveform.

`calendarDays` in `lib/compute/substrate.dart` finds the main sleep ending on the local day,
using the single `segmentSleep` path. Motion/heart-rate candidate windows are staged by the
transparent `cardioStager` in 30-second epochs using movement, HR and RR-derived variability.
Asleep time, light/deep/REM, wakes and efficiency come from that same staging. Missing observations
remain unobserved, not invented sleep. Stages, especially the light/deep split, are estimates;
coverage confidence is not measured accuracy or a probability that a label is correct.

`onehz_pipeline.dart` computes nightly HRV as the mean of cleaned five-minute RMSSD windows,
resting HR from the lowest qualifying 30-minute sleep window, and breathing from RR modulation.
The primary helper currently splits rejected reported beats but can join unreported time inside
one bucket and qualify a window from one surviving difference; `bugs.md` records a synthetic
reproduction. Do not interpret "five-minute" as five minutes of verified beat coverage.
These are local calculations, not device-supplied nightly scores. WHOOP documents heart-rate and
movement sleep detection and machine-learning staging, and a differently weighted whole-night
HRV. Similar signal families do not imply identical models, values or validated accuracy.
Its official OAuth API exposes processed sleep summaries; this app does not use that API.

Official references, checked 2026-10-11:
- [Activity and sleep detection](https://support.whoop.com/s/article/Automatic-and-Manual-Activity-Detection)
- [WHOOP cycles and sleep staging](https://support.whoop.com/s/article/WHOOP-Cycles?language=en_US)
- [WHOOP Recovery and HRV weighting](https://support.whoop.com/s/article/WHOOP-Recovery)
- [Official API sleep/recovery schemas](https://developer.whoop.com/api/)

**WHOOP 4 field integrity:** `skinTempRaw` is an unverified optical-block quantity, not
temperature. Builds 86/87 consumed it; Build 88 gated temperature-labelled outputs and
physiological inputs to verified device families, retaining stored history. Installed Build 89
keeps this repair. The primary HRV identity/gates and observed-day load repairs also ship;
Build 89 adjusts the shared beat-adjacency tolerance to WHOOP 4 record-stamped timing.
`bugs.md` owns defects, `todo.md` owns implemented state and open phone gates, and
`metrics-accuracy-research.md` preserves the research baseline. These changes do not establish
physical accuracy or vendor-model parity. `build-88-plan.md` is the originating specification;
`build-90-audit.md` retains the original findings; `todo.md` tracks the Build 90 source merged on `build-90` and its outstanding acceptance gates.
Sleep detection/staging does not consume this field. SpO2 is already refused by the pipeline;
the decoded red/IR counts are not sufficient for a trustworthy oxygen percentage.

### 2. Per-day scalars (`metric_series`, kept forever)

One number per day. These drive every trend, baseline and "against your usual" comparison.

**Recovery and heart**
- `readiness` = recovery score
- `rhr` = resting heart rate
- `rmssd` = HRV. Also `rmssd_whole`, `ln_rmssd`, `sdnn` and `hrv_cv`
  (within-night NN-interval CV: `100 * SDNN / meanNN`, not night-to-night HRV variation)
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
- `awakenings` = observed wake runs of at least five minutes, excluding leading/trailing
  wake; segmentation and stored scalars share one function. `longest_sleep_min` never
  bridges an unobserved gap.
- `unobserved_min` = recording gaps in the night; any gap makes the displayed sleep
  duration an "at least" bound, with the missing duration stated.
- `sleep_onset_sec` and `midsleep_sec` = bedtime and midpoint consistency
- `nap_min`

**Breathing and temperature**
- `resp_rate` = breaths per minute in sleep
- `brv_cv` = breathing variability; `brv_slope` = qualified window-rate trend
- `skin_temp_z`, `skin_temp_adc`, `skin_temp_coverage_frac` and `skin_temp_settled_frac`
  (WHOOP 4 temperature-labelled legacy outputs, not validated temperature)

**Load and activity**
- `strain` (0–21) and `trimp` = cardio load
- `calories` (active) and `calories_total`
- `steps`
- `active_min`
- `dyn_p90` = movement intensity

**Other**
- `stress` = overnight autonomic stress, 0–100
- `worn_min` = epoch-minute buckets touched by record runs after bridging gaps up to 120 s;
  shared by metric history and day detail. HR validity does not gate wear. Day segments
  carry `worn`, `charging`, `off_wrist`, `missing` or `pending` states; only WRIST events
  establish off-wrist time. Coverage excludes the tail after the committed record frontier.

Build 90 decoder integrity: historical v12/v24 records accept at most four RR values;
larger declared counts emit no beats. R10 retains an independent eight-value limit. Optical
fields from unconfirmed layouts are NULL, including across isolate serialization; old zero
sentinels read as absent. Metric CSV omits legacy `odi_per_hour` and `spo2` rows. This does
not make any withheld optical output available.

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
- **Sleep Coach** (in the cross-day rollup): estimated baseline need plus one quarter of the
  estimated sleep gap, less the applied nap credit, with the existing bounds retained.
  The unsupported strain bonus is removed (`strain_bonus_min` remains 0 for compatibility).
- **RR reporting quality:** `coverage.rr_reporting` stores reported counts, HR/60 expected-count
  estimate, eligible record count and estimated omitted share; `rr_omitted_share` retains
  its trend. Unknown old counts yield no estimate. This does not gate or change nightly HRV.
- **Spectra:** HF Welch segments, respiration sub-windows and REM spectral features require
  at least 90% measured interval coverage and exclude clock re-anchors. Scaling and segment
  lengths remain unchanged; no surviving segment means absence.
- **Restlessness map:** five-minute arm-angle cells flag an observed range greater than 5°;
  absent acceleration is omitted. This replaces the uncalibrated magnitude-minus-1 g map.
- **Cycles:** an unqualified cycle estimate or unavailable stages produce no count, including
  legacy zero placeholders at the read boundary.

### 4. Training

| Store | What it holds |
|---|---|
| `sessions` | every workout: type, start/end, strain, Method 1 active calories for run/walk, estimated HR/MET calories for other types, max HR, time in each HR zone, steps, cadence, device |
| `workout_route` / `workout_split` | GPS route points and per-kilometre splits (runs, rides, walks) |
| `session_detail` | From Build 93: what was typed during a workout that no sensor records (laps, pool length, stroke, interval rounds, poses, breathing pace, game score) as JSON by session; shown again when the workout reopens, deleted with it, carried by backup import and rebuild salvage |
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
| `food_def.category` | the user's own category label (custom labels in Build 86; '' = Uncategorised); existing labels are preserved, and the same field feeds Foods, log-screen and saved-meal-picker filters |
| `food_entry.grp` | a sub-heading inside a meal ("Oatmeal", "Omelette"); logging a saved meal fills it with the meal's name |
| `body_weight` | legacy daily aggregate; today's sets profile `weight_kg`. `unit`, `entered`, `source`, `origin_id` and `history_only` preserve input/provenance; backdated/imported rows never price a day. Build 90 uses the first reading of each day; all readings remain in Body history |
| `body_weight_reading` | Build 90 schema 50: every reading with identity, effective date, Unix-second measurement time, kg, input units/value, source/origin, history-only flag and creation time. Legacy daily rows migrate once; Body and Food quick-weigh-in use BodyLogDb and rebuild the daily aggregate |
| `day_zone` / `zone_change` | Build 90 schema 50: observed IANA timeline and per-day UTC boundaries/offsets. Native inbox is acknowledged after SQLite commits; launch/foreground/sync check for missed changes. Workers use persisted context, SRI compares absolute instants 24 h apart, and travel-spanning nights are excluded from bedtime comparisons. Past travel before the first observation is unknown; the first known zone seeds older assignment context |
| `food_day_count` / `food_entry.logged_at` | Build 90 schema 50: frozen calorie-goal/counting provenance and a separate logging timestamp. Legacy logging times remain NULL; new entries carry eaten time and separate original logging time in epoch seconds. Closed dates freeze the first known goal; manual/automatic provenance stays distinct |
| `body_measure` | build-86 source: one tape session, inches by AkshatOS site key (unknown keys kept) |
| `body_photo` | build-86 source: a progress-photo record; the JPEG lives in `body_photos/` (metadata stripped) |
| `lift_log` | build-86 source: one Lift Log workout as JSON, linked to its WHOOP session (imported AkshatOS history has none) |

## Where each core metric appears now

Five tabs on installed build 86: **Today · Trends · Food · Train · Progress**, with Body inside
Progress and a compact Body row on Today. Build 86 restructures Today
(recovery, sleep and strain side by side in one card with HRV and resting HR under them, then a
taller heart-rate canvas, steps/food, Body and maintenance), Food (one day card with calories and
all four macros plus a fixed Add, then meals, then maintenance) and Train (Resume while live,
history before charts, one options menu per row). The table below is the retained wearable/food
entry inventory from build 85, supplemented by the Build 86 contracts below; no core metric became
unreachable in 86. Build 87 preserves that inventory while replacing its composition; current
local destinations and acceptance gates are documented in `build-87-ui-plan.md`.

| Metric | Today | Trends row | Detail screen |
|---|---|---|---|
| Recovery | numeric score/verdict, HRV and resting HR | yes | Recovery (Build 90): a lead sentence naming the biggest mover; per input, last night against the score's own usual range (28 measured nights within 60 days), a plain word and the points it moved the score from a typical night (they add up to the score); a missing input says "Unavailable, not counted"; Recent HRV card (14 nights, usual band, 7-night average, shared with the HRV page); history |
| Sleep | card with a bar against sleep need | yes | Sleep: chart, stages, against your usual, overnight signals, naps |
| Strain | card with a bar and today's target | yes | Day strain: any day (arrows), draggable curve, zones, three-line method |
| Heart rate, all day | live bpm, then the day's line and range | — | Scrubbable minute-by-minute chart (stops at the current time) |
| HRV, resting HR | inside the recovery card | yes | metric detail with measured nightly HRV / daily HR charts |
| Steps, walking kcal | card | separate Steps and Step calories rows | Steps with inline hourly source graph; separate kcal trend |
| Maintenance estimate | card: resting · steps · run · food; tap for the detail sheet | step calories row | Food → Today (card and sheet) and History |
| Breathing rate | — | only when measured on at least half the nights of the last 30 | metric detail; Sleep overnight row when measured; Readiness says why it was not counted |
| Skin temperature-labelled legacy output | — | once 7 of the last 30 nights have one | metric detail and Sleep overnight row remain in Builds 86/87, but WHOOP 4 channel semantics are unverified; do not interpret the deviation as temperature |
| Wear time | — | yes | metric detail, with recorded hourly wear and unmeasured gaps |
| Breathing pattern in sleep | — | — | one tap below Sleep |
| Bedtime and sleep need | — | — | not shown (still computed); the wind-down reminder is off and hidden |
| Illness watch, past findings | card when amber/red | "Noticed" section | resting HR chart, findings log |
| Naps | — | — | Sleep → Naps section on a day with one; Naps screen to edit |
| Workouts, GPS | — | — | Train: Run / Walk / Lift / Other, run-or-walk streak, draggable 7-day strain (tap opens that day), running trends (draggable weekly distance, predicted 5K/10K, best 1K/5K/10K/half), recent sessions; a run opens the run screen (Apple Maps route, calories by distance and by heart rate, best efforts, verdict, splits, linked pace/HR/elevation charts, pace zones); a walk opens the same screen without the running-only parts |
| Food, calories left, macros | — | — | Build-75 source: Maintenance → Calories (opens the whole day) → Macros; meal cards show kcal and P/C/F; one dragged order for My foods and saved meals shared with the log screen (no sort); + opens the portion screen or saved-meal review; − / + amounts; up to two named measures per food; saved meals keep sub-headings; swipe either way deletes. Food → Today: ‹ day › with calendar and swipe, calorie and macro cards, maintenance, evening protein-left line, meal cards (Log; ⋯ copy from / copy to / save meal). Meal page: sub-groups, editable quick-add entries, swipe-to-delete with Undo. Log screen: search, My foods (default) / My meals, sort, direct Scan and product review, food detail with "After this, today" (Build 90: calories and protein left after this food, a "Fit what's left" amount, nutrient panel showing what is left of each goal; also on the amount sheet) and "often eaten with", named quick add with every macro on the sheet, an optional reference weight (g) and a "Save to My foods" pill (build-81 source); decimal servings. Build-82 local source: Food → Foods search; saved-meal rows show calories; tapping a saved meal on the log screen opens its review (with "Edit saved meal"); the saved-meal food picker searches, shows each food's serving and adds several; edit sheets ask before discarding typed values; dragging to a screen edge scrolls the page and heading selection before logging; saved-food/meal deletion directly in the picker |
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

**Readiness inputs (build-81 source, algorithm 91):** HRV 35%, resting HR 25%, last night's
total sleep 20%, breathing 12%, skin temperature 8%, each a robust z against your own trailing
nights (14 needed per input). Sleep's shortfall counts in full; a longer night than usual adds at
most one deviation. Scores stored before algorithm 91 keep the four-input formula. The "What
drove it" breakdown and the Low readiness notification used the separate glass-box model in
Builds 86/87; Build 88 source reads the composite's own contributions for both (B88-11).

**What moves it (build-81 source, personal build):** Recovery, HRV, resting HR and Sleep metric
screens show patterns from logged data (`lib/data/recovery_movers.dart`): the morning after eating
after 22:00, over the calorie goal, hitting the protein goal, a workout after 19:00, strain 14+,
10,000+ steps, and nights asleep after 01:00. A pattern needs five mornings with and five without;
days where a tag cannot be known (no food logged) count on neither side. The journal source it
replaced is no longer collected.

**Readiness:** history is a line (build-75 source; coloured bars before), opened from Trends
through the shared metric screen with the same ranges; its inputs open their own metric.
Dragging an empty day reads its stored reason (14-night baseline building, no sleep heart data, HRV or resting HR not measured, held back).

The earlier readiness read/baseline audit found no defect in the headline baseline read; it did not validate
the physical meaning of the WHOOP 4 temperature channel. The open temperature-field mismatch
above can affect readiness in Builds 86/87; Build 88 source removes it from every input.
Each night writes HRV (`ln_rmssd`), resting HR,
breathing and skin temperature into `metric_series`. `_BaselineHistoryCache` reads the last 28
earlier stored values per input, with no calendar-age bound, excluding imported days and other
band families. That exclusion applies to this headline baseline only; cross-day detectors do not
filter imports. `readinessComposite`
requires at least 14 earlier nights per input, at least two usable inputs and at least half the
weight; robust z-scores are combined with weights renormalised over available inputs. Missing
scores store `readiness_absent_diag`; `readinessGap` exposes the per-day reason. The sparse history
before 30 September reflects those baseline/missing-input/import rules, not a broken read path.

**Steps (phone only; Build 89 decision):** every step total — the day, the hourly graph, step
calories, workouts and runs — counts the phone alone (`LocalDb.resolvedStepsForDay` keeps band
steps off; tests of the band ladder switch it on).
Band step rows are still stored but never counted, so time the phone did not measure has no
steps and a day the phone did not cover shows "—". Before Build 89 the band filled uncovered
time (phone first): positive phone measurements owned overlapping time, accepted wrist-only
spans supplemented uncovered time and dense cadence could override a phone-zero span. Hour/source/day boundaries preserve
measured counts. Fine phone windows around source handoffs and session pauses avoid subtracting
whole-hour totals from part-hour sessions. Growing live wrist windows replace their earlier partial
rows rather than accumulating duplicates. From Build 89 source the personal build never requests the
live IMU at all (heart-rate-only live stream, `kHighRateLive`). Source provenance stays visible.
WHOOP 4 recorded history cannot accurately reconstruct offline steps beyond Bluetooth range.
`resolveDaySteps` in `lib/data/live_coverage_policy.dart` is the common counter.

**Wearable/running charts:** a line and a ring mark the finger-selected point, and the date and
value show in the chart's header (metric detail at every range, Readiness history, Train's strain
and weekly distance, day strain, hourly steps). Titles and selected values have their own
full-width rows; selected text wraps without ellipsis. Every tab refreshes on a pull: today's phone
steps first, then band sync and today's queued calculation. Measured steps publish immediately via
the shared coverage resolver, even without new band records; Today, Steps, Strain detail and today's
step-chart point agree. Stored counter/imported/interim counts remain fallbacks when no fresh source
covered the date. Explicit phone stillness is zero; an unread day stays absent. The calculation
enqueue is awaited, and read failures, holds and the 15-second today-calculation wait cap show a status message (build 84 onward).
Today/food cards also reread after committed food writes, derived changes, foreground return,
and the five-minute foreground refresh (including local day rollover and fresh phone counts). No pull is needed and
workout voice also enables the approved iOS audio background mode. A fresh launch opens Today; warm resume retains position.
Build 87 repairs Progress's separate plot: a dense local-calendar axis keeps missing days as
gaps, with dated scrub readouts and Readings/7-day mean for weight. All/Since start use retained
food/session history rather than fixed 400-day/year caps; failed families retain the previous
view when available, display Retry and withhold combined advice. Algorithm 91 is unchanged.

Local Build 87 shows protein alongside calories in diary meal/group totals, saved-meal rows and
copy previews. Absent protein remains untracked; remaining meal-card/meal-page calorie-floor
labelling gaps are documented in `bugs.md` and queued for Build 88, not universally fixed.
Today has recorded 10-minute/1-hour/Day HR views, direct diary portion editing and All-workout
activity/date filters. These change presentation/access, not metric formulas or history.

**Food coverage:** calories/protein are primary. Optional omitted macros remain null/untracked;
explicit zero is retained. Build 89 automatic counting uses calorie-complete past days reaching
half the current target; explicit Complete/Incomplete overrides remain. Missing optional macros do not
exclude a calorie day. Protein averages require eligible days with complete protein coverage,
not merely a displayed protein total or completed calorie diary. Counts/exclusions are separate
by nutrient; the app cannot detect every forgotten food or prove a complete diary.
Build 88 required a marked-complete past day (D13). Build 89 added automatic counting at half the current calorie target when every item has energy, with manual overrides. Build 90 freezes the qualifying target per closed date (legacy dates use the first-open goal; a hydrated missing goal stays missing) so later target edits do not reclassify old days; the evening-entry heuristic
is gone. Meal and day totals with an unknown item say "at least"; the food/weight estimate uses a
robust slope with a range and hides past ±300 kcal/day.
Recorded strain stays an estimate with its prescriptive target hidden until calibrated, and all
health findings respect app quiet hours. `build-88-plan.md` owns these choices and the version gates.
From Build 94 each prompt answers to its own switch: Detected workouts covers "Did you work out?"
and the forgotten-workout nudge, and Weekly lookback controls only the weekly lookback. Times
read in one 12-hour format and short dates as "Oct 4" throughout.
Food entries delete from the Food tab's meal cards as well as the meal page (swipe, with Undo);
an edited amount of 0 removes the entry, and Quick add shows what is left of the day. The
quiet-hours "Health exceptions break through" switch is gone: no health finding is critical.
Build 90 reads attach immutable frozen counting evidence to FoodEntry/NutritionDay, so
Progress's existing rollup calls retain the correct dated eligibility without API renames.
Entry edits preserve the original logging timestamp (unknown legacy values stay NULL), while
copied entries receive a new logging timestamp and retain meal time on their destination date.
The analysis export includes every individual body reading with source/history-only status,
uses the shared strength best-set/score rules and load/equipment meaning, labels each partial
nutrient total and uses a separate complete-day denominator for each weekly nutrient mean.
Reports render off the UI isolate; they are not restore files and contain no photo bytes.
From Build 93 a workout marked private is left out of the analysis export (with its Lift Log)
and of the CSV workouts and strength files; database and encrypted backups still keep it.
Lifetime starts at the earliest record of any kind, workouts included.

All four macro rows/icons remain visible; in Build 86 an unlogged nutrient displays as unknown,
not zero. Activity streaks accept ten active recorded purposeful-exercise minutes (including lifts
and Other exercise) OR reaching the
dated measured step goal. Displayed targets change immediately; raising an earned goal
cannot revoke that day's saved qualification threshold. Overlapping recorded run/walk windows
count only once toward ten minutes. A measured count correction can revoke unsupported
completion. No historical step-only days are invented before dated goals were recorded. From
Build 91 rest is automatic for both streaks: a missed day is a rest day by itself while there
are at most 2 in any 7 (two in a row allowed, a third ends the streak); rest keeps continuity but
never counts, today is never rest while open, and the Rest / Life happens buttons are gone
(older marked days only name how a day shows). From Build 92 every food total with an unknown
value is a minimum ("≥" / "at least") or "—" when none is known, on Today, the meal page,
saved-meal sheets and the food card; never 0. From Build 92 Pushups says when a short day would
be a rest day and warns only when both rests are used. Pushups has its own streak and does not earn the
general activity streak. `lib/data/rest_streak.dart` and `lib/compute/streak.dart` own the rules.

### Computed and stored, but shown on no screen

Still calculated every day and kept in `metric_series`, so a screen can be added back with its
history intact: stress score, LF/HF, within-night NN-interval CV, deceleration capacity, heart-rate
dip, heart-rate recovery, breathing variability, TRIMP, active minutes, sleep efficiency / deep /
REM as their own trend charts, chronotype, social jetlag and sleep regularity, fitness / fatigue /
form (training load), next-morning session cost, and the beat-by-beat night data.

## Sleep screen: what each section shows

1. **Total sleep:** time asleep, in bed, bedtime → wake, and % asleep while in bed.
2. **Through the night:** stage chart (deep in the sleep violet) with the stage names only in the
   colour key and five clock marks. Drag it: time, stage and available cardiac signals show in
   wrapping header rows. The legacy WHOOP 4 raw-count temperature scrub value was removed in
   Build 86; the remaining temperature-labelled row/chart is still unverified. No WHOOP 4 °C
   readout is valid. Deep uses the same violet in
   Stages. A compact wake-up/stretch summary stays visible; full caveats are under Night details.
3. **Stages:** Deep, REM, Light (minutes and % of sleep, summing to total sleep) and Awake.
4. **Against your usual:** your last 28 nights for time asleep, deep sleep, % asleep while in bed
   and when you fell asleep, plus (build-81 source) **Bedtime consistency**: the spread of your
   last 14 bedtimes as ±minutes, Steady (≤30) / Varies (≤60) / Irregular, from seven nights.
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
maintenance = BMR + step calories (steps outside runs) + running (Method 1) + digestion of the food logged.

- **BMR:** Mifflin–St Jeor for the whole day: 10 × kg + 6.25 × cm − 5 × age, + 5 for men, − 161
  for women (the midpoint otherwise). `bmrMifflin` in `lib/compute/profile.dart`.
- **Step calories:** 2.74 × steps × kg ÷ 8,368 (Weyand et al. 2010 form), energy above resting
  only, on the day's steps **minus the steps taken during that day's runs**. `stepCalories`.
  This is the app's chosen active-energy budget convention. The reported constant is metabolic
  J/kg per stride at economical walking speeds; a stride is two steps and 8,368 is 2 × 4,184.
  It is not a universal per-step mechanical minimum. `build-74-audit.md` owns the source limits
  and comparison/wording contract; no Budget coefficient or resting subtraction changed.
- **Running (Method 1, the accepted distance estimate):** 0.005 × kg × (0.17 × metres run + 0.1 × metres
  walked inside the run + 0.9 × metres climbed). This is Akshat's four steps folded together (speed ×
  time = distance, speed × incline × time = climb, 0.3 ÷ 60 = 0.005). `runFloorKcal`,
  `kRunO2PerMeter`. 0.17 (0.85 kcal/kg/km) from Build 90, Akshat's decision (0.143 before): a
  conservative budgeting calibration below the measured level-running means, not a personal
  constant (`build-90-research.md` K, `energy-recovery-independent-review.md`).
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
- **Digestion (thermic effect, build 84):** per logged entry, the low end of each range: 20% of
  protein energy (4 kcal/g), 5% of carbohydrate (4 kcal/g), 0% of fat, and 5% of kcal the logged
  macros do not explain when any macro is missing; with all three logged, unexplained kcal adds
  nothing; capped at 20% of the entry. 0 until something is logged. `digestionKcal`.
- **Lifts and other workouts are not added.** Strength sessions (weight training, bodyweight,
  functional, calisthenics, powerlifting) show only as "Lifting (extra, not in maintenance)" in
  the detail sheet: (MET − 1) × kg × active hours per session (3.5 MET for weight training;
  heart rate not used, build 85), less the step calories of steps inside its active windows, with
  "With lifting N kcal". `liftingOn`, `sessionActiveKcal`.
- Checked: 23 y, 80.5 kg, 186.69 cm, 15,000 steps, 2,500 kcal eaten with 180 g protein, 250 g
  carbs, 87 g fat → 1,861.81 + 395.38 + 194 = 2,451 with no run; with a 5 km run that took
  4,835 steps → 1,862 + 268 + 288 + 194 = 2,612. A 60-min lift at 80.5 kg: +201 (MET)
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
+ 1.8 * trusted_walk_climb)`, excluding resting already. The distance-equation maintenance comparison uses the same
full-day BMR and logged-food digestion allowance, with the same run ownership and step exclusions.
Build 90 session writers use AppState's post-commit session signal for both insights and Food
maintenance. Repository score/movement enrichment and deferred HRR use injected callbacks;
headless instances have no live UI callback. The shared manual-session writer also covers
manual logging, retiming, suggestion confirmation and coach logging; those UI callers do not
publish a second time. Train's other direct delete/edit calls belong to the UI lane. Health
auto-imports use a separate table and do not mutate sessions.
Historical Steps charts batch retained coverage through the same resolver used for day detail,
with stored local-day boundaries, instead of querying once for every metric date. Retained
series points without measured coverage stay intact; confirmed phone zero remains zero.

Build 90 qualifies ACSM for walking at 50–100 m/min and running above 5 mph;
missing moving time or other speeds retain a separately labelled Movement estimate. Daily
step distance does not establish walking speed. Current GPS climb is not trusted for additions. A recorded walking route replaces overlapping
phone distance; no walking-workout calorie addition exists. iPhone `CMPedometerData.distance`
is saved beside its accepted step coverage. Remaining steps use an explicit height-based distance
estimate when possible; absent distance/profile stays unavailable, never zero or an invented burn.

Budget and the qualified ACSM/Movement estimate comparison remain paired on Today/Food/history/Weekly, Trends/daily Steps,
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
Build 85 installation is confirmed by Akshat; calculation/refresh phone checks remain before
calling the carried-forward fixes verified on the current iPhone build.

Build 90's general bodyweight resistance uses 3.0 MET (Compendium 02056);
calisthenics remains 3.8, weight training 3.5 and powerlifting 5.0. Functional's retained
3.5 is explicitly an estimate without a matched Compendium entry. Net lifting energy is
`(MET - 1) × kg × active hours`, displayed beside maintenance, never added inside it.
The food/weight calibration retains its Theil–Sen trend and existing coverage/uncertainty
gates. Before 42 elapsed days its display envelope includes 4,858–7,700 kcal/kg conversion
uncertainty as well as the existing trend interval; this is display-only, not a target or
an additional statistical confidence claim.

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
- Build 90 current speed requires a fresh platform speed and finite nonnegative
  `speedAccuracy`. Invalid or unavailable uncertainty hides it immediately; position deltas
  do not stand in for an invalid speed. Every positive reported uncertainty is shown with
  ± in the selected speed units (including large uncertainty), explicitly for the latest
  GPS fix rather than the smoothed speed's error. Existing time-based smoothing, stationary
  and stale-time rules remain; outdoor validation is still required.
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
  cannot be reconstructed. Decimal inputs preserve precision across saves in either unit. From
  Build 95 Settings → Units sets Weight (kg/lb), Distance (km/mi) and Height (cm / ft, in)
  separately; stored values stay metric, and runs and walks follow Distance (pace, speed,
  splits re-cut per mile, best efforts including a mile, spoken updates).
  Metric prefills and food quantity/nutrient editors retain all supplied decimals.
  Sub-minute movement allocation from older minute-level records remains proportional; the
  app cannot reconstruct an exact step timestamp that was never recorded.
- **Workout calories, one number shown and stored (`sessionActiveKcal`):** strength sessions
  are (MET − 1) × kg × active hours (3.5 MET weight training, the lowest resistance-training
  Compendium value; heart rate shown as context, never priced, because it overstates lifting and
  Keytel's 57-90% HRmax range does not cover a lifting session's average). Sets and rests are
  priced together as the Compendium's whole-session averages; the band cannot isolate a
  15-second set. 60 active minutes at 80.5 kg = 201.25 kcal; 30 min = 100.6. The setup preview,
  live screen, summary, Train list and maintenance Lifting line all call it, at the session's
  recorded (else dated) weight over active time (start to stop minus pauses). Other non-step
  sessions keep the lower of net Keytel and (MET − 1) × kg × h, but heart rate competes only
  at or above 57% of the Tanaka HRmax (Keytel's fitted range, `kKeytelMinHrMaxFraction`);
  below it, or with no age, the MET estimate stands (Build 90: no near-zero cliff). All remain
  excluded from this maintenance budget. Treadmill, track intervals, sprinting and hurdles are
  running (distance method, phone motion distance without GPS; best efforts GPS-only).
  Stored daily HR/cadence `calories` and `calories_total` are separate analytics, not Method 1.
  **Stored workout calories (Build 90, algorithm 96):** every save path stores that same
  active figure (live stop, manual entry, run/walk Method 1, heart-rate re-score), so
  `sessions.calories` equals what the screens show; the legacy bout scorer (resting energy,
  170 cm without a height) no longer writes it. `sessions.calories_basis` says what a stored
  figure means: `active`, `legacy` (pre-Build 90, could include resting energy, kept as recorded
  because its inputs are gone) or NULL (not yet examined, or a `whoop`/`cloud` import kept as the
  vendor reported it). `repairSessionCalorieBasis` runs once per launch: it recalculates older
  own rows where the shown method's inputs exist and marks the rest `legacy`; nothing is
  subtracted by guesswork. The Active Energy workout-gap credit counts `active` rows only.
  Resting/digestion policy and the recovery formula are unchanged.

**Apple Health:** not used. Steps come from the iPhone's own motion sensor when **This phone →
Steps** is on; HealthKit stays excluded from the personal build.

**Food/weight maintenance inference:** labelled Estimated maintenance from food and weight.
It requires at least eight weigh-ins and fourteen fully covered food days aligned to the interval
from the first morning weight (inclusive) to the last morning weight (exclusive). Any missing or
heuristically incomplete day withholds the estimate; visible coverage explains why. Optional
omitted macros do not disqualify calorie coverage. Least-squares weight slope and 7,700 kcal/kg
remain approximations. This estimates total expenditure for that interval: do not add BMR,
movement or food digestion again. No automatic HR hybrid or coefficient adjustment is adopted.

## Layout Decisions (Build 89 Installed; Build 90 Implementation)

Akshat selected the calm A framework with B's compact macro section and approved
implementation. Akshat clarified that B includes its circular calorie-balance display: Food now
shows calories left/over in the ring, eaten and the fixed goal beside it, then four slim macro
rows (protein larger). A partial balance keeps its bound and withholds an exact arc. All four values/targets and explicit
missing/partial labels remain visible; maintenance comparisons live in their own panel.
The former decorative plate/utensil and linear calorie bar are replaced by that selected ring.
Unlogged nutrient bars are hatched with explicit not-zero copy. Diary items show calories and protein; full meal, group and entry
views retain all nutrients, portions and edit/delete/copy/save routes. Accessibility text
stacks values and actions; the week remains horizontally scrollable with the selected date
revealed, and Counted/Logged/Empty marks have a legend. Meals and Add food appear earlier;
single-item meals do not repeat the same totals. Every meal heading shows calories or absence,
and the overview's repeated full-macro footer is gone; full details still retain it.
Failed counting-status writes show an error and leave the displayed status unchanged.
Food progress uses the shared Progress
route to its Food destination. Copy a day reviews every item, portion multiplier and selection,
then logs into the viewed date in one explicit transaction; cancel and failed writes do not
partially copy the day. Existing calendar, portions, My foods/My meals, scanning, labels and
meal copy/save paths remain. Windows synthetic renders/checks are not native iPhone acceptance.

**Build 90 shared UI source:** Today uses one Recovery headline and right-aligned supporting
values, then early food/weigh-in/Train-or-Resume actions. Body, Pushups, HR explorer, freshness,
findings and week context remain; duplicated steps/food/maintenance lines are removed. Trends
groups related metrics; the header owns Pin favourites/Edit pins, missing-day counts stay on one
intact line and full-coverage repetition is removed. Budget and Movement estimates remain paired,
with the second method in full-width context. Train leads with Start/Resume and
retains Gym/Home, all activities, session history/edit/delete/import, Pushups, week/rest/streak,
strain/running and full Lift Log. Progress keeps one fixed-window goal check, outcome rows and
inputs grouped as Food/Training/Recovery with denominators; reasoning/next steps and every
Body/Strength/context detail, photo, reading, entry,
configuration and eight-period control remain. Shared metric rows align values independent of
charts or chevrons; large text stacks labels/comparisons and permits full detail titles.
Leaf/moon illustrations are decorative, excluded from semantics, and encode no metric.
Sleep/Recovery retain stages, corrections, missing-input/gap wording and all prior details.
Sleep correction is one collapsible card. Body comparisons use full-width rows; summary readings
use one decimal while milestones retain a second decimal or show the difference when rounding
would tie. Exact history/edit values remain. Food's Copy a day/Progress actions share one panel group.
Today's 10-minute/hour/day recorded HR and day detail stop scrubbing at the latest real minute,
capped by now; future/trailing unrecorded minutes cannot be selected. Internal gaps remain gaps,
accessibility uses the same cap, and live bpm stays separate. No metric computation changes.
Food library and log pickers now allow hold-drag in search/category results: visible matches
exchange their existing slots; hidden items and complete saved orders remain. Swipe deletion
still confirms and cancellation keeps the item. This is source/check evidence, not a new IPA.

**Build 88 source (DESIGN.md):** light kraft ground, cream 26 pt panels with every Surface,
family colours (recovery, sleep, strain, food, body; amber only for NEW/unavailable), a paper
tab bar with a green active tab and a paper range chip. Today is one panel: recovery hero
(116 pt, band word, HRV/resting HR, NEW on a newly seen night) then Sleep/Strain/Food/Protein/
Steps rows with seven-day tiles, then Maintenance; the HR card, daily actions, maintenance
card and week card follow as panels. Trends rows are label/chart/value: bars at 7 days, a daily
line under a 7-day average at 30 days, weekly points over a low-high band at 3 months; missing
days are hatched and no line bridges a gap. Status adds a Sync health group; Settings adds a
switch per health-alert kind. From Build 89 source: Food's date opens a month calendar and a
week strip marks each day counted, logged or empty; its card reads eaten / goal with what is left
or over beside it and a bar that stripes past the goal; Progress has one period selector for every
card, the answer first and one Body card; Settings → Your data → Export for AI analysis writes one
Markdown file (2 weeks to lifetime, food items up to 3 months). From Build 91 source: Progress's
goal card, until the check can judge, shows the first-check date and a checklist of what it
waits for (weekly weigh-ins and food with this week's dots; for recomposition a waist reading at
each end and one lift repeated on the same setup), with Log waist / Open Train buttons; Body and
What went in compare the last 7 days with the 7 before, What went in shows day counts where an
average rests on fewer than 7, the weight row is "Average weight" with the latest reading, and a
row opens its page on the same 7 days. Food's evening protein-left line sits under the goal
beside the ring. Before that, Food led with the
intake hero and four macro progress lines, then
one meal panel closed by the day's completion line; Train has four family start tiles, a week
panel (streak, strain, run km) and Recent in a panel; Progress leads with the Week/Month/Since
start review (7-day weight hero, weight/waist/lifts/protein/calories lines, one verdict panel);
Sleep, Recovery and the live run each open with their hero panel. The breathing-pattern screen
shows the across-nights card only (per-night chart removed). The Build 87 bullets below describe
what each tab still contains.

- **Tabs:** Today / Trends / Food / Train / Progress; Food keeps Today / History / Foods. Body
  lives in Progress, Pushups in Train with a compact Today shortcut. No sixth destination.
- **Look:** flat warm charcoal, soft sage/cyan/coral accents and readable neutral ink; no
  tab-coloured page wash or decorative bottom pill. Sections are unframed; framed items/tools
  use small radii. The rejected Build 86 ring/card hierarchy is replaced, not recoloured.
  Akshat approved implementation; structural phone acceptance remains open.
- **Today:** compact numeric recovery/sleep/strain and HRV/resting HR, then live/all-day HR;
  daily action rows; compact paired Budget/ACSM with full breakdowns; weekly report/coverage.
  A compact goal-based action section is back in 86; the greeting remains removed.
- **Trends:** core metrics with shared ranges, paired step calories and findings. Explore,
  Beats, Body clock, Stress row and Consistency cards remain removed; their data remains stored.
- **Food:** compact eaten/goal/maintenance and all four macros, Log again, actual meal/food
  ledger rows and compact paired maintenance;
  month history, shared dated weight and separate food/weight maintenance estimate; food/meal
  library, scans, custom labels and two-way equivalents. Complete/incomplete and safe-delete
  repairs are implemented, with device checks still open.
- **Train:** Run / Walk / Lift / Other, Resume, activity/protection streak, Pushups, recent/full
  history, strain and running trends. Removed activity-library tab, mascot, fitness/fatigue/form,
  cross-mode kg-lifted chart, morning-after/overreach cards and share poster stay removed.
- **Lift:** session-linked Lift Log with all six load meanings, splits, tracking-only, sets,
  previous performance, repeat last set, rest timer and qualified records; one shared clock,
  MET-only calories and unchanged maintenance. See `lift-log-integration-plan.md`; AkshatOS
  ownership/cutover is not complete.
- **Progress:** goal/review, raw/seven-calendar-day weight, measurement-week blocks, all eight
  tape sites, Steps, range/baseline controls, dated history/photos, strength, eligible food and
  activity/recovery. Independent two-panel photo selection, start/end times, backdated entry,
  local import and photo-inclusive recovery are implemented; phone acceptance remains open.
  Build 87 puts its dated chart first, uses named Measurement/Range menus and one Week/Month/
  Since start review with independently useful evidence; full guidance/criteria live in Details.
  `build-87-ui-plan.md` owns the remaining phone/acceptance gates.
- **Insights:** weekly/monthly/since-start comparisons and guarded, never-applied goal suggestions
  are implemented. Coverage/load meaning/dates still constrain interpretation; no measured muscle
  gain, cross-mode tonnage, automatic food target change or new lifting expenditure is implied.
  Personal source data/media/import files stay outside public app repositories.
- **Live/detail repairs:** fresh-GPS walking speed versus labelled average fallback, consistent
  day arrows, cross-midnight sleep signals, recorded-HR freshness, safe session/diary deletion,
  both-way historical portions and maintenance-based warnings ship in 86. Device verification
  is distinct from source implementation; the new UI must not regress these paths.
- **Sleep/Steps/metric detail:** naps remain available on empty days; sleep correction is folded;
  Tonight/target-bedtime surfaces remain removed. Hourly Steps bars/totals stay, the per-stretch
  list stays removed. Metric charts omit algorithm dotted/locked lines and Worn bars (their code
  was removed in Build 95).
- **Settings:** band, profile, alarm, This phone steps, notifications, units (Weight, Distance,
  Height), data, privacy and Status. Tasker/Shortcuts, double-tap, app icon, add-a-sensor,
  HealthKit import, AI coach/briefings, language picker and paced breathing were removed (Build 95
  removed their code). Movement-nudge/wind-down/step-goal alerts no longer exist; earning a streak
  needs no alert.
- **Notifications page (Build 95):** a bell on Today (unread dot) opens every notification by day,
  newest first, kept 90 days in preferences on the phone; tapping one opens its destination. What
  changed is reachable from Trends.
- **Progress, Body, Recovery (Build 95):** Progress leads with the first check, the next step and a
  tile per requirement, rules inline; Body names Latest reading, 7-day average and the selected
  period's average; Recovery states one reason with its numbers beside the score.
- **Pushups:** completed-set events, separate goal/streak/history and optional Home auto-pause;
  never sensor-measured reps, strain, maintenance calories or general activity-streak credit.
  Always permission is approved for Home only, not a new walking requirement.

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

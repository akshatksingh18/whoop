# WHOOP 4 Metrics Accuracy Research Prompt

**Status:** Source-backed research brief, not a completed validation study or an implementation
plan. Prepared against Build 87 (`0.9.54+87`, algorithm 91; same core formulas as installed
Build 86). Recheck source/version before using it after further app changes. The executed
  study and its second-pass corrections are in `metrics-accuracy-research.md`, and confirmed
  defects are in `bugs.md`. Where this brief and those files disagree, they win. No personal records,
photos, device identifiers or diagnostic captures are included.

The prompt below is self-contained. Source paths are optional audit references when the
researcher has access to the repository; lack of source access must be stated, not papered over.

**Research output:** [metrics-accuracy-research.md](metrics-accuracy-research.md) contains the
completed source/primary-source desk review using this brief. It does not constitute physical
accuracy validation or approval to implement every proposal. This reusable prompt retains the
current-source inventory; results and priorities belong in the report and `todo.md`.

For continued local research, read `build-88-plan.md` alongside this inventory: it reconciles
the two supplied external analyses and identifies unsupported claims, proposed repairs and
deferred experiments. Neither those analyses nor this prompt is an implementation specification.

## Prompt

I am building my own local-first iPhone fitness app for a **WHOOP 4.0 wrist band**. This is a
custom Flutter/OpenStrap-derived app, not the official WHOOP app, not an Apple Watch app, and
not a client using WHOOP's cloud API for scored sleep/recovery. It reads the band directly over
reverse-engineered Bluetooth, stores records in SQLite, and calculates metrics on-device.
The target is iPhone 17; the reported iOS version is 26.6.2. Do not assume firmware/hardware
capabilities of WHOOP 5.0/MG are available on WHOOP 4.0.

The app combines recovery, sleep, heart data, activity, GPS workouts, lifting logs, nutrition,
weight/tape measurements, photos and weekly/monthly progress. My principal goal is
**recomposition: becoming leaner while getting stronger**. I want substantially better
measurement integrity, estimation and useful personal insights, not scores tuned just to look
like another brand's numbers. Research first; do not implement code or change my targets.

Conduct a thorough, skeptical analysis of every metric and calculation below. Search official
WHOOP, Apple Watch/Apple Health, Garmin/Firstbeat, Oura, Fitbit/Google and Polar documentation
where relevant, plus original methods and device-validation papers. Explain what is actually
published, what is proprietary/unknown, what our available data can support, and which changes
are most likely to improve accuracy. Precision must be demonstrated against suitable references;
do not promise perfect accuracy or an exact proprietary clone.

### 1. Architecture And Available Inputs

- Durable historical WHOOP 4 records: timestamps/subsecond fields and counters, approximately
  1 Hz heart-rate values, up to four observed reported beat intervals per decoded record (the
  historical decoder accepts up to eight),
  and three low-rate motion/gravity-vector float fields. Actual beat coverage is variable;
  there is not a guaranteed continuous ECG-quality tachogram. RR durations have their own
  numerical resolution, which must not be confused with the record/timestamp resolution.
- Other decoded quantities include a green ADC/intensity count (decoded but not stored) and
  unknown optical-block counts. Decodable frame bytes are not retained after decoding.
  A count is not a calibrated optical waveform, temperature or oxygen saturation by its name.
  Distinguish validated semantics from a reverse-engineered label.
- WRIST_ON/WRIST_OFF, charging/link/device events help describe wear and collection, but are
  not official sleep-stage annotations or independently validated contact-quality scores.
- Live high-rate IMU/other protocol streams exist while connected. The app uses live 100 Hz
  motion for wrist step coverage; high-rate frames themselves are RAM-only, not continuous
  retained overnight waveforms. Historical WHOOP 4 R24 has no reliable cumulative step counter.
- The app does not receive official light/deep/REM labels, official Recovery, official Strain,
  official sleep need, a trusted SpO2 percentage or a verified WHOOP 4 skin-temperature channel
  through this current path. Processed WHOOP cloud API fields are a different data source.
- Phone inputs: direct iOS CMPedometer steps/distance/cadence and workout motion windows,
  location/GPS route points/times and altitude. HealthKit aggregate, Watch app and app extensions
  are excluded from the personal build. Do not assume continuous phone carriage or GPS in sleep.
- Manual inputs: dated age/height/weight/sex/profile and targets, food quantities/label nutrients,
  lifting sets/load meaning/equipment, body-site tape readings, photos, goal phase and corrections.
- BLE records must commit before the history ACK. Missing sensor time is not physiological zero.
  Derived results are algorithm-versioned. Raw data retention is limited for some decoded inputs;
  stored daily results/history remain, so arbitrary retrospective reprocessing is not guaranteed.
  The current schema drops legacy `raw_records`; undecodable `raw_archive` is not a complete
  backup and selectively thins old `undecodable_rec_v20` frames to one in 60. Inspect real
  retained inputs before proposing historical replay.
- A live HR reading, newest committed band record, completed calculation, and last completed
  qualified night have separate freshness meanings. Stale or pending data must not masquerade
  as current; iOS background execution is opportunistic, not an always-running process.

**Critical known issue, queued for Build 88 but not fixed:** the protocol explicitly deprecates
WHOOP 4 `skinTempRaw` (u16, inner offset 68/frame offset 72) as **not temperature**. It changes
too rapidly and is an unknown optical-block quantity. Slower candidate fields at other offsets
are unverified too. The app still averages/normalizes this field, charts it with temperature
labels and can pass it to readiness/illness-related consumers. A relative z-score does not
repair incorrect physical semantics. Start with an abstaining WHOOP 4 repair and downstream
audit, not a conversion-to-degrees guess. Preserve raw bytes and old results with honest provenance.

SpO2/oxygen dips are already refused in this pipeline: decoded red/IR quantities co-drift with
a fixed offset and do not provide trustworthy independent channels. Do not invent SpO2 from
them. Deprecated `skinContact` and `ppgRedIr` fields are also not what their old names imply.

### 2. Heart Rate, HRV And Cardiac Features

- HR is the band's reported optical bpm, not a new HR extraction from saved PPG. The app
  stores per-minute means for curves, with Day/1-hour/10-minute recorded-data views. Gaps must
  remain visible. Peak/trough display uses physiological rejection then a five-sample rolling
  median; valid floor 30 bpm, ceiling `min(220,max(200,220-age+25))` when age is known
  (220 when unknown). Audit
  whether a sample-count window remains a true time window in sparse records.
- RR preprocessing includes Lipponen/Tarvainen-style adaptive beat classification: default
  alpha 5.2, 91-beat local windows, minimum threshold 100 ms; plausible RR 300-2000 ms.
  Isolated artifacts can be corrected, multi-beat artifact runs dropped, and timestamp gaps
  preserved/reanchored. HRV is optical **PRV**, not assumed interchangeable with ECG HRV.
- `RMSSD = sqrt(mean((NN[i]-NN[i-1])^2))` over eligible adjacent intervals; do not bridge
  rejected runs/dropouts. `SDNN` is the standard deviation of eligible NN intervals; also
  mean NN and `pNN50=100*count(abs(adjacentDifference)>50ms)/eligiblePairCount`, with
  difference-autocorrelation/jitter gates. Secondary SDANN is SD of five-minute NN means and
  SDNN-index is mean of their SDs (current helper permits two qualifying windows); a nightly
  result must not be presented as a validated 24-hour Holter metric.
- Nightly headline HRV is primarily the arithmetic mean of valid consecutive five-minute
  sleep-window RMSSDs. This path has its own plausible-range/local-median 20% rejection and
  rejected-beat run handling, not simply the same cleaner as every secondary metric. Current
  source uses timestamps for bucketing then discards them; it can bridge unreported time within
  a bucket and accept a window with one surviving difference. A synthetic two-interval input
  gives the same result with a one-second or 298-second report gap. Audit timestamp continuity,
  repeated report seconds, usable coverage and nightly eligibility before tuning. A robust
  nocturnal/NREM-window estimator and whole-window RMSSD are fallbacks when the primary value
  is unavailable. Whole-window RMSSD is also retained separately. `ln_rmssd = ln(primary
  sleep-session RMSSD)` when that primary value qualifies; audit consistency with fallbacks.
  Build 88 presentation is selected, not implemented: primary-only headlines/readiness;
  unavailable primary remains absent, with labelled secondary estimates in details.
- Secondary nocturnal HRV uses robust five-minute windows, an NREM mask when available, and
  autocorrelation/coverage guards. Frequency features use Welch-averaged Lomb-Scargle on
  eligible NN/times: ULF approximately 0.0003-0.003 Hz, VLF 0.003-0.04, LF 0.04-0.15,
  HF 0.15-0.40; `LF/HF`, normalized LF/HF and band powers only when resolvable. HF is refused
  above the artifact gate (default 0.15); insufficient-span bands remain absent.
- Resting HR is the lowest qualifying **wall-clock 30-minute sleeping mean**, with a default
  90% coverage gate. No daytime substitution for absent sleeping RHR. Night average, first
  percentile/nadir, lowest-sample timestamp and waking/day mean are distinct definitions.
- HR dip is `100*(wakingMean-sleepMean)/wakingMean`, subject to eligible data on both sides
  (default minimum 300 valid samples each); it is not a blood-pressure dipping diagnosis.
- PRSA deceleration/acceleration capacity averages anchored RR neighborhoods and uses
  `(X0+X1-X[-1]-X[-2])/4`. PRV trends, not ECG risk thresholds.
- `hrv_cv=100*SDNN/meanNN` over eligible sleep NN; this is within-night interval CV, not
  night-to-night CV of daily RMSSD. HRV night shape, window variation and daytime curves are retained.
  Review their real coverage, adjacency, window duration and aggregation rather than inferring
  dense beat-by-beat coverage from a plotted line.
- HR recovery: post-effort peak-to-recovery bpm drop with timestamp-qualified windows; decay
  tau fits `HR(t) = a + b*exp(-t/tau)` with residual/coverage checks. Current context is not a
  standardized clinical recovery test. Observed HR ceiling uses sustained, quality-gated efforts;
  it is evidence of an achieved rate, not proof of true maximal HR.
- Irregular-rhythm screening is a heuristic NN-distribution/irregularity flag, not ECG, AFib
  diagnosis, a medical alert certification or a substitute for an ECG-capable wearable.

Sources: `lib/compute/onehz_pipeline.dart`, `hr_max.dart`, `derivation_engine.dart`, and analytics
`foundations/rr_correction.dart`, `clinical/hrv_time.dart`, `hrv_freq.dart`, `nocturnal.dart`,
`prsa.dart`, `irregular_rhythm.dart`, `workout/hr_recovery.dart`, `observed_max_hr.dart`.

### 3. Sleep Detection, Staging And Accounting

- Days are local-calendar midnight-to-midnight, not WHOOP sleep-to-sleep cycles. Main sleep is
  attributed to its ending day; the search includes the previous local noon onward. Manual
  confirmed/rejected windows are respected. DST/travel/gaps require explicit handling.
- The normal path combines low-rate motion/orientation and HR/RR via the advanced/cardio
  stager. Main-night qualification includes an in-bed duration of at least three hours and
  sufficient observed coverage; low-motion availability can force an HR-led sustained-dip
  fallback with lower confidence. The fallback is an estimate, not a band-provided night.
- Staging uses 30-second epochs. Features include motion/ENMO relative to the gravity scale,
  HR mean/SD, RMSSD/SDNN around approximately five-minute windows, LF/HF, and `R(k)` (mean
  absolute successive instantaneous-HR change) around approximately three-minute windows.
- Wake uses movement/HR arousal rules. REM uses a robust-z weighted score with relative
  immobility and HR-toward-wake gates. Deep is a low-confidence NREM subtype, using relatively
  low autonomic-variation features; Light is remaining NREM. Feature score weights currently
  are REM R(k) 0.43 / SDNN 0.32 / HR SD 0.27 / LF-HF 0.12, cutoff 0.5; Deep R(k) 0.53 /
  HR SD 0.43 / SDNN 0.41 / LF-HF 0.33, cutoff 0.3, with appropriate feature orientations and
  available-feature renormalization. Local/night HR baselines and capped personal-profile
  blending support the rules, followed by continuity/rescoring/consolidation.
- These are locally authored rules, not WHOOP's proprietary machine-learning model. Existing
  source benchmark comments are not fresh validation and normative stage proportions are not
  proof of correct epoch labels. Audit held-out stage agreement, especially deep versus light.
- TST is observed Light+Deep+REM time. Stage percentages divide by observed TST. In-bed time
  includes the detected/manual window; missing time is separately unobserved, not assumed awake
  or asleep. Efficiency is TST divided by the observed in-bed denominator. WASO, latency,
  REM latency, longest continuous sleep and awakenings have separate definitions; sustained
  awakenings use a five-minute floor, and onset latency is only defensible for forced windows.
- Cycles use peaks/troughs of smoothed minute RMSSD (HRV-derived estimated cycles), not merely
  a count of categorical REM blocks. Cycle series/count/mean duration have coverage envelopes.
- Naps have their own motion/HR detection and editable/rejectable records. They do not receive
  an invented full-stage breakdown; main-night overlap and absent/manual-only days matter.
- Restlessness and wrist orientation/position changes are motion-derived proxies, not measured
  body position from a torso sensor. Charging and wear gaps need independent presentation.
- Overnight HR, HRV and breathing lanes have different window requirements. Review why early
  sleep may have no HRV/resp points, whether centred windows unnecessarily lose edges, and how
  to improve coverage without fabricating initial-quarter data.
- Bedtime/midsleep store local clock offsets around 04:00 to avoid midnight wrap artifacts.
  Bedtime consistency uses recent bedtime spread (14-night window, at least seven nights;
  labels around 30/60 minutes). Sleep regularity uses a coverage-masked Phillips SRI: agreement
  of sleep/wake at matching times 24 hours apart, mapped as `200*agreement-100`.
- Retained chronotype, social jetlag, sleep debt and circadian summaries use work/free-day
  midpoint/duration histories. Weekends are the current free-day assumption, not a known work
  roster; audit that assumption. Circadian IS/IV, M10/L5, relative amplitude and cosinor are
  currently driven by qualified hourly HR histories, not verified temperature or full actigraphy.
- Sleep coaching is computed even where its recommendations are not shown: personal optimal
  duration supplies a baseline clamped to 7-9.5 hours; `need = baseline + debt +
  (clamp(dayStrain,0,21)/21)*45 minutes - today's nap credit`, clamped to 6-11 hours.
  `performance = clamp(100*TST/need,0,100)`. Bed/wake recommendations divide needed sleep by
  typical efficiency (clamped 75-99%) to estimate in-bed time. This is not official WHOOP Sleep
  Performance, which must be researched rather than assumed to use our definition.

Sources: `substrate.dart`, `derive_prepare.dart`, `onehz_pipeline.dart`, `crossday_pipeline.dart`,
analytics `sleep/segment.dart`, `advanced_stager.dart`, `cardio_stager.dart`, `hr_fallback.dart`,
`nap.dart`, `cycles.dart`, `sri.dart`, `accounting.dart`, `human/coaching.dart`.

### 4. Breathing, Temperature And Stress

- Sleeping respiration estimates RSA modulation in eligible cleaned beat intervals. It uses
  approximately 300-second, 50%-overlapping spectral windows and median/consensus qualification;
  candidate peaks search from 0.15 Hz to the supported ceiling, no higher than 0.5 Hz or the
  effective beat-rate Nyquist. Default consensus is at least 50% within 2 breaths/min;
  excessive artifacts (default above 30%) withhold the result. `breaths/min = peakHz*60`.
- This is estimated respiratory rate, not a direct respiratory sensor. The library also has
  RIIV/green-intensity/fusion algorithms: do not label them active simply because exported;
  the nightly app path currently calls RSA. Breathing variability uses qualified window-rate
  CV and trend slope (Theil-Sen); nightly trend/cross-night variants must not be conflated.
- CVHR breathing-disturbance candidates are cyclic HR/NN-pattern events, with count/rate and
  signal coverage; they are not SpO2 events, confirmed apnea, AHI or clinical sleep-apnea diagnosis.
- Current WHOOP 4 temperature-labelled output is a nightly mean of the **unverified** raw field
  and a deviation `(todayMean-historyMean)/historySD` (baseline bootstrapping starts with at
  least three earlier values). Raw-ADC baseline/settled-sample heuristics also exist; readiness
  requires its default 80% settled fraction. All of these are invalid as physiological
  temperature until the channel semantics are verified, regardless of coverage or smoothness.
- Stress uses the median of overlapping NN histograms (256 beats, 128-beat step, at least
  30 beats): `Baevsky SI = AMo_percent/(2*Mo_seconds*(maxNN-minNN)_seconds)` with 50 ms bins
  and a 20 ms range guard. Display score is `clamp(100*(ln(SI)-ln(20))/(ln(600)-ln(20)),0,100)`.
  This is an app-defined mapping of resting autonomic tension, not psychological stress and
  not Garmin/WHOOP's proprietary all-day stress. Audit whether gaps turn beat windows into
  misleading elapsed-time windows and whether thin input can still publish overconfident output.

### 5. Recovery/Readiness, Baselines And Findings

- Current headline Recovery is our transparent readiness composite, not official WHOOP Recovery.
  Nominal weights: ln(HRV) 35%, sleeping RHR 25%, TST minutes 20%, sleeping respiration 12%,
  temperature-labelled input 8%. Temperature's WHOOP 4 validity issue takes priority.
- Per-input baseline uses up to 28 earlier eligible nights, excluding imported/other-family
  values; at least 14 values per driver. Robust z uses median/MAD (`scale=1.4826*MAD`), with
  a mean/SD fallback when permitted. Degenerate/quantization-scale baselines are refused.
  HRV/sleep orient positively, RHR/resp/temp negatively; sleep surplus is capped at +1 z.
- At least two eligible inputs and nominal surviving weight at least 0.5. Renormalize available
  weights: `zComposite = sum(w*orientedZ)/sum(w)`; `score=100/(1+exp(-zComposite))`.
  The app withholds the headline if absolute composite z exceeds 5. Driver ranking uses the
  same contributions. Current confidence is a heuristic input-count envelope, not an externally
  calibrated probability of correctness or clinical readiness.
- Additional baselines use winsorized EWMA centers/spreads and deviations/percentiles; reported
  MDC is `1.96*sqrt(2)*typicalError`. Review whether observed biological variability is wrongly
  being used as measurement-error evidence. Separate these from the headline's robust baseline.
- Secondary weekly lnRMSSD/CV readiness and glass-box explanation models are retained; do not
  confuse their different windows/weights with the headline score.
- Illness watch uses one-sided RHR CUSUM with robust normalization (default baseline minimum
  seven, slack k=0.5, threshold h=4); multivariate anomaly and temperature-illness paths combine
  eligible RHR/HRV/resp/temperature histories. Findings/change points/notifications are
  observational flags, not a diagnosis. Trace the unknown-temperature contamination and
  false-positive rates, baseline enrollment, unsettled-day exclusion and repeat-notification gates.
- Recovery movers use logged previous-day exposure groups (late food, above goal, protein
  target met, late workout, strain >=14, steps >=10000, late bedtime). Each side needs at least
  five observed mornings; unknown exposures belong to neither side. Differences/associations
  are not proof of causation. Further library association, session-next-morning cost,
  overreaching and percentile models need real call-site and multiple-testing audits.

### 6. Strain, HR Zones And Training Load

- `HRmaxAge = 208-0.7*age` (Tanaka). An observed sustained ceiling is used when it exceeds
  that estimate, or age is unavailable; a lower achieved peak is not proof of a lower true max.
- Zones use 50/60/70/80/90/100% edges. Where an eligible observed ceiling plus >=14 nights
  of measured RHR history is available, use Karvonen HR reserve (trailing RHR median);
  otherwise qualified observed-%HRmax or age-estimated-%HRmax. These are intensity bands,
  not measured lactate/ventilatory thresholds. Time in zones uses timestamp/cadence-qualified
  durations, not credit across unobserved gaps; whole-minute rounding is presentation.
- Banister TRIMP sums `dtMinutes*x*y(x)`, `x=clamp((HR-RHR)/(HRmax-RHR),0,1)`;
  male `y=0.64*exp(1.92*x)`, female `y=0.86*exp(1.67*x)`. Waking day HR is per-minute;
  missing anchors/coverage should abstain. Check every day/live/session/rescan caller.
- Headline 0-21 strain subtracts quiet-waking TRIMP: `baseline=wakeMinutes*q*y(q)`;
  `net=max(0,TRIMP-baseline)`, `u=min(1,net/400)`, `strain=21*ln(1+14*u)/ln(15)`.
  **Current app callers still pass q=0.20**, although analytics contains a personal quiet-HRR
  estimator. Do not claim that estimator is already wired in. Consider baseline contamination
  by active days, minimum observation, changing anchors and score saturation.
- A separate older 0-100 strain helper exists. Trace actual served outputs; do not replace
  the current 0-21 definition in the inventory with that helper's formula. Session/day strain
  are not additive. Lifting sets do not currently create validated mechanical/muscular strain.
- CTL/ATL use daily TRIMP EWMAs: lambda `1-exp(-1/tau)`, tau 42/7 days; TSB=CTL-ATL,
  minimum 14 days. Audit initialization, missing-day zero filling and coverage before treating
  these as fitness/fatigue or ACWR as injury-risk predictions. Strain target/training reviews
  use readiness/load/sleep/context heuristics, not a validated optimal prescription.

### 7. Steps, Movement, Wear And GPS Workouts

- Accepted direct phone steps own overlapping time in the personal build. Qualified wrist-live
  steps supplement uncovered intervals, not add a second copy of the same activity. Confirmed
  phone-zero windows can reject weak wrist false positives; dense genuine gait can qualify.
  Source/time/hour/day/active-pause ownership and corrected counts must remain consistent.
- Live wrist pedometry works on high-rate motion. Low-rate historical WHOOP 4 motion alone
  cannot honestly recover precise offline step counts; no invented band counter/fallback counts.
  Motion ENMO/orientation, personal dynamic floor and active-minute summaries are separate proxies.
- Wear time counts eligible worn minutes/events/observations, distinguishing off-wrist from
  unobserved collection. Review current wear heuristics without using deprecated contact bytes.
- Routes come from the phone, not built-in WHOOP 4 GPS. Distance uses accepted coordinate
  segments, smoothing/jitter/teleport rejection and pause/stop-aware windows. Splits/best efforts
  interpolate covered distances/times; no route means no invented map/splits.
- Speed in km/h is `3.6*distanceMetres/seconds`; pace s/km is `1000/speedMps`; cadence is
  observed steps/min. Live current speed, smoothed speed and workout average are distinct.
  Audit current GPS/phone speed freshness, latency/staleness, stop behavior and background limits.
- Recorded run/walk gait splits use speed over +/-15-second windows: >=2.0 m/s run,
  0.5-2.0 walk, below 0.5 standing. Phone-motion fallback uses measured distance/cadence
  (run cutoff 140 steps/min). A post-session symmetric window is not a causal live filter.
- Pace curves use approximately +/-15-second smoothing; very low speed has absent running
  pace. Six relative pace zones use 5K-pace ratios 1.276,1.10,0.985,0.924,0.867.
  Predicted race time uses Riegel `T2=T1*(D2/D1)^1.06`, with qualifying distance/effort history.
  Best-effort records, HR drift/decoupling, session verdicts and context tags must retain real
  comparison qualifications; projection is not a measured VO2max or guaranteed race result.
- Altitude is smoothed for elevation display. Unverified vertical accuracy supplies no energy
  climb bonus; uphill coefficients below are only for trusted climb. Workout pauses must not
  create distance/steps/calorie duplication, including midnight splits or overlapping sessions.

Sources: `lib/data/live_coverage_policy.dart`, `lib/compute/derivation_engine.dart`,
`lib/gps/run_analysis.dart`, `run_history.dart`, route recorder and native phone-motion bridge.

### 8. Energy, Maintenance And Nutrition

These are deliberately separate estimates. Neither Budget nor ACSM measures individual TDEE,
and their difference is not a statistically validated upper/lower interval.

- Full-day BMR: Mifflin `10*kg+6.25*cm-5*age+sexOffset`; +5 male, -161 female,
  -78 other/unknown (our interpolation, not a separately validated sex equation).
- Budget walking net kcal: `2.74*steps*kg/8368`, excluding accepted run steps. This is a
  selected conservative convention, not a universal per-step physiological minimum.
- Budget run net kcal: `0.005*kg*(0.143*runMetres+0.1*walkMetres+0.9*trustedClimbMetres)`.
  The 0.143 running coefficient is the app's chosen budget, not ACSM's 0.2 running cost.
- ACSM comparison: `0.005*kg*(0.2*runMetres+0.1*walkMetres+
  0.9*trustedRunClimb+1.8*trustedWalkClimb)`. Route distance owns overlap, then accepted
  phone distance; otherwise explicitly height-estimated walking distance uses step-length
  factors approximately 0.415 male/0.413 female/0.414 other times height in metres.
- Digestion per entry: protein energy `4*P`, carbohydrate `4*C`, fat `9*F`;
  TEF `0.20*proteinEnergy+0.05*carbEnergy+0*fatEnergy`, plus 5% of nonnegative unexplained
  label kcal if any macro is missing; no unexplained-energy term when all three are known;
  cap 20% of label kcal. No logged food provides no logged TEF, not proof of zero digestion.
- Budget maintenance = full-day BMR + non-run step energy + accepted Budget runs + logged TEF.
  ACSM maintenance uses its own accepted walking/run distance terms plus the same BMR/TEF.
  Unknown run/step overlap uses the larger supported movement estimate, not unreduced addition.
  Dated profile/active windows prevent double counting. This is not burn elapsed since midnight.
- Lifting extra is separate, **not included in maintenance**: `(MET-1)*kg*activeMinutes/60`,
  weight/bodyweight/functional training 3.5 MET, calisthenics 3.8, powerlifting 5.0;
  subtract any already-counted step kcal inside the active session windows for the extra.
  Rest between sets is included unless explicitly paused; logged sets do not measure active
  muscular work time. Other exercise uses qualified catalogue MET/HR estimates, not one
  universal formula for swimming, intervals, cycling and strength.
- Separate Keytel HR net workout comparison: male gross kcal/min
  `(-55.0969+0.6309*HR+0.1988*kg+0.2017*age)/4.184`; female
  `(-20.4022+0.4472*HR-0.1263*kg+0.074*age)/4.184`; other uses their arithmetic mean.
  Net subtracts Mifflin BMR/1440 and floors zero per measured active minute/fraction. Missing
  HR minutes are not filled with workout-average HR. It is not added to Budget maintenance.
- Retained analytics daily-energy output is another HR-flex path: Keytel above
  `RHR+0.40*(HRmax-RHR)`, net of basal; qualified cadence/MET walking can cover refused low-HR
  minutes; no double billing. The package also retains a gross-bout path with revised
  Harris-Benedict resting coefficients and default-anchor fallbacks. Audit actual callers and
  profile guards; do not confuse these stored/legacy paths with the visible Budget/ACSM pair.
- Food definitions store nutrients per 100 base units. Amount scales linearly, with grams and
  up to two named serving equivalents in both directions (e.g. scoops <-> grams). Unknown kcal
  or macros are null, never zero. Group/meal/day sums retain partial/complete/unknown status;
  calories and protein are primary, carbs/fat/fibre remain available.
- Complete-day averages exclude partial days. Automatic completion uses a calorie-complete
  past diary with an evening entry; explicit Complete/Incomplete marks override where valid.
  Per-nutrient averages require complete coverage for that nutrient separately. These gates
  cannot detect an unlogged meal or prove diet accuracy. Trends name counted/excluded days.
- Goals are manually set and never silently raised for exercise. Red/over-maintenance semantics
  must distinguish fixed intake goal, modeled maintenance, missing estimates and partial logs.
- Food-and-weight maintenance estimate fits a least-squares kg/day slope to real weigh-ins:
  `TDEEestimate=meanCompleteDailyIntake-7700*slopeKgPerDay`; weekly rate `7*slope`.
  Current aligned wrapper needs at least 14 full intervening food days and eight weigh-ins
  spanning that interval. Backdated/imported history-only weight does not reprice old days.
  7700 kcal/kg is a simplified tissue-energy approximation, not proof that scale change is fat.
  Research dynamic energy balance/adaptation/water uncertainty and intake measurement error.

Sources: `lib/compute/profile.dart`, `lib/compute/day_upkeep.dart`, `lib/data/profile_history.dart`,
`lib/data/nutrition_store.dart`, analytics `workout/calories.dart`, activity catalogue.

### 9. Body, Strength And Integrated Progress

- One dated weight per day (latest wins), kg/lb conversion, raw readings and trailing
  **seven-calendar-day mean of observed weigh-ins**, not seven readings across arbitrary gaps.
  Missing days are not interpolated. Weekly blocks show their actual date range/count and
  compare only with a named real previous block; trend denominators/coverage remain visible.
- Tape sites: waist at navel, lower belly, hips, neck, chest, shoulders, right upper arm,
  right thigh. Store entered dated inches/site keys; changes are same-site comparisons.
  Waist-to-height = waist/height in matching units. The current US Navy male-form estimate is
  `86.010*log10(waistIn-neckIn)-70.041*log10(heightIn)+36.76`. The UI can use separately dated
  latest waist/neck inputs and identifies the date; audit timing, sex applicability and error.
  It is an estimate, not directly measured body fat or muscle mass. Photos are comparisons,
  not an automated body-composition measurement.
- Lift logs record exercise, reps, load, load meaning (total/plates-per-side/added load),
  equipment note and when a set was logged. That timestamp is not measured set start/duration.
  Compare the same exercise/load meaning/equipment only. For eligible 1-12-rep loaded sets,
  Epley score `load*(1+reps/30)` ranks comparable performance; >12 reps/bodyweight-only
  falls back to rep comparisons, but current `liftTrend` does not require fixed load: synthetic
  `60 x 15` then `65 x 14` becomes a down trend. The combined review can call identical sets
  getting stronger when `better=0/worse=0`. Audit fixed-load rep comparisons and distinct
  improved/unchanged/declined/incomparable states, including plateau/advice paths.
  This is not a true whole-system one-rep max for plates-per-side
  or added-only modes. Best sets/rep records, recent comparable-session trends and set-by-set
  comparisons have their own gates. Do not equate tonnage or stronger lifts with proven hypertrophy.
- Weekly/monthly reviews compare closed local-calendar periods. Weight mean/absolute/% change,
  food/protein means, same-site tape changes, comparable lifts, workouts, steps, sleep and recovery
  are independently qualified. The basic combined review needs at least three weigh-ins per
  side, four food days and a comparable lift; distinguish that from the stricter goal-advice gate.
- Goal phases: fat loss, recomposition, maintenance, lean gain and strength. Current target bands
  are weekly weight % and protein g/kg: gentle fat loss -0.50 to -0.25 and 1.8-2.4;
  moderate -0.75 to -0.50 and 1.8-2.4; faster -1.00 to -0.75 and 2.0-2.6;
  recomp -0.25 to +0.05 and 1.6-2.2; maintain +/-0.375 and 1.6-2.2;
  lean gain novice +0.25 to +0.50/intermediate +0.15 to +0.33/advanced +0.10 to +0.20,
  all 1.6-2.2; strength +/-0.15 and 1.6-2.2. These are current app policy, not universal optima.
- Fat-loss/lean-gain goal reviews use one closed week versus the prior one; slower phases use
  two versus two. Need at least five weigh-ins and five fully logged food days in every week,
  plus at least 14 days on the goal when known. Tolerance margin 0.1 percentage point/week.
  Maintenance can also compare with a held weight within +/-1.5%.
- Suggested intake step sizes derive `abs(gapPct)/100*kg*7700/7`, clamp 100-250 kcal/day,
  round to 25 kcal. Floors use max(estimated resting kcal, 1500 male/1200 female). Low protein
  can withhold a cut, worsening comparable lifts can prioritize recovery, and advice never
  automatically changes targets. Review medical/dietary suitability; a floor is not a guarantee
  of nutritional adequacy or safe intake for every person.
- Existing lean-gain waist heuristic compares >0.5 cm waist gain per kg scale gain; language
  can imply excess fat. **There is no validated tissue-identification ratio here.** Audit/remove
  unsupported certainty in recommendations. Waist falling and lifts improving is supportive
  context, not proof of exact fat loss/muscle gain; pump, water/glycogen, technique and measurement
  error matter. Assess lagged weekly/monthly cross-domain insights, not same-day causal stories.
- General activity streak: ten active exercise minutes or dated measured step goal achieved.
  Physical types include walking/running/lifting/other; overlap counts once. Up to two protected
  days in rolling seven, at most one Life happens, never consecutive protection; protection
  preserves continuity without inventing exercise. Pushups has its own logged-set goal/streak
  and reminder schedule, not automatic duration/HR/calories/general-activity qualification.
- Repeat-last-set, optional rest timer, manual past entry, historical imports and independent
  photo comparisons are workflow tools, not extra measured physiology.

Sources: `lib/data/body_log.dart`, `lift_log.dart`, `lift_progress.dart`, `progress_review.dart`,
`goal_plan.dart`, `recovery_movers.dart`, `pushups.dart`, `lib/compute/streak.dart`.

### 10. Complete The Inventory Before Recommending Changes

If source is available, follow decoded fields -> preprocessing -> callers -> stored JSON/scalars
-> served UI/exports/findings. Check `metrics-map.md`, `bugs.md` and `todo.md`, but source wins
over stale comments. The algorithm catalog contains old capability claims; do not treat its
"clinical/high accuracy/continuous RR/temperature" wording as validation.

Account for every active family above and retained secondary outputs: RMSSD/lnRMSSD/whole-window
RMSSD/SDNN/pNN/frequency powers/CV, PRSA, nocturnal dip/nadir/waking HR, HRR/tau/ceiling,
stress/SI, rhythm flag, RSA/BRV/CVHR, refused SpO2/ODI, raw-temperature-labelled baselines,
readiness/drivers/absence diagnostics, stages/TST/efficiency/latencies/cycles/naps/unobserved time,
bedtime/midsleep/SRI/chronotype/jetlag/debt/need/performance/circadian summaries, TRIMP/strain/
CTL/ATL/TSB/target/overreaching/session cost, wear/steps/motion/active minutes, routes/splits/
speed/pace/cadence/elevation/records/predictions/drift, all energy models, all nutrients/portions/
completeness, weight/tape/photo/body-fat proxies, lift performance, goal advice and reviews/streaks.
For library-only, hidden, refused or deprecated code, explicitly report that state; exported
methods alone do not establish an active app feature. Identify any missing current calculation.

### 11. Research Standards And Deliverables

1. Produce a complete metric-by-metric inventory: units, actual data source/sample rate,
   preprocessing, formula/model, window, aggregation, coverage/artifact/baseline gates,
   missingness/fallback policy, device-family scope, storage, current feature use and uncertainty.
2. For each vendor comparison, link the exact official page and relevant primary validation
   paper, with access/publication date, hardware generation/firmware, population and task.
   Distinguish documented behavior, inferable methodology, published algorithm, marketing and
   unknown proprietary details. WHOOP API output availability is not raw BLE input availability.
3. Separate signal-identity bugs, ingestion/timestamp/coverage failures, wrong units/window
   arithmetic, estimator shortcomings, unvalidated policy choices and misleading presentation.
   Trace downstream impact. Fixing sync freshness can improve availability, not recover an
   optical signal we never retained or make a heuristic clinically precise.
4. Propose changes using **only verified available inputs**, or clearly label new sensors,
   permissions, backend/cloud API, always-on streams, battery costs and datasets required.
   Explain confidence, likely benefit, failure modes, conflicts with other metrics and whether
   tuning would merely imitate a vendor number. Keep future WHOOP generations separate.
5. Prioritize critical invalid inputs/honesty first, deterministic low-risk corrections next,
   then personalized/calibrated estimates, and genuinely experimental models last. Give
   expected benefits as hypotheses where not validated, not invented accuracy percentages.
6. Design suitable validation: PSG for sleep/wake and four-class staging; ECG/chest reference
   for HR/beat intervals; independent respiration; manually counted steps; surveyed route/
   appropriate GPS reference; indirect calorimetry for energy when feasible. Body/circumference
   repeatability and reference composition methods have their own errors. Another wearable's
   score is a comparator, not ground truth for physiology or readiness.
7. Require independent participant/night/session holdouts, no personal-baseline future leakage,
   representative movement/sleep conditions, proper timestamp alignment, missing-data
   stress tests and subgroup/error reporting. Use bias/MAE/RMSE/Bland-Altman where suitable,
   sleep sensitivity/specificity/class confusion/kappa, false-alert burden, uncertainty intervals
   and abstention-vs-coverage tradeoffs. Verify licensing and reproducible dataset/model use.
8. Review energy/nutrition advice against primary research and authoritative health sources,
   including dynamic weight change, underlogging, adaptation and recomp confounding. Never
   diagnose illness or declare exact muscle/fat change from this app's proxies.
9. Finish with a concise ranked roadmap and detailed recommendation appendix: current method,
   evidence/known limits, proposed change, required inputs, validation test, safety/UX consequence,
   affected files/consumers, algorithm/schema migration and retained-history strategy. State
   what should remain unchanged, unavailable or experimental. Do not change code, export health
   records, publish anything or automatically alter food/training goals as part of the research.

Use generic technical searches only. Do not upload screenshots, personal health history, photos,
database captures, logs, credentials or private code. Follow any workspace/network approval
requirements when running this brief; this prompt does not grant new destination permissions.

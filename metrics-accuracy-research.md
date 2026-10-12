# WHOOP 4 Metrics Accuracy Research

**Status:** Source audit and primary-source desk research completed against Build 87
(`0.9.54+87`, algorithm 91, schema 49, source `b0eee377`). Recommendations are proposals,
not implemented or physically validated. Build 86 remains the reported installed app; Build 87
remains the testing candidate. Build 88 implementation, visual acceptance and release are separate
gates. Public sources checked 2026-10-11 using generic searches authorized by Akshat; no personal
records, screenshots, logs or repository content were sent to those sources. The expanded local
audit below adds synthetic HRV/strength reproductions. The second-pass source audit and refreshed
external round are recorded under "Second Pass" below; listed items there remain unverified.

## Read This With

- [Research brief](metrics-accuracy-research-prompt.md): the detailed current input, formula,
  unit, window, coverage and caller inventory. This report evaluates that inventory; it does not
  silently replace its account of the current code.
- [Metric map](metrics-map.md): stored and visible versus hidden/refused outputs.
- [Bugs](bugs.md): confirmed implementation defects, distinct from unvalidated estimators.
- [Build TODO](todo.md): implementation and acceptance gates. Research completion is not
  approval to implement every recommendation.
- [Consolidated Build 88 plan](build-88-plan.md): condensed research and both supplied AI analyses,
  source/primary-evidence corrections, twelve work packages and deferred experiments. Read this
  for next-build selection; the R01-R10 evidence below remains the detailed research reference.
- [Goal rules](fitness-goal-research.md): current goal policy and original evidence; several
  constants are explicitly conventions, not validated individual prescriptions.
- [Background plan](background-sync-plan.md): existing sync design and physical tests.

This is a targeted engineering literature review, not a preregistered systematic review or a
clinical validation study. Vendor documentation describes behavior; it does not disclose every
model or prove accuracy. Papers are restricted to their tested hardware, software, population,
window and task. Search indexing, abstracts and full-text access differed; limitations are named
where they affect the conclusion. No new datasets, pretrained models or vendor accounts were used.

## Conclusions

1. **Repair invalid inputs before tuning formulas.** WHOOP 4's consumed `skinTempRaw` is an
   unknown optical-block quantity, not a verified temperature measurement. Relative normalization
   cannot rescue it. Remove its physiological influence through an abstaining, versioned repair;
   hide unsupported Trends/Sleep rows as Akshat selected, without deleting original records.
2. **Make missingness and method identity first-class.** Partly missing TRIMP history can become
   zero load; displayed HRV and readiness HRV do not always use the same estimator. The primary
   also discards timestamps within five-minute buckets and accepts sparse differences. These are
   actionable source findings, not questions answered by copying a vendor's weights.
3. **Sleep/wake boundaries and signal coverage precede finer stages.** Our 30-second HR/RR/motion
   rules are not WHOOP's classifier. Fixing delayed availability may reveal earlier observations;
   it must never paint invented HRV across a missing quarter of the night.
4. **Do not infer exact fat or muscle from weight, tape, photos and lifts.** The current lean-gain
   waist rule can overstate tissue attribution. Cross-domain progress is useful when it reports
   separate qualified observations and uncertainty, rather than a causal or composition claim.
5. **Energy is a model, not a measured allowance.** Keep the selected conservative Budget and
   ACSM comparison distinct. Improve accounting, dated inputs and trend calibration before
   changing coefficients or adding lifting calories to maintenance.
6. **No defensible accuracy percentage exists for our app yet.** Better quality control and
   consistency are plausible benefits. Demonstrating physiological improvement needs independent
   references, held-out evaluation and an honest error-versus-coverage result.

## What The Hardware Gives Us

The current decoded WHOOP 4 substrate contains approximately 1 Hz reported optical HR, variable
reported beat intervals and low-rate three-axis motion. It does not retain a continuous raw PPG
waveform, EEG, a validated temperature channel or independent red/IR waveforms for SpO2. Live
high-rate IMU supports connected wrist step coverage but is RAM-only. Historical records cannot
reconstruct every offline wrist step. Direct iPhone pedometer and GPS are separate sensors with
their own carriage, permission, timestamp and uncertainty limits.

Consequences for research proposals:
- A library accepting raw PPG is not usable merely because we have an intensity count.
- A published ECG algorithm is not automatically validated on reported optical beat intervals.
- A model trained on another device needs compatible units, sampling, missingness and a genuine
  domain-transfer evaluation. Interpolation cannot recreate frequencies never sampled.
- Official cloud summaries would be a new authenticated data source, not evidence that our BLE
  decoder receives those scores. Cloud integration is not proposed as a dependency here.
- A newest committed record, a live reading, a calculated day and a qualified night need different
  freshness timestamps. Sync correctness improves availability, not underlying sensor accuracy.

Raw/decoded retention is limited after completed derivation. Stored versioned day results survive,
but they are not a complete substitute for raw input when evaluating a new algorithm retrospectively.
The current open-schema path drops legacy `raw_records`; `raw_archive` retains undecodable
records but selectively thins old `undecodable_rec_v20` frames to one in 60. It is not a complete
permanent raw-frame backup. The usual decoded cutoff is three days behind the data edge, with
bounded protection for unfinished derivation; inspect actual retained rows before promising replay.
Do not promise months of recalculation until retained inputs have actually been inspected.

## Vendor Comparisons And Their Limits

### WHOOP

WHOOP documents whole-night HRV with additional weighting toward slow-wave sleep and later sleep.
It does not publish weights sufficient to reproduce Recovery. Our mean of eligible five-minute
RMSSD windows and lowest qualifying 30-minute RHR are different definitions. Matching labels or
using the same hardware does not make their values interchangeable.
[Official Recovery](https://support.whoop.com/s/article/WHOOP-Recovery)

Current WHOOP Sleep Performance describes sufficiency, consistency, efficiency and sleep stress,
including for WHOOP 4. Our `TST / need` measure is sufficiency, not that entire score. The exact
combination is not published on the consulted page; copying a four-part description would still
produce our own unvalidated composite.
[Official Sleep](https://support.whoop.com/s/article/WHOOP-Sleep?language=en_US)

WHOOP Strain combines cardiovascular and muscular load. Strength Trainer incorporates exercise,
load and movement information unavailable in our manual set records. Our transformed TRIMP is
cardiovascular load, not a clone of muscular Strain or proof that an easy-HR lift was easy work.
[Official Strain](https://support.whoop.com/s/article/WHOOP-Strain?language=en_US)

**Direct validation, not a target to imitate:** Schyvens et al. (2025) compared six devices with
PSG in 62 adults, including suspected sleep-apnea cases. Forty WHOOP 4 recordings were analyzed.
Total-sleep-time bias was +24.46 minutes, MAE 50.31 minutes, and agreement limits approximately
-101 to +150 minutes. Sleep/wake sensitivity was 93.58%, versus wake specificity 40.13%.
These 2023-2024 lab-night recordings show considerable individual error, not our app's error
or the current 2026 model's accuracy. Exact firmware was not established in this review.
[Primary PSG study](https://pmc.ncbi.nlm.nih.gov/articles/PMC12038347/)

Dial et al. (2025) compared five wearables with ECG in 13 healthy adults across 536 nights.
WHOOP 4 nocturnal HRV had concordance 0.94 and MAPE 8.17% with substantial dispersion; RHR
concordance was 0.91. Repeated nights do not equal hundreds of independent participants.
This validates official device outputs under the study's definitions, not our RR decoder or
aggregation. The abstract was available; full-text access was blocked, so firmware and precise
reference-window choices remain unresolved here.
[Primary cardiac study](https://pubmed.ncbi.nlm.nih.gov/40834291/)

### Apple

Apple's October 2025 technical paper describes an accelerometer-based sleep classifier,
including an updated model for quiet wake in iOS/watchOS 26. It exploits high-frequency motion;
it is incorrect to say Apple necessarily needs HR for this classifier. Our sparse historical
motion is not equivalent input. The paper provides a validation design, not reusable model
weights or evidence for our heuristic stages.
[Technical paper](https://www.apple.com/in/health/pdf/Estimating_Sleep_Stages_from_Apple_Watch_Oct_2025.pdf)

Apple HealthKit's HRV quantity is SDNN. Comparing its displayed number with our RMSSD without
matching statistic and window is invalid. HealthKit remains excluded from the personal build;
researching this distinction does not enable it.
[HealthKit definition](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn)

Apple's wrist-temperature feature uses dedicated sensors, a nightly baseline and relative
changes; it is not an on-demand thermometer. That is a useful presentation distinction only
after a physical channel is validated, not justification for normalizing WHOOP's unknown count.
[Official temperature documentation](https://support.apple.com/en-us/102674)

The PSG comparison above is not validation of later software. No Apple readiness model was
identified as an equivalent open algorithm for our app.

### Oura

Oura reports an overnight average of five-minute HRV samples and separately shows average and
lowest nightly HR. Those aggregation choices are useful comparators, not proof that their exact
artifact filters or RHR selection match ours.
[HRV](https://support.ouraring.com/hc/en-us/articles/360025441974-Heart-Rate-Variability),
[RHR](https://support.ouraring.com/hc/en-us/articles/360025588793-Resting-Heart-Rate)

Svensson et al. (2024) evaluated Oura Gen3 with OSSA 2.0 in 96 generally healthy Japanese adults
aged 20-70, up to three ambulatory PSG nights each. The reported 91.7-91.8% accuracy is
sleep/wake accuracy, not universal four-stage accuracy. The authors disclosed Oura financial
support (confirmed in the second pass: mainly Oura-funded). This is generation/model-specific evidence, not transferable performance for WHOOP 4
or our app. Oura's cardiac outputs also appear in Dial's separate ECG study.
[Primary Gen3 study](https://pubmed.ncbi.nlm.nih.gov/38382312/)

### Garmin And Firstbeat

Garmin HRV Status uses a personal baseline established over roughly three weeks and a seven-day
average; unusually high as well as low values can be unbalanced. This favors personal ranges
over assuming that every increase is improvement.
[Device manual](https://www8.garmin.com/manuals/webhelp/GUID-25E3235D-44D2-4384-A591-DD1D71BEBCB1/EN-US/GUID-9282196F-D969-404D-B678-F48A13D8D0CB.html),
[Official explanation](https://www.garmin.com/en-US/blog/fitness/understanding-the-hrv-status-on-your-garmin-smartwatch/)

Garmin's stress feature uses HRV in inactive periods; Body Battery combines stress, rest, sleep
and activity as an energy proxy, not calories. Firstbeat's 2014 white paper describes separating
physical activity, stress, recovery and unrecognized periods. Neither source discloses enough
to reproduce today's proprietary model or validates our Baevsky-to-100 mapping.
[Stress](https://www.garmin.com/en-AU/garmin-technology/health-science/stress-tracking/),
[Body Battery](https://www.garmin.com/en-IE/garmin-technology/health-science/body-battery/),
[Firstbeat paper](https://www.firstbeat.com/wp-content/uploads/2015/10/Stress-and-recovery_white-paper_20145.pdf)

Garmin Vivosmart 4 appears in the PSG study and Fenix 6 in Dial's HRV study; their errors do not
establish performance for current Garmin devices, Firstbeat scores or our app. Proprietary sleep,
stress and energy scores have no directly reproducible replacement in the consulted sources.

### Polar

Nightly Recharge combines sleep with an ANS assessment using HR, RMSSD and respiration in the
first approximately four hours of sleep, relative to 28 days. This is intentionally a different
window from WHOOP/Oura whole-night methods. HR contributes most and respiration least, but the
consulted documentation does not provide a complete open scoring formula. Grit X Pro cardiac
outputs were evaluated in Dial's small ECG study; that is not validation of Nightly Recharge's
prediction of next-day performance.
[Official method](https://support.polar.com/en/nightly-recharge-recovery-measurement)

### Fitbit / Google

The current official readiness page describes HRV, resting HR and recent sleep, with a
personal-baseline period. Its updated model removed the older activity component. The current
Sleep Score page describes duration, settling into sound sleep, sound sleep, restlessness,
awakenings and interruptions. Do not copy legacy 50/25/25 weights as if they were current.
These pages describe behavior, not reproducible coefficients. Fitbit Sense/Charge 5 in the
PSG study are separate hardware/software evidence, not validation of the current revised score.
[Readiness](https://support.google.com/googlehealth/answer/14236710?hl=en),
[Sleep Score](https://support.google.com/googlehealth/answer/14236513?hl=en)

## Metric-By-Metric Assessment

The exact current formulas and gates remain in the brief. The following sections cover active
and retained families, and identify what to keep, repair, evaluate or leave unsupported.

### 1. Signal Integrity, Wear, Time And Availability

**Current:** decoded HR/RR/motion; wear events; local-calendar day boundaries; immutable
algorithm-versioned results; distinct live and history paths. Build 87 source already separates
committed-data freshness from calculation status, reuses unchanged calculation inputs and
repairs several wake/empty-burst paths. Physical-device verification remains open.

**Proposed:** preserve timestamps, source family, recording coverage, wear evidence and processing
status for every family. Check RR duration versus timestamp resolution, clock drift, duplicate
records, reset/wrap, out-of-order history and DST across preparation and persistence. A late
sync must fill genuine earlier observations without moving already-recorded events or inventing
continuous coverage. Reconnect/ACK repairs must preserve commit-before-ACK and bounded work.

Apple documents event-driven Bluetooth background handling and restoration, not perpetual app
execution. Treat the archived guide's approximate wake budget as guidance, not a guaranteed
deadline or a complete iOS 26 force-quit rule. Test lock, normal background, system termination,
user force-quit, range loss and return separately. Do not promise an exact wake schedule.
[CoreBluetooth guide](https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html)

**Validation:** newest record time, ingest time, derive time, chart-visible time and qualified-night
time measured independently; bounded cancellation/idempotent replay tests plus short daily visits
and the existing 72-hour soak. This is an availability claim, not validation of sleep stages.

### 2. HR, RR Cleaning And Headline HRV

**Current:** optical HR in bpm; eligible corrected beat intervals in ms. The primary uses a
plausible-range/local-median Malik-style cleaner; secondary NN paths use Lipponen-style adaptive
cleaning. Five-minute session RMSSD mean is primary, robust NREM/whole-window alternatives are
headline fallbacks; lnRMSSD readiness uses the primary only. RHR is the lowest sufficiently
covered 30-minute sleep-window mean, not a whole-night mean.

**Confirmed inconsistency:** `rmssdScalar` in `lib/compute/onehz_pipeline.dart` falls back to
other estimators, while `lnToday` does not. A visible HRV can therefore coexist with unavailable
readiness HRV. Cross-day detail can also use the fallback scalar. That is not necessarily a
reason to allow the fallback into readiness: mixing methods may corrupt a longitudinal baseline.

**Confirmed continuity/eligibility defect:** `sleepSessionWindowedRmssd` retains report time only
to choose five-minute buckets, then cleans values without timestamp boundaries. Rejected reported
beats split runs, but unreported time does not. One surviving difference can qualify a bucket.
A direct synthetic probe returned RMSSD 100 ms/confidence 0.3 from two intervals `[1000,1100]`
whether report times were one second or 298 seconds apart. This proves false continuity/sparse
admission, not a personal-data error estimate. `bugs.md` owns the exact reproduction.

**Selected presentation:** keep the primary canonical; if it is absent, leave headlines absent
and offer labelled secondary estimates in details. This is approved, not implemented.

**Proposed:** preserve report-time/dropout boundaries, respect multiple intervals sharing a
report second, and explicitly qualify usable continuity, window/night coverage and artifact
burden before output. Freeze numeric gates as testable engineering policies, not invented
clinical constants. Give each estimate method/window identity, artifact fraction, valid-window
count, observed duration and refusal reason. Rebuild only compatible baselines; legacy sparse/
gapped values cannot be admitted merely because the key matches. Do not silently pool whole-night
and five-minute RMSSD or replace cleaners as a side effect. Keep lowest-window
RHR but label its definition; evaluate an additional whole-night mean only as an explicit choice.

Lipponen and Tarvainen (2019) provide a tested adaptive artifact method. Their published method
does not establish that our port, thresholds, timestamps or optical inputs behave identically.
Compare against reproducible reference cases before tuning artifact thresholds.
[Original method](https://pubmed.ncbi.nlm.nih.gov/31314618/)

**Validation:** synchronized ECG at sleep/rest and separately during movement; RR match/missing/
extra-beat errors, artifact correction bias, RMSSD/lnRMSSD/RHR bias and agreement, refusal rate,
coverage by night. Compare raw and cleaned estimates; do not select filters using the held-out
night or just maximize correlation. Exclude adjacency across missing spans.

### 3. Secondary Cardiac And Autonomic Metrics

**Current:** SDNN, pNN50, five-minute/whole-night RMSSD, SDANN/index, frequency bands, NN CV,
PRSA deceleration capacity, nocturnal HR dip/nadir, waking HR, observed ceilings, recovery HR/tau
and rhythm flags. Most are secondary/retained, not the five-tab headline experience.

**Proposed:** retain duration/statistic-specific names and units. SDNN over one night is not
24-hour SDNN; NN CV is not night-to-night HRV variation. ULF/VLF require an appropriate span;
short or interrupted segments should not manufacture meaningful low-frequency powers. LF/HF
is not a direct measure of psychological stress. PRSA, rhythm flags and recovery tau need
application-specific validation; neither an exponential fit nor a pattern flag is a diagnosis.
Do not use capped HR or low-pass display data to validate a detector against itself.

The HRV Task Force standards distinguish statistics and recording durations. They are a method
reference, not certification of optical RR or a modern endorsement of every autonomic interpretation.
[Standards](https://pubmed.ncbi.nlm.nih.gov/8598068/)

**Validation:** analytical fixtures for units/windowing/spectra and reference ECG experiments.
For HR recovery, specify stop time, posture, active versus passive recovery and coverage; report
fit residuals/intervals or abstain. Keep arrhythmia and clinical prediction claims unavailable.

### 4. Sleep Detection, Stages, Latencies And Naps

**Current:** one main sleep window ending on the local day, 30-second rule-based staging from
motion/HR/RR features, continuity rules and bounded personal thresholds. TST and stage durations
sum observed epochs; efficiency divides by observed time, with unobserved time separate.
Manual timing can change the intended window, not create physiological measurements.

**Proposed:** prioritize missed onset/offset, quiet waking, long joins, false naps and off-wrist gaps
before optimizing deep/REM weights. Require independent signal eligibility per overlay: an HRV
five-minute window must not appear at sleep start when its beats do not exist. Distinguish a
real coverage gap from a plotting/window-alignment bug. Preserve early HR where present even
when early HRV is unavailable. Keep measured/estimated duration and wall-clock in-bed denominators
separate. Do not infer full stages for an unsupported nap or count missing time as sleep.

For a learned model, start with the actual retained feature set, not raw-waveform features we
cannot supply. Li et al. (2021) trained on ECG data and transferred to Empatica E4 PPG in a
different population; its four-class performance remained limited. Domain-transfer results are
evidence that testing is necessary, not an available drop-in model for our WHOOP RR stream.
[Original transfer study](https://pmc.ncbi.nlm.nih.gov/articles/PMC8564719/)

**Validation:** blinded PSG-aligned 30-second epochs, participant/night holdouts, per-class confusion,
sleep sensitivity and wake specificity, balanced metrics, TST/WASO/SOL bias and agreement, absent
epoch fractions. Include interrupted/short sleep, naps, still-awake periods and genuine contact
loss. Nightly total agreement alone is insufficient. A sleep diary helps boundary QA but cannot
validate light/deep/REM; a vendor hypnogram is only another estimate.

### 5. Cycles, Regularity, Need And Circadian Summaries

**Current:** HRV-pattern cycle estimates; bedtime spread/consistency, midsleep and SRI;
weekend/workday chronotype assumptions and jetlag; debt, baseline need, strain-related extra
need and nap subtraction; `100*TST/need` sufficiency. Hidden HR-based IS/IV, M10/L5, relative
amplitude and cosinor are not validated actigraphy or internal circadian-phase measurements.

**Proposed:** do not label RMSSD-pattern cycles as measured EEG cycles. Retain timing/regularity
statistics with real observed-state masks and local-calendar/DST handling. Ask for schedule
context before interpreting weekends as free days. Rename HR-based circadian outputs by their
input when exposed; do not claim endogenous phase or compare against activity norms. The source
already excludes the unknown temperature channel from `_crossDayCircadian`; preserve that guard.

Phillips et al. (2017) used 30-day sleep diaries in 61 undergraduates to study SRI and associated
timing/performance. It supports regularity as a distinct measure, not our individual sleep-need
coefficients, a causal progress claim or interpreting HR cosinor as biological circadian phase.
[Original SRI study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5468315/)

**Validation:** hand-computed wraparound/DST/shift-work/missing-mask tests; compare boundaries to
diaries, stages to PSG. Need/debt coefficients require prospective sleep opportunity, subjective
rest and next-day performance outcomes. Keep sufficiency transparent; no new proprietary-looking
sleep composite without separate selection and validation.

### 6. Respiration, BRV And Sleep-Breathing Patterns

**Current:** respiratory sinus arrhythmia frequency from eligible RR windows, in breaths/min;
nightly consensus and artifact gates. BRV describes change in estimated respiratory rate.
CVHR patterns are retained heuristics; SpO2/ODI are refused. Raw green-count RIIV fusion exists
as a library possibility, not a validated active independent respiratory channel.

**Proposed:** retain RSA as an estimate with covered windows, agreement and refusals. Validate
rate limits against beat sampling/Nyquist and irregular RR; do not tune output toward a normal
range. A second channel can support fusion only after waveform identity and independence are
verified. BRV inherits RSA error; CVHR is not AHI, apnea count or an oxygen dip detector.

Charlton et al. (2016) compared ECG/PPG respiratory algorithms using appropriate recorded signals.
That supports comparing candidate methods against independent respiration, not fabricating
waveform-based intensity modulation from our sparse counts.
[Original comparison](https://pubmed.ncbi.nlm.nih.gov/27027672/)

Hayano et al. (2011) evaluated ECG-based CVHR against PSG in referred patients. Its setting and
limits cannot justify a diagnostic claim for our optical intervals.
[Original CVHR study](https://pubmed.ncbi.nlm.nih.gov/21075771/)

**Validation:** synchronized respiratory belt/airflow or suitable reference at sleep and rest,
window-level error, coverage, low/high rates, missing beats and irregularity. Do not infer illness
or breathing disorder from disagreement alone; oxygen metrics remain unsupported.

### 7. Temperature And Oxygen Integrity

**Current confirmed bug:** unknown WHOOP 4 `skinTempRaw` is averaged and standardized into
temperature-labelled scalars/curves; nightly settled-temperature code and readiness can consume
it. Cross-day temperature-illness/anomaly/glass-box detail paths must also be covered by the repair.
The older SpO2/red-IR problem is already refused, not a missing feature to re-enable.

**Proposed repair:** family-aware verified-channel eligibility at preparation and consumer
boundaries; absence, never zero, for WHOOP 4 temperature physiology. Audit historical curves,
baselines, readiness, findings, notifications, export/read adapters and stale served versions.
Do not guess a Celsius conversion or substitute slower unverified offsets. Preserve original
bytes and old immutable results with an explicit unsupported/legacy status.

**Validation:** decoder-to-UI regression proving arbitrary unknown-count changes cannot change
temperature, readiness or temperature-related alerts; independently verified families must not be
accidentally disabled. Any future channel needs physical identity, units/calibration, contact and
environment characterization, and comparison to a suitable skin-temperature reference. Hardware
having a sensor does not prove this byte offset is its output.

### 8. Readiness, Stress, Illness And Personal Findings

**Current:** readiness is a robust personal-baseline composite with nominal weights
HRV .35, RHR .25, sleep .20, respiration .12, temperature .08; eligible weights renormalize,
then a logistic mapping yields 0-100. Current confidence formulas and gates are engineering
heuristics. Baevsky SI maps logarithmically from 20-600 to 0-100. RHR CUSUM, multivariate flags,
MDC-like thresholds and context movers also exist as retained/secondary analyses.

**Proposed:** repair invalid inputs and unify estimator identity first. Separate data quality,
personal deviation and any readiness interpretation; an envelope confidence is not probability
of recovery or clinical accuracy. Do not assume very high HRV or very low RHR is always favorable.
Keep stress limited to eligible inactive conditions and label it autonomic-pattern context,
not mental stress, anxiety or illness. A biological-history spread is not instrument test-retest
error; `1.96*sqrt(2)*TE` only has its intended measurement-change meaning with a suitable TE.

**Validation:** training-only personal baselines and held-out next-day outcomes; calibration,
false-alert burden, score stability, withheld-input behavior and coverage. Compare transparent
simple baselines before learned weights. Context movers require confounders, repeated exposures
and cautious language: observational association, not proof that a food/workout caused recovery.
Do not add alerts or medical interpretations simply because a stored detector exists.

### 9. HR Zones, TRIMP, Strain And Longer-Term Load

**Current:** Tanaka age estimate plus qualified observed upward ceiling; Karvonen when sufficient
observed ceiling/RHR history exists, otherwise percentage-of-max zones. Banister-style TRIMP,
quiet-baseline subtraction and logarithmic 0-21 strain. CTL/ATL use 42/7-day EWMAs; TSB is their
difference. These describe cardiovascular exposure, not total muscular stimulus.

Tanaka et al. (2001) derived an age-based population estimate. It is not an individual's measured
maximum or lactate threshold; ordinary walks cannot establish true HRmax.
[Original equation](https://pubmed.ncbi.nlm.nih.gov/11153730/)

**Confirmed source issues / policy limits:** all audited strain call sites pass constant
`quietWakingHrr = .20`; a library personalization option is not wired as the current method.
`_denseDailyTrimp` abstains if all values are unknown, but once one value exists it fills missing
rows/calendar days with zero. That creates apparent recovery across unobserved days.

**Proposed:** unknown load remains unknown; define minimum coverage for an observed zero and
an explicit gap policy for load models. Evaluate a qualified personal quiet-HRR baseline with
minimum inactive coverage and a dated RHR/max frame, rather than merely swapping a constant.
Preserve cardiovascular Strain semantics and use logged lift performance/sets as separate context.
Published ACWR associations do not justify injury-risk claims for CTL/ATL or TSB; a primary study
found similar associations after contriving the denominator.
[ACWR analysis](https://pubmed.ncbi.nlm.nih.gov/33332011/)

**Validation:** missing day versus observed-zero versus complete exercise day, DST calendar EWMA,
initialization/run length and all strain callers; held-out session effort/performance outcomes.
No quiet baseline change without a calibration experiment. Never infer overtraining or injury
from this unvalidated composite.

### 10. Steps, Workouts, GPS And Running Predictions

**Current:** interval ownership joins phone steps with qualified live wrist coverage, without
double-counting; phone zero has special qualified stillness semantics. GPS speed in m/s converts
to km/h, while average pace/speed and symmetric post-session smoothing are different quantities.
Cadence, run/walk splits, route/elevation, best efforts, HR drift and Riegel projections have gates.

**Proposed:** keep live speed causal: latest accepted native speed plus timestamp and speed
uncertainty, short trailing smoothing if tested, explicit stale/paused state. Do not use a
future-looking +/-15-second analysis window in live UI. Tighter update settings trade power for
latency and cannot guarantee sensor callbacks while suspended. Indoor phone-motion speed is a
different estimate; do not silently present it as fresh GPS.

CoreLocation exposes speed accuracy and a movement-distance filter, not a fixed guaranteed
refresh frequency. Reject stale/invalid points before aggregation and measure actual callback
and rendering delay instead of choosing a nominal timer.
[Speed accuracy](https://developer.apple.com/documentation/corelocation/cllocationspeedaccuracy),
[Distance filter](https://developer.apple.com/documentation/corelocation/cllocationmanager/distancefilter)

**Validation:** manual/video-counted steps across speeds, phone carriage and arm-only motion;
surveyed/reference routes, stationary jitter, starts/stops, tunnels, lock/background and pause
boundaries. Compare drift only at comparable workload with coverage. Race projections remain
projections from qualified efforts, not measured VO2max or guaranteed times. No overnight high-rate
stream/storage change or new sensor permission is approved by this recommendation.

### 11. Energy, Maintenance And Digestion

**Current:** Mifflin resting-energy estimate, selected conservative step/run Budget, separate ACSM
distance comparison, logged macro-based TEF, separate MET lifting and HR-based workout estimates.
Lifting/Keytel are not silently added to the selected maintenance. Legacy stored HR-flex/gross-bout
paths must not be mistaken for the visible Budget/ACSM calculation.

Mifflin et al. (1990) developed a resting-energy equation from indirect calorimetry in 498 adults.
This supports it as a population estimate, not a measurement of personal BMR. Our other/unknown
sex interpolation is not a separately validated equation.
[Original equation](https://pubmed.ncbi.nlm.nih.gov/2305711/)

Keytel et al. (2005) studied exercising adults during treadmill/cycle workloads. Its HR-to-energy
regression is not validated for psychological HR elevation, rest, short sets or every activity.
Keep it a qualified comparison, not automatic maintenance credit.
[Original HR-energy study](https://pubmed.ncbi.nlm.nih.gov/15966347/)

Primary calorimetry studies show meal composition influences thermogenesis; they do not establish
that fixed 20% protein/5% carbohydrate/0% fat terms precisely measure this individual's digestion.
Zero fat credit is a conservative accounting choice, not proof of zero physiological TEF.
[Meal experiment](https://pubmed.ncbi.nlm.nih.gov/11838888/)

The 2024 Adult Compendium updates measured and estimated activity METs for ages 19-59. It supplies
catalogue-level estimates, not individual energy measurement or active-set duration from a log.
Do not change a coefficient without checking gross/net semantics and the applicable activity.
[Compendium publication](https://pubmed.ncbi.nlm.nih.gov/38242596/)

Shcherbina et al. (2017) compared seven then-current wrist devices with ECG and indirect calorimetry
in 60 adults; energy estimates performed less reliably than HR. These older devices are not a
benchmark for WHOOP 4, but the study illustrates why accurate HR alone does not validate calories.
[Primary experiment](https://pubmed.ncbi.nlm.nih.gov/28538708/)

**Proposed:** retain chosen coefficients pending a separate decision; improve dated profile units,
route/phone/step overlap ownership, gross/net resting subtraction, midnight and pauses, and
logged-TEF completeness. Show Budget and ACSM as different models, never an uncertainty interval.
The displayed full-day estimate is not expenditure already elapsed today. Avoid exact-looking
deficit certainty and do not derive a universal daily correction from another wearable.

**Validation:** accounting fixtures before physiology; indirect calorimetry for selected sessions,
resting measurements for REE and doubly labeled water when feasible for multi-day expenditure.
Without these references, personal logged-intake/weight consistency can test plausibility but
cannot establish absolute calorie accuracy.

### 12. Food, Weight Trend And Intake Guidance

**Current:** per-100-unit nutrient scaling, bidirectional named portions, unknown nutrients kept
null; calorie and protein summaries retain completion status. Automatic past-day completion
cannot detect a forgotten meal. Intake/weight maintenance fits an OLS kg/day slope and uses
`mean intake - 7700*slope`; current gates require aligned full-food days and weigh-ins.

Hall et al. (2011) modeled dynamic energy balance and adaptation; weight response is not a fixed
linear conversion of daily deficit into tissue loss. This argues against treating 7,700 kcal/kg
as precise, especially over short/water-affected intervals. A dynamic model requires its own
inputs/validation; this report does not propose silently embedding one.
[Original model](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/)

**Proposed:** retain the seven-calendar-day observed mean and coverage count; evaluate a robust
longer trend against OLS with sensitivity to interval and logged-intake completeness. Explicitly
label this as an intake-and-weight estimate, not measured TDEE. Unlogged meals, water/glycogen,
illness, travel and inconsistent weighing can bias it. A complete button is a user assertion,
not a sensor observation. Do not apply an assumed underreporting correction to this user.

Goal phase bands, minimum history, 100-250 kcal steps, 25-kcal rounding and floors are current
policies, not precisely individualized outcomes. The max(resting estimate, 1200/1500) floor is
not proof of nutritional adequacy, and the existing alternative of adding steps at the floor
also needs safety review. Advice should pause with inadequate/conflicted data, recent goal
changes or relevant medical circumstances, and never auto-change a target.

NIDDK's Body Weight Planner is designed for adults, not children or pregnant/breastfeeding
people, and distinguishes model output from individualized care. It does not establish our
fixed floor as universally safe.
[Official planner](https://www.niddk.nih.gov/health-information/weight-management/body-weight-planner)

**Validation:** portions/units/nulls/completeness/import tests; held-out multiweek forecast error
and calibration with real observation counts. Simulate underlogging and rapid water shifts,
and require no recommendation rather than false precision. No automatic food or exercise change.

### 13. Body Measurements, Photos And Strength

**Current:** dated weight/tape at eight named sites, waist/height, male-form Navy estimate,
independent photo comparisons, and same-context lift records. Epley `load*(1+reps/30)` ranks
eligible 1-12-rep loaded sets; plate/added-load scores are not whole-system 1RM. Set logging
timestamps are not measured rep timing or active contraction duration.

**Proposed:** standardize same-site measurement instructions, units, time/context and repeated
readings without requiring a new sensor. Do not combine unrelated-date neck/waist readings
into an apparently current body-fat value. Audit sex/formula eligibility and withhold unsupported
cases. A photo comparison stays visual/manual, not AI-estimated body composition.

Schuna et al. (2013) compared the male DOD circumference equation with air-displacement
plethysmography in 21 young male ROTC cadets over an academic year. The methods did not track
small-gain composition changes equally. This is a specific warning against treating tape-derived
fat-free-mass changes as measured muscle, not proof that tape tracking itself is useless.
[Primary study](https://pubmed.ncbi.nlm.nih.gov/27182395/)

Repetition-to-failure prediction research is exercise/population-specific. A 2008 study of bench
press in young women found lower-repetition predictions more accurate; our casually logged sets
need not be near failure and do not inherit that validation. Keep records tied to exercise,
equipment, load meaning and reps; optional effort context would require its own product choice.
[Primary strength study](https://pubmed.ncbi.nlm.nih.gov/18714230/)

**Confirmed policy problem:** `waistFast` in `lib/data/goal_plan.dart` compares >0.5 cm waist
gain per kg of weight gain and can explain it as more than muscle accounts for. There is no
validated tissue-identification ratio behind this. Preserve a waist-trend observation but
remove unsupported fat/muscle certainty from advice after approval; do not replace it with a
different arbitrary ratio.

**Confirmed strength interpretation defects:** a synthetic review with identical `40 x 10`
sets and qualified weight/food produced "Consistent with getting stronger" because the headline
accepts `better=0, worse=0`. Separately, the high-rep `liftTrend` fallback compares rep counts
without a fixed load: synthetic `60 x 15` then `65 x 14` produced a down trend. Both diagnostic
tests passed via the documented Windows test workflow. Require improved/flat/down/incomparable
states and fixed-load rep comparison or abstention, including plateau/advice consumers. Do not
invent muscle mass or change the current rep-score limits to address these deterministic bugs.

**Validation:** repeated tape/scale measurement reliability, realistic error bands, date/site
alignment; comparison to appropriate body-composition references only where feasible. DXA/ADP
lean mass also has hydration and measurement limits and is not identical to muscle. For strength,
compare standardized performance, not mixed equipment or different rep effort as a guaranteed PR.

### 14. Integrated Reviews, Recomposition And Streaks

**Current:** the UI exposes independently qualified weight, food/protein, same-site tape,
workouts, steps, sleep/recovery and lift observations for closed weekly/monthly periods.
The combined `ProgressReview` still gates on weight, food and lifts together and can overstate
unchanged/incomparable strength as described above. Goal advice has stricter
gates than simple review. General activity and Pushups streaks have separate criteria; protected
rest days preserve continuity without claiming exercise.

**Proposed:** permit partial domain insights instead of withholding every observation until
all families qualify. Use multiweek weight/waist plus comparable strength, protein/intake and
recovery as evidence consistent with a direction, not proof of muscle/fat or causation. A single
week can be useful context; goal adjustment should be slower and confidence-qualified. Do not
penalize rest or invent pushup duration/HR/calories to fill the general-activity log.

Garthe et al. (2011) randomized 24 athletes to different loss-rate interventions with resistance
training; slower loss had advantages for lean mass/performance in that setting. It supports
considering training and pace together, not our exact recomp band or an automatic prescription.
[Primary trial](https://pubmed.ncbi.nlm.nih.gov/21558571/)

Longland et al. (2016) studied 40 young men during a short, intensive training/energy-restriction
intervention with different protein intakes. Its controlled results show recomp is possible in
that context, not that a large deficit or that protein amount is appropriate for every user.
[Primary trial](https://pubmed.ncbi.nlm.nih.gov/26817506/)

**Synthetic example of suitable wording:** "Four-week weight average is down, navel waist is
down and two comparable lifts improved. Logged protein met your selected range on 16 of 20
complete days. This is consistent with your recomposition direction; it does not quantify muscle
gain. Sleep coverage is incomplete, so no recovery comparison is available." Put dates/counts
beside values and explanation behind details; do not restore the rejected wall of Progress copy.

**Validation:** independent-family gates, partial/new-user states, closed periods, sparse/imported
records, goal changes, rest protection, source drift and no automatic target changes. Associations
should not become causal recommendations merely because several charts move together.

## Second Pass: Source Verdicts And Refreshed External Evidence

A second read-only source audit covered every family, including nutrition/body. A capped external
round was run with Akshat's approval of generic searches and fetches; no workspace content was
sent. New defects live in `bugs.md` "Second-Pass Source Audit Findings" and "Overnight Freshness And
Sync Lifecycle Gaps"; this section records only what changes or confirms the report above.

### Corrections To This Report

- **Hardware section.** Green intensity is decoded but never stored. Decodable WHOOP 4 frame bytes
  are not retained at all (`raw_records` is dropped, `rawTail` is never stored). Historical
  R10-lite HR bypasses the substrate. The historical decoder accepts up to 8 RR values, though 4
  are observed.
- **Section 2.** Confirmed: the fallback/`lnToday` split and the timestamp-free primary. The primary
  also has a pooled lag-1 ACF jitter gate and a 0.3 confidence floor. Lipponen windows count beats
  across re-anchored dropouts, and the shared 1000 ms re-anchor bridges about one missing beat.
- **Section 3.** PRSA uses L=2, not 64. The irregular-rhythm screens, `hrv_timeline`, `hrv_day`
  and daytime HRV also difference without timestamps. The `hrv_cv` UI label claims night-to-night
  variation.
- **Section 4.** Totals sum observed seconds, not 30-second epochs. Stage cutoffs are calibrated to
  normative proportions; held-out κ is 0.132 on another sensor's features. Manual windows still
  face the 50% observed floor, so the earlier `bugs.md` correction remedy was wrong.
- **Section 5.** The SRI defect is larger than "use observed masks": the mask is an in-window mask,
  so the index is not Phillips's whole-day measure (see the external evidence below).
- **Section 6.** RSA's whole-night Nyquist gate uses a gap-inflated mean NN. The absolute 0.02 g
  stillness gate likely empties the breathing lane. BRV skips the artifact gate.
- **Section 8.** Readiness's baseline is the last 28 stored values with no calendar bound. The
  on-screen breakdown and the Low readiness alert come from the glass-box model, not the
  composite. Every aggregate has internal critical priority and bypasses the app's quiet-hours
  gate; the iOS sink uses ordinary notification details, not Apple's Critical Alerts capability.
  Actual Focus/mute bypass or phone waking was not established. Cross-day
  detectors do not filter imports. The renormalized weights 38.04/27.17/21.74/13.04% are confirmed
  as arithmetic.
- **Section 9.** The constant's own documentation measures q=0.20 inflating no-activity days to
  6.93–12.14/21 in the upstream corpus whose quiet HRR exceeded it, not Akshat's current nights
  or every quiet day. The directional bias is conditional on that mismatch. CTL/ATL use gross TRIMP.
- **Section 10.** A labelled workout average does stand in for unavailable current speed.
- **Section 11.** Climb terms are inert (`climbM: 0`). All coefficients and worked examples match
  source.

### Refreshed External Evidence (Accessed 2026-10-11)

- **WHOOP Recovery HRV.** A WHOOP Data Science lead (community post, 13 Aug 2025) says HRV is
  computed in overlapping 5-minute windows stepping every 30 s across the whole sleep, weighted
  toward likely slow-wave and later-night windows; the "last slow-wave period" description is
  outdated. This is staff documentation, not a help-centre page, and gives no weights or hardware
  generation. [Post](https://community.whoop.com/t/hrv-extreme-spikes/6472/31)
- **WHOOP API.** The developer API exposes cloud-processed `hrv_rmssd_milli`, `resting_heart_rate`,
  `spo2_percentage` and `skin_temp_celsius` (4.0), stage summaries in ms, cycle counts, strain and
  kilojoules. These are cloud outputs only, not BLE fields. Sleep Performance's four components are
  exposed; weights are unpublished. [API](https://developer.whoop.com/api/)
- **WHOOP 5.0/MG.** Search summaries describe an enhanced PPG, a better accelerometer and improved
  skin-temperature tracking on 5.0, and MG-only ECG and Blood Pressure Insights. Official pages were
  JavaScript-only, so the WHOOP 4.0 sensor inventory remains unverified from an official page.
  Hardware having a sensor still would not identify a byte offset.
- **Schyvens 2025 and Dial 2025: confirmed.** Schyvens: Sleep Advances, 22 Mar 2025, WHOOP 4.0
  n=40, κ 0.37, VLAIO-funded. Dial: Physiol Rep, Aug 2025, WHOOP 4.0 HRV CCC 0.94, MAPE
  8.17±10.49%, RHR CCC 0.91, MAPE 3.00%, AFRL-funded.
- **Svensson 2024: confirmed and industry-funded.** Sleep Med 115:251-263; mainly Oura-funded, with
  authors receiving Oura support. Wake specificity was 73.0-74.6% despite 91.7-91.8% sleep/wake
  accuracy.
- **Apple.** The September 2023 sleep-stage paper describes an accelerometer-only classifier. The
  Oct 2025 appendix (over 10 MB) was not read, so its watchOS 26/quiet-wake specifics above remain
  unverified. Wrist temperature uses two sensors, 5-second sampling in sleep, a nightly value
  relative to a ~5-night baseline and at least 4 h of sleep tracking.
  [Apple](https://support.apple.com/en-us/102674)
- **Other vendors.** Polar Nightly Recharge (first ~4 h, 28-day baseline), Google readiness
  (activity removed; first score after 7 nights) and Garmin HRV Status (3-week baseline, 7-day
  average; Aug 2024 blog) are confirmed. Oura's 5-minute HRV aggregation and the current Fitbit
  Sleep Score page remain unverified from their own pages.
- **Primary citations above.** The WHOOP cardiac paper (PMC8160717) used WHOOP 2.0 with six adults.
  The Oura temperature pilot measured finger skin and oral temperature in 22 women. The Apple Heart
  Study's 0.84 is notification/ECG concordance, and 34% is AF on returned patches. Schuna 2013
  tested the DOD (Navy-form) equation in 21 male ROTC cadets.
- **SRI (Phillips 2017).** The probability that minute-level states 24 h apart match over the whole
  day, counting sleep and wake, with pairwise exclusion of missing data, scaled
  `200(x − 0.5)`. GGIR provides an open implementation. This confirms the in-window mask is not
  the published index.
- **Artifact correction.** Only the Lipponen & Tarvainen abstract was read. The open NeuroKit2
  implementation uses alpha 5.2, a 91-beat window, a median filter of order 11, c1 0.13 and c2 0.17,
  with no separate minimum-threshold floor. The app's 100 ms floor is therefore a local choice.
- **Windowed RMSSD.** RMSSD tolerates short windows (10-60 s reported at rest) better than SDNN,
  but uncorrected artifacts and false adjacency distort it more than deleted beats. That supports
  splitting at gaps over bridging them.
- **RSA respiration.** Charlton's review resamples irregular beat series to a regular 4-10 Hz grid
  and uses 30-90 s windows; it states no beat-count or gap rule. A whole-night mean-NN gate is not
  a published requirement.
- **Baevsky SI.** `AMo/(2·Mo·MxDMn)` with 50 ms bins, which depend on bin width. The commonly
  cited ~5-minute stationary record was not primary-verified, so 30 beats is a local choice.
- **Illness detection.** Mishra 2020 used CuSum on hourly residuals against a 28-day baseline.
  Alavi 2022 NightSignal used RHR ≥4 bpm over baseline on two consecutive nights; its CuSum
  comparator had 83.7% specificity. Follow-on summaries report ~2%/day false positives and PPV of
  4-10%. No paper gives our k/h, so alert burden needs its own evaluation.
- **Typical error.** Hopkins's typical error is the within-subject SD; limits of agreement are
  ±2.77×TE, matching 1.96·√2·SEM. Using day-to-day biological spread as instrument SEM is a
  judgement, not his definition.
- **TRIMP coefficients** (0.64/1.92, 0.86/1.67) were confirmed only from secondary sources. ACWR
  critiques were confirmed at abstract level.
- **Walking energy.** Weyand 2010's ~constant per-stride cost is confirmed, but the 2.74 J/kg/stride
  figure was not found, so the Budget walking constant's provenance remains unverified. Its
  selection rests on `build-74-audit.md`.
- **METs and resting energy.** Byrne 2005: 3.5 mL/kg/min overestimates measured resting VO2 by
  ~35%. Compendium resistance-training entries start near 3.5 MET.
- **TEF (Westerterp 2004).** Fat 0-3%, carbohydrate 5-10%, protein 20-30%, mixed diet ~10%. The
  app's 0/5/20% are the low ends.
- **7700 kcal/kg.** Thomas 2013 shows the static rule overestimates loss; doubly-labelled-water
  studies document 20-35%+ underreporting in some groups. Both support showing an uncertainty range
  rather than a point TDEE.
- **Navy equations** (secondary transcriptions): male `86.010·log10(waist−neck) −
  70.041·log10(height) + 36.76`; female `163.205·log10(waist+hip−neck) − 97.684·log10(height) −
  78.387`. SEE is about 3.5-3.7 %BF. Sources disagree on units, and the DTIC primaries were
  unreachable; the inch form matches the app's inputs.
- **Strength, protein and loss rates.** Rep-based 1RM predictions correlate highly but their error
  depends on exercise and rep range. Morton 2018's FFM benefit plateaus near 1.6 g/kg (non-deficit
  trials); Helms 2014 gives 2.3-3.1 g/kg lean mass in contest deficit. Garthe 2011 (n=24, 0.7 vs
  1.4%/wk) and Longland 2016 (n=40, 2.4 vs 1.2 g/kg) designs are confirmed from abstracts.
- **Steps, GPS and running.** Phone step counts are within a few percent at normal treadmill
  walking (Case 2015; Höchsmann 2018 MAPE <3, with wrist counts much worse). Phone GPS distance error
  is roughly 1-3% outdoors, with metre-scale horizontal error. The walk-run transition sits near
  Froude 0.5 (~2 m/s); the 140 steps/min run cutoff was not verified. Riegel's 1.06 is an elite
  fit that runs fast for recreational marathons.

Still unverified: official WHOOP 4.0 sensor specs, the Oct 2025 Apple appendix, Oura HRV pages, the
Fitbit Sleep Score version, the Lipponen paper body, Weyand's per-stride number and DTIC Navy
primaries. The nutrition/body second pass is recorded in `bugs.md`.

### Readiness Reconciliation And Targeted Verification

Generic external checks were approved and performed on 2026-10-12; no workspace content was sent.
The WHOOP staff post was accessible at its `www.community.whoop.com` URL and confirms overlapping
whole-sleep windows, but remains generation-unspecified staff explanation, not our BLE validation.
[WHOOP staff post](https://www.community.whoop.com/t/hrv-extreme-spikes/6472/31)

Apple documents a special entitlement for OS Critical Alerts. Source uses default Darwin details
and ordinary authorization, so internal quiet-hours priority must not be described as Focus/mute
bypass. Apple full-page retrieval was JavaScript-only; its indexed official documentation supplies
the entitlement rule. [Apple Critical Alert authorization](https://developer.apple.com/documentation/usernotifications/unauthorizationoptions/criticalalert)

Original SRI full-text retrieval was blocked by PMC's browser challenge; no new full-text review
or new numerical calibration is claimed. Its indexed all-day definition remains consistent with
the in-window-mask source defect. Existing paper-specific limits remain in the review above.

Three isolated current-code diagnostic tests passed: prior-night readiness served with today's
overnight date and no held-over flag, default-19:00 dinner-only food admitted as complete, and
internal health priority admitted during app quiet hours. These assert defects, not repaired
behavior or physiological accuracy. `bugs.md` owns the exact cases. Historical/backdated weight
inclusion in charts/means and exclusion from pricing/TDEE is already the selected contract;
"count in trends or history-only" was a false dichotomy, not a missing product decision.

Akshat selected health quiet-hours protection, hidden uncalibrated strain targets and explicit
food-day completion for advice/TDEE. Implementation remains deferred. Readiness requires exact
quality/history contracts and genuine task-layout approval, not more vendor-score imitation.
The TST-only richer-night guard intentionally protects pruned replay of the same night, and
manual overrides already bypass it; investigate replacement of a genuinely different shorter
night rather than treating every shorter result as wrong. RHR's whole-bpm noise floor on a
continuous mean is a quality-policy question, not proven integer rounding of the stored mean.
Similarly, zero above-rest session energy can be legitimate; do not force positive calories
from missing/conflicting HR or treat a new credit policy as a numerical repair.

## Ranked Build 88 Proposal Appendix

Only the temperature repair and design planning are already requested scope. The remaining items
below are researched candidates, pending product selection and implementation go-ahead. Priorities
describe integrity and usefulness, not promised percentage accuracy gains.
`build-88-plan.md` reconciles these proposals with both attached analyses and maps them into
B88-01..12; `todo.md` is the sole execution checklist. In particular, attachment-specific
weights, error ranges, tissue claims and automatic target changes are not adopted by this review.

### R01: Temperature Integrity (First)

- **Benefit:** stop unsupported physiology influencing recovery and alerts.
- **Files:** protocol records; `lib/compute/derive_prepare.dart`, `onehz_pipeline.dart`,
  `crossday_pipeline.dart`, derivation engine; repository/UI/export/notification consumers.
- **Inputs:** existing verified family identity and absence semantics; no new guessed channel.
- **Tests:** unknown counts cannot affect physiology, missing is not zero, independent families,
  served-version/UI legacy handling and retained raw history.
- **Gate:** Trends/Sleep row hiding with retained history is selected; other unique removals
  still need approval. Review algorithm bump, all consumers and recomputation before code.

### R02: Missing Load And Honest Zero (First)

- **Benefit:** avoid fictitious rest/recovery in partially missing training history.
- **Files:** `_denseDailyTrimp`/load assembly in `lib/compute/crossday_pipeline.dart`, analytics
  `onehz/clinical/load_trimp.dart`, downstream load/target/overreaching consumers.
- **Inputs:** real dated TRIMP plus coverage sufficient to distinguish an observed zero.
- **Tests:** completely unknown, partial gaps, skipped dates, genuine rest, DST and initialization;
  evaluate abstaining/split-history policies without inventing load.
- **Gate:** select the gap policy before code; version all changed derived outputs.

### R03: Goal Advice Without Tissue Certainty (First)

- **Benefit:** preserve useful tape/strength context without an unsupported fat diagnosis.
- **Files:** `lib/data/goal_plan.dart`, body/progress review and affected UI/research wording.
- **Inputs:** dated same-site measurements and comparable performance; no inferred muscle mass.
- **Tests:** waist-only noise, conflicting/sparse dates, weight gain/loss, unavailable protein and
  intake-floor cases; no automatic changes or generic extra-exercise advice at unsafe intake.
- **Gate:** approve replacement observation/advice and scope of eligibility safeguards. UI wording
  alone does not repair a recommendation branch; test the decision logic too.

### R04: HRV Continuity, Qualification And Method Identity

- **Benefit:** refuse sparse/gap-bridged primary HRV and prevent mixed-estimator baselines.
- **Files:** `lib/compute/onehz_pipeline.dart`, preparation/baseline reads, analytics HRV routines,
  repository, driver details and metric-series consumers.
- **Tests:** isolated pairs, rejected runs, timestamp dropouts, shared report seconds, each
  secondary path, method-specific history and repeated derive; independent ECG for accuracy.
- **Gate:** primary-only presentation is selected. Freeze continuity/window/night qualification,
  provenance persistence/schema needs and version boundaries before code.

### R05: Sleep Boundary And Early-Overlay Investigation

- **Benefit hypothesis:** fewer missed onsets/false sleep joins and clearer real coverage.
- **Files:** analytics sleep segment/stager, `substrate.dart`, preparation, sleep read/UI adapters.
- **Tests:** early HR versus early RR eligibility, no-data quarter, quiet wake, contact loss,
  corrected timings/naps; PSG boundary/stage comparison on held-out nights.
- **Gate:** deterministic rendering/window defects can be repaired separately; stage-threshold or
  learned-model improvements require reference evaluation and a versioned experiment.

### R06: Qualified Live Speed And Collection QA

- **Benefit hypothesis:** lower accepted-point-to-display latency with honest stale state.
- **Files:** native location/motion bridge, `lib/gps/`, active workout state/live UI.
- **Tests:** causal filter, timestamp/speed-accuracy admission, stop/resume, walking versus running,
  indoor estimates, background power/coverage, phone-sized display.
- **Gate:** preserve already implemented Build 87 changes, measure on phone before further tuning;
  no new always-on location permission or background guarantee assumed.

### R07: Personal Baselines And Readiness Validation

- **Benefit hypothesis:** more consistent personal deviation and less misleading interpretation.
- **Files:** analytics readiness/stress, orchestration and drivers/alerts; all strain callers if
  evaluating personal quiet HRR.
- **Tests:** training-only baselines, unusually high/low signals, removed temperature, mixed
  methods, bounded quiet-window sampling and held-out outcomes/false-alert rates.
- **Gate:** weights/quiet-HRR/scales are not self-validating; retain current coefficients until
  an experiment supports a selected replacement. No proprietary-score imitation objective.

### R08: Energy Ledger And Trend Calibration

- **Benefit:** deterministic no-double-counting first; improved trend robustness is a hypothesis.
- **Files:** `profile.dart`, `day_upkeep.dart`, profile history, nutrition store, workout calories,
  goal/review and relevant energy readers.
- **Tests:** units, dated weight, missing food/macros, gross/net, overlap, pauses, midnight,
  sensitivity to water/underlogging and longer-window holdouts.
- **Gate:** Budget/ACSM, TEF, lifting credit and target changes remain separate product decisions;
  no precise TDEE claim from improved fit to the same noisy intake/weight observations.

### R09: Measurement And Record Comparability

- **Benefit:** better repeatability and fewer invalid body/strength comparisons.
- **Files:** `body_log.dart`, `lift_log.dart`, `lift_progress.dart`, `progress_review.dart` and UI.
- **Tests:** site/date/unit alignment, Navy eligibility, identical/mixed-load/high-rep records,
  truthful stronger/flat/declining/incomparable headlines and plateau advice, partial measurement
  coverage, photos retained and import idempotence.
- **Gate:** optional effort/context fields or extra measurement prompts need design approval.

### R10: Experimental Outputs And Cross-Domain Insights

- **Benefit:** avoid medical/causal certainty while retaining available data.
- **Files:** secondary cardiac/respiration/circadian/CUSUM/MDC routines and any exposed readers,
  findings, progress summaries and notifications.
- **Tests:** units/windows/input provenance, eligible-family counts, no unqualified alarms,
  multiple testing/confounding, missingness, frozen baselines and clear refusal.
- **Gate:** hidden metrics stay hidden unless selected; oxygen, clinical rhythm/apnea diagnosis,
  exact muscle mass, measured VO2max and unverified temperature stay unavailable.

## Supplied AI Analyses: Claim Reconciliation

### Hardware, Time And Signal Quality

The long architecture analysis usefully flags temperature, but names the unknown field an optical
integrator without establishing that meaning. Keep it unknown. The actual
[decoder](packages/protocol/lib/src/records.dart) also deprecates `ppgRedIr` (a read straddling
another float) and `skinContact` (a float sign/exponent byte, not contact quality). These cannot
be repurposed as independent waveforms, wear flags or validated signal-to-noise gates.

Its proposed millisecond-counter clock regression does not match the decoder: `counter` is a
record counter, while `tsEpoch` is Unix seconds and `tsSubsec` is separate. The existing
[clock policy](lib/sync/sync_policy.dart) already correlates the band RTC and rejects implausible
times. Do not warp stored timestamps or fit a drift rate without evidence. Preserve the actual
transaction-commit-before-verbatim-HISTORY_END-ACK contract; this is not a new distributed
two-phase-commit protocol or a reason to add arbitrary `fsync` calls.

Apple provides raw motion APIs, contrary to the attachment's blanket access claim.
[Core Motion](https://developer.apple.com/documentation/coremotion/cmmotionmanager)
does not give our WHOOP history higher sampling rates. Nor does `CMPedometerData` expose a
phone-carriage confidence score: missing/zero phone steps are not proof the phone was absent.
Preserve existing interval ownership and qualified stillness/dense-wrist exceptions.
[Pedometer data](https://developer.apple.com/documentation/coremotion/cmpedometerdata)

### HRV And Recovery

The short analysis calls NREM-masked HRV the current headline; it is a secondary method. The
current primary uses five-minute windows across the sleep session, with the continuity/sparse
defects detailed above. Display fallback versus primary-only readiness is a real semantic issue;
Akshat selected primary-only headlines with labelled secondary details, not a switch to NREM.
The primary local-median cleaner differs from secondary quartile-deviation/spline correction;
the attachment's blanket local-MAD definition does not match either. Do not replace cleaners
without a separate validated experiment.
PRV/ECG differences depend on conditions, not a universal LF-down/HF-up law. One original
tilt-table study supports only its tested setting, not perfect daytime wrist PRV.
[Gil et al.](https://pubmed.ncbi.nlm.nih.gov/20702919/)

The analyses conflict on where the temperature weight should go. Use the existing available-input
renormalization, with its eligibility gates, for the integrity repair. If all other drivers
qualify, proportional weights are about 38.04% HRV, 27.17% RHR, 21.74% sleep and 13.04%
respiration. These are algebra, not calibrated optimal weights. Do not adopt the new 65%
coverage gate or an artificial dispersion floor; current nominal minimum is 50% plus two inputs.
Zero temperature weight must not leave it in baseline enrollment, drivers or other consumers.

The illness CUSUM is RHR-only; temperature affects other anomaly/illness paths. Audit those
actual consumers instead of removing the valid RHR detector. A heavy leg day must not trigger
an invented recovery penalty. Logged lifts can provide separate context. Even WHOOP describes
Strain as not directly determining Recovery.
[Official Strain](https://support.whoop.com/s/article/WHOOP-Strain?language=en_US)

### Sleep, Respiration And Medical Claims

Neither the proposed Cole-Kripke cutoffs nor forced stage durations have been validated on our
low-rate motion units. The original method is a trained actigraphy sleep/wake method, not a
drop-in four-stage classifier. Keep simple compatible candidates as experiments only.
[Cole and Kripke](https://pubmed.ncbi.nlm.nih.gov/1455130/)
The claimed universal 65-70% staging ceiling and excellent wake detection are not defensible;
compare like hardware, class definitions, populations and model versions. The full review
contains direct WHOOP 4 PSG evidence and newer Apple/Oura results without transferring them here.

SRI can describe regularity; its original study was observational and did not establish muscle
versus fat nutrient partitioning. Sleep boundaries themselves require validation. No added
rhythm thresholds, apnea diagnosis or hard spectral-duration gate inherits validity from an
ECG paper. The long attachment also alternates between 15% and 30% respiration artifact gates;
our RSA default is 30%, while other methods have different gates. Trace each caller.
[Original SRI study](https://pmc.ncbi.nlm.nih.gov/articles/PMC5468315/)

### Energy, Weight And Body Composition

Food/weight maintenance is useful context, not a mathematical gold standard or an automatic
target anchor. Intake omissions, water, changing body composition and interval choice bias it;
the 7,700 kcal/kg shortcut does not precisely identify metabolic adaptation. Preserve the
chosen Budget/ACSM comparisons and manually set targets.
[Hall's dynamic energy model](https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593/)

The long attachment misstates two current formulas: dividing Keytel's expression by 4.184
converts kJ/min to kcal/min, not the reverse; the TEF fallback credits known macros plus 5%
of unexplained label energy when a macro is missing, not 5% of all calories. Keytel's study
tested steady-state treadmill/cycle exercise, not our lifting estimates. No universal lifting
error percentage is justified.
[Original Keytel study](https://pubmed.ncbi.nlm.nih.gov/15966347/)

The proposed Kalman noise constants have no verified fit to this app. Smoothing weight cannot
separate water, muscle and fat. Keep the requested seven-day observed mean; a separate trend
experiment must handle elapsed time, gaps and lag. Existing Epley record eligibility is already
1-12 reps; a universal switch to ten is not a demonstrated repair. The attachment's recomp
decision matrix overstates tissue certainty. Waist and strength are observations, not proof of
hypertrophy, catabolism or fat gain.

### Precision And Citation Audit

Do not import either analysis's claimed app error bars, confidence probabilities or guaranteed
accuracy gains. No supplied matrix validates our decoder, windows or outputs. Older WHOOP and
Polar chest-strap papers are not WHOOP 4 BLE validation; a primary WHOOP cardiac paper explicitly
used WHOOP 2.0. The Oura temperature pilot measured finger skin and oral temperature, not core
temperature accurate to 0.13 degrees. Apple's 0.84 AF notification PPV refers to simultaneous
notification/ECG concordance; AF appeared on 34% of subsequently returned patches. None validates
new rhythm alerts here.
[WHOOP 2 study](https://pmc.ncbi.nlm.nih.gov/articles/PMC8160717/),
[Oura temperature pilot](https://pmc.ncbi.nlm.nih.gov/articles/PMC6883568/),
[Apple Heart Study](https://pubmed.ncbi.nlm.nih.gov/31722151/)

Some full-text opens were blocked or JavaScript-only; indexed primary abstracts/documentation
were used where accessible. Unresolved references and precise parameter provenance remain
unverified, rather than being promoted to facts. Correlation and group-level validation do not
establish individual precision in our app.

## Implementation And Validation Contract

### Before Changing Source

1. Select additional proposals and approve the visual direction. Temperature-row hiding and
   primary-only HRV presentation are selected; qualification policies remain to be frozen.
2. Specify each metric's semantic identity: source family, units, estimator, time window,
   coverage/artifact gates, baseline method and missingness. Different methods need explicit IDs.
3. Pin compatible reference data and evaluate licensing/consent/storage before collection. The
   current public-source approval is not approval to upload personal data or download/use a model.
4. Record acceptance metrics before tuning. Deterministic integrity defects should have exact
   invariants; physiological estimators need clinically/task-relevant error limits agreed from
   reference evaluation, not arbitrary percentages invented in this report.

### Evaluation Design

- Use participant-level holdouts for general models and chronological held-out nights/sessions
  for personal calibration. Randomly splitting adjacent epochs leaks the same night's physiology.
- Baselines use only past eligible observations; never future nights, held-out labels or post hoc
  filters selected for the desired result. Report development and final test results separately.
- Report bias, MAE/RMSE, agreement limits and uncertainty; correlation alone is inadequate.
  Cluster uncertainty by participant/night rather than treating repeated epochs as independent.
- For sleep, include wake specificity, per-stage precision/recall/confusion and observed coverage.
  For detectors, include false positives per observed day/night and abstention. For live features,
  include actual latency, dropouts, battery and recovery behavior.
- Include sparse/missing data, stationary-but-awake, exercise motion, poor contact, phone absent,
  profile changes, DST and travel; state subgroup limits rather than claim universal accuracy.
- Compare simplest transparent baseline, current algorithm and candidate on the same frozen
  inputs. Improve error at comparable coverage, or explicitly show the coverage/error tradeoff.
- A personal diary/device soak establishes operational reliability and boundary plausibility,
  not population validation or clinical precision. PSG/ECG/calorimetry may require additional
  equipment or professional participation; unavailable references limit the claims we can make.

### Versions, History And Release

Any changed analytics output requires an explicit `kAlgoVersion` decision under repo rules.
New metadata may require additive/idempotent schema handling; no schema bump is presumed by
this research. Never mix old/new estimator baselines silently, rewrite old immutable results,
erase raw bytes, or display an obsolete result as freshly corrected. Recompute only days with
usable retained inputs; identify unrecomputable history and legacy values honestly.

Keep cold/warm sync, cancellation, read-after-commit, served-version ceilings, import/recovery
and repeat-derive invariants in regression coverage. Only after source tests, full local/cloud
checks, reviewed packaging and physical acceptance should a new IPA be called ready. This report
changed no code, coefficients, targets, permissions, stored results or IPA.

## What To Keep And What Not To Promise

Keep the local-first architecture, explicit missing values, qualified real observations,
seven-calendar-day means, manual goals, separate calorie models, comparable lifting records,
independent photo selection, and feature-preserving navigation. Keep unavailable metrics
unavailable until their input and method are verified.

The strongest next build would be **more trustworthy first, more personalized second**:
invalid-temperature abstention, honest gaps, comparable methods and restrained advice, followed
by measured sleep/HR/speed experiments. No source reviewed establishes that our available signals
can reproduce every official algorithm or make sleep, calories and tissue change precisely known.

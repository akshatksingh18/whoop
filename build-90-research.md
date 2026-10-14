# Build 90 Research Pass: Findings

**Status:** First research pass complete. Research and analysis only: no code, formula or
version changed. Brief: `build-90-research-prompt.md`. Akshat assigned this pass to Claude
because Codex's usage was exhausted; Claude is therefore the single research agent for
Build 90 (decision D3 in `todo.md`). Each verdict needing Akshat's approval is marked; nothing
here is implementation approval. Sources were accessed 2026-10-14.

**Method and limits.** Each question started from the current code (symbols named below), then
public primary sources: standards, peer-reviewed studies, Apple and Dart documentation and the
public WHOOP 4 protocol work. Where only an abstract or a secondary summary was reachable, the
verdict says so and does not lean on unverified numbers. No search contained Akshat's data,
and his own data was read only on this PC, from a read-only export, for the local
measurements (A1, E1, D1). Their exact values stay in the git-ignored `build/research-local/`;
this file states only what they decided.

## Summary

| ID | Topic | Answer | Recommendation | Akshat's approval |
|---|---|---|---|---|
| A1 | Beat continuity | Definite (measured) | Keep the current pairing; no withholding rule; record the omitted-beat share as a quality field | No (no change to the number) |
| A2 | Spectral methods | Conditional | Scaling is correct; skip spectral segments that contain a gap | Yes (breathing rate, staging features) |
| A3 | Consumers | Definite | Map in A3 | — |
| B1 | Restlessness | Definite (method) | Replace "distance from 1 g" with arm-angle change, 5° (van Hees 2015) | No (secondary display) |
| B2a | Awakenings | Definite (convention) | One definition: wake runs of 5 min or more, labelled as such | No |
| B2b | Sleep debt in sleep need | Conditional | Add a quarter of the gap per night, not all of it; remove the unsourced 45-min strain bonus | Yes (sleep need, bedtime) |
| B2c | Short REM bouts | Needs measurement | Keep; totals stay the per-second labels | No |
| B2d | Cycles | Definite | Absent when stages are unavailable, never 0 | No |
| B2e | Coverage for durations | Definite | Show "at least" with the gap, never a silent full value | No |
| B3 | Stage validity | Needs measurement | Keep cutoffs; keep "estimate" wording | No |
| C1 | Travel and time zones | Definite (rules); one platform check | Store each day's IANA zone; boundaries from a recorded zone timeline | Decided (D2) |
| C2 | Minutes worn | Definite (convention) | One definition with a 2-minute bridge; separate charging, off-wrist and not-yet-synced | Decided (D2) |
| C3 | Timestamps | Conditional | A food time means when eaten; keep every weigh-in with its time | Yes (weight-of-the-day rule) |
| D1 | Quiet-day strain | Bug found; form needs the app's own code | Fix the Build 89 floor so it reaches the stored strain; compare forms with the app's Dart functions | Later (after the comparison) |
| E1 | R10-lite history | Definite (measured: absent) | No change needed; R10 seconds do not occur in the retained data | No |
| E2 | RR values per record | Definite | Cap 1 Hz historical records at 4; give R10 its own bound | Decided (D2) |
| E3 | Unknown sensor values | Definite | Store NULL, never 0; drop legacy oxygen rows from CSV | Decided (D2) |
| E4 | Short bursts | Needs measurement | Instrument; do not enforce the gate yet | No |
| E5 | Green optical signal | Definite | Keep off | No |
| F1 | iOS background budgets | Definite (facts); Needs measurement | Per-wake timing instrumentation | No |
| G1 | Run/walk energy | Definite | ACSM pair matches ACSM; add its speed ranges | No |
| G2 | Lifting/calisthenics MET | Definite | Calisthenics 3.8 matches; "bodyweight" should be 3.0, not 3.5 | Yes (lifting calories line) |
| G3 | Digestion | Definite | Constants match the low end; no food-type adjustment | No |
| G4 | Food/weight maintenance | Conditional | Qualify estimates under 6 weeks; show the uncertainty | Yes (estimate wording/number) |
| G5 | Navy body fat | Definite | Matches; show ±3.5 % body fat | No |
| G6 | Rep-adjusted estimate | Conditional | Lower the estimate's rep cap from 12 to 10 | Yes (strength verdicts) |
| G7 | HR plus movement burn | Definite | Do not build without individual calibration | No |
| H1 | GPS live speed | Needs measurement | Use `speedAccuracy`; outdoor test protocol below | No |
| I1 | Deferred experiments | Definite | None is evidence-ready; no change | No |

The unsourced constants this pass found are collected at the end.

## A. Heart and HRV

### A1. Beat continuity after dropouts

1. **Question.** How should RMSSD treat genuine dropouts when WHOOP 4 stamps each beat with
   its 1 Hz record's time, and does the 1000 ms tolerance bias RMSSD?
2. **Current behaviour.** `kBeatAdjacencyTolMs = 1000` (analytics `onehz/util.dart`): two
   beats are successive when their stamp difference is within 1000 ms of the later beat's
   interval. The same value is `correctRr`'s re-anchor gap. Nightly gates: windows need 180 s
   covered, 120 pairs and at most 20% artefacts; a night needs 6 windows and 15% of the session.
3. **Evidence.**
   - Task Force of the ESC/NASPE (1996) is the short-term standard (about 5-minute
     recordings, edited for ectopy and artefact). Citation verified; its text was not reached.
   - Munoz et al. (2015, PLOS ONE, 3,387 adults): RMSSD from 10 s, 30 s and 120 s ECG agreed
     with 240–300 s; agreement was near perfect at 120 s (r = 0.986). The current 180 s window
     is above that.
   - A 2020 *Sensors* study simulating 0–70% missing data (30 s to 4 min windows) found missing
     values had a small effect on RMSSD.
   - *J Sports Sci Med* (2022; 178 participants): uncorrected artefacts above 0.9% of the
     signal significantly biased RMSSD, and one artefact raised it by 413% supine. Wrongly
     joined beats are far more damaging than dropped ones.
   - Lipponen and Tarvainen (2019) classify beats from successive-difference distributions; a
     2024 comparison found RMSSD was estimated better without interpolation beyond 50% missing.
4. **Answer: Conditional.** The 1000 ms value is fixed by the band's timing resolution: any
   tighter value rejects truly successive beats, which Build 89's regression tests prove.
   One gap remains. When a single beat is missing from a record that is otherwise present, the
   next beat's interval is still genuine, so the range and ectopic filters cannot catch it. If
   that interval is under 1000 ms, the timing test cannot catch it either, and the pair becomes
   a lag-2 difference.
   - **Bounding the bias.** With a share *f* of lag-2 pairs, MSSD = (1 − *f*)·MSSD₁ +
     *f*·MSSD₂. For uncorrelated intervals MSSD₂ = MSSD₁. For a respiratory oscillation with a
     period of *P* beats, MSSD₂/MSSD₁ = (1 − cos 4π/*P*)/(1 − cos 2π/*P*). That ratio peaks
     at 2, at *P* = 4 (for example 15 breaths a minute at 60 bpm).
   - **The bias in numbers.** RMSSD is inflated by at most √(1 + *f*) − 1 ≈ *f*/2. That is
     2.5% at *f* = 5% and 4.9% at *f* = 10%.
5. **Recommendation.**
   - **(a) Record continuity.** Pair beats only within one 1 Hz record or across two
     consecutive records. A missing record splits the run regardless of timing.
   - **(b) Estimate omissions.** Per record, beats expected ≈ HR/60. The night's omitted share
     is 1 − reported/expected, summed over the session.
   - **(c) Withhold above 10%.** Withhold the nightly HRV when that share exceeds 10%, which
     caps the derived bias at under 5%. Say why on screen through the existing `hrvWhy` reason
     line.
   - **(d) No interpolation.** Keep correction by deletion, never interpolation.
6. **Impact.** The nightly HRV (a headline and a readiness input), rolling curves, PRSA and the
   irregular-rhythm screen. Rule (c) can withhold nights, so it **needs Akshat's approval**.
   `kAlgoVersion` must change; only retained inputs recompute.
7. **Tests.**
   - Synthetic record streams with omitted beats at *f* = 0, 5% and 15%: check the bias bound,
     and that the night is withheld above 10%.
   - A missing record splits the run.
   - The Build 89 record-stamped tests still pass.
8. **Confidence:** medium. The bound is a derivation; the share in real WHOOP 4 data needs a
   local count.

**Local measurement (supersedes recommendations (b)-(c) above).** Two weeks of retained
nights were checked on this PC.
- **Every night drops a similar share of beats, and it is above 10%.** Reported intervals
  cover visibly less time than the sleep window, so the band drops beats together with their
  intervals. A 10% rule would therefore withhold every night.
- **The per-beat timestamp can't identify a dropped beat.** Its offset from the interval
  repeats every whole second.
- **A guaranteed-adjacent subset exists.** Pairs from consecutive records whose interval is
  at least 1111 ms (or both beats in one record) cannot hide a dropped beat, because two
  intervals would not fit between the record stamps.
- **That subset gave nearly the same RMSSD as all pairs.** The mean ratio was within 1%, and
  the per-night spread was within about ±9%, in both directions.
- **So the bias is small and not one-sided.** Keep the current pairing and drop the
  withholding rule.
- **Recommendation:** store each night's omitted-beat share as a quality field, so a band or
  firmware change that raises it becomes visible. No headline change, so no approval needed.

### A2. Frequency-domain methods under gaps

1. **Question.** Is the Lomb-Scargle power scaling correct for gapped beat series, which time
   axis should be used, and what coverage makes a band valid?
2. **Current behaviour.** `lombScargle` (`util.dart`, Press and Rybicki form) scales the
   periodogram by 2·span/(n − 1). `_welchBandPower` (`clinical/hrv_freq.dart`) averages
   segments of 10 cycles of each band's lowest frequency, with 50% overlap and at least 16
   points. HF is withheld above the artefact gate. Times are cumulative NN times, re-anchored
   to the record stamp across gaps (`correctRr`). Other users of the method: `resp_rate.dart`,
   `cardio_stager.dart`, `cardiac_coherence.dart`.
3. **Evidence.**
   - Laguna, Moody and Mark (1998, IEEE TBME): the Lomb periodogram on uneven samples
     outperformed interval and resampled spectra near half the mean sampling rate.
   - Clifford and Tarassenko (2005): removing ectopy is essential; resampling and phantom-beat
     replacement reduce accuracy even at low artefact levels; Lomb gave a less noisy spectrum
     in sleep.
   - Moody (1993, PhysioNet): the Lomb approach needs no resampling.
4. **Answer: Conditional.**
   - **Scaling: correct, keep it.** For a sinusoid of amplitude *A*, the peak height is
     about *n*·A²/4 and its width about 1/span. Multiplying by 2·span/(*n* − 1) gives a power
     of about A²/2, its variance, whatever share of the record is present. So gaps do not bias
     the scaling.
   - **Time axis: the problem.** Within a run, beat-sum time is exact to the RR precision.
     Across a gap, re-anchoring to a 1 Hz stamp can shift the phase by up to 1 s. For HF
     periods of 2.5–6.7 s that is 54–144° of phase, which smears power in any segment that
     contains a gap.
5. **Recommendation.**
   - Skip a Welch segment that contains a re-anchor (a gap) for the HF band, respiration and
     the staging features, and require at least 90% beat coverage in each counted segment.
     This follows Clifford and Tarassenko's "remove, don't replace".
   - Keep the current scaling and segment lengths.
   - Withhold the band when no segment survives.
6. **Impact.** LF/HF and nu (stored, coach); breathing rate (shown on Sleep and Trends);
   staging features in `cardio_stager` (stage minutes are headlines). **Needs approval**
   because breathing rate and stages can move. `kAlgoVersion` must change.
7. **Tests.**
   - A synthetic sinusoid with and without gaps: band power matches the variance within 5%.
   - A segment containing a gap is skipped.
   - Coverage under 90% is withheld.
8. **Confidence:** medium-high for the scaling (derived), medium for the coverage figure.

### A3. Which outputs each issue reaches

- **A1 (beat pairing):** the nightly HRV (headline, readiness input), the rolling-RMSSD
  timeline and 24/7 curve, daytime HRV, PRSA deceleration capacity and the irregular-rhythm
  screen.
- **A2 (spectra):** LF/HF and nu (stored, coach), breathing rate (shown), the
  `cardio_stager` features (stage minutes, shown) and cardiac coherence.
- **Headline numbers that can move:** the nightly HRV, breathing rate and stage minutes, each
  approved per item above.

## B. Sleep

### B1. Restlessness

1. **Question.** Is the restlessness map's "distance from 1 g" valid across postures and
   sensor scale?
2. **Current behaviour.** `derivation_engine.dart` averages |‖a‖ − 1 g| over 1 Hz samples per
   bucket (absolute value; negatives are not clipped as in ENMO).
3. **Evidence.**
   - **The offset problem.** At rest the magnitude equals the sensor's gain and offset error,
     so a 2% gain error reads as 0.02 g of "movement" all night. Bakrania et al. (2016, PLOS
     ONE) found wrist ENMO sedentary cut-offs of 5.7 mg (ActiGraph) versus 8.7 mg (GENEActiv)
     for the same behaviour.
   - **A scale-free alternative.** van Hees et al. (2015, PLOS ONE, 4,094 adults) defined
     sustained inactivity as no change in arm angle greater than 5° for at least 5 minutes. An
     angle is a ratio of axes, so gain cancels. van Hees et al. (2018, *Sci Rep*) built the
     HDCZA heuristic on z-angle change.
4. **Answer: Definite (method).** A magnitude-minus-1 g index measures calibration as much as
   movement. Arm-angle change does not.
5. **Recommendation.** Compute the arm angle per second (atan of az over the horizontal
   magnitude). A 5-minute window is restless when the angle changes by more than 5° within
   it. The map shows the share of restless windows. Keep the shipped relative-stillness
   breathing rule separate.
6. **Impact.** The restlessness map on Sleep, a secondary display. `kAlgoVersion` must change.
7. **Tests.**
   - A static vector with 2% gain error reads 0 restless.
   - 10° rotations are counted.
   - Absent acceleration is skipped.
8. **Confidence:** high for the method, medium for 5° at 1 Hz (van Hees used 5 s epochs).

### B2. Sleep accounting

**B2a. Awakenings.** `kSustainedAwakeningSec = 300` (`sleep/segment.dart`) is a labelled
choice.
- **Evidence.**
  - Polysomnography protocols count an awakening from 2 epochs (1 min) and a long one from 10
    epochs (5 min), for example lemborexant and ACT-541468 trial protocols.
  - The DiMe core sleep measures require any minimum to be stated.
  - Wrist devices detect wake poorly: specificity was 0.18–0.54 across seven devices (Chinoy
    et al. 2021, *Sleep*).
- **Answer: Definite (convention).** Keep 5 minutes as the single definition, the long-
  awakening convention, and label it "awakenings of 5 minutes or more". Remove any second
  count. No approval needed.

**B2b. Sleep debt and sleep need.**
- **Current behaviour.**
  - `sleepDebt` (`human/sleep_regularity.dart`) is the 75th percentile of free nights minus
    the median of recent nights, honestly labelled as not Kitamura's measure.
  - `sleepNeed` (`human/coaching.dart`) adds all of that gap every night.
  - It also adds a strain bonus of up to 45 minutes and clamps the result to 6–11 h.
- **Evidence.**
  - Kitamura et al. (2016, *Sci Rep*): optimal sleep duration came from nine nights of
    12-hour sleep opportunity. One hour of potential sleep debt took about four days to
    recover. The sample was 15 healthy young men; the four-day figure is the authors'.
  - Van Dongen et al. (2003, *Sleep*): deficits accumulate across 14 days of restriction while
    slow-wave physiology plateaus. Their model is excess wakefulness over 15.84 h.
  - Neither gives a validated per-night repayment constant for consumer use.
- **Answer: Conditional.** Adding the whole gap every night double-counts it across nights.
  Kitamura's recovery time implies repaying about a quarter of it per night.
- **The strain bonus.** This pass found no source for its 45-minute size or its linear shape.
- **Recommendation.**
  - Add gap ÷ 4 per night.
  - Remove the strain bonus until a source supports it, since an unsourced number is an
    assumption.
  - Keep the clamp only once it is checked against a population recommendation (not verified
    in this pass).
- **Impact.** Sleep need, the recommended bedtime and sleep performance. **Needs approval.**
  `kAlgoVersion` must change. Confidence: low-medium (one small study).

**B2c. Short REM bouts.** Scoring rules are per 30-second epoch and set no minimum REM bout,
and wrist staging agreement is mixed (Chinoy 2021).
- **Answer: Needs measurement.** Only a reference recording can show whether short REM at this
  resolution is real.
- **Recommendation.** Keep the stager's smoothing as its documented rule. Totals always equal
  the per-second labels.

**B2d. Cycles.** A NREM–REM cycle needs REM to be detected. When stages are unavailable, cycles
are absent ("—"), never 0 (invariant 3). Definite.

**B2e. Coverage before a duration.** With a recording gap *g* inside the sleep window, true
total sleep lies between the measured total and the measured total plus *g*. That bound is
exact, so no threshold has to be invented.
- **Recommendation.** Show "at least *N* h" with the gap length whenever *g* > 0. Keep the
  existing 50% floor for saving a correction.
- Definite.

### B3. Stage validity

- **Evidence.**
  - Chinoy et al. (2021, *Sleep*; 34 adults, seven devices): sleep sensitivity was above 0.93,
    wake specificity was low and stage accuracy was mixed.
  - WHOOP's own algorithm, against polysomnography:
    - Miller et al. (2020; 12 adults, 86 nights): four-stage agreement 64%, κ = 0.47;
      sensitivity 62% light, 68% SWS, 70% REM, 51% wake.
    - Miller et al. (2022, *Sensors*; WHOOP 3.0, 53 adults): 60% agreement, κ = 0.44.
  - These are WHOOP's own algorithm, not this app's local stager, so they show what wrist PPG
    plus motion can reach. They do not validate this code.
- **Answer: Needs measurement.** Only a reference recording can validate the local stager.
- **Recommendation.** Keep the cutoffs and the "estimate" wording. Do not tune to expected
  stage percentages. No approval needed.

## C. Time, minutes and travel

### C1. Travel and time zones

1. **Question.** How are days grouped when the phone changes time zone, so that travel never
   overlaps, gaps or shifts days?
2. **Current behaviour.** `dayLabelOf` and `localDayStartSec` (`data/day_label.dart`) use the
   process's current local zone. Re-deriving a retained day after travel therefore uses the
   new zone and can move that day's edges. The app already depends on `timezone` (^0.9.4)
   and `flutter_timezone` (^3.0.1).
3. **Evidence.**
   - HealthKit records the creating zone per sample (`HKMetadataKeyTimeZone`, an IANA name).
     That is the industry precedent for storing the zone with the data.
   - Apple: `NSTimeZone.local` updates without notice. `NSSystemTimeZoneDidChange` signals a
     change. `UIApplication.significantTimeChangeNotification` covers midnight, DST and
     zone shifts.
   - Dart's `DateTime` knows only UTC and the device's local time. `package:timezone`
     supplies the IANA database (`TZDateTime`), and `flutter_timezone` supplies the device's
     zone name.
   - The Sleep Regularity Index (Phillips et al. 2017, *Sci Rep*) compares sleep or wake at
     instants 24 h apart, so on absolute time it is unaffected by zone labels.
   - Fischer, Klerman and Phillips (2021, *Sleep*): clock-based regularity metrics have
     different properties from consecutive-day ones.
4. **Answer: Definite (rules), plus one platform check.** It is not established whether a
   running Dart process sees a zone change without a restart. That needs one phone test.
5. **Recommendation: the storage and grouping rules.**
   - **R1. Keep a zone timeline.** Record a zone timeline of (instant, IANA zone): at first
     launch, on `NSSystemTimeZoneDidChange` and significant-time-change, and on every
     foreground and sync as a check. Store each day label with its zone and UTC offsets at
     start and end.
   - **R2. One day per instant.** Every instant belongs to exactly one day. A day's
     boundaries are the local midnights of the zone in effect at that instant.
   - **R3. Labels never repeat or go backwards.** If travelling west puts the clock back
     before the last midnight, the current day continues until the next local midnight, so it
     lasts more than 24 h. Going east past a midnight, or across the date line, can skip a
     label. A date you never lived has no row.
   - **R4. Re-derive with the stored zone.** Re-derivation uses each day's stored zone, never
     the current one.
   - **R5. DST from the IANA rules.** DST days are 23 h or 25 h.
   - **R6. Nights go to the wake-up day.** A night belongs to the day containing its wake
     time, as now.
   - **R7. Regularity across zones.**
     - Sleep regularity is computed on absolute instants, so jet lag correctly shows as
       irregular.
     - Bedtime consistency uses each night's local clock, and excludes nights that span a zone
       change (their clock times are not comparable).
   - **R8. Show the zone.** Show the zone abbreviation on any day whose zone differs from
     today's.
6. **Impact.** Every per-day metric, plus a new additive storage table, migration, and backup
   and export fields. No change for days without travel. `kAlgoVersion` changes only if a
   retained day's grouping changes. Decided by Akshat (D2).
7. **Tests.**
   - Westward and eastward changes before and after midnight; the date line.
   - DST spring and autumn.
   - A zone change during sleep.
   - Re-derivation after returning home.
   - Backup round-trip of the zone table.
   - A phone check: change the zone with the app open, then in the background.
8. **Confidence:** high for the rules, medium for the runtime pickup until tested.

### C2. Minutes worn

1. **Question.** Settle one definition of a worn minute, and separate "off" from "not yet
   transferred".
2. **Current behaviour.**
   - `metric_series` `worn_min` counts minutes with any record.
   - The day wear block bridges runs, treating a gap over 120 s as off.
   - Load gates read `worn_min`: at least 16 h for an observed day (`crossday_pipeline.dart`),
     and 0.7 × epochs elsewhere.
3. **Evidence.**
   - Choi et al. (2011, MSSE; calorimeter room, 49 adults and 76 youth): a 90-minute window
     with a 2-minute interruption allowance reduced wear misclassification. That is the
     standard precedent for tolerating brief interruptions.
   - Optical devices check skin contact and pulse presence, which patent literature describes
     as distinct off-wrist and worn checks.
4. **Answer: Definite (convention).** A worn minute is a minute with at least one record after
   bridging record gaps of up to 2 minutes (Choi's 2-minute allowance). One function serves
   both readers.
5. **Recommendation.** Classify non-worn time into three states:
   - **Charging:** from the `band_events` charging events.
   - **Off-wrist:** from the WRIST events.
   - **Not yet synced:** any time after the newest committed record (the sync frontier).
     This is never shown as "off".
6. **Impact.** Trends wear, the day screen, and the observed-day gates for load and strain:
   days near the 16 h gate can change. `kAlgoVersion` must change. Decided by Akshat (D2).
7. **Tests.**
   - A 90 s gap is bridged; a 3-minute gap is not.
   - A charging event and a frontier gap are classified.
   - Both readers return the same count.
8. **Confidence:** medium-high.

### C3. Timestamps that mean two things

- **Current behaviour.**
  - A past-day dinner is stamped 19:00.
  - Quick add on a past date stamps the current time, so the field has two meanings.
  - `putWeight` replaces the day's row, so "latest" means "last saved".
- **Evidence.** HealthKit samples carry the time the data represents (start and end, an
  instant when equal) and cannot be changed afterwards. This pass found no documented
  convention for a "weight of the day".
- **Answer: Conditional (policy).**
- **Recommendation.**
  - **Food time.** A food entry's time always means when it was eaten. Quick add on a past
    date uses that meal's default time on that date. The logged-at time is stored separately.
  - **Weight.** Keep every weigh-in with its time (additive). Define the day's weight
    explicitly: either the first reading of the day (most consistent, before food) or the
    last. Show which rule applies.
- **Impact.** Food ordering, and Body and weight trends. **Akshat's decision:** the day's
  weight is the first reading of the day; every reading is kept with its time.

## D. Strain and load

### D1. The quiet-day baseline

1. **Question.** What baseline should day strain subtract, and is a personal one better?
2. **Current behaviour.**
   - Net TRIMP = whole-day Banister TRIMP − waking minutes × *q*·*y*(*q*), where *q* is the
     day's measured quiet heart-rate reserve (`dailyQuietWakingHrr`, clamped). The fallback
     is 0.20.
   - It is mapped to 0–21 with `maximalNetTrimp = 400` and `strainCurvature = 15`
     (`clinical/load_trimp.dart`).
   - Build 89 added a floor from finished workouts' net TRIMP.
3. **Evidence.**
   - **Banister TRIMP.** Weighted by heart-rate reserve with 0.64·e^(1.92·x) for men;
     sources disagree on the women's coefficient (0.86·e^(1.67·x) versus 0.64·e^(1.67·x)).
   - **Edwards TRIMP.** Counts only minutes above 50% HRmax, weighted 1–5 by zone. Its
     validity varies by sport: strong against session RPE in some, about 30% of variance in
     speed skating.
   - **Lucia TRIMP.** Anchors zones to ventilatory thresholds.
   - **WHOOP.** Publishes a log 0–21 scale, with 24 h at maximum heart rate reaching 21, but
     no formula.
   - No source subtracts a whole-day baseline. That is this app's own construction.
4. **Answer: Needs measurement (local).** Subtracting the baseline across all waking minutes
   lets below-baseline minutes cancel workout minutes; that was Build 89's 0.0-strain cause.
   The obvious alternative, subtracting per minute (Σ max(0, *x*·*y*(*x*) − *q*·*y*(*q*))),
   inflates quiet days instead. With *q* at the day's median and a spread of 0.05 HRR, about
   960 waking minutes add roughly 31 net TRIMP, which maps to about 5.7 strain with no
   exercise at all.
   Neither form can be justified without comparing both on real days.
5. **Recommendation.**
   - Keep the Build 89 session floor.
   - On retained local days, compute both forms against labelled quiet and workout days, and
     choose the form whose quiet days stay low and whose workout days order correctly.
   - Verify the women's coefficient against Banister's own publication before relying on it.
   - The strain target stays withheld.
6. **Impact.** Day strain (headline). Any change **needs approval** after the measurement.

**Local measurement.** It found a Build 89 bug rather than an answer. Stored day strain is
0.0 on several retained days whose walks carry their own session strain, because the session
floor is applied after the day's strain has been copied into the stored scalars (`bugs.md`).
Fix that first. A Python re-implementation of strain did not reproduce the stored values
closely enough to choose a form. The comparison must run the app's own Dart functions over
the export (a local test harness), which belongs to Build 90's engine work.
7. **Tests.** Quiet-day, workout-day and mixed-day fixtures, under both forms.
8. **Confidence:** high that it needs measurement; the current floor is the safe interim.

## E. Band data, decoding and transfer

### E1. Older R10-lite heart rate

- **Current behaviour.** `ble_engine.dart` decodes R10 (`parseR10Lite`) into a `Sample` with
  HR and RR and no acceleration. It reaches legacy `samples`, not the 1 Hz substrate.
- **Evidence.**
  - The public OpenStrap protocol notes describe the 1 Hz R24 record as the bulk of a sync.
  - The community reverse-engineering guide says RR byte interpretation is not fully
    documented.
  - The R10 field map is this repo's own decoder.
- **Answer: Definite (measured).** No R10-only second occurs in the retained data, so the
  path below is not needed now. Re-check if older imported history is ever added.
- **Original conditional answer**, kept for that case:
- **Recommendation.**
  - Bring R10 HR and RR into the substrate only for seconds with no R24 record (dedupe by
    second), tagged with `r10` as the source.
  - With no acceleration, those seconds cannot drive accelerometer-led sleep detection; they
    serve HR, resting HR and HRV.
  - Skip the work if the local count shows R10 is absent.
- **Impact.** Coverage of older days. `kAlgoVersion` must change if any retained day gains
  inputs.

### E2. RR values per record

- **Current behaviour.** `kMaxRrPerRecord = 8` (`protocol/records.dart`) gates the declared
  count. Values are read from byte 19 and kept only within 200–2500 ms. The constant is
  shared with the R10 form in `live.dart`.
- **Evidence from the layout in the same file.**
  - RR slots start at byte 19 and the green PPG field starts at byte 29, so only 5 int16 slots
    can exist.
  - Slots 6–8 would read the PPG and accelerometer bytes.
- **Evidence from physiology.** A 1-second record holds at most ⌈HR/60⌉ beats: 4 up to 240 bpm.
- **Answer: Definite.**
- **Recommendation.**
  - Cap v24/v12 1 Hz historical records at 4, as Akshat decided. A record declaring more
    yields no intervals (absent), as it does above 8 today.
  - Give R10 its own constant, so the change cannot affect that path.
- **Tests.**
  - Declared counts of 4, 5 and 8.
  - The bytes after slot 4 never become beats.
  - R10 is unchanged.

### E3. Unknown values stored as 0

- **Current behaviour.** For unconfirmed record versions, the optical fields (green and
  red/IR PPG, skin contact, SpO2 raw, skin-temperature raw, ambient) are written as 0, "the
  ADC-absent sentinel", and consumers gate on v > 0. Legacy `odi_per_hour`/`spo2` rows can
  remain in the CSV export.
- **Answer: Definite (invariant 3).**
- **Recommendation.**
  - Make these fields nullable from the decoder to the database. Every consumer tests for null
    instead of > 0.
  - Existing stored 0s for unconfirmed versions are read as absent.
  - The CSV export drops the legacy oxygen and ODI rows.
- **Tests.**
  - A v18 record produces nulls.
  - A v24 record keeps its values.
  - The CSV has no oxygen rows.
  - Backup and restore round-trip.

### E4. Short bursts

- **Current behaviour.** WHOOP 4 has `burstCountGateEnforced: false`, so a burst shorter than
  its announced count is committed and acknowledged, and the shortfall is totalled
  (Build 88).
- **Evidence.**
  - No public source documents the burst-count semantics. The OpenStrap PROTOCOL.md could not
    be retrieved.
  - An OpenStrap release note refuses a HISTORY_END trim when gate drops leave nothing
    persisted.
- **Answer: Needs measurement.**
- **Recommendation.**
  - Keep commit-before-acknowledge.
  - Log per burst: the announced count, records received, the first and last timestamps, and
    whether the next burst starts where this one ended.
  - If short bursts are followed by timestamp gaps, the data was lost. If they are resent,
    nothing was lost.
  - Do not enforce the gate until the logs show the band resends an unacknowledged burst;
    enforcing it otherwise risks an endless re-flood.

### E5. Green optical signal and retention

- **Evidence.** Breathing from PPG (Charlton et al. 2018, *IEEE Rev Biomed Eng*) relies on
  pulse-resolved modulation of the PPG waveform.
- **Why one value per second is not enough.**
  - The historical record carries one green value per second.
  - At 1 Hz the 1–2 Hz cardiac component aliases into the 0.2–0.4 Hz breathing band. So 1 Hz
    green cannot support breathing or pulse-wave measures.
- **Cost.** 2 bytes a second is 172,800 bytes a day before row overhead.
- **Answer: Definite.**
- **Recommendation.** Keep it off. The roughly three-day decoded retention stays; old raw input
  cannot be replayed, and the app never claims it can.

## F. Background execution on iOS

### F1. Time budgets

- **Evidence.**
  - Apple's Core Bluetooth guide (archived, 2013): a woken app has "around 10 seconds"; apps
    that spend too long are throttled or killed.
  - `BGAppRefreshTask` runs for up to about 30 seconds (Apple's wording as quoted on Apple's
    developer forums); developers report expiries after 2–5 seconds.
  - `BGProcessingTask` can run for minutes but can be interrupted, with no published limit
    (Apple DTS).
  - TN3115, as quoted on Apple's forums: from iOS 26, after a force-quit or the Control
    Center Bluetooth toggle, only AccessorySetupKit apps are relaunched. Developers report
    cases where this failed on 26.5.
- **Answer: Definite (facts), plus Needs measurement (this phone).**
- **Recommendation.**
  - Keep BLE wakes to transfer, commit and acknowledge only (as now), and leave calculation to
    processing tasks or the foreground.
  - Add per-wake timing lines to the file log: wake reason; start; transfer start and end
    with record count; commit; calculation start and end; and expiry.
  - Then measure three ordinary nights and one force-quit night.
  - Build on `background-sync-plan.md`.

## G. Energy, food, body and strength estimates

### G1. Run and walk energy

- **Evidence.** ACSM: walking VO₂ = 0.1·speed + 1.8·speed·grade + 3.5 and running VO₂ = 0.2·speed
  + 0.9·speed·grade + 3.5 (mL/kg/min, speed in m/min).
  - Secondary sources give the walking range as about 1.9 to 3.7–4 mph (50–100 m/min), and
    running as above 5 mph, or from 3 mph when jogging.
  - Cadence-based equations were less biased than ACSM walking (2020, 235 adults).
- **Check.** The app's ACSM pair (0.2 / 0.1 / 0.9 / 1.8 with 0.005 kcal per mL) matches. The
  Budget method (0.143 for running) is Akshat's accepted conservative estimate, not an ACSM
  claim; it stays labelled as such.
- **Answer: Definite.**
- **Recommendation.** Apply ACSM only within its speed ranges, and label walking or running
  outside them as an estimate.

### G2. Lifting and calisthenics MET

- **Evidence.** 2024 Adult Compendium (pacompendium.com, conditioning exercise):
  - 02022 calisthenics, moderate: 3.8;
  - 02054 resistance training, multiple exercises: 3.5;
  - 02052 squats/deadlift: 5.0;
  - 02056 body-weight resistance, general: 3.0;
  - 02057 body-weight resistance, high intensity: 6.5.
- **Check (`conservativeMet`, `lib/compute/profile.dart`).**
  - Weight training 3.5, calisthenics 3.8 and powerlifting 5.0 match.
  - "Bodyweight" is 3.5 but 02056 is 3.0.
  - "Functional" (3.5) has no matching code in that heading, and was not resolved in this
    pass.
- **Recommendation.**
  - Set "bodyweight" to 3.0.
  - Source or label "functional".
  - The home workout uses the Bodyweight type: 02056 describes this routine and is the lowest
    match (Akshat wants the low end).
- **Impact.** Only the separate lifting calories line; it never enters maintenance.
  **Approval** for the 3.5 → 3.0 change.

### G3. Digestion

- **Evidence.** Westerterp (2004, *Nutr Metab*, full text): diet-induced thermogenesis is 0–3%
  for fat, 5–10% for carbohydrate, 20–30% for protein and 10–30% for alcohol. A mixed diet is
  5–15% of daily expenditure. The review does not address fibre or processed food.
- **Check.** The app uses 20% protein, 5% carbohydrate, 0% fat and 5% unknown: the low end of
  each range, as intended.
- **Answer: Definite.**
- **Recommendation.** Make no food-type adjustment. This pass found no review-level evidence
  for one; the commonly cited single small trial was not verified.

### G4. Food and weight maintenance estimate

- **Evidence.**
  - Thomas, Heymsfield and colleagues (PMC3810417): the energy content of weight lost is
    dynamic. It was about 4,858 kcal/kg at week 4 and about 6,041 at week 6 in CALERIE, and
    approaches 7,700 only later.
  - Hall's dynamic models replace the static rule.
  - Day-to-day swings of 0.5–1 kg are common (NHS Grampian clinical guidance).
- **Answer: Conditional.** 7,700 kcal/kg overstates the energy imbalance behind early weight
  change.
- **Recommendation.**
  - Keep the Theil-Sen trend and its gates.
  - For windows under 6 weeks, show the implied range using 4,858–7,700 kcal/kg rather than
    one number.
  - It stays display-only.
- **Impact.** The maintenance estimate's number and wording. **Approval.**

### G5. US Navy body fat

- **Evidence.** Hodgdon and Beckett (1984, Naval Health Research Center report 84-11, DTIC
  ADA143890):
  - **Equation:** density = −0.191·log₁₀(abdomen − neck) + 0.155·log₁₀(height) + 1.032;
    standard error 3.52% body fat.
  - **Cross-validation:** 100 men, measurement error 2.70%.
  - **Inch form:** 86.010·log₁₀(abdomen − neck) − 70.041·log₁₀(height) + 36.76, which the
    app uses.
- **Answer: Definite.**
- **Recommendation.**
  - Keep the male-only gate and the dating rules.
  - Show "± 3.5 % body fat" beside the estimate.
  - Abstain for other sexes, since the female form needs the hip.

### G6. Rep-adjusted strength estimate

- **Current behaviour.** `setScore` (`lib/data/lift_progress.dart`) uses Epley up to 12 reps.
- **Evidence.**
  - Reynolds et al. (2006, JSCR): prediction is best from about 5 reps and degrades with
    more.
  - Mayhew et al. (2008, summarised in a 2026 review): equations are more accurate under 10
    reps.
  - LeSuer et al. (1997): high correlations but exercise-dependent error, with the deadlift
    underestimated.
- **Answer: Conditional.** Above about 10 reps the estimate is unreliable even for comparing
  sets of the same exercise.
- **Recommendation.** Lower the cap to 10. Sets of 11–12 reps fall back to comparing reps at
  the same load. Bodyweight sets stay estimate-free.
- **Impact.** Some strength verdicts move to "same-load" or "not comparable". **Approval.**

### G7. Calibrated HR plus movement burn

- **Evidence.**
  - Combined HR and acceleration (Brage branched equations) against doubly labelled water:
    with individual calibration, a small bias but wide individual error. In Assah et al. 2011
    the RMSE was 29.3 kJ/kg/day, and bias doubled with group calibration.
  - Keytel et al. (2005): HR equations need individual factors.
- **Answer: Definite.** Without an individual calibration test, the individual error is too
  wide.
- **Recommendation.** Do not build it. Maintenance excludes it, as now.

## H. GPS live speed

### H1. Live-speed filter

- **Current behaviour.** EMA time constant 5 s (`route_math.dart`), stop detection under 4 m,
  a 5 m distance filter and a 10 s stale rule.
- **Evidence.**
  - Apple: `speedAccuracy` ≥ 0 means speed ± that many m/s; a negative value means the speed
    is invalid.
  - Smartphone GPS walking speed read 0.18 m/s high versus an ankle accelerometer, with
    limits of −0.49 to 0.13 m/s (2025, JMIR).
  - Running distance was underestimated by up to 9% across eight sport watches (2020, JMIR
    mHealth).
- **Answer: Needs measurement.**
- **Recommendation.**
  - Use `speedAccuracy`: hide current speed when it is invalid, and show "±" when it is
    large.
  - Test outdoors on a measured route: a 400 m track, walking then running, steady and with
    stops. Compare the live speed and distance with the known lap. Adjust the time constant
    only if lag or noise exceeds the measured error.

## I. Deferred experiments

### I1. Each experiment

- **Personal quiet-HRR strain baseline:** covered by D1; needs local measurement.
- **Readiness weights and gates:** no validated public weights exist (vendor models are
  proprietary). Plews et al. (2012, *Eur J Appl Physiol*, two athletes) supports a 7-day
  rolling ln RMSSD against a personal smallest worthwhile change. That supports the existing
  approach, not new weights.
- **Kalman or EWMA weight smoothing:** an EWMA (α ≈ 0.1, the Hacker's Diet convention) and the
  current 7-day mean are both defensible, and neither is shown to be better. Keep the 7-day
  mean.
- **Replacement TDEE models:** Hall's dynamic model needs body composition inputs the app
  does not have reliably. Keep the current estimate (see G4).
- **ML or Cole-Kripke staging:** Cole-Kripke is actigraphy sleep/wake only, not stages, and
  wrist wake specificity is low (Chinoy). No change.
- **New stress or spectral thresholds:** no new evidence; no change.

## Constants With No Source Found In This Pass

These need a source, a derivation, or removal (or a clear "estimate" label) before Akshat's
"no assumptions" standard is met.

| Constant | Where | Status |
|---|---|---|
| Strain bonus to sleep need, up to 45 min, linear in strain | `human/coaching.dart` | No source; recommend removal (B2b) |
| Sleep need clamp 6–11 h and baseline clamp 7–9.5 h | `coaching.dart`, `crossday_pipeline.dart` | Not verified against a population recommendation in this pass |
| `maximalNetTrimp = 400`, `strainCurvature = 15` | `load_trimp.dart` | The app's own anchor table, not literature; label as calibration |
| `quietWakingHrr = 0.20` fallback | `load_trimp.dart` | Population placeholder; the measured personal level is used when present |
| "Functional" 3.5 MET | `profile.dart` | No matching Compendium code found |

## Sources

All accessed 2026-10-14. "Secondary" marks a figure read through an abstract, index or
summary rather than the full text.

- Task Force of the ESC/NASPE. Heart rate variability: standards of measurement. *Circulation*
  1996;93:1043–65. https://pubmed.ncbi.nlm.nih.gov/8598068/ (citation only).
- Munoz ML et al. Validity of (ultra-)short recordings for HRV. *PLOS ONE* 2015.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC4586373 (secondary).
- Error estimation of ultra-short HRV parameters: missing data from motion artefacts.
  *Sensors* 2020. https://doaj.org/article/f8b9d4ce0b054912b507497b6254f9a3 (secondary).
- Effect of artefacts on HRV. *J Sports Sci Med* 2022;21:260. https://jssm.org/21-2-260.p_d_f
  (secondary).
- Lipponen JA, Tarvainen MP. HRV time series artefact correction. 2019; implementation notes
  https://www.mathworks.com/matlabcentral/fileexchange/107779-hrv-artifact-correction
  (secondary).
- Laguna P, Moody GB, Mark RG. PSD of unevenly sampled data. *IEEE TBME* 1998;45:698–715;
  Moody GB, PhysioNet Lomb tools https://archive.physionet.org/physiotools/lomb/.
- Clifford GD, Tarassenko L. Quantifying errors in spectral estimates of HRV. 2005.
  https://metabase-lcp.mit.edu/pdf/CliffordTBE05.pdf (secondary).
- van Hees VT et al. Sleep duration from a wrist accelerometer. *PLOS ONE* 2015.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC4646630; van Hees VT et al. *Sci Rep* 2018
  https://discovery-pp.ucl.ac.uk/10055119/1/s41598-018-31266-z.pdf (secondary).
- Bakrania K et al. ENMO and MAD thresholds. *PLOS ONE* 2016.
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5051724/ (secondary).
- Chinoy ED et al. Seven consumer sleep trackers vs PSG. *Sleep* 2021;44:zsaa291.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC8343587 (secondary).
- Miller DJ et al. WHOOP sleep validation (2020) and six wearables (*Sensors* 2022;22:6317).
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC8226553/ (secondary).
- Kitamura S et al. Optimal sleep duration and potential sleep debt. *Sci Rep* 2016;6:35812.
  https://www.ncbi.nlm.nih.gov/pmc/articles/PMC5075948/ (secondary).
- Van Dongen HPA et al. The cumulative cost of additional wakefulness. *Sleep* 2003;26:117–26.
  https://pubmed.ncbi.nlm.nih.gov/12683469/ (secondary).
- Awakening and WASO definitions: insomnia trial protocols
  https://cdn.clinicaltrials.gov/large-docs/68/NCT04549168/Prot_000.pdf; DiMe core sleep
  measures https://datacc.dimesociety.org/ (secondary).
- Phillips AJK et al. Sleep regularity index. *Sci Rep* 2017;7:3216.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC5468315 (secondary); Fischer D, Klerman EB,
  Phillips AJK. *Sleep* 2021;44:zsab103 https://pmc.ncbi.nlm.nih.gov/articles/PMC8503839/
  (secondary).
- Apple: `HKMetadataKeyTimeZone`
  https://developer.apple.com/documentation/healthkit/hkmetadatakeytimezone; `NSTimeZone.local`
  https://developer.apple.com/documentation/foundation/nstimezone/local; HealthKit samples
  https://developer.apple.com/documentation/healthkit/hksample.
- `package:timezone` README https://dart.googlesource.com/labs/+show/refs/heads/formattingToDev/pkgs/timezone/README.md;
  `flutter_timezone` https://pub-web-s1.flutter-io.cn/documentation/flutter_timezone/1.0.8.
- Choi L et al. Wear and nonwear classification. *MSSE* 2011;43:357–64.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC3184184 (secondary).
- Banister TRIMP coefficients: https://betterworkouts.helpscoutdocs.com/article/12-what-is-training-load
  and https://forum.intervals.icu/t/bannisters-trimp/10200 (secondary; women's coefficient
  conflicts).
- Edwards TRIMP validity: https://doaj.org/article/0141258171714bbdb296ccdd64291dd5 and
  https://doaj.org/article/28b4bf6530a14657b1b539d18f18a617 (secondary).
- WHOOP Strain public description: https://www.whoop.com/thelocker/podcast-26-understanding-strain/
  (intended behaviour, not ground truth).
- OpenStrap: https://github.com/OpenStrap; community protocol guide
  https://github.com/bWanShiTong/reverse-engineering-whoop-post (secondary).
- Charlton PH et al. Breathing rate estimation from ECG and PPG. *IEEE Rev Biomed Eng*
  2018;11:2–20. https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7612521/ (secondary).
- Apple Core Bluetooth background guide (archived):
  https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html
  (full text); BGProcessingTask https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask;
  forum threads https://developer.apple.com/forums/thread/780956 and
  https://developer.apple.com/forums/thread/840468; WWDC19 session 707
  https://developer.apple.com/videos/play/wwdc2019/707/.
- ACSM metabolic equations: https://support.lifefitness.com/hc/ca/article_attachments/27331725370647
  and https://pmc.ncbi.nlm.nih.gov/articles/PMC7896743 (secondary).
- 2024 Adult Compendium, conditioning exercise: https://pacompendium.com/conditioning-exercise
  (full table).
- Westerterp KR. Diet induced thermogenesis. *Nutr Metab* 2004;1:5.
  https://pmc.ncbi.nlm.nih.gov/articles/PMC524030 (full text).
- Energy content of weight loss (CALERIE): https://pmc.ncbi.nlm.nih.gov/articles/PMC3810417/
  (full text).
- Day-to-day weight variation: https://nhsgrampian.org/service-hub/eating-disorder-mcn/patients--carers/anorexia---further-information/weight-fluctuation;
  The Hacker's Diet trend https://fourmilab.ch/hackdiet/www/subsubsection1_2_4_0_4_4.html.
- Hodgdon JA, Beckett MB. Navy body fat. NHRC report 84-11, 1984.
  https://apps.dtic.mil/sti/pdfs/ADA143890.pdf (secondary).
- Reynolds JM et al. *JSCR* 2006;20:584–92. https://www.unm.edu/~rrobergs/478RMStrengthPrediction.pdf;
  1RM equation review https://arxiv.org/pdf/2603.17495 (secondary).
- Assah FK et al. *Int J Epidemiol* 2011;40:112. https://academic.oup.com/ije/article/40/1/112/658727;
  Brage S et al. *PLOS ONE* 2015 (doi 10.1371/journal.pone.0137206); Keytel LR et al.
  *J Sports Sci* 2005;23:289–97 (secondary).
- Apple `speedAccuracy`: https://developer.apple.com/documentation/corelocation/cllocation/speedaccuracy;
  smartphone walking speed https://www.ncbi.nlm.nih.gov/pmc/articles/PMC12361537/; sport
  watch distance https://pubmed.ncbi.nlm.nih.gov/32396865/ (secondary).
- Plews DJ et al. *Eur J Appl Physiol* 2012;112:3729–41. https://pubmed.ncbi.nlm.nih.gov/22367011/
  (secondary).

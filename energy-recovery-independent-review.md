# Independent energy and recovery review

**Status:** Research and source audit complete; recommendations only. No app formula, stored
metric, algorithm version, dependency or release changed. Source examined: `9170201b` on
`build-90-codex`, algorithm 95. Evidence checked 2026-10-15. The user's explicit request for an
independent second review supersedes the first pass's single-researcher restriction for this task.

This reviews the supplied Claude response, not an unseen implementation of its proposed changes.
Its referenced research sections J/K were not in the reviewed checkout; they are now in
`build-90-research.md`, corrected after this review. No personal export was opened and
no personal measurements are reproduced here. All numerical examples below are synthetic.
Primary studies and authoritative definitions outside the supplied bibliography form the evidence
base. Some evidence was available only as a published abstract; that is not full-paper validation.

## Decision summary

- Keep the Mifflin resting estimate, conventional net exercise accounting, conservative strength
  estimates, run-step de-duplication and explicit separation of intake goals from expenditure.
- Reconsider the running budgeting coefficient: 0.143 produces 0.715 kcal/kg/km. A proposed 0.17
  produces 0.85, a defensible conservative choice for ordinary steady level running, not a
  demonstrated personal calibration or a guaranteed minimum.
- Do not add a universal 1.2 awake multiplier on the explanation that Mifflin omits wakefulness.
  It predicts resting energy expenditure, which already concerns the awake resting state.
  Everyday non-step activity is incompletely modelled, but its size is not established by that fact.
- Do not certify every stored calorie as active. A legacy workout scorer retains resting energy,
  while the main workout UI applies a different net method. Resolve that semantic boundary first.
- Fix or replace the other-workout minimum selector before describing it as realistically low:
  it has a reproduced discontinuity that can produce almost zero energy for a real session.
- For recovery, improve measurement/baseline consistency and expose nightly versus rolling context.
  Three-night weighting and a two-z cap are candidate product calibrations, not established recovery
  equations. A higher score after changing a formula does not establish greater accuracy.

## 1. First define what each number means

Food energy is intake. Resting energy is expenditure at rest. Active exercise energy is expenditure
above a stated resting reference over the same interval. Gross exercise energy includes that
interval's resting component. Daily total expenditure includes resting energy, digestion and
exercise/nonexercise activity. These should not all be converted into an “active calories” number.
The National Academies distinguishes these components and defines PAL against BMR, not against
an arbitrary calculator's resting estimate. [NASEM 2023](https://www.nationalacademies.org/read/26818/chapter/6)

The desired software contract is:

    gross interval energy = resting interval energy + active interval energy

    daily total = daily resting + digestion + nonoverlapping active components

These are accounting definitions, not proof that any component model is accurate. A full-day
resting budget plus movement recorded so far is also different from energy actually spent so far.
`DayUpkeep` deliberately uses the former. Its current-day number must keep that qualification.

## 2. The 1.2 proposal: real omission, unsupported universal correction

`bmrMifflin` implements the standard simplified male/female Mifflin equation correctly. The original
study predicts REE; calling the function BMR does not turn it into a sleeping-only estimate.
Keep it as a population prediction, not “the most reliable equation for every individual” or a
physiological lower confidence bound. Its sex-midpoint branch is a disclosed software convention,
not a separately fitted population equation. [Mifflin et al. 1990](https://pubmed.ncbi.nlm.nih.gov/2305711/)

Independent posture experiments undermine the assertion that quiet sitting universally costs
1.3–1.45 times a person's resting rate. Levine et al. found quiet sitting only about 4% above supine
rest, with much larger increases when fidgeting; Miles-Chan et al. found less than 2% difference
between comfortable sitting and supine rest. These small controlled studies do not say daily NEAT
is negligible; they say posture and movement must not be conflated.
[Levine et al. 2000](https://pubmed.ncbi.nlm.nih.gov/11101470/),
[Miles-Chan et al. 2014](https://pubmed.ncbi.nlm.nih.gov/24290343/)

Three different quantities are easily confused:

- A daily PAL multiplier already represents an aggregate lifestyle expenditure relative to BMR.
- A standard MET uses a conventional resting reference, not each person's measured resting rate.
- Multiplying predicted REE by 1.2 during awake hours assumes a 20% extra background cost.

The third is the proposal here. It is an assumption, not a consequence of the other two. METs
and individual resting metabolism differ materially; the standard reference cannot simply be
read as an individual ratio. [Byrne et al. 2005](https://doi.org/10.1152/japplphysiol.00023.2004)

Synthetic arithmetic: with REE 1,800 kcal/day and 16 awake hours, the proposed extra is
`0.2 × 1,800 × 16/24 = 240 kcal/day`. That is an additional 13.3% of daily REE, not a full-day
20% uplift. It does not guarantee that the final daily ratio becomes 1.35.

Adding that cost across every awake minute also risks overlapping activity already priced above
rest during walks and workouts. Requiring a recorded sleep night would make an otherwise similar
day's energy change simply because sleep data became available. No sleep record is not evidence
of no awake activity; nor is it permission to invent awake duration.

**Recommendation:** decline a universal 1.2 “being awake” correction as presently justified.
Model any residual non-step activity separately, disclose uncertainty, and prevent overlap with
already-priced intervals. Alternatively show an independently modelled total-day estimate beside
the deliberately incomplete Budget. Neither a population PAL range nor a multiplier supplies a
guaranteed personal minimum. Comparisons involving PAL must also use compatible BMR/REE denominators.

## 3. Running: 0.143 is very conservative; 0.17 is reasonable with limits

The flat running code simplifies exactly to:

    Budget net kcal = 0.005 × mass_kg × 0.143 × distance_m
                    = 0.715 × mass_kg × distance_km

Using 0.17 gives 0.85 kcal/kg/km; the 0.2 comparison gives 1.0. No resting subtraction should be
applied again to these distance terms: the resting oxygen term is already absent.

The statement “25–30% below what any study measures” is too strong. Minetti et al. measured
3.40 J/kg/m, approximately 0.813 kcal/kg/km, in ten elite mountain runners on level ground;
their methods explicitly subtract resting oxygen consumption. The current 0.715 is about 12%
below that group mean, versus 28.5% below the 1.0 comparison. This is a counterexample, not a
population minimum. [Minetti et al. 2002](https://doi.org/10.1152/japplphysiol.01177.2001)

More recent work explicitly distinguishes gross and net running costs, subtracting seated rest
before calculating net cost. That supports comparing like with like rather than treating every
published running calorie as an active calorie.
[Selinger et al. 2022](https://nmbl.stanford.edu/wp-content/uploads/Selinger-Current-Biology-2022.pdf)

Synthetic 80 kg, 5 km, level-running example:

- Current Budget: 286 kcal.
- Proposed 0.17 Budget: 340 kcal, an 18.9% increase over the current amount.
- Existing 0.2 distance comparison: 400 kcal.

**Recommendation:** if the aim is a realistically conservative level-running estimate rather than
an intentionally heavily discounted budget, favour 0.17 over 0.143. Describe it as a conservative
budget calibration, not an established new physiological constant. Approval is still needed.

Qualifications that remain even after changing the coefficient:

- The fixed oxygen-to-energy conversion is an approximation that depends on fuel use; “5 kcal/L”
  is not itself a universal minimum. [Fletcher et al. 2009](https://doi.org/10.1152/japplphysiol.00307.2009)
- Uphill and downhill costs are asymmetric. Summing ascent while treating descents as level cannot
  guarantee a lower estimate on predominantly downhill routes. Do not install a mountain-running
  slope model on the strength of one flat coefficient.
- The code already separates walking breaks and limits the ACSM label by speed. That is useful,
  but speed alone does not validate steady-state equations for sprints, repeated acceleration,
  unusual terrain or all grades.
- GPS distance, ascent noise, paused windows and gait classification can dominate a small
  coefficient change. Keep provenance, de-duplication and missing-data labels.

## 4. Walking and steps

`stepCalories = 2.74 × steps × kg / 8,368` is implemented consistently with its existing
stride/step and joule-to-kcal convention. It is about 0.3274 kcal/kg per thousand steps; a
synthetic 80 kg person gets about 262 kcal for 10,000 steps. It is used as a net walking estimate.

The constant does not model speed, slope, load, stop/start patterns or individual economy.
Independent, broader walking models explicitly include speed, height, grade and carried load.
Keep the simple estimate for budgeting, but withdraw any promise that it is always below measured
walking expenditure. The distance comparison is also not a second independent measurement when
its distance was itself inferred from steps and height.
[Weyand et al. 2013](https://doi.org/10.1152/japplphysiol.01333.2012),
[Ludlow and Weyand 2017](https://pubmed.ncbi.nlm.nih.gov/28729390/)

Daily accounting subtracts run-associated steps before adding run energy. When overlap is unknown,
`DayUpkeep.parts` uses the larger movement estimate instead of adding both. These are sound
de-duplication policies. They may omit genuine movement when coverage is uncertain; uncertainty
is preferable to silently treating it as fully measured. Do not “correct” a missed-phone-step day
by inventing a default step count.

## 5. Strength and other workouts

The main UI uses `(MET − 1) × kg × hours`, with 3.5 for weights, 3.0 bodyweight, 3.8 calisthenics,
5.0 powerlifting and an explicitly estimated 3.5 for functional training. The subtraction makes
these conventional standard-net estimates; sets and ordinary between-set rests share a session
average, while explicitly paused time is excluded. Excluding normal inter-set rests again would
apply a session-average rate to an incorrectly shortened duration.

These are defensible coarse conservative categories, not proof of each workout's actual energy.
Direct calorimetry studies of bench press and squats demonstrate task/load variation. Standard
MET rest also differs from individual REE, so adding standard-net energy to predicted REE is an
approximate accounting convention rather than exact physiological partitioning.
[Robergs et al. 2007](https://pubmed.ncbi.nlm.nih.gov/17313290/),
[Byrne et al. 2005](https://doi.org/10.1152/japplphysiol.00023.2004)

For other activities, the lower of a population HR estimate and a category MET estimate is a
deliberate discount. It is not a validated combined estimator or a confidence bound. Taking the
minimum of noisy estimates tends to select negative errors. Population HR relationships also
need activity/context and individual calibration; accurate HR alone does not prove accurate kcal.
[Rennie et al. 2001](https://pubmed.ncbi.nlm.nih.gov/11404659/),
[Brage et al. 2015](https://doi.org/10.1371/journal.pone.0137206),
[Shcherbina et al. 2017](https://pubmed.ncbi.nlm.nih.gov/28538708/)

### Reproduced issue: the minimum selector can be unrealistically low

`otherWorkoutActiveKcal` falls back to MET when net HR is zero, but uses the minimum as soon
as HR becomes slightly positive. A synthetic 80 kg, 180 cm, 40-year-old male, 30-minute activity
at 4 MET gives 120 kcal just below the HR zero-crossing, but about 0.045 kcal just above it.
The two test heart rates differ by 0.02 bpm around 57.3 bpm. This is a mathematical probe,
not a suggested exercise intensity or a personal observation.

That discontinuity is code-proven. A “lower end” policy must not allow a minute positive
out-of-domain HR prediction to erase nearly the entire activity estimate. **Prioritise a coherent
validity/fallback policy over choosing the minimum of every available positive number.**

### Reproduced issue: stored and displayed workout energy have different meanings

`computeManualSessionStats` calls `Calories.estimateBoutCalories`, which includes resting energy
below its activity threshold and a gross HR rate above it. Manual writes and substrate re-scoring
can persist that result in `sessions.calories`. Meanwhile the main Train/detail UI generally
recomputes conventional net calories using `sessionActiveKcal`.

An ignored synthetic probe at resting HR for ten minutes returns about 12.48 kcal from the stored
bout scorer, exactly its Harris–Benedict resting contribution. It is not an active-energy-only field.
The stored value is read by workout-gap crediting and the platform health-export path. Apple Health
export is disabled in the personal profile, so this is not proof that the installed personal build
exported a wrong sample. The semantic mismatch nevertheless prevents an all-fields-net certification.
The same legacy call substitutes 170 cm when height is missing; this is an assumed input, not
recorded anthropometry. The newer net helper instead requires the inputs its formula needs.

**Recommendation:** define gross/net/provenance on the persistence boundary; reconcile manual,
live, re-scored, imported and retimed sessions and every consuming export/credit path. Do not
blindly subtract resting energy from all historical rows: some already contain net values, and
older raw input may no longer exist. This requires a deliberate migration/recalculation decision.

## 6. Digestion and food energy

The current TEF policy is 20% of protein energy, 5% of carbohydrate energy, 0% of fat energy,
and 5% of unexplained energy when composition is incomplete, capped at 20% of logged food kcal.
It is intentionally low. Zero assigned to fat means an omitted small contribution, not a claim
that metabolising fat has no cost. Meal composition, protein type, measurement duration and
individual physiology alter measured thermogenesis; the exact code rates are not guaranteed
minimums for every meal. [Acheson et al. 2011](https://pubmed.ncbi.nlm.nih.gov/21228266/),
[Mixed-meal calorimetry, 1990](https://pubmed.ncbi.nlm.nih.gov/2202889/),
[Kinabo and Durnin 1990](https://pubmed.ncbi.nlm.nih.gov/2400767/)

Keep this conservative policy rather than raising TEF to compensate for missing NEAT. Important
small details are already present: negative/invalid grams do not add energy, unknown composition
is qualified, and a cap limits inconsistent macro entries. Remaining limitations include:

- Label calories, 4/4/9 macro energy, fibre, sugar alcohols and rounding need not match exactly.
  Do not overwrite a labelled energy value merely to force a 4/4/9 identity.
- The TEF function treats carbohydrate grams as ordinary carbohydrate; it has no fibre/polyol
  adjustment and can therefore overstate that component even while the total policy is low.
- Complete macro entries with unexplained energy receive no extra TEF on that remainder. This
  omits possible alcohol/fibre-related effects; it is not measurement of zero digestion.
- Missing food kcal produces no TEF contribution in the current model. Missing must remain visible;
  a day's modelled amount is not evidence that no other food was eaten.

The FDA describes permitted calorie calculations and label rounding; exact apparent macro/calorie
agreement is not a suitable validation target. [FDA Food Labeling Guide](https://www.fda.gov/files/food/published/Food-Labeling-Guide-%28PDF%29.pdf)

## 7. Daily maintenance: incomplete versus incorrectly calculated

`maintenance` currently adds full-day predicted REE, net walking, Budget running and logged-food
TEF. `DayUpkeep` intentionally excludes lifting from its total and shows a separate incremental
lifting line after deducting in-session step energy. Other non-step exercise, such as cycling,
is not automatically a component of this maintenance sum either.

Thus “maintenance” is a conservative component budget, not a comprehensive daily expenditure
estimate. Some everyday non-step activity is missing too. Claude is right about that omission,
but not about wakefulness being wholly absent or a unique correction factor following from it.

Recommended interface/accounting separation:

- Keep the user's deliberately conservative Budget, explicitly naming excluded components.
- Keep lifting beside it, as already requested; any total including lifting should say so.
- If a comprehensive total is desired, add nonoverlapping net workout contributions and an
  explicitly modelled/calibrated residual activity component. Do not silently change the Budget's
  existing inclusion policy or raise the fixed intake goal when expenditure increases.
- Never add the Budget and Movement/ACSM numbers together. They are alternatives for the same
  movement, and often share input measurements.

Population energy requirements help check plausibility, but cannot prove an individual's true
maintenance from a single estimated ratio. Energy compensation is another reason daily totals
are not indefinitely additive; the population finding is not a reason to discount each run by a
universal percentage. [Careau et al. 2021](https://pubmed.ncbi.nlm.nih.gov/34453886/)

## 8. Food/weight maintenance is an inference, not a measured gold standard

The code uses a robust weight slope and logged intake. Its short-window display additionally
spans conversion assumptions of 4,858–7,700 kcal/kg before 42 elapsed days. This is better than
one falsely precise conversion, but those endpoints do not make a universal physiological interval.
Its slope confidence interval does not cover systematic food omission, fluid changes, body
composition uncertainty or metabolic adaptation.

Dynamic body-weight research explicitly accounts for changing energy expenditure and tissue/fluid
composition. “After six weeks, 7,700 becomes exact” is not an implication of that literature.
[Hall et al. 2011](https://pubmed.ncbi.nlm.nih.gov/21872751/),
[Hall and Chow 2011, intake inference](https://pubmed.ncbi.nlm.nih.gov/21562087/)

For calibration, use consistently collected weight and genuinely complete intake over the same
span, and test predictions on later data. The app's half-goal automatic counting rule is a logging
convenience, not proof of complete intake. Selective/incomplete counted days can bias inferred
maintenance downward. Self-report errors are independently documented; do not “validate” a low
expenditure estimate against an equally incomplete diary.
[Intake24 DLW validation](https://pmc.ncbi.nlm.nih.gov/articles/PMC6722486/)

## 9. Recovery: what the current number actually does

The canonical headline uses last night's log HRV, asleep lowest-30-minute HR, total sleep and
respiration; the temperature input is unavailable when its source/quality is unsupported. Each
usable input is compared with its own baseline, oriented, weighted and passed through a logistic:

    z = sum(weight × oriented input z) / sum(surviving weights)
    score = 100 / (1 + exp(-z))

Nominal weights are HRV .35, RHR .25, sleep .20, respiration .12, temperature .08. At least two
inputs and nominal weight .5 must survive. Sleep's positive contribution is already capped at
one z. Baselines take up to 28 eligible prior values within 60 calendar days, with at least 14
values per input. Today and future dates are excluded. This is not a fixed 14-night algorithm,
and 28 usable values do not necessarily arrive after exactly two more calendar weeks.
The headline also withholds a composite when its absolute z exceeds five (`kReadinessZCap`);
that saturation guard is different from clipping each input at two z. More baseline nights can
move both the median and dispersion in either direction; a longer baseline does not guarantee
a higher score.

A zero composite maps to 50 by design. Neither that logistic, the weights, the confidence label
nor proposed two-z clipping is a validated percentage of physiological recovery. Do not transplant
another company's colour thresholds or average score and infer scientific equivalence.

Independent HRV research supports averaging for longer-term training interpretation, while also
showing that higher HRV is not universally better: functional overreaching can accompany elevated
parasympathetic indices. An overnight autonomic signal is not a complete readiness-to-perform test.
[Flatt and Esco 2016](https://pubmed.ncbi.nlm.nih.gov/26200192/),
[Le Meur et al. 2013](https://pubmed.ncbi.nlm.nih.gov/24136138/),
[Schmitt et al. 2013](https://pubmed.ncbi.nlm.nih.gov/23951198/)

### Assessment of the three recovery suggestions

**Three-night weighted average:** reasonable to test for a steadier recent-state signal, not
established as the best daily recovery formula or an exact reproduction of Oura. It can also
conceal a meaningful acute change. Specify whether the product answers last night or recent days.
For illustration only, independent equal-weight noise falls to 1/sqrt(3), about 58%, with three
samples; four equal samples halve it. Unequal weights and correlated nights change that result.
There is no general guarantee that three weighted nights halve noise.

**Cap any one input at two z:** possible influence control, not an evidence-derived physiological
threshold. Inspect beat quality, a tight baseline, measurement resolution and genuine unusual
signals first. Clipping cannot distinguish artifact from illness or real fatigue. If trialled,
retain raw deviations and alerts separately and disclose clipped versus unclipped contributions.
Artifacts can strongly affect RMSSD. [Bourdillon et al. 2022](https://pubmed.ncbi.nlm.nih.gov/35719238/)

**Make HRV and Recovery use consistent history:** support consistent underlying nightly estimator,
method version, quality admission, exclusions and clearly named dates. Different labelled views
may legitimately answer different questions; a nightly HRV number, a weekly trend and a multi-input
score need not all show the same verdict.

If recent three-night HRV is introduced, calibrate it against a comparable history of aggregates,
or explicitly justify a different variance model. Exclude the nights being judged from the
comparison baseline, define missing-night and gap rules, and avoid mixing estimator versions.
Do not smooth sleep/respiratory warnings away merely to make the headline less volatile.

**Recommendation:** keep the unmodified nightly observation, add a distinctly labelled recent
trend, and compare candidate headline changes against held-out observations, reported recovery
and performance. Agree a scoring policy before implementation. The private counterfactual scores
in the supplied response were not reproduced here; public papers cannot verify them.

## 10. Implementation order if changes are approved

1. Resolve workout persistence/consumer gross-versus-net semantics and the minimum-selector
   discontinuity. These are more concrete than choosing a larger daily multiplier.
2. Decide which daily figure is an intentionally conservative Budget and which, if any, claims
   comprehensive expenditure. Preserve the separate lifting policy until explicitly changed.
3. Trial 0.17 for ordinary level-running Budget; retain the existing comparison and qualifications.
4. Keep REE, walking and strength estimates with honest limitations; do not raise every component
   to compensate for omitted activity or force a population PAL minimum.
5. Treat digestion and food/weight inference as qualified estimates; improve input completeness
   before calibrating any residual activity amount.
6. Reconcile HRV measurement and baseline definitions, then evaluate rolling/clipped candidates
   without selecting parameters simply because they make a low score higher.

All changes to stored outputs still require an algorithm-version decision, synthetic regressions,
additive/idempotent storage changes where needed, retained-input recalculation limits and cloud
checks. A research recommendation is not approval to change a headline or reinterpret old rows.

## 11. Verification and limits

28 existing targeted tests pass in `run_calories_test.dart` and `build90_energy_test.dart`.
They check implemented arithmetic, net distance/MET conventions, overlap accounting, domains and
display ranges; they do not establish individual physiological accuracy.

One additional ignored synthetic probe passes while deliberately reproducing the two undesirable
semantics above. Its source is `build/research-local/calorie-semantics-probe_test.dart`; no private
data is involved. No full local suite/build ran and no app behavior was edited.

No gas-exchange measurement, doubly labelled water measurement, personal food/weight calibration,
ECG comparison or prospective recovery-outcome validation was performed. Older wearable-validation
studies establish limitations, not an error percentage for this exact WHOOP implementation.
Several papers concern trained athletes, small cohorts, morning supine measurements or treadmill
protocols; they do not directly validate a whole-night PPG-derived consumer recovery score.

### Source-code map

- `lib/compute/profile.dart`: resting, step, distance, net HR/MET and digestion helpers.
- `lib/compute/day_upkeep.dart`: daily component accounting and exercise/step overlap.
- `lib/compute/manual_session.dart` and
  `packages/analytics/lib/src/onehz/workout/calories.dart`: legacy stored bout scorer.
- `lib/data/local_repository_impl.dart`: manual persistence and substrate session re-scoring.
- `lib/compute/derivation_engine.dart` and `lib/health/health_export.dart`: stored-calorie consumers;
  the latter is disabled in the personal build.
- `lib/data/nutrition_store.dart`: food completeness, counting and weight/intake inference.
- `packages/analytics/lib/src/onehz/wellness/readiness_composite.dart`,
  `lib/compute/onehz_pipeline.dart` and `lib/compute/derivation_engine.dart`: recovery estimator,
  headline quality guard and historical baseline selection respectively.

## Source access notes

The evidence linked at the claims is outside the supplied bibliography: original Mifflin rather
than the supplied review; NASEM rather than the supplied FAO chapter; independent posture studies;
Minetti/Selinger/Fletcher rather than the supplied running references; later broader walking work;
independent HR/calorimetry and dietary-validation research; and independent HRV monitoring studies.
Minetti and Selinger methods were checked in full-text PDFs. Mifflin, Miles-Chan, Levine, Robergs,
Rennie and Shcherbina were checked through their published abstracts/records; full texts were not
all available. The remaining links support the narrow claims attached to them, not blanket
approval of every formula. Secondary search hits, commercial calorie calculators and social-media
posts were excluded from the verdicts. No private content was used in a web query or request.

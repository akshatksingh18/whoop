# Fitness Goal Rules And Their Evidence

**Status:** Implemented in build-86 source (`lib/data/goal_plan.dart`, Progress → Goal); not yet
phone-tested. Change a number here and in the code together, with its test
(`test/build86_goal_plan_test.dart`).

The goal is chosen by Akshat in the app, not written into code. The review only suggests; it never
changes a goal. Labels: **[P]** primary study or position stand, **[R]** narrative review,
**[PR]** practitioner guidance, **[C]** convention or synthesis with no direct trial behind it.
Research was gathered by web search; where only an abstract or a secondary summary was read, the
source list says so.

## Rules as implemented

| Goal | Weekly change of the 7-day average | Window | Protein (g/kg body weight) |
|---|---|---|---|
| Lose fat, gentle | −0.25 to −0.5% | 1 closed week vs the one before | 1.8–2.4 |
| Lose fat, moderate | −0.5 to −0.75% | 1 vs 1 | 1.8–2.4 |
| Lose fat, faster | −0.75 to −1.0% | 1 vs 1 | 2.0–2.6 |
| Recomposition | −0.25 to +0.05% | 2 vs 2 (four weeks) | 1.6–2.2 |
| Keep it off | within ±1.5% of the held weight | 2 vs 2 | 1.6–2.2 |
| Build muscle, under a year | +0.25 to +0.5% | 1 vs 1 | 1.6–2.2 |
| Build muscle, one to three years | +0.15 to +0.33% | 1 vs 1 | 1.6–2.2 |
| Build muscle, over three years | +0.1 to +0.2% | 1 vs 1 | 1.6–2.2 |
| Get stronger at this weight | −0.15 to +0.15% | 2 vs 2 | 1.6–2.2 |

- **Data gate (all goals):**
  - two weeks since the goal last changed [C];
  - five or more weigh-ins in every week of the window [C, close to MacroFactor's 10 of 14];
  - five fully logged (or marked complete) food days in every week [C].
- **Margin:** a rate within 0.1%/week of the band counts as inside, so one noisy fortnight does
  not trigger a suggestion [C].
- **Lifts slipping:** two or more comparable lifts worse, and more worse than better. Sleep,
  protein and training are checked before any calorie change. During a cut that is losing too
  fast, +150 kcal or one to two weeks at maintenance is suggested. The break is offered for
  hunger and adherence, not as faster fat loss (S10, S11, S14).
- **Protein first:** when the suggestion would be to eat less and protein is below its range, the
  review asks for protein first [R, S1].
- **Step size:** 100–250 kcal, in 25 kcal steps, sized from the gap at 7,700 kcal/kg. The size is
  [C]; the nearest anchor is a 25–50 g carbohydrate step (S1). 7,700 kcal/kg overstates the
  deficit lean people need (S12, S13), so it only sizes the step.
- **Floor:** the larger of estimated resting energy (Mifflin) and 1,500 kcal for men or 1,200 kcal
  for women. Those are the lower ends of the guideline intake targets (S17). At the floor, the
  review offers more steps, a maintenance break or ending the phase.
- **Build muscle, waist check:** a waist rising faster than about 1 cm per 2 kg of gain is
  flagged as fat gain [C, no validated ratio].
- **Recomposition stall:** after eight weeks with no stronger lifts and no smaller waist, the
  review suggests a dedicated fat-loss or muscle-gain phase [C].
- **Safety:** the Goal screen says to set goals with a clinician when there is a medical condition
  or a history of disordered eating.

## Evidence by goal

- **Fat loss:** 0.5–1.0% of body weight per week keeps lean mass best (S1). Leaner people should
  go slower (S1, S7). In Garthe 2011, about 0.7% vs 1.4% a week gave similar fat loss, but the
  slower group gained lean mass and strength (S3). In cuts, deficits of roughly 500 kcal or more
  blunt lean-mass gain but not strength (S14), so falling strength is a meaningful signal.
  Protein is 2.3–3.1 g/kg lean mass (S1, S7), about 1.8–2.6 g/kg body weight when moderately
  lean [C mapping].
- **Recomposition:** documented even in trained people, most likely in novices, returning lifters
  and higher body fat (S5, abstract). Weight stays flat to slightly down. Judge on four to eight
  weeks, not two (S7).
- **Keep it off:** within 3% of the reference weight counts as maintenance (S15, summary). The
  inner ±1.5% band is [C]. Reverse dieting is untested against a direct return to maintenance
  (S9). Expenditure can stay below what mass loss predicts for a year or more (S9), so the review
  judges observed weight change, not a pre-diet maintenance figure.
- **Build muscle:** about 0.25–0.5% a week for novices and intermediates and about 0.25% for
  advanced lifters (S2). The practitioner "medium" rates are 0.5, 0.325 and 0.15% a week for
  beginner, intermediate and experienced [PR, S16]. Faster gain adds fat, not muscle (Garthe 2013,
  S4; Helms et al. via S16).
- **Strength at maintenance:** the strength trend is the signal. Protein is 1.6–2.2 g/kg (S6
  breakpoint 1.62 g/kg, upper interval about 2.2).
- **Noise:**
  - Use 7-day averages and judge over 14 days or more.
  - Water from salt, glycogen or a refeed can move weight 1–2 kg [C].
  - Luteal-phase water gain is about 0.5 kg in small studies; compare the same phase or use
    four-week windows.

## Not implemented

- Adaptive expenditure estimation (intake minus change in stored energy over a smoothed trend,
  S16). The app keeps its own conservative maintenance estimate. A Hall-model or adaptive estimate
  would be a separate decision.
- Leanness-scaled fat-loss pace. There are no published body-fat cut points (S1), so pace is
  Akshat's choice.

## Sources

- S1 Helms, Aragon, Fitschen 2014, Evidence-based recommendations for natural bodybuilding contest
  preparation: nutrition and supplementation, JISSN 11:20 — https://pmc.ncbi.nlm.nih.gov/articles/PMC4033492/ [R]
- S2 Iraki, Fitschen, Espinar, Helms 2019, Nutrition Recommendations for Bodybuilders in the
  Off-Season, Sports 7(7):154 — https://pmc.ncbi.nlm.nih.gov/articles/PMC6680710/ [R]
- S3 Garthe et al. 2011, Effect of two different weight-loss rates on body composition and
  strength and power-related performance in elite athletes, IJSNEM 21(2):97 [P, abstract]
- S4 Garthe et al. 2013, Effect of nutritional intervention on body composition and performance in
  elite athletes, Eur J Sport Sci [P, abstract]
- S5 Barakat et al. 2020, Body Recomposition: Can Trained Individuals Build Muscle and Lose Fat at
  the Same Time?, Strength Cond J 42(5):7 [R, abstract]
- S6 Morton et al. 2018, protein supplementation meta-analysis, BJSM 52:376 —
  https://pubmed.ncbi.nlm.nih.gov/28698222/ [P]
- S7 Aragon et al. 2017, ISSN position stand: diets and body composition, JISSN 14:16 —
  https://pubmed.ncbi.nlm.nih.gov/28630601/ [P]
- S8 Jäger et al. 2017, ISSN position stand: protein and exercise, JISSN 14:20 [P, summary]
- S9 Trexler, Smith-Ryan, Norton 2014, Metabolic adaptation to weight loss, JISSN 11:7 —
  https://pmc.ncbi.nlm.nih.gov/articles/PMC3943438/ [R]
- S10 Byrne et al. 2018, MATADOR, Int J Obes 42:129 — https://pubmed.ncbi.nlm.nih.gov/28925405/ [P]
- S11 Peos et al. 2021, ICECAP, MSSE 53(8):1685 — https://pubmed.ncbi.nlm.nih.gov/33587549/ [P]
- S12 Hall 2008, What is the required energy deficit per unit weight loss?, Int J Obes —
  https://pubmed.ncbi.nlm.nih.gov/17848938/ [P]
- S13 Hall et al. 2011, Quantification of the effect of energy imbalance on bodyweight, Lancet
  378:826 — https://pmc.ncbi.nlm.nih.gov/articles/PMC3880593 [P]
- S14 Murphy & Koehler 2022, Energy deficiency impairs resistance training gains in lean mass but
  not strength, Scand J Med Sci Sports 32:125 [P]
- S15 Stevens et al. 2006, The definition of weight maintenance, Int J Obes 30:391 [R, summary]
- S16 MacroFactor, algorithms and bulking calculator articles — https://macrofactor.com/ [PR, vendor data]
- S17 2013 AHA/ACC/TOS obesity guideline (500–750 kcal deficit; 1,200–1,500 kcal women,
  1,500–1,800 kcal men) [P]

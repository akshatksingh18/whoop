# Build 85 audit: lifting calories, digestion, two-method labels, stale data, UI makeover

Akshat's request after installing build 84 (audit only, no app or code changes): explain the Lift
setup's "about 252 kcal per 30 min from 6 MET and your weight", how lifting calories really work,
whether heart rate is used and what happens when it stays low; check digestion against its
sources on the conservative side ("touching the floor", not a large underestimate); add a
one-line duration description; separate the Budget (Method 1) and ACSM figures everywhere they
appear; find other stale or mismatched data end to end; and audit the whole UI for a makeover
(dull grey lines such as "walking route + phone motion / estimated step length" and "Eaten 2,448 ·
… under Budget maintenance"). Status: audit complete; decisions for Akshat are listed at the end.
Nothing here is implemented.

Profile used for worked numbers: 23 y, male, 80.5 kg, 186.69 cm (BMR 1,861.8125 kcal/day,
resting 1.29293 kcal/min). Each number was checked by script.

## 1. Lifting calories

### What the app does today: three different numbers for one session

| Where | Formula in code | 30 min, 80.5 kg | 60 min |
|---|---|---|---|
| Lift setup ("About N kcal per 30 min") | `Activity.kcal`: catalogue MET 6.0 × 3.5 × kg ÷ 200 × min, **gross** (includes resting) | 253.6 → 254 (252 at 80.0 kg) | 507 |
| Live screen, session summary, Train list | `otherWorkoutActiveKcal`: **net**, the LOWER of (3.5 − 1) × kg × h and Keytel at the session's mean HR minus resting | 100.6 (if HR ≥ 85 bpm) | 201.25 |
| Maintenance sheet Lifting line (build 84) | same net value over active minutes, minus step calories inside the session | ≤ 100.6 | ≤ 201.25 |

- The setup preview is the old gross 6.0 MET figure (Compendium 02050, "vigorous, powerlifting or
  bodybuilding"), about 2.5× the number the session then shows. It is stale against build 78's
  decision to price strength work at 3.5 MET net.
- The summary's explanation card is also stale: it says "Estimated from 6.0 MET, your weight and
  heart rate", but the figure is 3.5 MET net or the heart-rate estimate, whichever is lower.
- The live screen falls back to the gross 6.0 figure (`_kcal` in `live.dart`) whenever the net
  estimate is unavailable, so one session can switch formulas mid-way.
- Duration: the session uses active time (start to stop minus pauses, `WorkoutClock`); the Train
  list's lifting rows use the stored `duration_min`, which includes pauses. No screen says which.

### Does heart rate count, and what happens when it stays low

Yes, as a cap: the app takes the lower of the two. With this profile, Keytel minus resting is:

| Mean session HR | Net kcal/h by HR | Net kcal/h by 3.5 MET | Shown (lower) |
|---|---|---|---|
| 70 bpm | 61.6 | 201.25 | 61.6 |
| 80 bpm | 152.1 | 201.25 | 152.1 |
| 85.4 bpm | 201.2 | 201.25 | crossover |
| 90 bpm | 242.6 | 201.25 | 201.25 |
| 110 bpm | 423.5 | 201.25 | 201.25 |

So a lifting session whose average heart rate stays under about 85 bpm (long rests between heavy,
low-rep sets do this) is priced by heart rate and can drop to a third of the MET floor. That is
not "touching the floor"; it is below any measured value for resistance training.

### What the research says

- **Compendium (2024 Adult Compendium, [pacompendium.com](https://pacompendium.com/conditioning-exercise)):**
  02054 resistance training, multiple exercises, 8-15 reps, varied resistance: 3.5 MET; 02052
  squats/deadlift: 5.0; 02050 vigorous free weights / powerlifting / bodybuilding: 6.0. 3.5 is the
  lowest resistance-training code, so 3.5 (2.5 MET above resting) is the evidence floor.
- **Measured sessions:** strength sessions measured by indirect calorimetry span about 2.4-7.9
  kcal/min gross (most 4-8), i.e. about 1.1-6.6 kcal/min above resting for this profile; young
  adults' sessions fit about 5 MET at 60-80% 1RM
  ([MET study, Biology of Sport](https://www.termedia.pl/Determination-of-metabolic-equivalents-during-low-and-high-intensity-resistance-exercise-in-healthy-young-subjects-and-patients-with-type-2-diabetes,78,27014,0,1.html);
  [moderate-intensity session, HKBU](https://scholars.hkbu.edu.hk/en/publications/energy-expenditure-estimation-of-a-moderate-intensity-strength-tr/)).
  The app's 3.354 kcal/min net (3.5 MET) sits in the lower part of that range.
  Oxygen-based measurement misses the anaerobic share of hard sets, so measured values themselves
  lean low.
- **Heart rate during lifting:** at a given % of max heart rate, oxygen uptake during weight
  lifting is lower than in steady aerobic work (the HR-VO2 line is shallower), so heart-rate
  calorie formulas overstate lifting ([weight-lifting HR/VO2 study](https://pubmed.ncbi.nlm.nih.gov/2072844/));
  devices roughly doubled measured energy in resistance work
  ([Polar Verity abstract](https://our.utah.edu/ucur/validity-and-reliability-of-heart-rate-measurements-and-energy-expenditure-by-bicep-worn-polar-verity-during-light-resistance-training/)).
- **Keytel's own range:** built from steady exercise at 57-90% of max heart rate
  ([Keytel 2005](https://pubmed.ncbi.nlm.nih.gov/15966347/)); about 109-173 bpm for this profile
  (Tanaka 191.9). Whenever heart rate is the lower number for lifting (under ~85 bpm) it is being
  used outside the range it was built on. Vendors switch to resting energy below that range
  ([Hexoskin](https://support.hexoskin.com/how-is-the-energy-expenditure-calculated)).
- Accuracy to expect: none of these methods measures one person's session; group studies spread
  about ±40% around the mean. A floor is the honest target.

### Recommendation

- Price strength sessions by MET only: (3.5 − 1) × kg × active hours (201.25 kcal per active hour
  here), the lowest resistance-training Compendium value. Stop using heart rate to lower it (it is
  outside Keytel's range exactly when it would win) or to raise it (heart rate overstates lifting).
  Keep heart rate on the summary as context (average, peak, zones), not as calories.
- Show the same number everywhere: setup preview "About 101 kcal per 30 active min (3.5 MET above
  resting)", live, summary, Train list, Lifting line. Remove the gross 6.0 fallback.
- Use active time everywhere (Train list too) and say so in one line: "Active time: start to stop,
  minus pauses."
- Optional, if Akshat wants it: 5.0 MET for sessions he marks as heavy squat/deadlift
  (Compendium 02052). Not recommended by default; 3.5 is the floor.
- Calorie basis line on the summary: "3.5 MET above resting × 80.5 kg × 0:58 active. Heart rate
  is shown but not used: it overstates lifting."

## 2. Digestion (build 84) against its sources

- Rates are the published low ends: protein 20-30%, carbohydrate 5-10%, fat 0-3% of their energy
  ([Tappy 1996](https://rnd.edpsciences.org/10.1051/rnd:19960405)); a mixed diet 5-15% of intake
  ([Westerterp 2004](https://www.biomedcentral.com/1743-7075/1/5)). Build 84 uses 20 / 5 / 0 and
  5% for food without macros: every rate is exactly the floor of its source. Correct.
- How far below the likely value it lands: on his 180 g protein / 250 g carb / 87 g fat 2,500 kcal
  day, 194 kcal (7.8%) against 267 at the range midpoints (10.7%): 73 kcal low, about 3% of intake.
  On a 15%-protein day, 137.5 (5.5%) against about 214 at midpoints: 76 low. A whole-diet chamber
  measurement of a high-protein diet was 14.6% and of a high-fat diet 10.5%
  ([Westerterp 1999](https://doi.org/10.1038/sj.ijo.0800810)), so the formula is a true floor and
  will not overestimate.
- Verdict: matches the "touching the floor" brief; the gap to the likely value is 70-80 kcal/day,
  smaller than the ±190 kcal uncertainty of the BMR equation. No change recommended. One wording
  fix: the sheet's long line could read "Low end: protein 20%, carbs 5%, fat 0% (5% without macros)."

## 3. Two methods, labelled everywhere

The Budget (Method 1, the green number) and ACSM (blue) figures appear side by side in some places
and singly in others, and several labels do not say which method they are:

| Place | Today | Problem |
|---|---|---|
| Maintenance sheet "Budget breakdown" | Resting / Steps / Digestion rows are Budget only; ACSM is one grey line "ACSM movement: walking 312 · running 0 kcal" | Steps row does not say "Budget (Weyand steps)"; ACSM has no breakdown |
| Food/Today maintenance card | BMR · STEPS · RUNNING · DIGESTION chips | Budget only, unlabelled, beside a two-number header |
| "Eaten 2,448 · N under Budget maintenance" | one grey caption | Only Budget compared; no ACSM comparison; easy to miss |
| Steps screen and Step calories screen | Budget/ACSM pair with subtitles "Steps / distance budget" and "Standard distance model" | Jargon subtitles; distance-source line floats under both |
| Step calories hourly chart | "kcal · budget" | Fine; ACSM has no hourly view, say so |
| Distance source line | "Walking route + phone motion / estimated step length" | Internal wording; it describes only ACSM's distance |
| Lift setup / summary | single calorie number | Not a two-method figure; must not borrow either label |

Recommendation: one shared component for every two-method figure: two columns headed "Budget
(Method 1)" in green and "ACSM" in blue, each with its own breakdown rows (Resting, Walking,
Running, Digestion) so nothing is mingled, and a one-line "how measured" under each column
(Budget: "your steps × weight (Weyand)"; ACSM: "distance × weight (ACSM walking/running)"). The
distance source becomes a small labelled chip under ACSM only: "Distance: GPS route",
"Distance: phone motion", "Distance: step length estimate".

## 4. Stale and mismatched data, end to end

Fixed in build 84 (verify on the phone): Today strain 0.0 vs Day strain (revision on today's row);
readiness rescan not refreshing screens; background relaunches running the foreground session;
pull-to-refresh waiting on four days.

Still present (source-level findings, by severity):
1. **Lifting: three different calorie numbers and a wrong explanation** (section 1).
2. **Today strain early in the day:** before today's day row exists, Today reads the interim
   wake-features strain while Day strain falls back to the latest complete day's bundle. Early
   morning they can show different days' numbers. Fix: Day strain should show "Today not
   calculated yet" instead of the previous day when today has no row, or both should read one source.
3. **Train list vs session duration:** list rows price lifting on `duration_min` (with pauses);
   the session and the Lifting line use active time.
4. **Maintenance footer** says "Lifting and heart-rate estimates are not added" directly under a
   Lifting line that now exists; reword to "The Lifting line is shown, not added."
5. **"Your normal range" from 1 day:** Steps/Step calories show Lowest = Typical = Highest from one
   day ("From 1 of your own days"). Hide until 7 days.
6. **Repeated captions:** the Step calories screen says "already included in maintenance" three
   times and Steps twice; the distance source repeats on both cards.
7. **Sync log counts are cumulative** per connection ("OFFLOAD SUMMARY records=9818"), so they read
   as huge pulls. Log per-sync counts.
8. **Background calculation:** data syncs in the background but numbers wait for the app to open
   (by design since build 84); Today should show "Updated 07:05" so an old number never looks current.
   A visible "as of" time is the main missing stale-data guard across Today, Food and Trends.
9. **Leftover test artefacts:** `test/failures/` holds September golden diffs of the old upstream
   Home (ignored by Git); delete locally to avoid confusion.
Checked and fine: run-history cache (cleared on every data change), readiness pin (ring and chart
use the same pinned value), profile edits (bump the revision), food writes (revision listeners).

## 5. UI makeover audit

What the captured screens show (maintenance sheet, Steps, Step calories; rendered from the
existing UI_CAPTURE tests): every line is the same grey caption weight, numbers and explanations
compete, the same sentence repeats, and important comparisons ("N under maintenance") sit in
small grey text at the bottom of a card. Large dark gaps sit between sections while long text
blocks fill cards.

Principles (keeping Akshat's minimal, plain-words style: one accent per pillar, no decoration):
- **One hierarchy per card:** a label (small caps, ink2), the number (large, pillar colour), one
  short qualifier (ink2). Explanations move behind an info tap or into a collapsed "How it's
  worked out" row.
- **Status chips instead of sentences:** "Distance: GPS route", "Steps: phone", "Approximate",
  "Updated 07:05", "Not in maintenance". Chips are scannable; sentences are not.
- **Comparison rows as the hero, not footnotes:** "Eaten 2,448 · Budget 2,451 · 3 under" becomes a
  bar or a three-number row with the difference coloured (green under, amber over).
- **Breakdowns as stacked bars:** maintenance as one horizontal bar split Resting / Walking /
  Running / Digestion, with the rows below; Budget and ACSM as two bars on the same scale.
- **No repeats:** each fact once per screen; remove duplicate "already included" captions.
- **Empty and thin states:** hide "normal range" and trends until enough days; say what is
  missing in one line with the fix.
- **Consistent units and rounding:** kcal without decimals everywhere, thousands separators
  everywhere ("2243 kcal" in the sheet header vs "1,862 kcal" in rows today).
Per screen:
- **Today:** rings stay; add "Updated hh:mm" under them; maintenance card becomes the stacked bar
  plus "Eaten vs Budget" row; workout and steps cards get one number each with a chip.
- **Food → Maintenance sheet:** two columns (Budget | ACSM) with their own breakdown rows; Lifting
  as a separate dashed row under the total labelled "Not in maintenance"; digestion one short line.
- **Steps / Step calories:** one card for the count (source chip), one for the two-method calories,
  chart, then range only when it has 7+ days; delete the repeated captions.
- **Lift setup / live / summary:** one calorie number with "3.5 MET above resting · active time";
  heart rate as its own card (average, peak, zones).
- **Trends and detail screens:** same label/number/chip pattern; dates as "Tue 7 Oct" everywhere.
Way of working: build the shared pieces first (two-method block, stat row with chip, stacked bar,
"Updated" stamp), then apply screen by screen, with UI_CAPTURE renders of each screen before and
after for Akshat to approve.

## Decisions for Akshat

1. Lifting: MET-only 3.5 floor (recommended), or keep "lower of" with heart rate, or 5.0 for
   marked heavy sessions.
2. Digestion: keep the build-84 floor (recommended) or move to range midpoints.
3. Two-method block: Budget (Method 1) | ACSM columns with their own breakdowns everywhere
   (recommended).
4. Stale-data guards: "Updated hh:mm" stamps on Today/Food/Trends, and Day strain not falling back
   to a previous day for today (recommended both).
5. UI makeover scope: shared components plus Today, Food maintenance, Steps/Step calories and the
   workout screens in one build (recommended), with before/after renders first; or a smaller pass.

## Implemented in build 85 (Akshat's decisions)

- **Lifting:** `sessionActiveKcal` prices strength by (MET − 1) × kg × active hours only (3.5 MET
  weight training); heart rate is shown, never priced. Setup preview, live screen, summary
  basis line, Train list (now on active time) and the maintenance Lifting line all call it, at
  the session's recorded (else dated) weight. The gross 6.0 MET preview and live fallback are
  gone. Sets and rests stay priced together (the band cannot isolate a 15-second set; the
  Compendium values are whole-session averages, and longer rests lower the true average, so 3.5
  is the floor for typical sessions rather than a guarantee for very long-rest ones).
- **Digestion:** unchanged floor; the sheet's line moved under "How it's worked out".
- **Two methods:** `CaloriePair` shows Budget (Method 1 · steps) and ACSM (Standard · distance)
  under their own coloured rules with per-method breakdowns in the maintenance sheet.
- **Stale/mismatch:** day measures (all-day heart rate, wear, stress, strain, timeline) read the
  exact day only; Day strain shows today's interim figure (the one Today reads) instead of
  yesterday; "Updated hh:mm" on Today; Lifting footer contradiction removed; normal range from
  7 days; repeated captions replaced by chips; sync-log totals labelled "totals since connect";
  the background and 15-second pull-to-refresh notes removed.
- **Food categories:** `food_def.category`, chosen in the food editor, filtered by one shared
  `FoodCategoryFilter` on Food → Foods, the log screen's My foods and the saved-meal picker.
- **Walks:** speed in km/h on the live screen, summary and walk detail (average and chart);
  runs keep pace; split times stay time per km.
- **Makeover:** new tokens (card light and edge, page glow, section style) and pieces (`Tag`,
  `UpdatedStamp`, `StatTile`, `StackedBar`, `CompareRow`, `Explain`); restyled cards, sections,
  status cards, pills, tabs, tab bar, back button, Trends rows, food rows, link rows; new Today
  hero, Today tiles and maintenance card, maintenance sheet, Calories ring card, macro grid,
  Train start discs.

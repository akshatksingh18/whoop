# Next build — `0.9.37`/`70`

**State:**
- **Build 70** is implemented in source on Akshat's go-ahead. Everything is in one build, and the
  local tests pass.
- **Left:** building it, installing it over build 69, and the phone check below.
- **Build 69:** its own phone check is folded into this one.
- **Process:** when the phone check passes, clear this file and record anything still open in
  `CLAUDE.md`. Shipped behaviour is described in `CLAUDE.md` and `metrics-map.md`, not here.

## Readiness audit (Akshat asked for an end-to-end check)

No broken link was found. The path is:

1. Each night stores HRV (`ln_rmssd`), resting heart rate, breathing and skin temperature as
   `metric_series` rows.
2. `_BaselineHistoryCache` reads the earlier nights for each, leaving out imported days and days
   from a different band family, and keeping the last 28 values.
3. `readinessComposite` (packages/analytics) needs:
   - at least 14 earlier nights per input (`readinessCompositeMinBaseline`);
   - at least 2 inputs;
   - at least half the weight.
4. Each input is scored as a robust z against its own baseline, and the weights renormalise over
   the inputs present.
5. A missing score stores why in the day bundle's `readiness_absent_diag`.

**Why the history before 30 September is sparse:** that 14-night rule (plus nights with HRV or
resting HR not measured, and imported days, which never count). Build 70 shows the stored reason
for any empty day while dragging the history (`readinessGap`), so the exact cause of each gap can be
read on the phone.

## Phone check for build 70

1. **Charts:**
   - Trends → Steps or Time asleep at Month and 3 months: a finger now moves the cursor.
   - No dotted version lines, no "needs 182 days" line, no Worn bars under the chart.
2. **Sleep:**
   - Stage names appear only in the colour key; there is no card under the chart.
   - Dragging shows time · stage · bpm · HRV · temp in the header.
   - Overnight signals is three rows (heart rate, HRV, skin temperature); breathing appears only
     when measured.
   - A Naps section shows on a day with a nap.
   - "Fix sleep times" is folded.
   - The Breathing pattern screen is one card with a small chart, and its caveats fold under
     "What this means".
3. **Trends:**
   - There is no Naps section.
   - Skin temperature opens a chart (this band's nights only), or the row is hidden with fewer
     than 7 nights.
4. **Readiness:**
   - The history is coloured bars.
   - Dragging an empty day says why it has no score.
   - Under "What drove it", a line says why breathing was not counted.
5. **Steps:** the day total follows the phone wherever the phone counted. The band only fills time
   the phone missed. Analytics version 87 recalculates the last few retained days.
6. **Run screen:**
   - Medal pins (1/2/3) sit on the map where each top-3 effort ended.
   - Steps come from the phone, with a cadence figure.
   - A Cadence chart is on Graphs.
7. **Live run or walk:** "Voice each km" toggle. A spoken line comes at each km with that km's
   pace. Check with music playing (it ducks) and with the screen locked (untested; see below).
8. **Food → Today:**
   - ‹ Today › with a calendar, and swipe for other days.
   - Meal cards with Log and ⋯ (Copy from / Copy to / Save meal).
   - In the evening, "N g protein left today".
9. **Meal page:**
   - Sub-headings with totals.
   - Swipe left deletes an item.
   - Tap an item to change its amount or move it to a sub-heading.
   - "Add food" and "Copy, or save as a meal" buttons.
10. **Log screen:**
    - Meal selector, search, and Recent / My meals / My foods.
    - Sort on My foods.
    - + logs at once; tap opens the detail.
    - The detail shows grams, serving chips, meal, time, % of daily goals, and "Often eaten with".
    - Create a food asks for description and serving grams.
    - Quick add has a name and a time.
11. **Food → History:**
    - A weight card with "Log weight" and the 7-day trend. After 2+ weeks of weigh-ins and food,
      it shows measured maintenance.
    - A "This week" deficit card.
    - A draggable maintenance-vs-eaten chart.
    - Every day of the month listed; tap one to see it or add food late.
12. **Today:** a "This week" card (deficit, protein, km, streak, sleep), and the strain card reads
    "Aim for about N today".

## Known limits

- **Voice cues with the screen locked are untested.** The personal build has no `audio` background
  mode (its capability contract forbids adding one without a decision), so iOS may hold the voice
  until the app is in front.
- **Logging weight changes the profile weight.** Resting energy and every calorie number then use
  the newest weight.
- **Measured maintenance needs complete food days.** It waits for 8 weigh-ins, 10 complete food
  days and 14 days of span inside the last 4 weeks.

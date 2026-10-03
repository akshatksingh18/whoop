# Next build — `0.9.36`/`69`

**State:** implemented in source with Akshat's decisions applied, and the local tests pass.
Building, installing and the phone check are the steps left. When the phone check passes, remove
this file's contents and record anything still open in `CLAUDE.md`. Shipped behaviour is described
in `CLAUDE.md` and `metrics-map.md`, not here.

## Akshat's decisions (applied)

- **Walk breaks inside a run:** costed as walking (0.1 per metre, not 0.143), so the distance
  number stays a minimum. Heart rate is used through Method 2, which covers walk breaks minute by
  minute.
- **Streak:** a day counts with at least 10 minutes of running or walking.
- **Removed:**
  - the Steps screen's list of stretches;
  - Today's "Tonight · Bed by" card;
  - the Sleep screen's Tonight section;
  - the wind-down reminder (read as off and hidden).
- **Breathing rate:** the Trends row shows only when the last 30 days measured it on at least half
  the nights slept. The rule is applied automatically, so no manual count was needed.

## Not done from the plan

- The reason a night's breathing rate was withheld is not shown under Readiness → What drove it.
  The row still says "Not measured". The reason is stored in the day bundle
  (`respiration.rsa.note`) if it is wanted later.

## Phone check for build 69

1. **Your 5 km run:**
   - Calories shows "From distance" and "From heart rate", or one number when they are within
     50 kcal of each other.
   - "Running · walking km" shows when the run had walk breaks.
2. **Food → Today, Maintenance:**
   - A RUNNING part shows on a day with a run.
   - Tap the card: each line names its own numbers.
   - Steps are the day's steps less the run's steps.
3. **Train:**
   - Run · Walk · Lift · Other.
   - The streak card counts days with 10 minutes or more.
   - Drag across the strain bars. Tap opens that day, with arrows to the other days.
   - Drag across distance per week.
   - Best times shows only 1K, 5K, 10K and half marathon.
4. **A walk started from Walk:** shows the map, distance and calories, with no best efforts or
   pace zones.
5. **A run not started in the app** (confirmed from "did you work out?"): within 7 days, with the
   phone carried, it shows distance, splits and cadence, marked "from your phone's motion sensor".
6. **Pull down on Today:** the spinner stays until the sync and the numbers finish. Pull down on
   Trends, Food and Train too. With the band off, a "Band not connected" note shows.
7. **Charts:** a finger shows a line and the date and value in the header. Check:
   - Trends → any metric, Month;
   - Readiness history;
   - Day strain;
   - Steps by hour.
8. **Sleep:**
   - No Tonight section.
   - Lanes named Awake / REM / Light / Deep.
   - Five clock marks.
   - Dragging shows the time and stage in the header.
9. **Today:** no bedtime card.

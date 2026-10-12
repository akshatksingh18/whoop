# Build 88 Proposal For Review

**Status:** approved by Akshat on 2026-10-12. Scope (section 1), the quality/history rules
(section 2) and every recommended choice (C1 note-only, C2 "—", C3 off, C4-C8 yes, C10
built-in review) are accepted, and the go-ahead for one combined Build 88 is given.
Implemented in local Build 88 source; `todo.md` owns its status and the few places source
deviates. It turns `build-88-plan.md` into plain language and sets the exact quality and history
rules (plan decision D2). The numbers are engineering rules tested on synthetic fixtures; they
are not clinically validated thresholds and still need checking on real nights.
Settled decisions are not reopened: strain target withheld (D3), health alerts respect quiet
hours (D4), historical weights chart-only (D6), food days count only when marked complete
(D13), and no body-fat estimate for non-male profiles (D7, since only Akshat uses the app).

## 1. What Build 88 Changes

### Numbers you will see differently

1. **Skin temperature disappears for the WHOOP 4.0.** The byte the app treated as temperature is
   not temperature. It stops affecting recovery, illness and "unusual night" alerts, and the
   Trends and Sleep temperature rows are hidden. Old stored values stay in the database untouched.
2. **HRV becomes stricter.** A night's HRV only counts when enough real, back-to-back heartbeats were
   recorded. Gaps in recording are no longer stitched together into fake beat-to-beat changes. On a
   thin night HRV shows "not measured" instead of a guess; a clearly labelled backup estimate sits in
   the details.
3. **Breathing rate appears more often and more honestly.** Today one gap anywhere in the night can
   cancel the whole night's breathing rate, and a stillness check that assumes gravity reads
   exactly 1 g throws away most of the night. Both get fixed, so you should see breathing on more
   nights, with each value backed by enough clean data.
4. **The Stress score needs real data.** It currently publishes from about 30 beats. It will need at
   least 20 minutes of clean recording, or it shows "not measured".
5. **Recovery explains itself correctly.** The "what drove it" breakdown and the Low-recovery alert
   now use the same calculation as the score on the ring (today they come from an older model).
   The baseline only uses nights from the last 60 days, so a long break never compares you with
   months-old data.
6. **Alerts calm down.**
   - All health alerts respect quiet hours.
   - An unusually *good* night, a single partial day, yesterday's still-arriving data or an
     imported day can no longer raise an alert.
   - The illness alert text no longer mentions HRV, because it only uses resting heart rate.
7. **Strain stops showing a target.** The score stays, labelled an estimate. Load history no longer
   treats days without data as rest days.
8. **Sleep fixes:**
   - Sleep regularity is computed the published way, over the whole day, with missing time excluded.
   - The backup sleep detector needs at least 3 hours, during night-time hours.
   - A later, longer real night can replace an earlier short one.
   - "Fix sleep times" warns you before saving when too little of that window was recorded; today
     it can silently publish no night.
   - The Home sleep bar compares last night with last night's need.
9. **Food and progress:**
   - A past day counts as "complete" only when you mark it.
   - The calorie card says "so far" on unfinished days.
   - Meal totals with an unknown item say "at least".
   - Protein advice uses only days where protein was fully logged.
   - The strength review says improved, same, down or "not comparable", and never calls unchanged
     lifts "stronger".
   - The body-fat estimate (male formula) shows the dates of both measurements and refuses
     implausible values.
   - Advice wording describes what was observed instead of claiming fat loss or muscle gain.
10. **Calories:**
    - A run whose steps were only partly recorded no longer makes the run's calories vanish.
    - Daylight-saving days get a 23- or 25-hour resting burn.
    - A stuck lift session cannot add hours of lifting calories, and overlapping lifts count once.
11. **Live run speed:**
    - It reacts faster (smoothed over seconds, not GPS points).
    - It recognises when you stop.
    - Average pace uses moving time.

### Things you will notice in daily use

12. **Today never shows an old night as last night.** If last night had no sleep recorded, Today says
    so instead of quietly showing an earlier night's recovery.
13. **Sync and calculation are more dependable:**
    - Calculations that were skipped because another one was running get retried, not marked done.
    - Background work stops properly when iOS asks.
    - The app cannot get stuck waiting for the band after switching apps.
    - A wrong future timestamp cannot make "Band data" say "just now".
14. **Better local diagnostics:**
    - Background sync steps are written to the app's own log file with times.
    - Problems can be traced without guessing.
    - Nothing leaves the phone.
15. **New look.** Five tabs and every feature stay. A new structural design is built on a warm
    light-brown background, chosen from the design board (section 5).

### What does not change

- Your calorie and protein targets.
- The Budget/ACSM coefficients.
- The readiness weights.
- No new permissions, cloud services or Apple Health.
- No SpO2 and no medical diagnoses.
- All stored history is kept. Days that can no longer be recalculated (raw band data is kept
  only about 3 days) keep their old values and are marked as calculated by the older method where
  the method changed.

## 2. Quality And History Rules Per Changed Metric

Each rule gets a test that fails on today's code and passes after the change. "Absent" means
the screen shows "—" or "not measured" with a one-line reason in details. Nothing is ever
filled in from another metric.

### Shared beat rule (all HRV, PRSA, irregular-rhythm, stress, breathing paths)

- **Adjacent beats.** Two reported beats form a valid pair only if their timestamps are adjacent:
  the gap between their reported times equals the second interval within ±250 ms. No rejected
  beat may sit between them. Anything else splits the run.
- **Plausible beats.** Intervals must be 300–2,000 ms.
- **Shared report seconds.** Several intervals reported in the same second keep the existing
  back-walk placement. They are not treated as exact ECG times; they only form pairs within the
  same record chain or across records that pass the adjacency test.

### HRV (headline nightly RMSSD)

| Rule | Proposed value |
|---|---|
| Window | 5 minutes of wall-clock time inside the sleep window |
| Window qualifies | at least 180 s covered by accepted beats, at least 120 valid adjacent pairs, artifacts at most 20% |
| Night qualifies | at least 6 qualifying windows (30 min) covering at least 15% of time asleep |
| Headline | mean of qualifying windows' RMSSD (current method, repaired) |
| Otherwise | absent; the labelled secondary estimate is shown in details only |
| Readiness input | headline only, never the secondary |
| Baseline | only nights computed by the new method (`rmssd_v2`); 14 needed; last 28 within 60 days |
| History | old nights stay visible in charts marked "older method", but never enter the new baseline. While HRV warms up (about 14 nights), readiness still works from resting HR, sleep and breathing (combined weight 0.57, above the 0.50 minimum) |

The same adjacency rule covers the HRV timeline, the 24/7 HRV curve, daytime HRV and PRSA. Their
windows need at least 60% beat coverage to plot a point. The Sleep HRV row never falls back to
averaging chart points.

### Breathing rate (RSA)

| Rule | Proposed value |
|---|---|
| Window | 300 s at 50% overlap (unchanged) |
| Window qualifies | at least 70% of the window covered by accepted beats, artifacts at most 30% |
| Frequency ceiling | from that window's own mean beat interval, not the whole night's |
| Night qualifies | at least 6 qualifying windows, with the existing 50%-within-2-breaths consensus |
| Stillness gate (overnight lane) | movement within 0.02 g of that window's own median magnitude (relative), on 90% of the window |
| Breathing variability | the same 30% artifact gate (today it is skipped) |
| History | stored breathing is the same quantity, so the baseline keeps old nights. Nights the old gate refused simply stay absent |

### Stress score

- At least 20 minutes of accepted beats in total and at least 3 qualifying 256-beat windows.
- A window's time span must be no more than 1.3× the sum of its beat intervals, so a window with a
  hidden gap is refused.
- Otherwise absent.
- History: old scores stay in storage, but the hidden Stress screens stay hidden.

### Irregular-rhythm screen

- Uses the shared beat rule and needs at least 3 hours of covered sleep.
- **Recommended:** the result appears only as a details-only note, "irregular pattern seen —
  not a diagnosis", with no push notification. A sparse-beat wrist screen is not AFib detection.
- This recommendation needs your yes; see choice C1.

### Temperature (WHOOP 4.0)

- **WHOOP 4.0, unknown-family and imported values.** No temperature value in any calculation,
  alert, baseline, export total or screen.
- **Other families.** Gen5 hardware with a verified sensor keeps its own path, which does not apply
  to your band.
- **History.** Stored `skin_temp_*` rows stay in the database. Every reader skips them for WHOOP 4.0,
  unknown and imported days. Old readiness scores are not rewritten.

### Readiness (recovery score)

- The inputs, weights, 14-night minimum, at least two inputs and 0.5 combined weight stay unchanged.
- **Baseline.** The last 28 eligible values, only from the last 60 calendar days.
- **Explanation and alert.** The breakdown under the ring and the Low-recovery alert both use this
  same score. Its band scheme is 61/37/26.
- **Low-recovery alert.** At most once per day, only after the night is complete, respecting quiet
  hours, and only when the score is below 26.
- **Quantum check.** The resting-HR check uses 0.5 bpm for its 30-minute average, not whole bpm.
- **History.** Stored readiness for past days is not recalculated. New days follow the new rules.

### Health detectors (illness CUSUM, anomaly, resting-HR shift)

- **Input days.** Only settled days, so both today and yesterday are excluded until finalised.
  Imported and other-band days are excluded too.
- **Direction.** Anomaly fires only for a worse direction: higher resting HR, lower HRV or higher
  breathing.
- **Resting-HR shift.** Called with real dates; evidence older than a 7-day gap restarts it.
- **Notifications.** All respect quiet hours, once per finding.
- **History.** Detectors rerun from stored daily values with the new filters, so no raw data is
  needed.

### Training load and strain

- **Observed days.** A day's load counts only if the band recorded at least 16 hours that day.
  Otherwise the day is "unknown", never zero.
- **Fitness/fatigue.** These are computed only over runs of observed days.
  - 1–2 unknown days inside a run are skipped (no decay).
  - 3 or more end the run.
  - Fatigue needs 7 observed days and fitness 28 before either is used.
  - Uses net load, not gross.
- **Strain score.** Unchanged and labelled an estimate. No target is shown.
- **Dependents.** The sleep-need strain bonus and the "strain 14+" pattern are marked as estimates.
  They switch off on days whose strain is not observed.
- **History.** Stored daily strain values are kept. Load summaries recompute from them with the new
  unknown-day rule.

### Sleep

| Item | Proposed rule |
|---|---|
| Main night | at least 3 h in bed, at least 50% observed (unchanged) |
| Backup (heart-rate) detector | also at least 3 h, starting between 18:00 and 06:00 local, unless you set the window |
| Replacement | a later night ending the same day with more sleep replaces the earlier pick |
| Manual correction | save is blocked with a message when under 50% of the window was recorded |
| Sleep regularity | minute grid over the whole day; only minutes recorded on both days count; needs at least 5 day-pairs each at least 70% recorded |
| Fell asleep / bedtime | labelled "in bed at" when taken from the in-bed start |
| Home sleep bar | last night ÷ last night's need |
| History | past nights are not restaged (raw data is gone). New nights use the new rules; regularity recomputes from stored hypnograms |

### Food, weight and progress

- **Complete day.** Only when you mark it (settled). The 19:00 default and evening-entry shortcuts
  no longer count.
- **Unknown values.** Meal and day totals with unknown items say "at least". Unknown protein is never
  counted as 0.
- **Protein advice.** Needs at least 5 protein-complete days in the window.
- **Food/weight maintenance estimate:**
  - Needs at least 14 complete days and at least 8 weigh-ins, with at least 3 weigh-ins in each half
    of the period.
  - Uses a robust slope (median of pairwise slopes) and shows a ± range.
  - It is hidden when the range is wider than ±300 kcal/day.
  - It never sets targets.
- **Waist and tape changes.** Only compared with a reading from within 7 days of the period start,
  and always dated.
- **Strength comparison:**
  - The same in Review and live: same exercise, load meaning and equipment.
  - For 1–12 reps it uses the rep-adjusted score, otherwise reps at the same load.
  - A heavier-but-fewer-reps pair with no same-load match is "not comparable".
  - The trend is shown over a stated date span.
- **Body-fat estimate.** Male formula only. Hidden outside 3–50%, or when the neck reading is more
  than 30 days from the waist reading. Both dates are shown.
- **Recomposition verdict.** Uses the weight trend plus waist and comparable lifts. Missing waist or
  lift data means "not enough data", never "no progress".
- **History.** All raw logs stay. Reviews recompute from them.

### Calories

- **Partly recorded run steps.** The run keeps its calories, and only the uncovered steps are priced
  as walking.
- **Resting burn.** Scaled by the day's real length (23, 24 or 25 h).
- **Lifts.** A session with a fabricated end time, or one longer than 4 hours, gets no lifting
  calories. Overlapping lifts count once.
- **History.** Past days recompute from stored inputs.

### Live run speed

- **Smoothing.** Over time, a time constant of about 5 s.
- **Stopping.** No accepted fix for 5 s while slowing below 0.5 m/s means "stopped".
- **No fix for 10 s.** The current speed shows "—" or the labelled average (choice C2).
- **Average pace.** Uses moving time.
- **Constants.** Confirmed by a real outdoor walk and run before they are fixed.

### Freshness and sync (deterministic, no thresholds to tune)

- **Last night.** "Last night" means a night with recorded sleep; otherwise Today says none was
  recorded.
- **Skipped calculations.** Retried.
- **Background stop.** Stops every calculation and the band transfer at a safe point.
- **Band wait.** At most 20 s, then the normal reconnect path.
- **Timestamps.** Ones more than 10 minutes in the future, or missing, never move "Band data".
- **Version.** One algorithm-version bump (92) for all output changes.

## 3. Optional Choices Explained

| # | Choice | What it means | My recommendation |
|---|---|---|---|
| C1 | Irregular-rhythm note | Keep the wrist-beat pattern check as a details-only note with no notification, or remove it entirely | Details-only note |
| C2 | Live speed with no fresh GPS | When the phone has had no new GPS fix for 10 s: show "—" for current speed, or show the session average labelled "avg" | Show "—" and keep the average as its own separate number |
| C3 | Keep raw optical bytes | Store about 7 days of the unexplained band sensor bytes (roughly 15–20 MB) so a future study could find out what they are, possibly real skin temperature. It does not fix anything now | Off, unless you want that research later |
| C4 | Data-quality line | Under each metric's details, one line such as "HRV not measured: 3 of 6 needed windows" | Yes, it makes "not measured" understandable |
| C5 | Sync health panel | In Settings → Status: when the band last woke the app, transferred, saved and calculated, with ages | Yes, it is cheap and helps sync debugging |
| C6 | Measurement prompts | When logging tape: a reminder to use the same spot and time; an optional second reading; and the app records weigh-in time, so "morning weight" is true | Yes |
| C7 | Food/weight range | Show the maintenance-from-weight number as a range ("2,350–2,650") instead of one number | Yes, already in the rules above |
| C8 | Per-alert controls | A Settings list to set each health alert type on or off | Yes, small |
| C9 | Chest strap reference | Deferred, as you said | Not now |
| C10 | Finish reviewer | See below | Use the built-in degraded review; install the agent only if you want the extra check |

### What the "finish reviewer" is

Impeccable, the design tool, has an optional helper called the **finish reviewer**. After a
screen is built, it starts a fresh AI assistant that has not seen the build conversation. It looks
only at the screenshots, the chosen design direction and the quality rules, then lists what is
off: misaligned spacing, weak contrast, controls that do not look like iPhone controls, text that
gets cut off.

The point is a second pair of eyes that is not biased by having built the screen. Installing it
means copying one small definition file from Impeccable's pinned source into `.claude/agents/`.
Without it, Impeccable has a written checklist version that I run myself in a fresh session.
Either way it is a review aid, not a requirement. Each run costs some usage, like any other agent.

## 4. History And Version Summary

- **One algorithm-version bump (92) covers every output change.** Only the last ~3 days can be
  fully recalculated, because the raw band data is gone after that.
- **Changed methods.** HRV, stress, breathing gates, sleep regularity and alerts: older days keep
  their stored values, marked "older method" where shown, and are never mixed into a new-method
  baseline.
- **Unchanged quantities.** Resting HR, sleep duration and stored breathing keep their full
  history for baselines.
- **Temperature.** Nothing is deleted; it is simply never read for the WHOOP 4.0.
- **Before installing.** Take an encrypted backup, copied off the phone.

## 5. Design Options

The options were made with Impeccable's direction round, entirely locally; nothing was uploaded.
The phone-sized pictures are in `.impeccable/mocks/decision/`, with one PNG per option and
`board.html` showing all five. Each option is a phone-sized Today screen with
synthetic numbers on your requested warm light-brown ground, with the data on top.

| Option | Feel | Strength | Risk |
|---|---|---|---|
| **Earth Pigment Studio** (Impeccable's assigned direction) | Warm sand paper. Each area owns one earth colour: recovery green, sleep indigo, strain terracotta, food ochre. The last 7 days show as small colour tiles | Rich colour that still separates cleanly; very glanceable | Five colours must stay disciplined |
| **Training Logbook** (my pick) | Kraft cover with a cream ruled page, pencil-dark ink, red pencil for records. The week is ticked day by day | Personal and calm; missing days are obvious as blanks | The most familiar idea; could feel like a paper costume if overdone |
| **Departure Board** | Warm tan with white panels and tabular numbers. Anything new or stale is highlighted amber until you look | Best at honesty about fresh vs old data | Feels more like a utility than a personal app |
| **Print Annual Plate** | Warm stock, crisp black numbers, hairline grid, tiny corner marks | Very clean and readable | Least colour and warmth |
| **Category standard** | Apple Fitness-style rings and white grouped cards on warm sand | Instantly familiar | Looks like many other apps |

**Shortlist (Akshat): options 1, 2 and 3.** Recommended combination, pending Akshat's
approval (`combined.png`):
- Earth Pigment Studio as the base world.
- From Training Logbook, a hatched blank for every missing day.
- From Departure Board, an amber "new" marker that stays until seen, plus amber
  missing-data rows.

One world owns the page; the other two lend only these behaviours.

**Revision 2 (Akshat):** option 2's deeper kraft ground (`#D9C3A0`), with all the data on one
cream panel (`#F4EBDA`) above it; option 1's colours and option 3's markers are kept. Still
pending approval.

**Variation round (smoother 26 px corners):** `.impeccable/mocks/variants/` sheets 1-2.
- Kraft darkness: A light `#E4D3B5`, B medium `#D9C3A0`, C deep `#C9AE84`, D cocoa `#A98A62`.
- Colours: E jewel earth, F soft muted.
- Numbers: G big hero, H compact.
- Layout: I separate panels, J bar charts.

Akshat picks one per axis.

**Chosen (Akshat, 2026-10-12):**
- C deep kraft, E jewel colours, G big numbers;
- single panel with tiles, and J bar charts on Trends.

Recorded in `DESIGN.md`. **Locked by Akshat on 2026-10-12**, including Trends lines at 30 days and
3 months. Screen set: `.impeccable/mocks/screens/`, covering Today,
Trends, Food, Train, Progress, Sleep, Recovery and Live run.

Tell me the number you like, or a steer such as "warmer" or "more colour" for a new round. After you
pick:
1. I write `DESIGN.md` with the exact colours and type scale.
2. I sketch the other four tabs in the same direction.
3. You approve the full phone-sized layouts. Swatches alone do not pass.

Only then does any Flutter code change. Your request pins a light warm-brown ground. That replaces
the earlier "avoid a brown/orange wash" note and makes Build 88 a light-appearance design; the
current app is dark-only.

## What I Need From You

1. Approve or adjust the scope in section 1.
2. Approve or adjust the rules in section 2. Any number can be changed.
3. Answer choices C1–C8 and C10.
4. Pick a design direction on the board.
5. Then give the implementation go-ahead.

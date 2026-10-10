# WHOOP As An All-In-One Fitness App

**State:** Approved for implementation in Build 86 (one build); in progress, not yet built or
phone-tested. Akshat accepted the integrated workout, Body and one Progress page, selecting repeat
last set, rest timer, comparable records and photo comparisons, plus workout times and historical
body/photo entry. Imported/backdated weights are history-only and never change past calorie
numbers. Publication, AkshatOS removal and entry-ownership cutover still need separate approval.
The expanded requested plan includes explicit seven-day weight/diet correlations, weekly/monthly
whole-body reviews, goal-aware intake reviews, general activity/rest protection, food/navigation/
chart/action repairs and a structural UI redesign. Pushup Reminder is requested exploration,
with parity/capability/ownership choices open; `build-86-audit.md` owns source findings.
Akshat's confirmed goal is **recomposition: leaner while getting stronger**.
Build 85 remains installed with Today / Trends / Food / Train; AkshatOS retains Lift
Log and Body. `todo.md` owns combined approval, `lift-log-integration-plan.md` owns exact lifting
parity, and `../akshatos/hub-plan.md` owns the unchanged cross-project boundary.

## Product Direction

One app for wearable measurements, training, food and body progress, with one entry per real
event. A workout is not separately started in two apps; a weigh-in is not copied between three
screens. Progress brings these records together without turning HR strain, weight loss or an
estimated body-fat percentage into a fabricated measure of muscle gain.

Accepted overall direction (details remain subject to final scope review):
- **Today:** keep the existing daily wearable view; add compact weigh-in/measurement shortcuts
  and a link to Progress, not a second detailed progress dashboard.
- **Trends:** retain all existing reachable wearable metrics and drill-downs.
- **Food:** retain foods, diary, macros and Budget/ACSM maintenance. Its weight entry uses the
  same record as Body; keep the existing entry point unless Akshat approves removing it.
- **Train:** retain Run / Walk / Lift / Other and existing history. Lift includes the set logger.
- **Progress:** planned fifth tab, one consolidated recomposition page with Body entry/history
  and drill-downs. Body is not a sixth tab or a separate app inside the app.

A Progress destination reachable from Today remains a possible later layout revision, not an
instruction to change the accepted overall direction. No navigation has shipped. No existing
metric or removed journal/AI coach is silently removed or restored by this plan. Retain shared
accessible control conventions but redesign hierarchy, composition and flow, not just colours/
rings. Use compact unframed sections, stable chart dimensions and familiar icon controls;
no marketing screen or explanatory wall.

## Exactly How A Lift Would Work

1. Open Train, choose Lift, and choose a saved split, Empty workout or tracking only. Split choice
   does not change the selected activity's calorie assumptions.
2. Tap Start once. Create one durable WHOOP session and its optional lift draft. Show existing
   elapsed time, HR, strain, calories and Pause/Finish above the exercises and set-entry controls.
   Show the saved local **Started** time as well, without replacing the elapsed timer.
3. Log load/reps, see all sets from the last same-mode performance, and add/search/reorder/remove
   exercises using Lift Log's current rules. Each edit/delete/Undo saves before success is shown.
4. Leave the screen or lock the phone; resume the same workout and saved sets. Set entry works
   without a connected band; unavailable sensor values remain unavailable.
5. Finish once, producing one history entry and summary containing both wearable context and
   exercises/sets. A tracking-only zero-set workout stays valid. Forgotten-finish review must
   explicitly choose Now versus Last logged set; it must not silently extend or shorten time.

**Workout-time requirement:** all existing live workout types should show their persisted start
time; summaries show start and actual saved end, with dates when crossing midnight and respecting
the system's 12/24-hour display. Pause/resume and reopening must not reset Started. Reuse the
session row/`WorkoutClock`, not a new `DateTime.now()` or an active-duration-derived start/end.
Active time and total elapsed time remain distinct. Unknown/reconciled ends stay explicitly
unknown; a reviewed last-set end is labelled as the user's selected end, not sensor-measured.

Port Lift Log's domain behavior into Flutter/SQLite rather than embedding the entire SwiftUI hub
or keeping two active stores. Preserve its six load meanings, pounds, editable splits, complete
previous performance, skips/order, recovery, history and exports. The existing unused strength UI
and `saveStrengthSets` are a foundation to repair, not an already-working parity switch.

## HR And Workout Synchronization

- Session ID and `WorkoutClock` are the shared authority for start, end, profile and manual
  pauses. Store set-event timestamps on that session's absolute timeline; local dates are display
  and reporting labels, not a second clock. Relaunch, midnight and clock changes need tests.
- Plot logged-set markers against the recorded HR timeline. A set's `completedAt` means it was
  logged/completed then, not that the app measured its start, duration or every repetition. Do not
  assign the entire gap between entries to the next exercise or claim exact per-set HR/calories.
- Keep measured HR during rest as context and preserve manual pause behavior. Logging a set is
  not a pause/resume command. Live high-rate sensor streams stay RAM-only; durable history
  supports later analysis.
- Missing HR remains a visible gap, not a zero, interpolated proof of effort or muscle-strain
  estimate. Later offload updates the same workout's wearable summary with input-revision and
  coverage information; it does not duplicate sessions or rewrite manually logged sets.
- Existing `ClockPolicy` guards unsafe band/phone disagreement. Do not shift/snap stored 1 Hz
  records using `ClockRef`: its drift is not an approved historical timestamp correction. If
  clocks disagree, withhold a precise set/HR association until it is trustworthy.
- Retain build-85 MET-only lifting calories, captured body weight, active time and between-set
  rest. HR and set volume do not price lifting, and lifting is not added into maintenance.
- One notification coordinator must reconcile WHOOP's quiet-HR prompt and Lift Log's one-hour
  no-entry reminder. No automatic end based on low HR, rest or a missed notification.

## Body Inside WHOOP

Preserve Body's current features (`../akshatos/body-log.md`): one weigh-in per local day; trailing
seven-calendar-day averages; measurement-week blocks; eight optional tape sites; editing/history;
front/side photos and comparisons; optional weekly measurement reminder; CSV and full recovery.
Keep the circumference body-fat estimate clearly labelled, secondary and dependent on its actual
inputs/formula. Neither tape nor photos are a direct measurement of muscle mass or fat lost.

**One weight source:** extend WHOOP's existing `body_weight` path, not an independent Body weight
table that can disagree with Food. Retain kg for calculation and original input unit/value,
source UUID and recorded timestamp for lossless import/export and pounds display. A rounded
display conversion must not replace calculation precision.

Use a shared durable weight mutation across Body and Food. Logging today's weight may update the
current profile consistently; importing an old entry must not act like today's weigh-in or
reprice a workout's captured profile. Preserve dated `ProfileHistory` precedence. WHOOP's current
`BodyWeight.put` stamps the write as now, so it cannot be reused unchanged for historical import.
Review affected derived-output/version policy explicitly; do not silently rewrite sealed days.

Use the same profile height for Body estimates and existing calculations, with explicit conflict
review between WHOOP cm and imported Body inches. Preserve measurement UUIDs, individual site
keys (including unknown newer keys), recorded timestamps and missing values. Body's measurement
weekday remains a Body setting, not an accidental change to WHOOP's Monday weekly report.

Photos remain app-owned local JPEGs, loaded only when viewed, with front/side date and pose labels.
Preserve orientation and strip location metadata on capture/pick; no background gallery scan,
external photo analysis, telemetry attachment or public-repository media. Use selected-photo
access where possible. Update camera/picker privacy descriptions and personal-iOS validators
when implementation is approved: current WHOOP descriptions cover food scanning/file import,
not retained body photos. Photo work is foreground/user-initiated, not part of a BLE wake.

### Historical Entry

An Add entry action opens a date picker with today preselected, allowing a past calendar date for
weight, any supported tape measurement or a manually attached photo. Edit/delete works at that
date as well. Keep the effective measurement/photo day distinct from creation/import time and
unknown actual capture time; a screenshot's new EXIF time must not silently assign it to today.
Permit multiple photos per day and a photo without a weigh-in. Removing a weight does not remove
its day's photos. Existing same-day weight replacement requires visible review/confirmation.
Historical additions refresh affected charts/comparisons without becoming a new current profile
weight or repricing captured workouts. This is not permission to invent/backdate sensor steps,
HR, nutrition or timed workouts that were never recorded.

## The Single Progress Page

Header: Recomposition and a chosen journey baseline, followed by a compact body-history chart
with the two selectable controls below. Show latest available dates and coverage by data family.
Do not make a combined opaque score or require fresh wearable data to view saved body/lifting records.

### Measurement And Range Controls

Use the MyFitnessPal screenshots as interaction references, not a pixel copy or an instruction to
add advertising/premium blocks. Keep WHOOP's visual grammar and the all-in-one page:
- **Measurement menu:** Weight, Steps, Neck, Waist, Hips, plus the other existing Body tape sites
  (lower belly, chest, shoulders, right upper arm and right thigh). Changing the metric changes its
  chart, units, summary and dated entries; it does not delete data or replace wearable Trends.
- **Range menu:** 1 week, 1 month, 2 months, 3 months, 6 months, 1 year, Since start and All.
  Use explicit calendar boundaries/end dates and one shared date policy. Since start uses the
  chosen journey baseline; All can include records before it. For a site with no baseline reading,
  show its first actual reading in range with its own date, not an invented start value.
- **Summary:** for weight/tape, Start / Latest / Change with actual dates and appropriate units;
  Latest means latest in the chosen range, not necessarily the latest available today. Raw
  endpoint change is distinct from the seven-calendar-day weight trend. No zero/default start
  when a comparison is unavailable. Steps use period totals and covered-day averages rather than
  body-measurement-style "weight lost" statistics.
- **Chart and entries:** show recorded points without manufacturing daily observations. Weight
  can offer Readings / 7-day trend, with coverage; tape uses actual measurement dates. Recommend
  filtering the associated entries to the selected period, with an explicit All history route so
  an old row is not displayed beneath a newer range's statistics without context.
- **Entries:** newest first, date/value/unit, edit access and photo thumbnail or attach-photo
  action. Open the selected day's records/photos. On narrow screens wrap menus and summary
  content without hiding date context; retain stable chart/photo sizes.

Recommend a compact recent-entry preview on the consolidated page, with full dated history and
photo comparison opening from it. A long imported entry list must not push every strength/food/
recovery section out of practical reach. The full history screen retains the measurement/range
controls and chronological list inspired by the supplied screenshots. Compute range summaries
from actual dated records rather than copying a screenshot's cached header or inventing a row.

The body metric selection does not switch the entire app to a weight-only dashboard. Strength,
food, activity/recovery and the weekly review remain lower sections with clearly stated periods.
Journey-start comparison and a future user-chosen goal-phase baseline must remain distinguishable;
do not reset earlier history or change private coaching anchors when importing the journey.

1. **Body progress:** seven-day weight trend beside waist change, other selected tape sites and
   same-pose photo comparison. Weight is context, not a lower-is-always-better success indicator.
   Show actual measurement dates; do not carry an old waist into a new week as a fresh reading.
2. **Strength progress:** sessions and logged sets, with exercise-level comparable history. Show actual
   same-load rep improvements or same-rep load improvements using matching load meaning and
   equipment context. A heavier stack number on a different machine is not a comparable PR.
   Pinning and warm-up flags were not selected; use an exercise selector and label counts as
   logged sets, not working/hard sets. Comparable records are selected as detailed below.
3. **Food consistency:** calorie/protein averages over eligible logged days, target coverage and
   number of days included. Missing food is unknown, not zero intake or proof of adherence.
   Preserve Budget/ACSM and the separate approximate food/weight maintenance estimate; do not
   add them together, automatically change targets or invite eating back lift calories.
4. **Activity and recovery:** recorded steps, run/walk distance, training frequency, sleep and
   recovery context over matching periods. Higher strain is not automatically better progress;
   associations are descriptive, not proof that a sleep or food change caused a lift result.
5. **Combined review:** weekly, monthly and since-start source-linked observations across body,
   strength, daily intake and recovery, with evidence-qualified goal review and one useful next
   action. Preserve a complete review after Monday; it is not only a transient Week card.

Illustrative only, not Akshat's data: weight broadly stable, waist lower and the same-mode lift
improving can be displayed together as observations relevant to recomposition. The app must not
translate them into "X kg muscle gained" or a precise body-composition verdict.

### Comparison Rules

- Reuse recorded observations and local fact templates; no cloud/LLM service is required.
- Weight smoothing uses available readings in seven calendar days, with the observation count.
  Sparse data should show what is recorded without a strong trend verdict. Baseline and end
  windows must be explicit; a single baseline reading is not a seven-day mean.
- WHOOP's existing Monday report and Body's measurement-week blocks are different. Recommend
  Monday-to-Sunday for the combined closed-week review, preserving Body's chosen weekday in its
  own history. Compare tape entries at their real dates, not invented weekly samples.
- Current partial weeks must not be presented as like-for-like full-week totals. Show counts and
  interval lengths; mark missing/partial HR, food, sleep and body data separately.
- `WeekNumbers.weightChangeKg` is first-to-last weight, not a smoothed trend delta. Reuse its
  eligible queries where appropriate, not that label for the new Progress comparison.
- Compare strength only after comparable recorded performances exist. Preserve current previous-
  performance parity; new insight comparisons need stricter equipment/context review where the
  old normalized-name-plus-mode match is insufficient. No aggregate "kg lifted" across meanings.
- Save goal/baseline choices without deleting earlier history. If weekly summaries are persisted,
  version their inputs and label revisions after late data or edits. Do not freeze stale facts or
  silently mutate existing immutable daily metrics. Review the algorithm-version decision.
- The hidden run/walk Training review is not a strength/recomposition engine. A new page does not
  automatically restore that removed entry point or reuse its bounded notification history as an
  unlimited progress ledger.

### Seven-Day Weight, Diet And Whole-Body Reviews

This is explicit requested scope, not a promise that build 85 already does it. One local review
model joins dated source records without duplicating them. Every observation links to its inputs
and shows its own coverage; missing data in one family must not hide all the others.

- **Daily intake:** show recorded kcal/protein and the chosen dated goal, alongside Budget and
  ACSM maintenance estimates, eligibility and estimated balance. Keep a per-day drill-down and
  a trend overlay with separate scales/units. A late evening food entry is only the existing
  completeness heuristic, not proof that every meal was logged. A user-marked Complete/
  Incomplete day is a proposed safeguard to review, not an implemented requirement.
- **Seven-calendar-day weight mean:** average actual daily weigh-ins in the trailing window,
  show the reading count/date span and never forward-fill missing days. Preserve raw readings
  and raw start/latest change alongside smoothing. Historical weekly-only imports can yield
  one observed reading in a window, not seven new measurements or a confident weekly slope.
  Compare explicitly labelled endpoint windows, not the first/last raw value relabelled Average.
- **Weekly:** recommend the last closed Monday-Sunday against the prior closed week, selectable
  on any day. Current week remains available with a partial label and matched elapsed-day
  comparison. Combine weight means/raw readings, waist/site changes at actual dates, same-
  context lift comparisons, completed sessions/activity, eligible calories/protein and measured
  sleep/recovery. Do not hide recorded protein because maintenance is missing.
- **Monthly:** calendar month against the preceding complete month, with day-count and coverage
  context rather than treating 28 and 31 days as identical training totals. Current month is
  partial; compare matching elapsed periods. Measurements report real paired dates and elapsed
  days, even if they fall outside the reporting boundary; no fabricated month-end reading.
- **Since start/ranges:** retain the chosen journey baseline and the existing 1 week, 1/2/3/6
  months, 1 year, Since start and All controls. A future goal-phase baseline is separate from
  the weight-loss journey and never deletes it. Compare strength only where both ends have
  compatible exercise/equipment/load meaning; show new lifts without invented baseline records.
- **Diet correlation:** compare estimated balances with observed weight trends over aligned
  multi-week windows, not same-day scales. Water, glycogen, food contents, measurement timing,
  logging omissions and expenditure uncertainty can obscure the relationship. Show associations
  and discrepancy, not "this meal caused this weight change" or exact fat lost from calories.
  Keep the food/weight maintenance estimate distinct from Budget/ACSM and label its assumptions.
- **Body and strength together:** stable/down weight, lower waist and improving comparable
  performance can be described as consistent with the stated recomposition goal. Changes at
  chest/arm/thigh/shoulders can be shown but cannot identify muscle versus fat, fluid, pump or
  tape placement. More load/reps is observed performance, not measured muscle mass. Circumference
  body-fat estimates remain labelled estimates; no photo-based body-composition classifier.
- **Coverage:** calorie-day eligibility, complete protein, paired food/maintenance, weight,
  tape sites, logged sets and wearable measurements use independent denominators. Unknown
  nutrients can be lower bounds, not complete totals. Preserve dated targets/profile rules;
  no invented food or workouts accompany the screenshot weight import. Recompute affected
  reports after edits/backfill/import with visible input revisions and bounded queries.

### Goal-Aware Intake And Training Review

The user's question "should I increase or reduce intake?" belongs in the combined review, but
not as an automatic diet prescription. Use deterministic local fact templates, not a reinstated
AI coach or uploaded health history. A proposed review shows: observed changes, included dates/
counts, relevant uncertainty, then a decision to consider and a link to review the goal.

- **Continue:** comparable performance is improving and the body trend fits the user's goal,
  with sufficient recorded evidence; do not demand lower weight every week.
- **Gather evidence:** sparse weigh-ins, incomplete meals, changed machines, missing tape or
  stale sensor data prevent a useful comparison. Suggest the specific missing record rather
  than inventing a verdict or reducing intake by default.
- **Review fueling/recovery/training:** repeated performance decline plus weight trend/intake
  context warrants reviewing food, recovery and training together. A short plateau or one
  poor sleep is not grounds to cut calories or diagnose low energy availability.
- **Consider a deliberate adjustment:** only after a sustained, adequately covered window,
  stable goal phase and an explicitly reviewed rule. The user edits/applies the target; never
  silently overwrite it, eat back lift calories or combine expenditure models. Numeric change
  sizes, minimum coverage/window thresholds and any protein recommendation need approval and
  safeguard tests before activation. The existing approximate maintenance estimator is evidence,
  not an exact strength-phase calorie prescription.

For a strength emphasis, surface comparable lift progress, training consistency, adequate fueling
and protein coverage, and sleep/recovery context. Do not auto-prescribe an exercise programme,
aggressive deficit, surplus or supplement. Significant unexplained changes, persistent poor
recovery or a medical/nutrition concern warrant qualified review, not stronger app certainty.
No diagnostic muscle-loss claim is possible from the currently planned inputs.

The public evidence and limits are linked in `build-86-audit.md`: NIDDK's dynamic energy model,
the resistance-training/energy-deficit meta-analysis and a protein/exercise randomized trial.
Group evidence supports cautious design, not direct personalization from sensor logs. The review
should answer "what does our evidence suggest?" while allowing "not enough evidence yet".

### Activity, Rest Protection And Pushups

General activity includes completed purposeful physical sessions (including lifting) and dated
step-goal achievements, with a reviewed Pushups-goal contribution. One day is counted once.
Keep Pushups' own daily-goal streak distinct from the general activity continuity display.
Rest or Life happens protection preserves continuity visibly without recording a nonexistent
workout, steps, calories or Pushups goal. Exact threshold/allowance/retroactive rules remain for
approval; a weekly-consistency view is an optional companion, not forced daily hard exercise.
Distinguish pending activity data from a confirmed inactive day; reconcile late backfill against
that day's protection ledger without fabricated activity, duplicate awards or a false break.

Proposed Pushups location: Train -> Movement breaks / Pushups, with compact Today Start/Done
access. Reuse its existing Start/Pause/End, interval, automatic nudges, daily goal/history and
protected action receipt semantics; preserve the `Squat*` source identifiers when importing.
Done records a completed set event, not measured reps/duration/HR or strength-log tonnage.
It never starts/stops the user's WHOOP workout or duplicates expenditure. Progress can show
actual completion/consistency with its own dates and coverage.

WHOOP needs one early notification coordinator, categories/payload namespaces and a shared
pending-request budget. Do not install a competing native delegate or cancel other reminders.
Persist Done/Pause receipts before finishing a cold/locked callback, replay idempotently and
retain receipts on write failure. Only notification taps navigate; actions must not pull the
user away from another tab. A finite queue cannot promise indefinite ignored nudges between
infrequent visits. Prioritize existing critical alerts; review Pushups' current 60-request
batch alongside rest/Body reminders with actual pending-request tests.

Home auto-pause is optional in AkshatOS and uses Always location; WHOOP currently excludes this
personal permission. Preserve that boundary until an explicit parity/capability decision, rather
than silently dropping Home or adding Always for a walk. Local JSON import must preview IDs,
goal snapshots and history, keep active-reminder restoration opt-in, and require stopping the
old batch before enabling the new one. No AkshatOS feature/store is removed and no two-app
background synchronization is promised. `../akshatos/hub-plan.md` owns the cross-project gate.

### Structural UI And Safety Requirements

Prototype new full flows, not isolated recoloured controls: compact Today status/freshness with
usable HR history, stable workout controls with integrated sets, diary-first Food, and Progress
opening on body/strength evidence then a combined review. Keep the proposed five destinations
and all existing unique metrics available; ask before deleting any metric/entry point. No sixth
Body/Pushups tab, marketing hero, explanatory wall or nested cards.

Use shared chronological controls; fixed-size expansion/action hit areas; confirmed destructive
menus; consistent portions and user labels; current versus average speed; full-night chart reads;
and maintenance status separate from diet-goal progress. Loading, genuinely empty, partial,
stale, offline and failed-save states must be distinguishable and preserve user edits. Plan
large-text/narrow-screen/VoiceOver/back-gesture and tab/date/filter state QA. Nice-to-have
shortcuts and optional Food-day completeness remain review choices in the audit/TODO.

## Import, Recovery And Cutover

User-selected local imports only: Lift Log JSON (or hub `lift-log.json`), Body's
`body-log.json` plus `photos/` (or hub `body/`). Preview validated records, date/unit/height
conflicts, missing media and duplicates before committing. Preserve original IDs/timestamps;
repeating an import must be idempotent. Same-day weight conflicts need an explicit choice, not
last-import-wins. Existing workout linking is reviewed, not an automatic time-overlap guess.

Historical lift-only records can supply previous performance and strength comparisons without
fabricated HR, strain, workout duration or additional expenditure. Body import similarly cannot
invent food/recovery data. Unknown fields need round-trip preservation where the source contract
requires it. Use synthetic parity fixtures, not private health records in tests or source.

### Screenshot-Based MyFitnessPal Import

Akshat cannot export his MyFitnessPal history and supplied screenshots for a later generated
import. He requested documentation now, not app code or an import file. The private canonical
inventory is `../../health/fitness/docs/myfitnesspal-import-source.md`, with weights in that
project's existing `data/weight-log.csv`. Follow its `CLAUDE.md` before reading/generating data.
Do not copy personal readings, screenshots, photo dates or generated payloads into either public
app repo or hosted CI. Public tests use synthetic fixtures only.

During approved implementation, generate a versioned local body-history import from that private
source and validate it against the implemented importer. Include source attribution, original
unit/value, day precision, deterministic generated IDs and a baseline reference. Original
MyFitnessPal timestamps/UUIDs are unknown; generated IDs and import timestamps must not masquerade
as them. Preview count/date/unit interpretation, duplicates and existing same-day conflicts;
commit only after confirmation and make re-import idempotent.

These screenshots provide weight only, not numeric tape/steps/food/HR data. Import everything
actually supplied, with other data absent. Small photo thumbnails are association evidence, not
full images to harvest. Akshat will manually add screenshots of the original photos to their
chosen historical days; attaching them does not require rerunning or replacing the weight import.
The future generated payload stays in the private health source area, not the app repository.

Current gaps to resolve before authoritative use:
- WHOOP automatic `.osbk` recovery seals a compressed SQLite snapshot, not external JPEG files.
  Design and verify a versioned encrypted database-plus-media payload before photos become
  authoritative. Keep old encrypted/database backups readable and unsupported new formats
  explicitly rejected by older readers. Stage files/database with rollback, bounded memory and
  corruption/path/low-disk validation. Final payload design remains an implementation decision.
- AkshatOS Body's current `stageBackup` omits photos whose files cannot be copied; restore skips
  unavailable photo files. Its standalone screen reports the count, but the full-hub adapter
  currently returns success without forwarding that warning. A successful manifest import is not
  proof every original photo survived. WHOOP migration must preview missing media and either
  block or obtain an explicit partial-import choice. Never silently delete the original library.
- Extend encrypted recovery, explicit exports, salvage and deletion paths for all new records
  and photos. Backup/delete/restore acceptance must cover a genuinely changed library.

Back up both apps and retain AkshatOS modules until validated import, combined phone acceptance
and explicit entry-ownership approval. Private coaching records remain authoritative under their
existing contract until separately switched. Screenshot-derived records and media associations
are preserved only in the private health source, not in this repository.
There is no ongoing two-app/cloud synchronization promised by a one-time import.

## Candidate Scope And Optional Extras

**Accepted feature direction; final implementation go-ahead still pending:** the queued sync
repair, full existing Lift Log parity, Body parity and unified weight entry, safe import/media
recovery, and the basic
Progress page with source-grounded weekly/monthly/since-start comparisons and seven-day diet/
weight/body/strength reviews. Include the requested reliability/food/activity/redesign work,
with Pushups still exploration and numeric guidance/protection policy awaiting review.
Include the four selected
extras below, live/summary workout times, backdated body/photo entry, measurement/range controls
and the privately generated MyFitnessPal import during implementation. Build 86 scope collection
remains open; this is plan acceptance, not permission to start code. Implement dependencies in
order within one approved release; do not assume separate releases or shrink accepted parity without asking.

### Selected Extras And Deferred Ideas

Selected items are accepted feature choices, with implementation deferred. Other items are
explicitly deferred, not removed from existing stored data. Illustrations below are synthetic, not
Akshat's training or body records. Prefer optional controls that reduce entry work; do not make
every set require effort, equipment, timing and scheduling fields before it can be logged.

1. **Repeat last set (selected):** prefill load/reps from the preceding set today or a selected set
   from the last comparable session. The user adjusts reps/load and explicitly logs the new set; prefill
   alone must not create a performed set. Preserve the exact unit/load meaning, never carry a
   machine stack value into a per-hand exercise, and show where the suggestion came from. Set
   editing/relaunch must not produce a duplicate. This is faster entry, not automatic progression.
2. **Pinned focus lifts (deferred):** choose a small set of exercises to follow on Progress, independent of
   split ordering. Each shows baseline/latest comparable performance, dates and a simple history;
   tapping opens its recorded sets. Match load mode and equipment context. Pins are shortcuts,
   not a claim the other exercises do not matter or a composite strength score. Stronger lifts
   remain observed performance, not direct evidence of a measured amount of new muscle.
3. **Warm-up flags (deferred):** tag a set Warm-up or Working, with a small optional control in set entry.
   Retain both in the workout; report logged working-set counts separately rather than treating
   every light preparatory set as equivalent. Existing/imported sets remain Unclassified unless
   explicitly tagged, not retroactively guessed. Working is the user's classification, not proof
   of high effort. The flag does not alter session timing or MET-only calories.
4. **Rest timer (selected, optional in use):** optionally start after a newly logged set using a
   user-selected default, with per-exercise overrides, add-time/skip and a quiet local alert.
   Countdown uses a durable deadline,
   not a process kept alive while locked; reopening shows elapsed/remaining time correctly. Edits
   to an old set must not restart it. Timer state is separate from WHOOP Pause, it cannot identify
   the actual rest interval from HR, and platform notification delivery is not guaranteed precise.
5. **Effort ratings (deferred):** optional self-reported reps in reserve (RIR: how many additional reps the
   user thinks remained) or a clearly defined perceived-effort scale (RPE). Recommend one input
   style, not two obligatory fields. A missing rating is unknown, not zero. This adds context to
   same-load/same-rep comparisons; it is subjective, not a sensor measurement or a reason to
   auto-adjust food/training. Avoid claiming exact RPE/RIR conversion without an explicit policy.
6. **Planned versus completed (deferred):** an optional flexible split queue or weekly schedule, explicitly
   linked to finished workouts. Show planned sessions, recorded sessions and carried/rescheduled
   items without forcing weekday adherence. A tracking-only lift can show a linked session with
   set detail unavailable; absent logs alone cannot prove the user did not train. Target reps/load
   programming remains a separate decision from scheduling, and no schedule auto-starts a workout.
7. **Context-qualified personal bests (selected):** same-load rep records and load records at a specified rep
   count, qualified by exercise, load mode and equipment. For example, 40 lb per hand for 10 reps
   after 8 comparable reps is a rep improvement. A 45-lb set for fewer reps is a different result,
   not automatically a superior one. Unknown/mixed historical contexts cannot manufacture PRs.
   Keep records quiet in summary/Progress; editing/deleting a qualifying set recomputes the record.
   No cross-mode tonnage leaderboard or default estimated-1RM ranking.
8. **Independent photo comparison (selected):** two equal, stable image panels, each with its own
   chosen photo/date. Tap a panel to make it active, then drag/swipe a bottom dated thumbnail
   strip to select its photo; the other panel stays unchanged. Allow any saved photo against any
   other, with same-pose filtering as a convenience rather than a hard restriction. Show both
   dates/pose labels (unknown stays unknown), make the active panel clear and provide an icon
   to swap sides. This filmstrip selection is not an image-overlay slider: the user's request is
   independent photo choice. Preserve full-body framing, with deliberate zoom if needed, rather
   than automatically cropping away differences. Nearby dated measurements/weight can accompany
   the pair, retaining actual dates/coverage. Different poses/lighting remain comparison limits;
   no AI muscle/fat verdict, gallery scan or upload. Manually attached historical screenshots use
   the chosen photo day, not today's image-file timestamp, and need full encrypted recovery.

**Current selection:** repeat last set, rest timer, comparable records and independent photo
comparison. Pinning, warm-up flags, effort ratings and training scheduling remain deferred.
Baseline/import correctness and sync/recovery remain prerequisites. Prioritization is about
implementation order, not authorization to split Akshat's approved combined scope across releases.

Other options remain separate: muscle-group volume after explicit exercise/equipment tagging and
a documented non-double-counting rule; a local exportable report with explicit photo scope; and
user-controlled progression suggestions after enough comparable records. No automatic overload,
unreviewed numeric diet prescription, automatic target rewriting or HR-derived muscle
assessment is proposed. Evidence-qualified user-reviewed suggestions are requested above.

## Implementation And Acceptance Gates

- Keep the accepted core/four extras/times/history controls in the combined Build 86 plan; obtain
  a separate implementation go-ahead after scope collection. Resolve background modes, exact
  report-week/baseline behavior, intake-review safeguards, activity/rest rules, Pushups parity/
  capabilities, structural design, forgotten finish and import conflicts/entry ownership before code.
- Repair bounded background collection first. Preserve one BLE owner and commit-before-ACK;
  short wakes must not run full fitness reports, imports, image processing or media encryption.
- Reuse current session, weight, profile, nutrition and UI helpers; add only necessary durable
  schema/commands. Set/measurement writes invalidate their bounded summaries, not all day metrics.
- Test shared start/pause/finish and clock disagreement, loss/relaunch/backfill, set parity and
  failures, six load meanings, zero-set workouts and unchanged build-85 calorie examples.
- Test closed-week/month/partial-range denominators, seven-day sparse weights, incomplete protein,
  diet/maintenance disagreements, goal-phase changes and withheld suggestions; then safe diary/
  session deletion, both-way historical servings, custom labels and atomic recovery/reset.
- Test same-day/import conflicts, original timestamps and precision, height/profile precedence,
  missing sites/media, repeated imports, timezone/DST windows, sparse/partial weeks, late summary
  revisions and full encrypted recovery. Photo privacy descriptions must match actual behavior.
- Test two-panel independent selection/scrubbing/swap across narrow layouts, date-only historical
  entry, selected-period chart/summary/list agreement, repeat-set confirmation and rest-timer
  relaunch/lock/edit behavior. Validate the private screenshot dataset locally without publishing
  it; no fake photo files or unsupplied measurements may appear after import.
- Run full regression/payload checks, then a real gym session, body-entry/photo/restore pass and
  brief-use locked two-hour/overnight/72-hour sync gates on the iPhone. Publication, IPA generation,
  migration/cutover and removal require their own existing authorizations and acceptance gates.

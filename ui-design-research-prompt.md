# WHOOP Fitness App Design Prompt

**Status:** Standalone design brief for Build 88 planning. Describes current Build 86/87 features,
the user's rejected visual direction and desired experience. No replacement design, navigation
removal, implementation or new IPA is approved by creating this prompt. Use synthetic data for
mockups; no personal photos or health records are included. Impeccable is the selected design
method, with its pinned local engine and project hook manifests installed. Native Flutter review
is still necessary; the automatic web detector does not audit Dart. `impeccable-setup.md` owns
tooling verification and first-use trust, not product acceptance.

The local `build-88-plan.md` condenses the current research/accuracy safeguards and maps the
requested redesign to B88-08/B88-09. Its analytical context must not turn the main screens into
long explanations or revive hidden metrics; use qualified values and short summaries with details.

## Prompt

Design a genuinely new, polished mobile experience for my personal fitness app. You know nothing
about it yet, so this brief supplies the product, features, workflows, constraints and preferences.
Make the actual app experience, not a promotional website. You decide the design, composition,
hierarchy, typography, visual system and palette. Do not simply recolour the current cards.

### Selected Design Method

Use [Impeccable](https://github.com/pbakaus/impeccable) as design guidance: critique/shape the
experience, distill noisy content, explore layout and purposeful colour, then adapt/harden/polish.
Its native iOS references include Flutter; use task-first Operate guidance and familiar iPhone
affordances, not a web landing-page style. Preserve functionality while replacing the rejected
visual composition. Show two or three genuinely different phone-sized concepts with synthetic
data before production implementation, including Today/Progress and representative Food/Train
states. Design-tool selection is not approval of a palette or composition.

Swatches and fact cards alone do not meet my request. Show actual phone-sized compositions with
charts, diary rows, navigation and live controls using synthetic data, even without image generation.
Build 88 includes the production structural redesign after I choose that direction, not just
design concepts accompanying a functional-only release.

Selected Build 88 policies, not yet implemented: health findings respect quiet hours; retain
recorded strain as an estimate but hide its uncalibrated target; intake advice and food/weight
TDEE require explicitly completed food days. Partial logs remain visible. These changes must not
add explanatory paragraphs to every primary screen.

Use the reviewed installed tooling; do not run floating installers/updates, upload app data,
create duplicate project instructions or change metrics through a design task.
Native Flutter/Simulator/phone checks remain necessary; a browser detector or attractive mockup
cannot establish app correctness. The local implementation contract is in `build-88-plan.md`.

### Product And User

I am making my own iPhone app that connects directly over Bluetooth to a **WHOOP 4.0 wrist band**.
It is a custom Flutter/OpenStrap-derived, local-first app, not the official WHOOP app. Band data
is stored locally and analyzed on the phone. It also uses the iPhone's pedometer and workout GPS,
and lets me log food, lifting, weight, body measurements and progress photos.

The target device is iPhone 17. Think native-quality, touch-first iPhone interaction, with safe
areas, the keyboard, accessibility and long-running workout states taken seriously. There is no
backend required, no Apple Watch companion or HealthKit aggregate in this personal build.

My goal is **recomposition: becoming leaner while getting stronger**. I want this to become my
all-in-one body/fitness app: wearable recovery and sleep, diet, exercise, lifting and body progress
should work together. I usually open it briefly to check insights or log something; at the gym
I need efficient, dependable controls. I need all the meaningful data without a wall of text.

### Why The Current Design Is Not Working

The installed Build 86 and the Build 87 redesign retained too much of the old feeling: rounded
containers, metric rings/bars, stacked sections, coloured icons and long scrolling pages. Some
layouts changed, but the experience still felt like the same app with a visual treatment.

Progress in particular had too many sentences, repeated "not enough data" explanations, long
eligibility rules, disclaimers and empty sections before useful evidence. Safety matters, but
it should not dominate the page with repeated prose.

The current colour direction also fails for me. It looks as though brightness was lifted: dull,
washed out, lacking contrast, and the sparkle/vitality of the app has gone. "Peaceful and warm"
must not become bland grey, muddy brown/orange, pale overlays or softened contrast everywhere.
I want rich, contrasting colours, clear dark/light separation, attractive charts and a lively,
confident identity that is still comfortable and calm. Do not interpret sparkle literally as
glitter or visual effects. I am not asking for neon everywhere either.

Design a structural and interaction makeover, not the same rings/cards in a new shade. Keep the
information and capabilities, but rethink how they are organized, scanned and acted on. You are
free to explore; the current placement/shape of a control is not a design requirement.

### Current Logical Areas

The app currently has five main tabs: **Today, Trends, Food, Train, Progress**, with settings/data
tools reached from the app. Treat these as the complete product areas. You may propose another
navigation structure if it is clearly better, but show where every feature goes. Do not silently
remove a metric, entry point, history view or workflow because it makes a cleaner mockup.

### Today: Daily Check-In

Current data and actions:

- Recovery/readiness score and verdict; HRV in ms and resting HR in bpm; access to the driver
  breakdown, personal baseline/history and reasons when a score is unavailable.
- Last night's sleep duration, in-bed/start/end time, efficiency and progress against computed
  sleep need; access to full Sleep detail.
- Day strain on a 0-21 scale, its target and zones/detail.
- Live heart rate plus recorded **10-minute, 1-hour and Day** views, daily range and scrubbed
  time/value. Recent recorded data and current live bpm are distinct.
- Steps, dated goal, progress and phone/wrist source/coverage; deeper hourly/day movement detail.
- Food intake summary and useful calorie/protein context; quick access to logging.
- Body weigh-in/measurement entry and occasional measurement-day context.
- Start/resume training and relevant current-session state.
- Daily maintenance energy estimates, with paired Budget and ACSM values and breakdown access.
- Date, band battery, connection/freshness status, settings and meaningful exceptions/findings.

The question is "What matters today, and what do I need to do next?" Choose a hierarchy that
answers it quickly. Not every metric needs equal visual weight or another large floating card.
Do not make sync status or a missing calculation obscure valid recorded data.

### Trends: Wearable History And Comparisons

- Today, seven days, 30 days and three months; daily values versus period averages must be clear.
- Recovery, sleep, HRV, resting HR, day strain, steps, step calories, qualified breathing rate,
  temperature-labelled legacy history and wear time.
- Metric detail at the selected range, daily earlier/later navigation, dated charts/readouts,
  longer-range summaries, comparisons against personal baseline and missing-data reasons.
- Observed findings/"Noticed", history and relevant recovery-mover associations from logged
  behavior. They describe patterns, not proved causes.
- Sleep detail includes stages and the full overnight timeline; other metrics open their own
  relevant details. An overview sparkline must not replace access to the underlying chart.

Some advanced computations remain stored but not surfaced as standalone personal-build screens:
autonomic stress, LF/HF, deceleration capacity, HR dip/recovery, training-load summaries,
chronotype/jetlag/regularity and sleep-coach recommendations. Do not advertise these as new
existing screens; any expansion is an optional design proposal, separate from preserving the
features currently reachable.

### Sleep And Recovery Details

- Total sleep, in bed, start/end, efficiency; estimated Light/Deep/REM/Awake durations and shares.
- Time-based hypnogram with scrubbed stage/time and qualified HR/HRV/breathing signal data;
  missing/off-wrist collection is distinct from sleep and wake.
- Wake-ups, longest sleep stretch, estimated cycles and expandable night details.
- Personal comparisons and bedtime consistency; unusual nights/findings where justified.
- Overnight HR, HRV and qualified respiratory-rate traces; breathing-pattern history/detail.
- Naps reachable even on an empty/main-night-absent day; add/edit/reject/restore.
- Fix/confirm sleep times without confusing corrections with machine-detected certainty.
- Recovery drivers and history, with each input opening its relevant metric; unavailable inputs
  and baseline enrollment stay understandable without paragraphs repeated on every screen.

**Important honesty constraint:** these are locally estimated sleep stages, not WHOOP's official
algorithm. WHOOP 4's currently temperature-labelled raw channel is physically unverified and a
Build 88 repair is queued. Akshat selected hiding unsupported temperature rows from Trends and
Sleep while preserving stored history. Primary headline HRV must be unavailable when ineligible;
labelled secondary estimates belong in details, not as silent substitutes. SpO2 is not supported by the current decoded
signals. Build 88 designs must also leave room for the selected B88-11/B88-12 changes: the
composite's own drivers under the Readiness ring, per-type alert controls, a details-only
data-quality line, a Status sync-health panel and a sleep-correction coverage warning.
Show only the items Akshat selects (`build-88-plan.md` Decision Register). Do not invent oxygen percentage, clinical apnea diagnosis or exact muscle/fat readings.

### Food: Everyday Logging, Targets And History

- Today/dated diary, History, and Foods/saved meals. Left goes earlier; right goes later,
  disabled appropriately on Today. Calendar/date selection and swipe navigation are consistent.
- Calories eaten, fixed calorie target and remaining/over context; protein, carbs, fat and fibre,
  amounts and targets. Calories and protein are the primary priorities, not the only metrics.
- Four meal slots: Breakfast, Lunch, Dinner, Snacks. Each meal can contain named subgroups.
  Show **calories and protein** on meal/subgroup summaries and anywhere else useful, with
  honest partial/unknown values; detailed items retain other macros.
- Search/add foods, barcode scan with editable review and manual fallback, Quick add with name,
  optional reference weight and all macros, optionally save it as My food.
- Food definitions from a label or manual input; editable nutrients/serving, user-created
  category labels (not forced predefined categories), search/category filters and ordering.
- Up to two named serving equivalents plus grams: entering scoops can show grams; entering
  grams can show the corresponding decimal scoops. Portion steppers/decimal entry and direct
  one-tap portion editing from diary rows must be effortless.
- Saved meals/templates, review/edit before logging, usual quantities, batch addition and
  retaining subheadings. Copy meals from/to another date and save a logged meal as a template.
- Recently/repeatedly logged foods for fast logging; retain full library access.
- Edit/delete entries and saved items with destructive confirmation/discard protection; accidental
  swipe must not silently delete food. Moving/reordering/group changes stay understandable.
- Complete/Incomplete day marking and automatic status, separate from complete macro coverage.
  Unknown nutrient is not zero; partial totals/averages are qualified compactly.
- History: dated/month-grouped logs that reopen for editing, intake versus maintenance charts,
  weekly completed-day totals/deficit context and food/weight maintenance estimate when eligible.
- Budget/ACSM maintenance comparison and detail: resting energy, walking/steps, runs, logged
  digestion; lifting extra remains separately identified rather than quietly added twice.
- Weight logging/trend remains accessible from diet context too, using the same weight source
  as Progress, not a duplicate log.
- Calorie warning colour must distinguish the fixed goal from modeled maintenance. Slightly
  above a dieting target is not automatically red; genuinely above the chosen maintenance
  comparison can be. An unavailable estimate must not fabricate a green/red conclusion.

Do not turn food logging into a form-heavy sequence. This is a frequent task where one clear
add action, good search, easy amount editing and rapid return to the meal matter enormously.

### Train: Purposeful Exercise And Live Workouts

- Run, Walk, Lift and Other activity selection; add a past workout and browse all saved history.
- Recent/all workout lists with activity/date filters and reset; clear date/start/end/duration,
  strain and relevant distance/calorie context. Stable options and expansion controls.
- General activity streak counts qualifying physical exercise, including lifts/Other, or a
  measured dated step goal. Rest/Life happens protection preserves continuity within limits
  without pretending exercise occurred. Show real activity versus protected days distinctly.
- Running trends: weekly distance, achieved comparable best efforts/records and qualified
  projected 5K/10K times. Day-strain chart links to its selected day.
- Active workout: start clock time, elapsed/active duration, live HR, time in zones and the
  relevant speed/pace, distance, cadence/steps, GPS/route state and calorie estimates.
- Walking uses km/h; running uses useful pace context. Current speed and session average need
  clear labels/freshness, not an old number that silently looks live.
- Pause, resume, finish and safe collapse/return without losing the ongoing session. Lock/
  background continuity and optional voice/distance cues are part of the real workflow.
- Completed summary: start **and end** time, duration/pauses, route/map, splits, pace/HR/
  elevation charts, cadence, zones, paired energy estimates, records and session context where
  available. A walk does not need running-only race prediction content.
- Completed workout deletion is reachable with confirmation. Never place a bin where the
  expansion/collapse control moves, or make opening details change the action positions.
  Live discard is clearly separate from finish and benign navigation.
- Sharing a workout is an explicit action, not an automatic publication/upload.

### Lifting Integrated Into The Workout

Lift Log is **inside the live Lift session**, not another disconnected workout in another app.
The session's HR, time and eventual WHOOP summary stay connected with the exercise log.

- Add/order exercises and log sets of load/reps; retain routines/templates and prior history.
- Load meaning and equipment notes matter: total load, plates per side and bodyweight/added
  load are not interchangeable. Units and context must be legible.
- Previous comparable sets, repeat-last-set, best sets/rep records and progress versus the
  same exercise/equipment. No deceptive comparison between machine and dumbbell variants.
- Optional rest timer with efficient start/adjust/skip, using its saved deadline across
  app backgrounding rather than an unreliable on-screen ticking state.
- The live session stays usable while entering/editing sets with the keyboard open. HR activity
  and session timing are context; a set's log timestamp is not measured repetition duration.
- Lift history/import exists alongside wearable sessions; imported logs may have no HR-linked
  session. Avoid implying sensor data was measured for historical manual entries.

### Pushups

The app includes Pushup Reminder, ported from my other personal hub app, AkshatOS.

- Start/pause/resume/stop a reminder session, choose reminder interval and daily set goal,
  log completed sets, reminders/nudges and daily recap/history.
- Its own streak and completed-set goal, with correct paused/active state; Home-based auto-pause
  is an optional existing workflow, not a reason to request location without context.
- Pushup logs do not automatically create measured workout duration, HR, calorie burn or
  general activity-streak completion. Keep that distinction without cluttering the main page.
- Make its entry and ongoing reminder status discoverable without another oversized explanation.

### Progress: One Place To Understand The Journey

- Goal selector: recomp, fat loss, maintenance, lean gain, strength. Current goal/phase and
  start date, with eligible advisory review; targets only change when I choose them.
- Weight/Steps/eight tape sites as selectable metrics; readings and **7-day weight average**.
- Date ranges: one week, one month, two months, three months, six months, one year, Since start,
  All; dates/coverage must match the selected range rather than compressing missing history.
- Weight in kg/lb and dated body measurements: waist at navel, lower belly, hips, neck, chest,
  shoulders, right upper arm and right thigh. Start/current/change, useful charts and entries.
- Add today's entry or go back to a date; edit/delete with confirmation; all-history access.
- Local historical imports from AkshatOS Body/Lift Log and generated MyFitnessPal history files;
  import review/deduplication and source labels. History-only weights do not silently reprice
  old calorie calculations. Importing my history should make this journey visible, not erase it.
- Progress photos with dates and front/side context. **Two independently selected photo panes**:
  each side can choose any dated photo using an easy timeline/thumbnail strip. I liked being
  able to drag through the bottom photo timeline to pick the image for that side in MyFitnessPal.
  Do not limit comparison to adjacent/latest photos. Historical photos can be added manually.
- Weekly and monthly evidence: weight-average change, waist/other measurements, comparable
  lift progress, workout activity, intake/protein, steps, sleep and recovery. Show what changed
  together and whether it supports the goal, with drill-down to the actual dated evidence.
- Diet context: daily/period intake versus estimated expenditure, observed weight trend and
  qualified goal advice about reviewing intake, protein, recovery or training. No automatic
  calorie changes and no claimed proof that a single day's food caused a scale change.
- Measurement/body-fat proxies and photos are not exact fat/muscle separation. Lifts improving
  while waist falls can support recomp, not certify muscle gain. Keep uncertainty accessible.
- Each evidence family can show useful data even when another is missing. Avoid one giant
  "Needs data" card suppressing everything, or separate empty cards repeating the same text.
- Missing eligibility can be a compact state with detail on demand. Safety explanations and
  formulas belong in contextual detail, not a paragraph wall at the top of Progress.

The main question is "Am I progressing toward being leaner and stronger, and what should I pay
attention to?" Design the answer as a coherent view, not a dump of separate databases.

### Settings, Reliability And Data Ownership

- Band connection/pairing, battery, data freshness and status; automatic catch-up/manual refresh
  and retryable failures. Show latest recorded data versus calculation time honestly.
- Profile/targets, phone-motion/GPS/reminder preferences and other existing feature settings.
- Local data import/export, encrypted backups/restore and photo data protection.
- App version/status and sideload signing expiry/reminders; renewal is separate from band sync.
- No always-running iOS guarantee. Reopening should show recorded information promptly and
  catch up automatically, without forcing a pull-to-refresh for ordinary use.
- Offline use, cancelled/pending calculations, empty data, partial coverage, permissions denied,
  errors, date rollover and an active workout while switching tabs are first-class design states.

### What I Want From Your Design

1. An original, cohesive visual direction with rich contrasting colour, comfortable surfaces,
   clear hierarchy and character. Explain the concept briefly, then show the actual app.
2. A feature-preserving information architecture and navigation map. Make common tasks short
   and deeper detail discoverable; a simplified first viewport must not mean fewer features.
3. Phone-sized screen designs for all five logical areas, plus meal logging/portion editing,
   live Walk, live Lift, completed workout, sleep detail and independent photo comparison.
   Use consistent synthetic sample data, dates and units, not my real records.
4. Connected flows/prototype where possible: daily check-in -> detail; add/edit meal -> diary;
   start Lift -> set/rest -> finish; resume active workout; weigh-in -> progress; choose two
   dated photos; read weekly/monthly evidence. A set of disconnected attractive screenshots
   is not enough to demonstrate usability.
5. Populated, first-use/empty, partial, stale/syncing and error/retry states, plus large text,
   long exercise/food names and keyboard-open forms. Show that safe areas and navigation never
   cover the final rows/actions. Do not fill empty states with fictional health data.
6. A usable design system: surface/text/accent/state/chart colours, type sizes, spacing,
   standard touch targets, controls and accessibility/VoiceOver/contrast behavior. Familiar
   icons for tools, clear commands, menus for option sets, toggles for binary choices and
   numeric steppers/inputs. The current Flutter app uses Lucide icons.
7. Structural changes over cosmetic ones: avoid another endless stack of oversized rounded
   cards, nested cards, oversized rings or explanatory prose. Keep repeated list items and
   genuinely framed charts/tools where useful, not every page section in a floating container.
   Do not add a landing page, decorative orbs, gradients-as-content or irrelevant stock imagery.
8. A short feature-preservation checklist and separate optional improvements. Call out any
   changed navigation/removal, new permission or new data requirement for explicit review.
   Do not change algorithms, invent metrics, delete history or assume approval to implement.

Do not be constrained by the current layout. The purpose of this brief is to give you complete
context and let you design a substantially better experience. Make it feel distinctly new,
beautiful, quick to use and trustworthy, with the data still there when I need it.

Keep health records/photos private. Creating or reading this brief does not authorize uploads,
public prototypes, external design-tool submissions or new network destinations; follow the
workspace's approval policy when executing it.

# Build 75 audit: installed build 74 findings

Each item records what Akshat saw on installed build `0.9.41`/`74` (source `ba5bb29f`), the
root cause, sibling defects found on the same code path and the design. Akshat decided D1–D8
below and approved implementing the audit together as build `0.9.42`/`75`. Source `0.9.42`/`75` (commit `1c203f17`) is published with Akshat's approval; Linux CI `37514558854` (3,369 tests, 371 intentional skips) and personal macOS build `37514599309` pass. Downloaded source/version, checksum, ZIP integrity and payload/extension checks pass.
Nothing is phone-verified yet. `todo.md` owns the release
and phone gates; the "Build-75 implementation" section at the end records what changed.

## Decisions (Akshat)

| # | Decision |
|---|---|
| D1 | Live Activity stays Running/Walking only (treadmill counts as running), but must actually appear. Akshat saw nothing on a Walking session |
| D2 | Today · 7 days · 30 days · 3 months everywhere, with links carrying the same range/day |
| D3 | Bars → lines at my judgment: day-by-day series become lines; hourly totals and weekly distance stay bars |
| D4 | Saved-meal + opens a review list (amounts editable, items can be left out), then one Log |
| D5 | Breakdown keeps sleep, naps, workouts, band off the wrist and HR extremes; food and band charger/restart events go. Battery belongs on Today instead |
| D6 | Non-run workouts stay out of maintenance; walking steps stay in |
| D7 | My judgment, for a kitchen-scale user: grams stay the base; up to two named measures are reference shortcuts |
| D8 | Swipe either way to delete on every food list |

The strawberry milkshake and fiber duplicates in the screenshot were intentional.

## 1. Live Activity does not appear during workouts

### What exists

Build 74 contains a working-looking chain: `LiveActivity.update` in `lib/live/live_activity.dart`
→ method channel → `ios/LiveActivityBridge.swift` (`Activity.request`) → the
`OpenStrapWidgetLiveActivity` widget extension. The personal transform keeps the extension,
sets `NSSupportsLiveActivities`, uses no App Group, and Sideloadly installed it with
`drop_plugins = 0`. The data travels in ActivityKit `ContentState`, which is the approach that
works on free-team sideloads (App Groups do not)
([example of the same fix](https://github.com/nadolc/IncomeMeter/pull/9)).

### Why nothing shows (confirmed and probable causes)

1. **Confirmed scope gap.** `live_activity.dart:37` and `_pushWorkoutActivity`
   (`lib/state/app_state.dart:6721`) return immediately unless `isRunType`/`isWalkType` is true.
   Only types containing "run", "walk" or "hik" qualify. Weight training, HIIT, cycling,
   treadmill, track intervals, sprinting, rowing, the generic "Workout"/`other` type and
   auto-detected workouts never request an activity. This matches the original build-74
   contract ("narrow Run/Walk"), so it is a scope decision, not a regression.
2. **Silent failure.** `LiveActivityBridge.publish` returns `false` without a reason when
   `areActivitiesEnabled` is off (`LiveActivityBridge.swift:66`), the app is not foreground
   (line 85), or `Activity.request` throws. Dart swallows the error. There is no log line or
   Status-screen row, so a Run/Walk failure cannot currently be diagnosed from the phone.
3. **Phone settings to check.** Settings → WHOOP must show a **Live Activities** toggle. If the
   toggle exists, iOS recognised the support key; it must be on. Face ID & Passcode → Allow
   access when locked → Live Activities must also be on (Strava documents the same two switches:
   [Strava Live Activities](https://support.strava.com/hc/en-us/articles/39508401687693-Strava-Live-Activities-on-iOS)).
   A missing toggle would point at extension signing/recognition instead.
4. **Creation is foreground-only.** A session resumed by crash recovery or started by a band
   gesture while backgrounded never gets an activity; only updates work in the background.

**Needed from Akshat:** which activity type was started when nothing appeared, and whether the
Settings → WHOOP → Live Activities toggle exists.

### Sibling issues

- When updates stop for 45 s (`staleDate`), the widget swaps its system timer for a frozen
  duration (`OpenStrapWidgetLiveActivity.swift:38`). The clock then looks stuck even though
  the workout is still running. iOS computes the timer itself, so it should keep running unless
  the session is paused; only HR/pace should go stale.
- The lock-screen card says "Tap for controls ›" even though no controls exist there; the tap
  only opens the session.
- Treadmill and track sessions are run-like but `isRunType` excludes them, so they also miss
  run pace, the running row of maintenance and best efforts (see section 7).

### Recommended design

- **Every recorded workout** gets an activity. The attributes gain an activity kind:
  - Distance sports (run/walk/hike/cycle/row/swim): time, distance, pace or speed, HR + zone,
    last km.
  - Everything else (gym, HIIT, sports): time, HR + zone, time in the current zone, strain so far.
    The activity's own icon and name are shown, never the route.
- Keep the native timer running while not paused; mark only HR/pace as stale.
- Return a reason string from the bridge (`disabled`, `background`, `ios<16.2`, the request
  error). Log it and show it on the Status screen ("Live Activity: on / off in Settings /
  failed: …").
- Change "Tap for controls ›" to "Tap to open". Lock-screen pause/finish buttons need iOS 17
  `LiveActivityIntent`. On iOS 26 such extension intents depend on installer code-signing
  flags, which Sideloadly free signing does not guarantee. Keep them deferred until that
  separate check passes.
- Optional, like Strava's setting: request frequent updates (`NSSupportsLiveActivitiesFrequentUpdates`).

## 2. Trends and metric detail screens

### 2a. A day's row appears only after touching the chart

`metric_detail.dart:1286`: the selected-day row (`_picked`) is built only when `_pick != null`,
except for Steps and Step calories, which build it from the newest day. Every other metric
(Time asleep, HRV, Resting HR, Strain, Breathing, Skin temperature, Wear) hides the way into a
day until the chart is touched. This is the exact defect fixed for Steps only, not shared.

**Fix once:** always render the row for the newest day (or the last selected day). Add ‹ › arrows
to move the selection without touching the chart. Never offer a future day.

### 2b. Some rows open nothing

`_dayScreen` (`metric_detail.dart:1461`) has a destination only for sleep/deep/REM/efficiency,
steps, step calories and strain. HRV, Resting HR, Breathing rate, **Skin temperature**, Wear time
and Readiness return `null`, so their row has no chevron and opens nothing. Skin temperature is
the case Akshat found; it is one of six.

**Fix:** give every metric a dated destination:
- HRV, Resting HR, Breathing rate, Skin temperature → that night's Sleep screen, scrolled to
  Overnight signals (where those night values live).
- Wear time → the day breakdown/timeline for that date.
- Readiness → `ReadinessDetail(day:)`, which already accepts a day.

### 2c. Opening a metric ignores the range chosen in Trends

`health_screen.dart:332` opens `MetricDetail(r.key)` with no range, and `MetricDetail` always
starts at Today (`_range = 0`). Readiness opens `const ReadinessDetail()`.

The range sets also differ:
- Trends: Week / Month / 3 months (`health_screen.dart:95`).
- Metric screens: Today / 7 days / 30 days / 6 months / Year (`metric_detail.dart:723`); the
  last two appear only once 182/365 days exist, and there is no 3-month option.

So a 3-month Trends view cannot open a 3-month metric view at all.

**Fix (D2):** one shared range list, `Today · 7 days · 30 days · 3 months`, on Trends and every
metric screen. Opening a row passes the current range. Changing range inside a metric applies
to that screen only, so Trends' choice survives the round trip. Keep 6 months/Year as later extra
options on detail screens only.

### 2d. Trends numbers do not change with the range

`health_screen.dart:384`: each row's large number is `vals.last`, the newest reading, in every
range. Only the small "Avg …" line moves. The same mistake was already fixed in `MetricDetail`
(whose own comment explains it) but not on the Trends list.

**Fix:** Today shows today's value. Other ranges show the range's average for physiological
metrics, and an average per day with the total where meaningful (steps, step calories). The
sparkline covers the same range. Add a small change versus the previous equal range
("+12 ms vs prior 30 days").

### 2e. Today / 7 days / 30 days look alike

Today draws no chart for most metrics; 7 and 30 days draw the same card with a different
number of points. Recommended per-range content:

- **Today:** the day's own detail embedded, as Sleep and Strain already do (HRV through the
  night, live/resting HR curve, wear by hour, steps by hour).
- **7 days:** the line plus a day-by-day list (newest first, each row opens that day), and this
  week versus last week.
- **30 days:** the line with a 7-day rolling average, weekly averages and best/worst day links.
- **3 months:** the rolling average as the main line, monthly averages, and the change from the
  first month to the last. These are descriptive changes only, with no causal claims.

### 2f. Readiness differs from every other metric

- No range tabs. It draws coloured **bars** for up to 90 days (`readiness_detail.dart:537`).
- The HRV / Resting HR / Breathing / Skin temperature rows ("Better than usual") are static
  (`_row`, line 638) and open nothing.
- A past day opened through `ReadinessDetail(day:)` gets its score but no breakdown.

**Fix:** use the shared range tabs and a line with coloured readiness-band dots. Make every
breakdown row open that input's metric screen at the same range/day. Store or recompute the
per-day breakdown so a past day explains itself too.

### 2g. Connecting related screens

Static rows that should become links (always carrying the same day and range):
- Readiness breakdown → HRV, Resting HR, Breathing rate, Skin temperature.
- Sleep → Overnight signals rows → the matching metric screen and that night.
- Sleep → "Breathing pattern in sleep" opens `SleepBreathingScreen()` without a day
  (`sleep_detail.dart:633`), so a past night opens the current view.
- Strain day → its workouts and heart-rate day.
- Resting HR → the night it came from.

Rule: a link opened from Today goes to Today; from a range goes to that range; from a day
goes to that day.

### 2h. Smaller chart defects seen in the screenshots

- The readout repeats the unit: "Monday, 5 October, 7h 05m **min**". Minute metrics already
  format as hours/minutes, so the frame's unit must be dropped for `min` metrics, as the
  headline already does.
- Skin temperature's spec has no unit, so its chart says "**score**" ("-0.5 score"). It is a
  deviation from your own nights; Trends already labels it `SD`. Use one label everywhere and
  explain it once.
- Skin temperature still carries the upstream "suppressed" spec with a personal exception
  (`metricSuppressed`). It needs an honest personal spec rather than an exception.

## 3. Bar charts to lines

Bar charts in the personal build: Readiness history, Train "Strain, last 7 days" and
"Distance per week" (this is the "Time/Train tab" in Akshat's note), Food history
"Maintenance and eaten by day", Sleep breathing "Each night", Steps/Step calories by hour, and
Wear by hour.

Per D3: convert the day-by-day series (Readiness, Strain 7 days, Food maintenance vs eaten,
breathing cycling by night) to lines with the shared scrubber and day row. Hourly totals and
weekly distance are totals per bucket; recommend bars or a stepped line there. If Akshat
still prefers lines everywhere, the change is one painter swap per screen.

## 4. Bottom bar re-tap

`app_shell.dart:76` and `app.dart:574`: tapping the current tab only re-saves the tab
preference. The shell's own comment says re-taps are meant for scroll-to-top, but no screen
implements it.

**Fix:** a re-tap of the current tab resets it to its first view:
- **Today:** scroll to top.
- **Trends:** scroll to top and the default range.
- **Food:** Today sub-tab, today's date, top.
- **Train:** scroll to top.

Detail screens are pushed above the shell, so the bar is not visible there and needs no change.

Siblings to verify: tapping the iOS status bar should scroll the visible tab to top. With four
lists in an `IndexedStack` sharing the primary scroll controller this may scroll the wrong list
or none. Leaving a tab and returning should keep its scroll position (it does).

## 5. Food

### 5a. Fixed personal order instead of sort filters

- `MyFoods.all` (`nutrition_store.dart:1004`) orders by most recently eaten, then A–Z. The log
  screen adds a Recently eaten / A to Z / Z to A cycle (`food_diary.dart:996`, pill near 1438).
- Saved meals order alphabetically (`meals`, line 1016).
- Neither list can be reordered.

Removing the sort pill removes only the "Recently eaten" and A–Z views; search still finds
any food, so nothing becomes unreachable.

**Fix:** add a persistent position to `food_def` and `meal_template` (an additive column, as
`grp` was added). One order is shared by Food → Foods and the log screen. Remove the sort pill.
Reorder by long-press then drag (Flutter's built-in `ReorderableListView`, no new dependency);
long-press keeps drag from fighting swipe-to-delete and scrolling. Search still filters
without changing the saved order. New foods go to the top; the first migration seeds positions
from today's recently-eaten order, so nothing jumps.

Apply the same drag order to:
- items inside a meal page and their sub-headings (a `food_entry` position within
  date/meal/group);
- the saved-meal editor.

### 5b. Tap opens edit; swipe deletes

Food → Foods uses `_chooseAction` (`nutrition_screen.dart:710`), an Edit/Delete sheet, for both
My foods and Saved meals, and neither list supports swipe. The log screen already swipes. **Fix:**
tap opens the editor directly; swipe (D8) deletes with the existing confirmation and Undo
message, on both lists.

### 5c. **+** logs a baseline amount without review

`_quickLogFood` (`food_diary.dart:1078`) writes the last-logged amount, or the reference
serving, immediately. The screenshot's breakdown shows Strawberry Milkshake and Goodbug Fiber
each logged twice within a minute, which fits accidental one-tap logs (Akshat to confirm
whether those were intentional).

**Fix:** + opens the existing `FoodDetailSheet`, prefilled with the last amount. That is the
"edit page" requested: amount, meal, sub-heading, time and Log. Saved meals follow D4.

### 5d. Meal totals on the Food screen

`MealCard` shows "Eggs and 5 more · 776 kcal" only. **Fix:** "776 kcal · P 77 · C 43 · F 32"
(fibre in the meal page), same rounding as the meal page so totals agree.

### 5e. Card order

Current order (`nutrition_screen.dart:836–846`): Calories → Daily maintenance → Macros → meals.
Requested: Daily maintenance → Calories → Macros → meals. One-line reorder.

### 5f. Calories card opens the whole day

The Calories card has no tap target. **Fix:** a Day page showing Breakfast, Lunch, Dinner and
Snacks with their sub-headings and per-meal totals, plus day totals at the top. Reuse the meal
page's grouped list instead of a new layout; each item keeps tap-to-edit and swipe-to-delete.

### 5g. Servings: duplicated chips, steppers, two measures

- **Duplicated chips.** `food_diary.dart:1684` labels each chip
  "k serving(s) · k × reference amount in the food's unit". For a food whose unit is itself
  "serving", that prints "½ serving · 0.5 servings" and "1 serving · 1 serving". For Eggs
  (1 serving = 1 egg) the chips repeat.
- **Steppers.** There is no − / + control; changing 1 egg to 4 needs select, delete, type.
- **Model limit.** A food has one unit, and nutrition is stored per 100 of that unit
  (`myFoodDef`). The macros scale, but "1 scoop" and "29 g" cannot both be valid amounts.
  That is why food names carry "(1 scoop)".
- **Layout.** In the portion sheet the macro rows are a centred `Wrap`, so numbers do not line
  up (screenshot).
- **"Check label values" edits the saved food itself**, changing every future log, while
  presented as part of logging one portion. It should say so, or offer "this entry only".

**Recommended model (D7):**
- Base nutrition stays per 100 g (or ml).
- Each food may name up to two measures with their weight: "scoop = 29 g", "egg = 50 g",
  "link = 71 g". Count-only foods with no known weight keep the current per-unit model.
- The portion sheet shows a unit switch (g | scoop), a large amount field with − / +, and chips:
  - count units: 1 · 2 · 3 · 4 (± steps of 1, with ½ available);
  - weight units: one, two, three measures in grams (± steps of one measure, or 5 g when none).
  Each chip is labelled once ("2 scoops · 58 g"), never twice.
- Entries store the chosen measure and its grams, so changing a measure's weight later does not
  rewrite past days, consistent with saved meals' existing unit guard.

**Food editor tidy-up:** replace "Serving unit" text + chips + "Serving amount" with one line,
"Nutrition label is for [1] [scoop ▾] weighing [29] g", then the nutrients. The weight is
optional for count foods.

### 5h. Saved meals lose sub-headings

`MealTemplate` stores only `(food, amount, unit)` (`nutrition_store.dart:949`).
- `saveMeal` drops `FoodEntry.group`, so "Eggs and Sausage" / "Oatmeal" vanish.
- `logMeal` then files every item under one heading named after the saved meal.
- The editor shows a flat list.
- Two entries of the same food in one meal share one unit-map key.

**Fix:** store `grp` (and order) per item in `items_json`. Old templates without it load as
ungrouped. The editor shows and edits sub-headings with drag order. Logging restores each
item's own sub-heading, and the chosen target heading applies only to ungrouped items. Store
items as a list of objects, not a map keyed by food.

### 5i. Meal times on today

`foodEntryTime` (`nutrition_store.dart:175`) stamps every entry logged *today* with the current
clock, whatever the meal: dinner logged at 10 AM is recorded at 10:11 AM (screenshot). It also
affects history ordering and any future meal-timing insight. **Fix:** today uses now only when now
falls in that meal's window; otherwise use the meal's default hour, and the time chip stays
editable.

## 6. Day breakdown is noisy

`day_timeline.dart` merges sleep, naps, workouts, band-off segments, lowest/highest HR, band
events (charger/restart), every individual food entry (line 241), doses and timed journal fields,
plus an untimed block (journal notes and meals without a time, line 336).

**Fix (D5):** keep Asleep, Nap, Workout, Band off your wrist, Lowest and Highest heart rate.
Remove food, doses, journal fields and charger/restart events from the list. The untimed block
then has nothing left and goes too. The day graph's four lanes (HR, sleep, workouts, movement)
already match this.

What would become unreachable (feature-removal check, Akshat to approve per item):
- **Food entries:** none. Every entry stays on the Food day, meal page and history.
- **Doses and timed journal fields:** none in practice. Medication and the journal are already
  removed from the personal build, so these rows only appear for old stored data.
- **Band events (on charger, restarted, etc.):** this list is their only screen. They explain
  gaps but are not a primary metric. Keep them stored; hide them from the list, or fold them into
  the existing "Band off your wrist" line as its reason.

## 7. Calorie and maintenance verification

### Verified as implemented

- **Daily maintenance (Budget):** full-day Mifflin–St Jeor BMR + walking energy
  `2.74 × walked steps × kg ÷ 8,368` + run Method 1
  `0.005 × kg × (0.143 × run m + 0.1 × walk-break m + 0.9 × climb m)` + 10% of food logged.
  - Run steps are removed from the step term, so they are not counted twice.
  - Overlapping sessions count once. Unknown overlap uses the larger of the two estimates, not
    the sum.
  - Weight comes from the dated profile.
- **Plausibility:** at 80 kg, 10,000 walked steps give about 262 kcal. The ACSM walking
  comparison at roughly 0.75 m per step gives about 300 kcal, so Budget is the conservative one,
  as intended.
- **ACSM** is shown beside Budget on the same ledger and never added to it. HR/Keytel stays
  analysis only.

### Findings and edge cases

1. **Gym, cycling, rowing and swimming add nothing to maintenance** (documented in
   `metrics-map.md`). A 24-minute "Workout" showing 335 kcal on Train contributes 0 to the Food
   maintenance number; only its incidental steps count. Cycling and rowing have no steps, so a
   1-hour ride adds nothing. This is a deliberate floor, but Train never says so. Decision D6:
   keep it and label it, or add a labelled net estimate for non-step activities only
   (net HR/MET minus resting, excluding minutes already priced by steps).
2. **Two calorie conventions on one tab.** Train cards for non-run workouts show *gross* HR
   calories, which include resting burn and use Harris–Benedict resting energy. Run/walk details
   and maintenance use *net* active energy with Mifflin resting energy. For the 24-minute
   example, about 25–30 kcal of the 335 is resting energy already inside BMR. Use net "Active
   calories" everywhere, with one BMR formula.
3. **Treadmill, track intervals and sprinting are not run types.** A treadmill run is priced
   by steps (walking cost, about 25–35% lower than the running estimate), gets no running row
   and no best efforts. Classify run-like types explicitly; treadmill distance comes from
   steps/cadence, never GPS.
4. **Fast walking can still get the running coefficient**: the distance split classes ≥2.0 m/s
   or ≥140 steps/min as running, even inside a Walking activity (`workout-sync-audit.md` item 5).
   Confirm whether build 73/74 closed this. If not, the activity type should cap a walk at the
   walking coefficient.
5. **Today's maintenance is partial by nature.** BMR is the whole day while steps and food are
   so far. "851 under Budget maintenance" at noon will shrink by evening. Label it
   "so far today" or show the projected whole-day steps separately.
6. **Food thermic effect follows logging.** Ten percent of logged food is added, so forgotten
   entries also lower maintenance. That is acceptable, but should be visible in the breakdown
   (it is).
7. **Phone not carried:** with the phone left behind, wrist steps are low-rate and walking energy
   is understated; the app labels distance sources, but maintenance gives no "phone was not
   carried" hint. Show a coverage line when phone coverage is low for the day.
8. **Missing profile fields:** BMR needs age, height and weight; sex falls back to the midpoint.
   The live gross estimate defaults height to 170 cm. One more reason to retire the gross path.

## 8. Other sibling findings

- Trends, metric screens and Readiness each implement day/range state separately. A single
  "dated range" helper (range + selected day, passed on every link) prevents these mismatches
  recurring.
- Food → History and the Train weekly charts have their own day pickers. Once 2a/2c land they
  should use the same always-visible day row and arrows.
- `MealCard` names a meal after its first entry ("Eggs and 5 more") while the meal page orders by
  sub-heading. After 5a, use the first item in the saved order.

## Suggested build-75 grouping

1. Navigation and charts: 2a–2h, 3, 4 (one shared range/day helper first).
2. Food workflow: 5a–5f, 5h, 5i, 6 (ordering migration, editors, day page).
3. Serving model: 5g. It changes stored food definitions and needs a migration with
   round-trip tests on existing foods, saved meals and backups.
4. Live Activity: 1. Diagnostics first, so the next phone test explains itself, then all-workout
   layouts.
5. Calorie labels and run-type classification: 7.2–7.5; 7.1 only after D6.

Each group needs fixed-clock chart tests (midnight, gaps, future days), migration tests for every
new column, VoiceOver labels, enlarged-text layouts and the usual full suite, personal-profile
and payload checks before any IPA.

## Build-75 implementation (source `1c203f17`)

- **Live Activity:** the bridge returns a reason for every start/update ("started", "Live
  Activities are off for WHOOP in iOS Settings", "iOS refused: …", "waiting for the app to be
  open"), logs it, and Settings → About → Status gains **Lock screen · Live Activity**: iOS
  permission, the installed extension's bundle ID versus the app's, and a one-minute sample
  started by a tap. A start refused while not frontmost now retries on the next foreground;
  creation is allowed whenever the app is not backgrounded (a permission alert at workout start
  made the old `.active` check fail). Dismissed or ended activities are replaced rather than
  silently updated. The lock-screen timer keeps running while updates are stale and only stops
  when paused; the footer reads "Tap to open". Treadmill sessions are eligible. The exact phone
  cause is still unconfirmed: the Status row/sample is the next diagnostic.
- **Trends/metrics:** one range list (`kRangeDays`) on Trends (default 7 days), every metric
  screen and Readiness (Trends now opens Readiness through the shared metric screen, whose Today
  tab embeds the Readiness view). Trends rows show today's value or the range's daily average.
  The selected range travels into the metric. Every metric shows its newest day row without a
  touch, with ‹ › arrows; HRV, resting HR, breathing and skin temperature open that night's Sleep,
  Wear opens the day breakdown and Readiness opens its day. 7 days lists each day, 30 days weekly
  averages, 3 months monthly averages; 30 days and longer draw a 7-day average under the daily
  line. Readiness breakdown rows and Sleep's overnight signals open their metric at the same day.
  Minute metrics no longer print "min" twice; skin temperature reads SD, not "score".
- **Charts:** Readiness history, Train's 7-day strain, Food's maintenance/eaten history and the
  breathing-by-night chart are lines; hourly steps/wear and weekly distance stay bars.
- **Tabs:** re-tapping the current tab scrolls it to the top; Food also returns to Today on
  today's date and Trends to its default range.
- **Today:** the band's last reported battery (and charging) beside Settings.
- **Food:** one saved order (`food_def.pos`, `meal_template.pos`, seeded from the previous
  order on first open) shared by Foods and every log screen, dragged by holding a row; the sort
  pill is gone. Foods/Saved meals open their editor on tap and delete on a swipe either way
  (confirmed). Food + opens the portion screen prefilled with the last amount; saved-meal +
  opens the review list. Meal pages drag within a sub-heading (`food_entry.pos`, kept across
  edits) and swipe either way. Saved meals store each item's sub-heading and restore it when
  logged; the editor shows sections, drags and swipes. Meal cards show kcal and P/C/F; the Food
  screen order is Maintenance → Calories → Macros; the Calories card opens a whole-day page.
  The shared amount control has − / + and chips labelled once (counted foods 1–4; weighed foods
  their measures with grams). Foods take up to two named measures. "Check label values" is
  renamed "Edit saved food" and says it changes future logs. Today's meal timestamps use the
  meal's usual hour outside its window. Today's maintenance gap reads "so far".
- **Day breakdown:** sleep, naps, workouts, band off the wrist and HR extremes only.
- **Deferred, with reason:** Train's gross non-run workout calories and treadmill/track run
  classification for maintenance (D6 keeps non-run workouts out of maintenance; changing the
  stored session calorie path needs its own reviewed change); a stored per-day Readiness
  breakdown for past days; iOS status-bar tap to top.

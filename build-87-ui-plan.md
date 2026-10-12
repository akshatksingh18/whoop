# Build 87 UI Audit And Implementation

**Status:** Published and built as `0.9.54`/`87`, source `b0eee377`, with Akshat's approval.
Local checks, Linux CI `38156660026` and personal macOS build `38156663594` pass. The downloaded
IPA passes source/version, checksum, ZIP and personal payload checks and is the single candidate
in `../final-ipas/whoop/testing/WHOOP-0.9.54-build87-b0eee377`. Build 86 remains installed with
its rejected UI. Structural design and physical background acceptance remain separate gates.
`todo.md` owns release scope and gates; this file owns the implemented UX and verification.
Akshat approved source implementation and requested a pretty, peaceful warm palette. Existing
Build 86 remains installed; Build 87 is a validated testing IPA, not an installed or accepted replacement.
The latest colour feedback rejects the current direction as washed out/dull and requests richer
contrast and vitality. That redesign is queued in Build 88 (`todo.md`), with the standalone
`ui-design-research-prompt.md` brief; the Build 87 artifact and implemented contract below are
unchanged, not evidence that the palette is accepted.

## Evidence And Boundary

- Reviewed Akshat's 13 Build 86 phone screenshots and the current local UI/data source. App
  source baseline is `651345e7`; later repository changes include documentation and tooling.
- Inspected the five-tab shell, Today, Trends, Food, Train and Progress; traced the related
  live-workout, Lift Log, summary, sleep/readiness/metric, Pushups, settings and data routes.
- This is a screenshot/source audit, not a completed interactive phone audit. Back gestures,
  accessibility, keyboard, permission recovery, locked workouts and actual sync timing remain
  device tests. An image with sparse data does not prove a sync failure.
- No personal readings, photo content, logs or import payloads belong in this public-repo plan.
  Use synthetic fixtures for future previews. No new external service, permission, entitlement,
  network dependency or AkshatOS ownership change is proposed.
- Preserve all currently reachable unique features and metrics. Reorganizing a control is not
  permission to remove its function. Removed journal/AI coach/Live Activity and unselected
  scheduling, effort-rating, warm-up and pinning features stay out of scope.

## Findings

Findings describe the installed Build 86 baseline; the replacement contract is below.
Priorities describe user impact, not a claim of data corruption. Findings labelled
source-confirmed can be reproduced through their cited contracts; phone behavior is not implied.

### P1: Progress Hides The Answer

1. **Eligibility dominates the first viewport.** Screenshots 11-13 show the goal explanation
   before the chart, followed by repeated unavailable-review, history and strength panels.
   [`ProgressScreen._page`](lib/ui2/screens/progress_screen.dart:280), `_goalCard` and
   `_reviewSection` print requirements, next actions and caveats in multiple large surfaces.
   This is the opposite of the requested quick, data-first progress check.
   **Repair:** compact goal row, dated chart first, one selected-period review; criteria and
   methodology behind an explicit details control. Keep uncertainty beside its conclusion.

2. **One missing input suppresses otherwise usable review findings.**
   [`review`](lib/data/progress_review.dart:355) returns early when weight, food or comparable
   lifts miss a gate. A missing lift comparison therefore prevents the combined review from
   reporting available weight/food observations. Standalone sections still exist further down.
   **Repair:** independent body, strength, diet and recovery results with their own counts;
   withhold the combined verdict/intake suggestion until its existing evidence gate passes.
   Do not weaken a gate just to populate an attractive dashboard.

### P1: Dates And Coverage Need To Be Trustworthy

3. **Progress charts discard elapsed time.**
   [`_bodySection`](lib/ui2/screens/progress_screen.dart:377) passes only values to `LineChart`;
   sparse raw observations become equally spaced, and unavailable seven-day means are omitted.
   [`LineChart`](lib/ui2/charts.dart:375) spaces points by index. The main plot has no dated axis
   or finger readout. A long gap can look like regular observations.
   **Repair:** calendar slots/timestamps, visible gaps, actual date/unit/axis and an accessible
   cursor. Raw points stay raw; smoothing never manufactures daily weigh-ins. A single reading
   gets a dated marker, not a trend verdict.

4. **All/Since start do not read all data families over the same history.**
   [`ProgressData.load`](lib/ui2/screens/progress_screen.dart:135) loads food for 400 days and
   workouts for one year, while body and lift history are loaded without those cutoffs.
   The wearable `getChart` path reads retained metric history, not a default 90-day limit.
   **Repair:** query each selected/reporting window with explicit retained coverage. Long-range
   summaries need complete aggregates and paginated detail, not silently capped totals or an
   unbounded UI-isolate rebuild. Label genuinely unavailable older evidence.

5. **Strength and reviews compare different periods under one page.**
   [`_strengthSection`](lib/ui2/screens/progress_screen.dart:982) compares two halves of the
   chart's selected range; `_reviewSection` independently compares closed weeks/months/first
   journey week. The review dates are shown, but the strength halves are not named when populated.
   **Repair:** separate the chart-history range from a clearly labelled review period. All
   cells inside that review use its exact before/after dates. Exercise-history exploration can
   retain arbitrary ranges and the current split-range comparison, labelled in its detail view.

6. **The workout breakdown omits Other.**
   [`_activitySection`](lib/ui2/screens/progress_screen.dart:1116) counts all completed sessions
   but prints only lift/run/walk subcounts. The total is not necessarily wrong; its displayed
   breakdown is incomplete (screenshot 13).
   **Repair:** include Other and reconcile disjoint category totals; identify unclassified or
   imported-only records without inventing timed sensor sessions.

### P2: Empty, Partial And Failed Are Too Easy To Confuse

7. **Food can show a profile weight as though it were a dated weigh-in.**
   [`_weightCard`](lib/ui2/screens/nutrition_screen.dart:485) falls back to `Profile.weightKg`
   when the dated ledger is empty; Progress correctly has no chart in that case. Both use the
   shared `body_weight` ledger, not competing weight stores.
   **Repair:** label profile-only weight explicitly, show a reading's effective date, and keep
   Log weight available. Never seed a dated record from a profile value without a real entry.

8. **Food completion and macro completeness need distinct labels.** A complete calorie day
   need not have complete protein data, so screenshot 13's missing protein average is not proof
   that the average failed. [`foodWindow`](lib/data/progress_review.dart) uses separate kcal and
   protein denominators. Food History's footer at
   [`nutrition_screen.dart:462`](lib/ui2/screens/nutrition_screen.dart:462) describes only the
   evening-entry automatic rule, despite Build 86's manual complete/incomplete overrides.
   **Repair:** compact per-nutrient coverage and one reachable explanation of Automatic/Complete/
   Incomplete. A missing nutrient remains unknown, not zero; unknown diary contents cannot be
   certified by the app. Do not silently include incomplete macros to remove a dash.

9. **Progress read errors can masquerade as absent data or replace valid saved sections.** Its
   chart helper catches errors and returns null; other load failures take the whole page to
   `_failed`, even after a valid `_d` existed
   ([`ProgressData.load`](lib/ui2/screens/progress_screen.dart:135),
   [`reload/build`](lib/ui2/screens/progress_screen.dart:239)).
   **Repair:** family-level loading/error/empty states, visible Retry and dated last-known values.
   A failed wearable refresh must not hide saved body/photos/sets or show "nothing recorded".

### P2: Composition And Controls Still Feel Like Build 85

10. **One generic surface dominates every task.** Screenshots 1-13 retain warm gradient panels,
    large radii, icon wells, rings and vertically stacked cards. `Surface` defaults to the same
    gradient/radius (`grammar.dart:469`), and the shell adds a tab-tinted top glow
    (`app_shell.dart:128`). Different accents cannot make these workflows structurally distinct.
    **Repair:** neutral dark canvas, unframed bands/rows, restrained separators and purpose-built
    tools. Use cards only for genuinely framed tools or repeated items; no nested cards.

11. **Today and Food spend too much space before the next useful action.** Today's recovery
    hero and action surface push HR down; Food's ring/day surface and large meal cards slow
    scanning (screenshots 1-2, 6-7). Train similarly spends space on four start tiles and a streak
    hero before the session list (8-10).
    **Repair:** compact wearable status on Today, a real diary on Food and start/resume plus a
    chronological session list on Train. Preserve deep detail without making it the overview.

12. **Progress's two horizontal chip strips require hunting.**
    [`_menus`](lib/ui2/screens/progress_screen.dart:325) hides measurements and ranges offscreen.
    **Repair:** two labelled menus whose selected values remain visible; all current choices stay
    available. Use segmented controls for Readings/7-day mean and Week/Month/Since start review.
    Do not replace a control with an unexplained icon or make horizontal scrolling mandatory.

### P2: The Visual Acceptance Test Missed The Actual Experience

13. **The Build 86 redesign render is not a first-viewport or full-shell test.**
    [`build86_redesign_render_test.dart`](test/build86_redesign_render_test.dart:288) renders
    Today/Food/Train at 390 logical pixels wide but 2,200/4,200 high; it does not include Progress
    or the actual `AppShell`. Passing its overflow checks cannot establish a good phone layout.
    **Repair:** real-height first viewports, scrolled states, all five tabs plus live/detail/edit
    flows, and populated/partial/new-user fixtures. Separately require Akshat's design acceptance.

## Implemented Experience

### Additional Date Provenance Repair

`_blockLine` previously described the last nonempty measurement-week block as the previous
week, even across missing weeks, and could include a future reading in the current block.
It now excludes future readings and names the actual earlier block's start date. Body estimate
context likewise excludes future measurements and labels a separately dated neck input rather
than implying all inputs came from the waist measurement's day. Invalid profile height does not
render an estimate. The formula and stored records are unchanged; a synthetic regression covers
the dated readouts.

### Shared Language

- Keep **Today / Trends / Food / Train / Progress**. A sixth Body/Pushups destination or a new
  navigation hierarchy is unnecessary. Preserve lazy tab loading, state, reselect behavior,
  notification routes and the return-to-live-workout bar.
- Dark remains the accepted default. Build 87 uses warm graphite (`#1B1C19`), clearly separated olive-grey
  tool surfaces, richer emerald/mint, turquoise, lavender and coral accents with bright neutral ink.
  Akshat rejected the first muted palette as dull; keep colour lively in meaningful signals and
  actions while the background stays quiet.
  No brown/espresso treatment or tab-wide colour wash. Colour is an
  indicator, not the only label for good/bad, partial, selected or paused.
- Flat bottom navigation with stable icon/label columns and a clear selected state. No floating
  decorative pill. Actual scrollable content ends above it and the home indicator.
- Page headings are compact; primary numbers have tabular figures. Fixed chart, toolbar and
  control dimensions use responsive constraints; large text can stack content without truncating
  essential dates, units or values. No viewport-based font scaling or negative letter spacing.
- Familiar Lucide icon commands with semantic names/tooltips; visible labels for destination and
  option menus. Keep 44-point targets. No tiny inline trash icon beside an expanding row.
- Overview copy budget: one short conclusion and at most one useful next action per section,
  no repeated eligibility paragraphs. A numeric value can carry a small coverage label. Show
  warning/uncertainty adjacent to the affected result; put full criteria/formulas in details.
  Safety-critical save/permission/backup failures must stay visible, not disappear into Info.

### Today: A Brief Check-In

First viewport, normal text: date/status header; compact Recovery / Sleep / Strain band; HRV and
resting-HR values; a useful wide HR trace and its live/recorded age; compact daily shortcuts.
The recovery ring is no longer the page's oversized hero. Tapping each metric still opens its
full detail in one action.

- Clearly separate latest band record, live sample age and calculated-insight time. Syncing or
  calculating occupies a stable status slot and opens existing Status. No global "Updated" badge
  may imply that every metric is equally fresh. Do not draw a recent HR segment that was not saved.
- Small Steps / Food / Body / Pushups / Train rows carry current values and direct actions;
  Resume replaces Start while a real session exists. Preserve measurement-day/reminder context.
- Retain both Budget and ACSM totals in a compact maintenance row; tap for the existing full
  breakdown, sources and separate lifting/HR analysis. Neither becomes an editable diet goal.
- The weekly report and findings remain reachable below or through named detail rows. Health
  warnings stay visible when active; a normal day does not need an explanatory wall.

### Trends: A Scannable Wearable Ledger

A shared Today / 7 days / 30 days / 3 months control sits over grouped, unframed metric rows:
recovery/sleep, cardiovascular signals, activity/temperature/wear. Each row gives its value/unit,
sparkline and specific coverage where needed. One shared caption explains the selected aggregation;
avoid repeating the same "Daily average" sentence ten times.

- Preserve Recovery, Sleep, HRV, resting HR, Strain, Steps, Budget/ACSM step calories, breathing
  when eligible, skin temperature when eligible and wear time, including current visibility rules.
- Keep the range when opening detail; retain day arrows, calendar, Jump to Today, dated cursor
  and all metric-specific detail. Do not change existing calculations or normal-range gates.
- Noticed/findings use a compact observation with a date and source; the full log stays available.
  Do not infer a numerical change or causal explanation that the current evidence does not supply.

### Food: A Diary, Not A Dashboard

Keep Today / History / Foods. Today opens with its date control, a compact eaten/goal/balance
summary and four readable macro totals, then the actual meal ledger. A single obvious Add command
lets the user choose a meal; each meal retains its direct Log action and overflow operations.

- Use meal headings and food rows, not four oversized floating cards. Food rows preserve amount,
  both-way serving equivalents, grams when known, kcal and `P / C / F / Fb`. Missing stays unknown.
- Keep Log again, saved-meal review, copy from/to, save meal, subgroup editing/reordering,
  search/clear, portions, Quick add, scans, custom labels and food/meal library management.
  Logging must remain an explicit commit; no new automatic nutrition or repeated-tap duplicates.
- Typed-goal progress and estimated-maintenance balance are separate readouts. Red remains tied
  to above estimated Budget maintenance, not a minor goal overage; unknown maintenance is neutral.
  The screenshot's large overage is not evidence that the implemented colour rule is wrong.
- The complete/incomplete control is compact and understandable. Partial macros have their own
  coverage. Keep confirmed deletion, Undo, discard guards, validation and failed-save retry.
- History prioritizes its dated chart and expandable month/day ledger. Weight/history-based
  maintenance remains accessible with profile-only versus measured weight clearly labelled.
  Keep weekly deficit, exclusions, Budget/ACSM history and all past-edit routes.

### Train: Start, Resume, Then Review

First viewport: a compact Run / Walk / Lift / Other start row (or the active-session resume block),
one weekly activity strip with the streak, and recent sessions grouped by day. A workout row has
fixed expander and separate safe overflow targets. Show the useful existing workout statistics,
not only a giant strain number; open the full session in one tap.

- Weekly activity shows earned activity versus protected rest/life-happens days distinctly;
  protected days are not workouts. Keep streak details, longest streak and the exact earning rules.
- Pushups is a functional row with actual state/count and its own day, reminders and streak,
  not a promotional feature-description card. It still adds no sensor strain or calories.
- Keep All workouts, historical/manual entry, Fix times and confirmed Delete. All activity types
  remain startable; no catalog/type is silently lost when simplifying the first row.
- Keep seven-day strain, run distance history, predictions, best efforts and records in named
  performance sections/details. These are moved into a scannable hierarchy, not removed.

### Progress: Show What Changed

First viewport, normal text: compact goal/baseline row with Add entry and Body settings; visible
Measurement and Range menus; dated body chart; latest value, actual change and coverage. For weight,
make **7-day mean** a first-class readout with its observed-day count, with a Readings/7-day mean
control. A single weigh-in is still shown usefully without promising a seven-day trend.

Immediately after that:
- **Body / Strength / Diet / Recovery evidence:** compact numeric rows with changes where
  eligible, actual dates/counts and a named detail destination. No universal progress score.
- **One review:** Week / Month / Since start, explicit before/after dates, one concise conclusion,
  comparable input results and an optional next action. Partial evidence stays useful while the
  combined verdict/intake adjustment remains unavailable. Full reasons are available in Details.
- **History and Photos:** compact entry preview, All history and a visible Compare photos route.
  Keep add/edit on any past date, units, measurement weekday, journey baseline and reminders.

Measurement choices remain Weight, Steps and all eight Body tape sites. Range choices remain
1 week, 1/2/3/6 months, 1 year, Since start and All. Start/Latest/Change uses real in-range readings;
Steps uses totals and covered-day averages. A selected empty range gets one small state with
Add/All history, not several repeated empty panels. Do not silently change a user's range.

Photo comparison retains two independently selected panels, date/pose labels, active-side state,
the bottom dated filmstrip, optional pose filtering and Swap. Preserve full-body framing and
manual historical attachments; do not replace it with first/latest-only or an overlay slider.

Goal selection retains all five existing phases and their settings. Keep goal-phase start and
journey baseline distinct. Food, training, weight and waist can be presented together, but neither
tape/photos nor stronger lifts prove measured muscle gain. Intake suggestions remain opt-in,
evidence-qualified and never automatically applied; no nutrition-model change is part of this UX plan.

### Live Workouts And Detail Routes

- Walk/run: stable start time and session identity; large elapsed/distance/current-speed or pace
  numbers; current versus average/source/fix-age explicit. HR/zones, cadence, route, voice and
  Budget/ACSM remain accessible. A stale speed must not be labelled current. Paused state is clear.
- Lift: one WHOOP session, one clock and one Finish. Bring the active exercise, previous sets,
  load meaning and editable set rows into the foreground; retain all six load meanings, split
  management, repeat-last-set, rest timer, skips/order/search, progress and qualified records.
  Keep HR/strain/MET calories and sensor context available without crowding set entry. Logging
  a set never invents measured set duration or resets the workout clock.
- Keep fixed pause/resume/end controls and minimize/return. No decorative empty control slot.
  Back/minimize must not end a session; a short mistaken workout has a safe summary Delete path.
- Summary: actual start/end/active time and saved state first, then type-specific charts/results.
  Keep route, splits, zones, HR/drift when eligible, set markers, calories, timing correction,
  retry-save and confirmed deletion. Never derive wall-clock end from active duration.
- Sleep/readiness/strain/other metrics: date navigation, their main chart and concise values first;
  methodology and corrections secondary. Keep complete night signal windows and honest recording
  gaps, stages, naps even on empty days, sleep-breathing, readiness drivers and their source status.
  Do not fill missing early-night HRV just to make a chart look complete.
- Settings retains band/profile/alarm, This phone steps, units, notification management, privacy,
  local diagnostic/status, import/export and encrypted database-plus-photo recovery. Permission
  recovery and failed backup/save actions stay conspicuous. Keep existing notification destinations
  and Pushups Home's manual/permission fallback; no new Always request or background promise.

## Feature Preservation And Navigation Gate

The replacement uses `metrics-map.md`, existing route/data tests and personal-build visibility
flags as its preservation inventory. The new render/flow fixture covers the main compositions;
the physical walkthrough below remains required. Every visible field must have a destination;
paired calorie methods remain paired where currently shown.

- Today -> existing Recovery, Sleep, Strain, Steps and all-day HR details; direct Food/Body/
  Pushups/Train actions; both maintenance methods; weekly report/findings; Settings/Status.
- Trends -> every currently eligible row, range-specific detail, day navigation and findings log.
- Food -> goals/macros, diary meals/subgroups/entries, log/search/portion/scans, personal foods/
  labels/meals, all history, weight/maintenance estimates and complete/incomplete controls.
- Train -> every activity type, setup/tracking-only/Lift splits, active resume, all summaries,
  manual/history/time edits, performance/records, streak/protection and Pushups.
- Progress -> goal/baseline/settings, all measurements/ranges/units, raw/mean/block history,
  labelled body estimates, import/past entries, dated photos/comparison, exercise comparisons,
  dietary/activity/recovery evidence and weekly/monthly/since-start reviews.
- Data/settings -> profile/units/source controls, permissions, alarm/reminders, status/logs,
  original import/preview/dedupe, CSV/JSON exports, encrypted photo-inclusive backup/restore.
- Preserve current notification and return/back entry points. An old shortcut can remain compact
  even when its data has a better primary home. Removal still requires Akshat's approval per item.

## Design And Phone Acceptance

Artifact production was explicitly approved before phone design acceptance. The validated IPA
is a testing candidate, not a design approval or permission to promote recovery/refresh ownership.

### Design Review Gate

1. Produce local, synthetic-data previews at actual phone height with the real five-tab shell:
   all five first viewports, one scroll continuation per page, live Walk/Lift, summary, Food add/
   edit, measurement entry and the photo comparison. No oversized full-page render as sole proof.
2. Show populated, sparse/partial and new-user Progress. Include missing protein, profile-only
   weight, an older chart-range reading, Other workouts and a failed/stale data family.
3. Akshat has authorized implementation and palette judgement. Hierarchy/flows still need his
   acceptance on the previews/phone; colour approval alone does not pass that gate. No mandatory new feature or sixth destination is assumed.

### Implementation QA Gate (After Approval)

- At normal text on the primary phone viewport, Today shows its HR trace, Food shows the first
  meal, Train shows recent sessions and Progress shows its chart without scrolling through copy.
  At enlarged text, controlled stacking/scrolling is acceptable; clipping is not.
- Screens at 320/390/430 logical-pixel widths, actual iPhone safe areas/heights, landscape and
  1x/2x/maximum-supported text; actual shell, keyboard, active-workout bar and scrolled last row.
  Keep the accepted dark default; verify token contrast wherever existing light tests still apply.
- Primary drill-down is one tap; complex history/settings is at most two deliberate navigation
  actions from its tab. There is no mandatory horizontal filter hunting. Add/log/start is explicit.
- Exercise the 2-3-minute daily visit: open -> honest recent data/status -> insights -> log food/
  body or resume session -> close. UI work must not stall BLE collection or foreground catch-up.
- Previous always moves left to an older local date; Next moves right, future is disabled;
  calendar/Today agree. Test DST, month boundaries, overnight sessions and the iOS edge-back gesture.
- Tabs retain their defined day/filter/scroll state; reselect-to-top/Today behavior is explicit and
  consistent. Opening a notification/history row carries its date/session, not today's default.
- Delete/cancel/Undo, unsaved edits, duplicate taps, failed writes/retries, permission denial/
  return from Settings, offline launch, local import conflicts and backup/media failures.
- Compare full feature/field inventory before/after. Test sparse dated axes, seven-calendar-day
  counts, long history windows, disjoint workout categories and aligned review denominators.
- VoiceOver labels/order/chart summaries and non-colour status; 44-point targets, clear disabled
  actions, reduced motion, long exercise/food/category names and chart cursor accessibility.
- Focused widget/data tests plus full existing regression, personal payload and artifact checks;
  release-build phone walkthrough, gym/locked workout and background/soak acceptance. Passing CI
  is necessary but cannot replace Akshat's structural design acceptance.

## Implementation Order And Separate Reliability Work

Implemented on Akshat's go-ahead: preserve the field/route inventory and dated-view models;
repair range/coverage/error presentation; build the shared flat shell/controls; recompose Progress
and Food; then Today/Train/Trends and their live/detail flows; verify all states and device gates.
This is a coherent candidate plan, not authorization to distribute selected features into smaller
releases or to publish another unreviewed cosmetic pass.

Build 87 implements the deferred per-input calculation reuse and WRIST_OFF silence-reconnect
work in `background-sync-plan.md`/`bugs.md`/`todo.md`. Keep those separately tested; the redesign itself
cannot fix iOS wake scheduling or prove background reliability. No change to analytics coefficients,
step ownership, calorie pricing, stored history, signing identity or recovery format is proposed.
Review algorithm-version requirements if a later implementation changes computed output.

## Approved Convenience Improvements

Akshat requested further convenience proposals with approval before changes. These three are
approved additions to Build 87. Implementation, publication and local/cloud/artifact checks are complete; phone acceptance remains open:

- **Recent HR on Today:** 10-minute / 1-hour / Day selection using recorded timestamps and
  existing chart data. Preserve the full-day view, real gaps and Live/Recorded freshness;
  correct local-day/DST boundaries are required. A shorter view cannot recover unrecorded data.
- **Direct diary portion editing:** tapping a food row opens its existing amount editor instead
  of first navigating through the meal and action sheet. Reuse saved-food conversion, grouping,
  validation and awaitable writes; keep meal/group actions, unknown-definition edit fallback,
  confirmed deletion and existing historical values intact.
- **All-workout filters:** activity and date-range controls inside All workouts, retaining month
  groups and saved history without narrowing the unfiltered view. Clear/reset must be obvious; imported or unknown types
  cannot disappear from All, and filtering must not change streaks, totals or saved sessions.
  Reopening a custom range safely bounds both dates if old history was removed or the clock changed.

No new tab, permission, service, nutrition rule or storage migration is needed. Re-tapping the
current tab already scrolls to top, and the freshness line already opens Status; these existing
shortcuts are not new feature proposals. Akshat approved all three; `todo.md` records their verification gates.

## Protein And Freshness Follow-Through

- Primary filled actions keep their brighter accent colour with measured AA black/white labels,
  instead of darkening it for white text. Typography uses natural zero letter spacing.
- Shared diary date selectors wrap historical dates at accessible text sizes; meal detail drops
  redundant usage paragraphs without removing controls.
- Meal-group headers, compact diary meal headers, copy-preview summaries and saved-meal rows
  now show protein beside calories. Known-only totals are explicitly "at least"; wholly missing
  protein stays "Protein not tracked". Item macros and the existing complete-macro summaries remain.
- Today reads its served day-result payload and committed timestamp together. End-of-pass
  freshness may lag after a later-day cancellation, but cannot hide or misdate the already
  committed current-day activity. Prior-night qualification remains separate.
- Recent recorded HR excludes zero/unavailable values and unverified secondary sensor sources.
  The existing primary-band source rule and minute coverage threshold are reused.

## Local Verification And Remaining Gates

- `build87_redesign_render_test.dart` exercises the real five-tab shell at 320/390/430 widths,
  portrait/landscape and 1x/2x/3.1x text, plus actual-height photo, live Walk/Lift, summary and body
  entry flows. Populated/empty and failed-family fixtures are synthetic; capture output is local
  ignored `build/ui_capture/`. No phone data/media enters fixtures.
- `build87_sync_test.dart` compares fresh/reused outputs across isolates, daytime/profile/baseline/
  stage/window/temperature edits, failure and cancellation; it checks unknown/on/off-wrist and
  pre-link replay/future wear evidence. Failed goal/food-mark reads use strict reporting rather
  than substituting the default goal or automatic completeness; prior successful families remain. Reuse is process-local and bounded, not a persistent night cache or
  proof of phone CPU improvement; preparation/sleep staging remain uncached.
- Algorithm 91, formulas, schema, capabilities, signing identity, source ownership and recovery
  format are unchanged. Existing calculation cancellation and commit-before-ACK stay intact.
- Retained history currently materializes daily food entries and session rows for the overview.
  The previous silent cutoffs are removed; SQL aggregates/paged details for very large multi-year
  histories remain a performance ceiling, not a claim of pagination. All-workout filters reuse
  the existing native-session ledger and imported-workout adapter; that adapter still limits its
  imported overview to 200 rows. This is an existing visibility ceiling, not a complete imported
  archive or a storage deletion. Raising it/paging it is a separate follow-up.
- Final standard regression passes: 3,611 tests, 404 intentional skips, no failures.
  Personal-profile render/data/sync/token/contrast checks pass all 310 tests. A final two-test
  personal run covers primary-button contrast and the custom-date repair added after the
  extended suite compiled its fixture; the full standard run also includes that repair.
  Static analysis has no errors/warnings and 133 informational lints. Personal-iOS contracts
  (9), profile check, package-pin guard and `git diff --check` pass locally. These are Windows
  checks. Separately, Linux CI passes 3,616 tests (399 intentional skips), and the personal macOS
  compilation, downloaded source/version/checksum, ZIP CRC and payload contract all pass.
  `setup.md` owns the exact source, workflow and artifact evidence.
- Optional upstream golden references are not committed in this checkout. The standard suite
  intentionally skips them; generated capture previews are retained under ignored `build/`,
  separate from `test/goldens/`. Captures are visual review material, not approved golden baselines.
- Actual-height shortcut/protein previews are rendered locally with synthetic data; they are
  review material, not Akshat's design acceptance.
- Still open: Akshat's structural acceptance, physical keyboard/VoiceOver/edge gestures, gym/
  locked workout, foreground freshness, background CPU/wake/offload and 72-hour soak checks.
  Source/layout checks and existing Build 86 CI cannot substitute for those gates.

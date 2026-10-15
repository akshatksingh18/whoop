# WHOOP Build Plan And Verification

**State:** Akshat reports Build `0.9.56`/`89` installed and being tested. Build 88 was the previous
install. Build 89 works on his phone and becomes the cached recovery build before Build 90 installs;
until then Build 70 remains cached recovery. Build 90's engine/data and approved A + compact B interface are implemented in local source;
integration, full cloud checks and native/device acceptance remain open.
Build `0.9.37`/`70` remains the accepted recovery build. Akshat confirmed its phone check
(including build 69's) and current-version automatic-refresh enrollment at the existing signed
identity, with no error. The completed feature checklist is cleared; `CLAUDE.md` and
`metrics-map.md` describe shipped behavior, readiness baseline rules and known limits.

- Current sync evidence (`bugs.md`, "Background sync and slow pull-to-refresh"): real transfer
  gaps recover on foreground launch, although background offloads work in other periods.
  MetricKit confirms background CPU-limit exits for its 8 Oct reporting window, without
  timestamps tying them to individual gaps. Research/source tracing is complete in
  `background-sync-plan.md`; bounded repair and personal background modes ship in installed
  build 86, but physical background acceptance remains open.
- Previously installed build `0.9.40`/`73` initially looked good, but its Strain cursor selected
  future times. Build 74 implemented the repair; `build-74-audit.md` records the wider
  graph/navigation/notification findings and calorie-model research. Outstanding phone checks
  carry forward to build 85, excluding the Live Activity removed in build 81.
- Previously installed build `0.9.39`/`72` was not accepted. Akshat reported background
  voice cues delayed until foreground and supplied sync/calorie/macro/profile issues. The
  build-72 streak did not count step-only goal days. `workout-sync-audit.md` owns its findings and approved
  repairs; the build-73 replacement below passes local/CI/macOS and artifact validation.
- Today refresh updating steps is confirmed on build 72. Build-73 maintenance verification remains open:
  Akshat reports unchanged calories; the main Food card updates in an isolated real-repository
  probe, but an already-open build-72 maintenance breakdown remained stale. Build 73 addresses
  that source defect; the report owns the earlier reproduction and the phone pass remains pending.
- Complete the broader physical-device matrix in `CLAUDE.md`, including locked/background route
  recording, range-loss restoration, system termination, overnight collection and the 72-hour soak.
- Verify naturally elapsed unattended refresh cycles, the alert thresholds, Wi-Fi/USB recovery
  and controlled expiry recovery. The previously forced-due refresh and current-version enrollment
  do not prove the long-term schedule.

## Build 90 (`0.9.57`/`90`): All Work Merged, Visual Review Then Release

**State:** the Claude lane, the Codex engine/data lane and the calm interface Akshat selected
(A overall with B's compact macro rows, built by Codex after he assigned it the whole UI) are
merged on `build-90` (version `0.9.57+90`, algorithm 95, schema 50); no Build 90 IPA is built
or installed. Akshat chose to ship the whole backlog in `build-90-audit.md` ("Complete
App-Wide Worklist") in this one build, including the full engine depth, plus a home bodyweight
workout (`home-workout-proposal.md`). Claude integrates, pushes and runs every GitHub check.
Next: Akshat's visual approval of the merged pages, the full cloud run, then the release phase.
Local synthetic checks do not establish native iPhone acceptance.

### Decisions (Akshat, Build 89 review)

- D1 Scope: everything in the audit worklist ships in Build 90, not split across releases.
- D2 Engine: full depth. Fix and test the code-provable items (one worn-minute definition, a
  per-day time zone so travel never shifts days, blank instead of 0 for unconfirmed sensor
  values, no legacy oxygen rows in CSV, a 4-value RR cap in the decoder, older R10-lite heart
  rate reaching the analytics substrate where present). Research every remaining item
  thoroughly so that no constant is an assumption: each number either cites a primary source
  or is derived and tested; unknown stays absent. Recalculation covers only retained inputs
  (about three days of raw); older stored days keep their values and nothing is invented.
- D3 Research: one agent only does internet research. Akshat reassigned it to Claude when
  Codex's usage ran out, and the first pass is done (`build-90-research.md`); the engine lane's
  implementation follows its verdicts. Queries never contain Akshat's data. A finding that changes a headline formula (sleep staging, readiness,
  strain baseline) is summarised for Akshat's per-item approval before it merges; findings
  that need phone measurements ship instrumentation and a safe default.
  Akshat subsequently requested Codex's independent internet review of calories and recovery;
  this explicit exception is recorded in `energy-recovery-independent-review.md`. Its new
  recommendations are research only, not additional formula approval.
- D4 Food counting (B90-10): each counted day keeps the calorie goal it was judged against;
  days before Build 90 freeze at the goal on Build 90's first open (no older goal history
  exists). Manual marks win; "Counted automatically" is labelled apart from "Marked complete".
- D5 Optional features, all in: pinned Trends (up to 3); copy a whole food day (review,
  adjust portions, untick, explicit Log, into the viewed date); edit or delete a finished lift
  set with progress recomputed (no adding a forgotten set; session times, HR and calories
  unchanged); dated milestones on Body and Strength (no scores or notifications). Warm-up flags
  and RPE/RIR stay out.
- D6 Layout: accepted A calm framework with B's whole calorie/macro component: remaining
  calories in a ring, eaten/fixed goal beside it, then four slim macro rows (protein larger),
  retaining all four values/targets. Today has one recovery headline, right-aligned supporting
  values, then food/weigh-in/train actions; Body and Pushups remain available. Steps, food
  and maintenance each appear once. Trends groups related rows and retains missing-day
  context. Train leads with Start/Resume. Progress retains one fixed-window goal verdict,
  with outcomes and inputs opening the full details and all eight exploration periods.
- D7 Fallback: Build 89 works on Akshat's phone; it becomes the cached recovery build before
  Build 90 (which changes the database) is installed, after an off-phone encrypted export.
- D8 Process: Claude writes Codex's brief; Codex commits on its own branch and never pushes;
  Claude privacy-reviews, pushes and runs CI. Screenshot gates: an early Progress preview, then
  one full review of every changed screen before the IPA.

### Lanes and file ownership

The original split below governed the first engine/UI implementation. Akshat subsequently
assigned the entire approved A + compact B UI task and related documentation to Codex;
Today, Trends, Train, Progress, shared components and their tests are now included. Existing
reviewed features are retained from `1ceba06b`. Claude still handles integration, privacy review,
pushes, cloud checks and release metadata; Codex never pushes or edits another worktree.

- **Claude lane (`build-90-claude`, separate worktree):** Progress overview and Body / Strength /
  context details, History range, quick weigh-in, milestones (B90-01, B90-04, B90-09); Today
  redesign, freshness line and links; Trends and pinned metrics; Train redesign, compact
  Pushups row and Train's large text; Lift Log: home workout, variations, finished-set
  correction; design system: Reduce Motion back (B90-03), tab labels and selected-state
  semantics, consistent tap affordances (B90-08 shared parts). Files: `progress_screen.dart`
  (split into new files), `progress_review.dart`, `goal_plan.dart`, `body_log.dart`,
  `home_screen.dart`, `today_plan.dart`, `pushups_screen.dart`, `health_screen.dart`,
  `workout_screen.dart`, `lift_log.dart`, `lift_log_ui.dart`, `lift_progress.dart`,
  `theme.dart`, `grammar.dart`, `app_shell.dart`, the widget gallery, `pubspec.yaml` and
  version metadata.
- **Codex lane (`build-90-codex`, main checkout):** all engine/data work (D2; Claude owns research D3); workout-deletion publication (B90-02 data side); analysis export (B90-05..07);
  backup/export wording (B90-11); frozen food counting (B90-10); Food redesign, Food large text
  and Food's Progress link; whole-day food copy; performance profiling and bounded queries.
  Files: `packages/protocol`, `packages/analytics`, `lib/compute/` (including
  `derivation_engine.dart` and `kAlgoVersion`), `db.dart`, `app_state.dart`,
  `nutrition_store.dart`, `analysis_export.dart`, `profile/data.dart`, `media_backup.dart`,
  `lib/l10n/`, `nutrition_screen.dart`, `food_calendar.dart`, `food_diary.dart`.
- **Shared rules:** three contracts land on the base branch before the lanes split: one
  `openProgress(context, destination)` entry, a session-change publication hook in AppState,
  and additive-only changes to the food-window/rollup functions Progress reads. Codex keeps new
  Food widgets private to its own files; any public widget it adds is registered in the
  gallery in a marked Codex block. Codex updates the full approved UI render cases and affected current-state design/docs.
  Claude records cloud/release evidence in `setup.md` and guides at integration. Small targeted local checks only; full
  suites run on GitHub.

### Phases

- [x] 0. Setup (Claude): the reviewed audit/doc edits are committed on `build-90` (from
  `main`) with the three contracts (`openProgress`/`ProgressDest` in
  `lib/ui2/screens/progress_routes.dart`, `AppState.publishSessionChange()`, and the
  additive-only note above `rollupDay`); `build-90`, `build-90-claude` and `build-90-codex`
  are pushed to origin and local-backup. Linux CI `38618327848` on the contracts commit
  passes 3,719 tests (427 intentional skips; 133 informational lints, no errors or warnings).
  Codex's lane brief is written when implementation starts.
- [x] Research pass (Claude, D3): `build-90-research.md`, with the local measurements from
  Akshat's export (values only in git-ignored `build/research-local/`): A1 needs no change
  (the withholding rule is dropped; store the omitted-beat share as quality), E1 R10 is
  absent (no change), and D1 found a Build 89 bug (`bugs.md`: the day-strain floor never
  reaches the stored strain), added to the engine lane. Phone measurements stay open: C1
  zone pickup, E4 bursts, F1 wake timing, H1 outdoor speed.
- [x] Akshat's research decisions: every recommendation accepted (A2 gap segments, B2b sleep
  need adds a quarter of the gap and drops the strain bonus, G2 bodyweight 3.0 MET, G4 the
  maintenance range under 6 weeks, G6 the 10-rep cap). C3: the day's weight is the first
  reading of the day; every reading is kept with its time. Exercise energy stays at the low end of its source and beside maintenance, never
  inside it: lifting and home workouts already use (MET − 1) × weight × time on a separate
  line. Runs and walks stay inside maintenance through the step and distance formula
  (Akshat: walking is normal daily movement, which that formula was built to include). D1's strain form is chosen later by
  running the app's own functions over the export.
- [x] 1. Lanes in parallel: Claude lane on `build-90-claude`, Codex lane on
  `build-90-codex` (both lane notes below); the early Progress preview was sent.
- [x] 2a. Merge (Claude): Codex's commits privacy-reviewed, then Codex lane and Claude lane
  merged into `build-90`; `0.9.57+90`; one `kAlgoVersion` bump (94 → 95, Codex's combined
  changelog). Integration: Today's clock labels read the recorded zone, LiveFeed takes the
  movement estimate and speed uncertainty, session writes publish once from the repository.
  The first merged analysis found five test-file nullability errors from the optical change
  and three unused imports; fixed.
- [x] 2b. Full GitHub tests on the merged branch: Linux CI `38734578809` passes 3,853 tests
  (437 intentional skips; 165 informational lints, no errors or warnings). Eleven older tests
  were updated to Build 90's contracts (null for unconfirmed sensors, platform-qualified live
  speed, the new Food card and energy labels, the shared session signal) and
  `EnergyComparison` joined the ui2 barrel.
- [x] 2c. First screenshot review (superseded by the calm UI): synthetic captures; the tab
  bar keeps its labels whole at 2x/3.1x over Food.
  Akshat's review: Progress looks better; Today, Trends and Food look noisy and inconsistent.
  Audit findings (not yet fixed): `MetricLine` leaves the empty chart slot's share as dead
  space at the row's right end, so values float mid-card when a row has no history; rows
  without a chevron (Today's Food) end further right than the others; units inline with the
  big number make digits end at different places; the 92-pt uppercase label column wraps
  labels and splits words ("SKIN TEMPE / RATURE"); every row uses the 30-pt number, so
  nothing leads; coverage ("7/7 days") repeats on every complete row; Today shows steps,
  food and maintenance two or three times; Trends' Step calories block breaks the list's
  pattern; Food's calorie card carries about 20 numbers (eaten, goal, left, maintenance
  gap, four macros with targets and bars), every food repeats a P/C/F/Fb line, and the
  maintenance gap repeats in the card below. Today's "resting HR 53 asleep" (joined with
  non-breaking spaces) now breaks mid-word in the hero card; it moves to its own line in the
  redesign. Full-page mockups of the proposed Today, Trends, Food and Train, with the current
  full pages beside them, were made; Akshat then selected Codex's A + compact B composition,
  which addresses these findings, and assigned the whole UI to Codex.
- [ ] 2d. Calm UI merged into `build-90` (Codex `f9190e48`, `b11fa463`, `28a5dd2a`): Codex's
  UI files carry the reviewed Claude-lane source from `1ceba06b`, so the merge takes them
  whole and keeps the integration fixes. Next: Akshat's visual approval of the merged full
  pages, then the full GitHub run.
  Claude's visual audit of the merged full pages (synthetic, 1x) found, before approval:
  Today's quick actions are uneven, Food/Steps sub-lines differ ("/2,300", none), the HR range
  control leaves a gap, maintenance shows "Unavailable" as a number; Trends' Step calories
  value wraps over three lines and coverage orphans "days" at 30 days; a stray line beside
  Food's plate, meal totals only on multi-item meals; Train shows Training review, empty
  week dots beside "2 sessions this week", leftover space under This week and Pushups, and
  the Import card touching the strain card, still named Health Connect; Progress's Add body
  entry looks disabled; Body's average-weight card is cramped and milestones show 2-decimal
  inches; context shows recovery as "72%"; the Recovery page is titled Readiness; Sleep says
  no hypnogram while listing stages and leaves Fix sleep times outside a card.
- [ ] Recovery sensitivity (Akshat's Build 89 phone, reported in review; decision open):
  one night's HRV, below every night in the 14-night repaired-HRV baseline while the other
  inputs were normal, scored recovery in the high 20s ("Take it easy"). The cause is in the
  formula, not a calculation fault: the HRV input is a robust z against only 14 nights with
  a tight spread, it is unbounded, and the composite maps z through an unscaled logistic, so
  one input at about −2.5 σ carries the score alone. The HRV detail page uses a different,
  longer history, so it called the same night ordinary. Options for Akshat (headline change,
  needs his approval and research): a longer or rolling-mean HRV baseline (Plews-style),
  a bound on any one input's z, and the HRV page using the same window as recovery. The
  baseline lengthens on its own as repaired-HRV nights accumulate.
  Researched in `build-90-research.md` J (recovery: recent-night HRV blend, a bound on one
  input, one HRV history everywhere) and K (energy end to end: steps, Mifflin, lifting,
  Keytel and digestion verified at the low end; the running Budget coefficient and the
  day total sit below realistic, with an awake-time cost and 0.17 mL/kg/m proposed). Each
  headline change waits for Akshat's choice.
- [ ] 3. Release: promote Build 89 to `final-ipas/whoop/backup/` (D7); personal macOS build,
  validation and the single testing candidate.
- [ ] 4. Akshat's phone acceptance: the still-open Build 89 checks below, every Build 90
  change, and the device/operational matrix in `build-90-audit.md`.

### Home bodyweight workout (audit, Claude lane)

Most of it exists. Calisthenics (3.8 MET) and Bodyweight (3.5 MET) are lift types, so a workout
of either type gets the Lift Log panel: saved splits (up to 20, 40 exercises each), set logging,
repeat last set, rest timer, previous performance and history. A workout starts and logs with
no band ("No band connected"); calories stay the existing MET estimate; a 10-minute session
counts for the streak as a lift day. Sets accept weight 0, comparisons at the same weight are
reps-based, and no strength estimate is made without load, so a reps-only set is honest today.
"Added weight" (bodyweight excluded) fits a loaded backpack. Comparisons already separate by
name, load mode and the exercise's setup note.

Missing, with the smallest fix:
- Reps-only entry needs a typed "0" and reads "0 lb added × 12". Fix: in Added weight, a blank
  weight logs bodyweight only and reads "Bodyweight × 12" or "+10 lb × 12". No new mode, so
  backpack and bodyweight sets stay one exercise (heavier for fewer reps reads "not comparable").
- Variations: the setup note already keeps comparisons valid, but "last time" and Repeat look
  up name and mode only, so after a variation change they show the other variation. Fix: use
  the note there too, label it "Variation", and offer that exercise's earlier variations as
  one-tap chips plus "New variation". "Push-up · Feet raised" stays one Push-up exercise.
- Starting: Lift starts Weight training; Calisthenics needs Other and the picker. Fix: Lift
  offers Gym or Home; Home starts the Bodyweight type with the Home split. Bodyweight is the
  lowest matching Compendium code for this routine (02056 body-weight resistance, general,
  3.0 MET after G2), as Akshat wants the low end; Calisthenics stays at 3.8 for other use.
- A ready, editable Home split: Push-up, Backpack row, Bed-edge dip, Split squat, Leg raise.
- Not added (Akshat's constraints): timed plank, programming, targets, RPE/RIR, progression
  suggestions, new calorie logic.

Akshat's decisions: variations inside one exercise with variation buttons (H1); a blank
weight logs bodyweight only, no new mode (H2); Lift asks Gym or Home (H3); push-ups logged in
a workout stay separate from the Pushups daily count (H4); the five names above (H5); loads
stay in pounds (H6). Home loads can be dumbbells or a backpack of unknown weight: a
dumbbell-held exercise uses the existing Weight per hand mode, a backpack of known weight
uses Added weight, and an unweighed backpack is logged as a variation ("Backpack") with a
blank weight, never a guessed number. A changed load mode is a separate comparison history.

### Lane notes

- Claude: implemented on `build-90-claude` (each with synthetic tests; lane CI passed; merged
  into `build-90` with the Codex lane; not yet phone-checked):
  - Progress overview (`goal_review.dart`: one fixed closed-week verdict with its dates and
    exact missing evidence; Weight/Waist/Strength rows and the inputs line from the same
    weeks), Body / Strength / Food-training-recovery detail pages with History range,
    before → now and milestones (`progress_milestones.dart`); `openProgress` opens a detail
    page over the asking screen so Back returns there.
  - B90-01 body entry validates every field before writing and reports partial saves; quick
    weigh-in layout; C3 every weigh-in kept in `body_weight_reading`, the day's weight is its
    first reading (add or correct; readings listed and deletable). B90-04 goal save recovery.
  - B90-03 Reduce Motion keeps iOS edge-back; B90-08 large text for the shell (tab labels keep
    size), titles (Apple Large Title scaling), Progress, Train tiles and section actions;
    VoiceOver selected states; MetricLine values before sparklines with tap chevrons.
  - Home workout (Lift asks Gym or Home; Home split; blank Added weight = bodyweight;
    variation chips; variation-aware last time); finished-set fix/delete (D5).
  - Train order (start, suggestions, recent, week, pushups); B90-02 `publishSessionChange` on
    workout log/edit/delete; Today plan card before the HR chart, freshness line opens
    Status; Trends real dates and pinned favourites (D5); resting HR labelled "asleep".
  - G6 strength estimate cap 10 reps; G5 Navy ± 3.5%.
  - Both requests to Codex are done in its lane: Food's quick weigh-in goes through
    `BodyLogDb.putWeight`, and Sleep/Readiness/metric detail say lowest 30-minute average
    while asleep.
- Codex: Independent calorie/recovery review is complete in
  `energy-recovery-independent-review.md`, against `9170201b` and additional primary sources.
  Two synthetic reproductions remain open: legacy stored workout kcal includes resting energy
  (and assumes 170 cm when height is missing), and the other-workout HR/MET minimum has a
  discontinuity around zero net HR. `bugs.md` and `metrics-map.md` qualify those paths.
  Running 0.17 is a reasonable conservative candidate; a universal awake 1.2 multiplier and
  exact three-night/two-z recovery tuning are not established by the supplied justification.
  Existing targeted energy tests pass (28); an ignored synthetic semantics probe passes (1)
  while reproducing both issues. No private export, formula, schema, algorithm version or
  dependency changed; no full build/suite, commit, push or phone validation in this review.
  New numerical behavior remains subject to Akshat's approval.
  Akshat selected A overall with B's compact macro section and approved app
  implementation. This supersedes the earlier D6 single-row macro composition: Food now
  uses the selected B balance ring and four compact nutrient/target rows (protein larger),
  preserving all four nutrients. The Codex-owned Food implementation is complete in source:
  remaining calories inside the ring, eaten/fixed goal beside it, visible Add food, smaller week marks, calorie/protein diary rows, no repeated full-macro footer, and large-text meal/action
  reflow. Full meal/group/entry nutrient detail and existing logging, portions, calendar,
  scanning, library, labels, copy/save, maintenance and Progress routes remain. Failed counting
  status writes report failure without falsely changing status. No metric/storage formula or
  dependency/version change. The ignored preview now defaults to the selected A+B blend;
  its 38-group preservation map distinguishes demos/specifications from production proof.
  Checks pass: `build90_calm_food_test.dart` (6), `build90_food_ui_test.dart` (7),
  `build89_food_test.dart` (6), and three selected full Food renders at 1x/2x/3.1x (3).
  Targeted analysis has no errors/warnings; existing curly-brace style infos remain.
  Rendered Food top/lower views were inspected; this is synthetic Windows evidence, not phone
  acceptance. The reviewed shared tab-label and Reduce Motion fixes are retained for the full UI.
  Akshat explicitly assigned the whole approved UI task to Codex, including Today, Trends,
  Train, Progress and shared components. The earlier file split is superseded for this UI
  implementation; no push, rebase/branch switch or other-worktree edit is authorized. Akshat
  later explicitly authorized the regular merge of integrated `build-90` into this branch.
  Reviewed Build 90 Progress/Body/Lift workflows and their models are carried forward from
  `1ceba06b` into this checkout so the layout refinement retains those features.
  UI source now applies that framework across Today, Trends, Train, Progress, Sleep and
  Recovery. Shared rows align digits with a stable action gutter; units sit below; full
  comparison labels/values and detail titles reflow at large text. Trends groups related
  metrics and prints missing-day counts only when needed; both energy methods remain.
  Today keeps its real data/status, HR chart, Body, Pushups and weekly card, with early
  Log food / Weigh in / Train-or-Resume actions and no duplicate totals. Train keeps Gym/Home,
  history/options, imports, week/rest/streak and full Lift Log. Small leaf/moon artwork is
  decoration only. Progress keeps its fixed review verdict, all reasoning/next steps, dates,
  missing evidence, eight detail periods, weight/tape/photo history, strength and context.
  Log Food and Food → Foods now permit hold-drag while searching/filtering. Reordered
  matches occupy their existing slots; hidden items keep their positions and the full order
  is saved. My foods and My meals retain swipe-to-delete and cancellation.
  Source commits: Food `f9190e48`; reviewed workflows `b11fa463`; the calm whole-UI
  refinement and filtered-order repair are committed together in the current change.
  Final checks: 20 main/detail cases at 1x/3.1x reach the actual bottom, with every intermediate
  viewport captured; four affected Body/context rerenders pass, then two 3.1x regressions
  explicitly confirm stacked comparison groups. Common layout (4), quick Body entry (3),
  iOS Reduce Motion back (3), Home workout meanings (4), filtered gesture/order/swipe (3),
  existing Foods search (1), Today quick actions (1) and fixed goal review (5) pass.
  Targeted analysis of six changed paths has no errors/warnings (10 informational lints).
  The ignored `build/ui_capture/calm-ui-review.html` gallery includes the lower/intermediate
  sections, not only top views; `build/research-local/claude-a-b-ui-handoff.md` is updated with
  full progress, ownership grants and integration/device gates. DESIGN, CLAUDE, README, audit,
  bugs and metrics-map are synchronized. Root/container routing and background-sync-plan were
  checked: this UI work changes neither their routing nor background behavior, so no edit is
  needed there. No push, full local suite/build, new IPA or phone acceptance claimed.
  Akshat clarified the missing B ring; the correction restores the full selected card rather
  than only its rows. Ring fill is remaining / fixed goal only when exact; missing intake/goal
  uses absence, and partial energy keeps its bound without an exact arc. Macros retain targets,
  completeness, unknown hatching and full details. The plate/utensil and linear calorie bar are
  replaced. Synthetic card/counting/copy checks pass (25); full Food scroll renders pass at
  1x/2x/3.1x. Targeted analysis has no errors/warnings (four existing informational lints).
  The quoted 24 observations are individually checked in `build-90-audit.md` under
  Current Visual Acceptance. Akshat approved the six presentation choices and explicit fixes;
  other observations keep their individual open/profile/fixture dispositions there. No phone
  or cloud acceptance is claimed.
  Akshat approved a regular local merge after the requested fast-forward proved impossible
  (`c8ddfb73` and `e7af786e` diverged). Both histories and the integration fixes are preserved
  in merge `8ab9c756` on Codex. The six presentation choices and explicit fixes are implemented:
  consistent Today `of <goal>` sub-lines and equal action fills; Trends pins in the header,
  intact coverage and full-width Movement context; every meal's energy in its heading with
  singleton duplication removed; Copy a day/Progress grouped in the meals panel; Food/Training/
  Recovery input groups retaining every denominator; active Add body entry; full-width Body
  comparison rows; and a collapsible Sleep correction card. Body summaries use one decimal;
  milestones use two decimals or the actual difference when rounding would tie. Exact stored
  readings/editing and all routes remain. Progress recovery uses a plain score, not a percent.
  Akshat also requested a thorough Today HR scrub check. All three ranges and day detail now
  use the last finite positive recorded minute at or before now; trailing gaps/future samples
  cannot be selected. Range changes clear selection, retained cursors clamp to new limits,
  pointer/VoiceOver share the limit, and internal gaps remain. Live bpm stays separate. No
  acquisition or metric/storage formula change. Current targeted checks pass: compact Food
  (15, including all-meal/singleton/unknown states at 1x/2x/3.1x), milestones (6, including both
  rounding-tie cases), shared layout (4), Sleep correction expand/collapse/actions (1), and
  real Today HR range/gesture/accessibility plus data-boundary/DST cases (7). Seven affected
  whole-page renders pass at 1x; Food, Sleep, 30-day Trends, Progress and Body also reach their
  real bottoms at 3.1x without overflow (5). Total: 45 targeted checks; no full local suite/build.
  Targeted analysis of nine affected paths has no errors/warnings; informational style lints
  remain. Normal-size captures were visually inspected across top/lower sections. Claude will re-render
  full pages, privacy-review, push and run cloud checks afterward.
  No reset/rebase, push or other-worktree edit was done. Analytics and schema remain unchanged.
  Task 1 committed as `22d8003f`, ready for Claude: schema 50 implemented; all 4 targeted checks in
  `test/build90_schema_test.dart` pass (v49 migration/idempotency, encrypted full snapshot
  restore/wipe, legacy-export restore, and scoped day export). No full local suite or build.
  Schema 50 adds `day_zone(date, zone_id, start_offset_sec, end_offset_sec, start_ts, end_ts)`
  and `zone_change(at_ts, zone_id)` (Unix seconds, offsets east of UTC); no guessed legacy zones.
  `body_weight_reading` has the requested fields plus preserved `unit`, `entered`, `origin_id`;
  legacy IDs are `legacy:<date>`, `at_ts` is unchanged, `created_at` is migration time. The
  one-time seed is guarded by `sync_cursor.name = b90_body_reading_seed`; old-file imports
  seed legacy daily rows too. `food_entry.logged_at` is nullable for unknown old logging times.
  `food_day_count(date, calorie_goal, basis, counted, frozen_at, updated_at)` stores frozen
  counting provenance; task 8 now integrates first-open goal freezing and new writes. All four tables are in
  import/salvage and full snapshots, day exports carry their scoped context, and wipe is dynamic.
  Body's first-reading selection/writes are retained from the reviewed UI source. Task 2 implemented: historical
  v12/v24 RR counts cap at four, R10 retains its independent eight-value limit, unconfirmed
  optical inputs stay nullable, legacy zero sentinels read as absent, and CSV omits legacy
  oxygen metrics. All 5 synthetic checks in `test/build90_decode_integrity_test.dart` pass.
  Algorithm version is 95, with one changelog entry for the approved analytics-output changes.
  Akshat also assigned `csv_export.dart`, `day_label.dart`, `local_repository_impl.dart`,
  `day_timeline.dart` and `activity/live.dart` to Codex. No push or full local build/test run.
  Task 2 is committed as `05d7dca2`. Task 3 now shares bridged record-minute accounting
  across metric history and day wear; event-backed charging/off-wrist, recording gaps and
  pending sync have distinct timeline copy. `build90_wear_test.dart` passes 4 checks and
  `wear_coverage_test.dart` passes 12, including the actual two-reader comparison.
  Task 3 is committed as `d5b602a7`. Task 4 now persists the native zone inbox and timeline,
  day boundaries/offsets, worker context and dated chart anchors; SRI uses absolute 24-hour
  separation, and bedtime history excludes travel-spanning nights. Ten timezone checks and
  five schema/recovery checks pass, including encrypted restore/cache hydration. Native Swift
  build and open/background phone delivery are unverified. Legacy exports cannot reconstruct
  earlier travel: the first observed zone seeds older assignment context, explicitly an
  assignment convention rather than historical evidence. No dependency change.
  Claude integration needed: change the one shared `home_screen.dart:clockOfTs` implementation
  to `DayClock.localAt(ts.round())` so all times use the persisted zone; date formatting for
  chart instants should use `dayLabelAtSec`, while calendar-only arithmetic keeps `dayLabelOf`.
  Other Claude-owned headers can use `DayClock.abbreviation(date, nowSec: ...)`; shared detail
  navigation and Recovery already show differing zones. Sleep/Recovery display fixes continue
  in task 5. Claude owns the stale top-level planned-status wording and documentation indexes.
  Task 4 is committed as `07fff90d`. Task 5 data/compute is implemented: per-record RR-count
  provenance and omitted-share quality (no new HRV gate), explicit re-anchor metadata and
  90% spectral coverage for HF/respiration/REM, arm-angle restlessness, a single five-minute
  awakening function, quarter-gap sleep need without strain bonus, absent unavailable cycles,
  and recording-gap lower-bound wording. Eight beat-quality and seven accounting tests pass;
  three selected Sleep widget checks also pass (gap wording, 2x and 3.1x layout).
  Existing sleep-need clamps were retained; their
  outstanding source review remains research work for Claude. A1 method review for Claude:
  the quality estimate uses the documented HR/60 versus retained RR count, with denominators;
  confirm this definition since the local-measurement paragraph supersedes recommendations
  (b)-(c) without stating a replacement formula. This field does not gate any headline.
  No strain formula change.
  Task 5 is committed as `c03421f5`. Task 6 implementation uses bodyweight 3.0 MET,
  labels functional as an estimate, qualifies ACSM by measured moving speed and retains
  out-of-domain/unknown-speed values under Movement estimate. Shorter-than-six-week
  food/weight displays include the 4,858–7,700 conversion envelope without changing the
  trend/gates or feeding advice. Run/walk remain in maintenance; lifting remains separate.
  Akshat assigned `activity/summary.dart`, `activity/run_detail.dart` and `day_steps.dart`
  to Codex. Task 6 is committed as `7b442912`. Food quick weigh-in delegates to BodyLogDb and uses its canonical daily weight
  for the profile; first-reading persistence still depends on Claude's Body implementation.
  Resting HR labels name the lowest 30-minute average while asleep on all three owned details.
  Claude integration needed: in `workout_screen.dart`'s LiveFeed constructor, keep
  `acsmCalories: app.workoutAcsmKcal` and add
  `movementEstimateCalories: app.workoutMovementEstimateKcal` so unsupported speeds retain
  the explicitly labelled comparison. Also pass
  `currentSpeedAccuracyMps: app.routeTracker?.freshSpeedAccuracyMps(DateTime.now().millisecondsSinceEpoch)`
  beside its existing freshSpeedMps call. Live speed now requires this provenance and shows
  the latest GPS speed uncertainty (including at large values) rather than hiding it behind
  a position-derived fallback. Task 7 implements per-wake ids/stage timing and per-burst counts/timestamp continuity.
  Four existing Build 88 speed checks and five focused diagnostics/speed tests pass, including interrupted wake cleanup, invalid
  speed despite valid position fixes, retained large uncertainty and its live-screen label.
  The existing T11 commit-before-ACK ordering regression also passes. Outdoor/overnight
  phone measurements and Claude's two live-feed fields remain required. New EnergyComparison gallery entries are confined
  to the marked Codex lane block. Nine focused energy checks pass, including 1x/2x/3.1x
  layouts; two selected Build 73 dated-weight/restore regressions pass. Native iPhone
  appearance and the merged first-reading ledger test still need Claude CI/phone verification.
  Task 7 is committed as `96238e62`. Task 8 Food/export source now freezes the first
  known profile goal per closed date (including confirmed absence), passes immutable counting
  evidence through existing entry/rollup reads, keeps manual marks distinct, and preserves
  separate eaten/logged timestamps. Seven synthetic counting tests pass, including a read
  before profile hydration. Analysis includes all historical weigh-ins/provenance, shared
  lift best-set rules and nutrient-specific partial totals/denominators; rendering runs off
  the UI isolate. Ten focused export tests and four existing export regressions pass;
  five schema checks pass, including actual encrypted backup/restore and legacy import. Generated export copies are removed after
  share completion/cancellation/failure; result copy distinguishes unconfirmed delivery.
  Backup descriptions distinguish database references from actual photo files, restore
  support and in-container loss. Native share/restore and Food phone acceptance remain open.
  Akshat assigned `log_workout.dart`, `coach_actions.dart` and `auto_workout_import.dart`
  to Codex. The auto-import file needs no session-contract change: Health imports write
  separate `imported_workouts`, not `sessions`.
  Food data/exports are committed as `b1b6d786`. Task 9 is committed as `6b182095` and implemented with a compact calorie
  summary, four macro columns (protein larger), readable stacked large-text values, a
  week-state legend, direct Food Progress routing and no repeated singleton totals.
  Copy day selects a source, reviews each item/portion/selection and commits only on Log.
  Seven focused Food checks pass, including cancel/no-write, transaction rollback and
  the full copy/portion/selection flow at 1x/2x/3.1x;
  three actual Food phone-size render checks pass at 1x/2x/3.1x and normal text exposes the
  first meal. The confirmed large-text week stays in one horizontal row and Log again
  actions use full labels without a fixed-height clipping box.
  Claude shared-UI issue: `app_shell.dart` bottom-tab labels split words at 2x/3.1x
  (Today, Trends, Train, Progress). Screenshots are local synthetic captures under
  `build/ui_capture/b90_codex_food_*.png`; this needs the Claude lane's tab-bar fix.
  The targeted unknown-intake render regression also passes.
  Session refresh/history optimization is committed as `c7c37ed0`. Owned session paths
  now publish after successful writes: live start/stop/orphan recovery,
  repository start/end/privacy, substrate score/movement enrichment and deferred HRR,
  CSV/database/Lift imports, reset and detail RPE/type/delete/context edits. Two durability
  checks cover failed-save abstention and successful retry/repository signals. Manual
  logging, retiming, suggestion confirmation and coach logging now share the post-commit
  notification in `_writeManualSession`; the form no longer emits its own duplicate refresh.
  Suggestion-only dismissals refresh insights only after their write succeeds. Two focused
  manual/retime/coach checks pass, covering successful publication and write-failure abstention;
  all 11 existing manual-entry/suggestion-review widget and date checks also pass.
  Claude integration: do not publish again when LogWorkout returns from a successful manual
  save or retime; the repository already did. Keep the Train delete/edit signals for its other
  direct database mutations.
  Task 10 tools are committed as `35c34f93`: `tool/strain_comparison.dart` and the read-only runner
  `tool/strain_measurement.dart` using the app's TRIMP/coverage/strain functions,
  the fixed shipped quiet reference and the existing session floor. Both synthetic checks pass,
  including a complete read-only export read (sleep envelope, source exclusion, coverage and
  unchanged input-file metadata); the private case is skipped without an input path. Set
  `WHOOP_MEASUREMENT_DB` locally and run only `test/build90_strain_measurement_test.dart`
  to perform it; output is fixed under ignored `build/research-local/`. Set
  `WHOOP_SYNTHETIC_PROFILE=1` for `test/build90_history_profile_test.dart`. Akshat restored
  an export and the targeted private read-only run now passes. File length and modification
  time are unchanged after the read. The comparison and local review stay only in ignored
  `build/research-local/strain-comparison.json` and `strain-comparison-review.md`; no private
  values or dates are copied here. The strain formula is unchanged.
  D1 research discrepancy resolved: the shipped code uses the fixed `quietWakingHrr` 0.20 at
  every call site (the personal level is not wired in), and `build-90-research.md` now says so.
  The baseline level is a separate approval-gated choice from the whole-day/per-minute form.
  A1's quality method (HR/60 expected versus retained count) and the sleep-need clamps are
  confirmed there too. No invented quiet-day labels: a date without
  a recorded workout is only a quiet candidate, and pruned raw cannot reproduce a full day.
  Synthetic 3-/10-year actual-reader profiling found the Steps chart's per-date measured lookup
  as the dominant Progress cost. Food month/day and session readers did not justify caps.
  A shared batched coverage resolver replaces the historical per-date query loop, preserves
  every retained point, confirmed zero and multi-day coverage, and uses stored travel/DST cuts.
  Two step-history equivalence checks pass (old series, measured zero, multi-day spans and
  stored DST cuts), as does the existing legacy zero-width coverage reader regression. Post-change ten-year Progress reads were 0.38–0.42 s versus 1.4–1.7 s before
  on this Windows FFI probe; with daily phone coverage they were 0.64 s. These are synthetic
  desktop timings, not phone acceptance. Food's existing six Build-89 regressions also pass.
  Query and timing reports stay in ignored `build/research-local/`; merged Progress needs recheck.
  Assigned Codex implementation and measurement work is complete; merged cloud checks and
  phone acceptance are still open. Recommendation: keep the shipped whole-day form and the
  corrected session floor. No-recorded-workout dates are only quiet candidates; confirm labels
  and usable coverage locally before choosing a replacement, then obtain Akshat's approval.
  The single algorithm-95 changelog includes the approved output changes. The restored-export
  check is measurement only. A complete copy/paste Claude handoff is local at
  `build/research-local/claude-build-90-handoff.md`.

## Build 89 (`0.9.56`/`89`): Installed, Testing And Acceptance Open

**State:** Akshat's screenshots show Build 88 installed: the night's HRV curve drew, but the
nightly HRV read "Not measured" and Recovery scored without it. His exported database (read
locally only, nothing committed) showed why: WHOOP 4 `beat_ts_ms` is the 1 Hz record's
sub-second phase, the same for every record, so successive beats read about 1000 or 2000 ms apart
whatever their interval. The Build 88 250 ms adjacency rule rejected most successive pairs: on 13
real nights the nightly HRV was absent on 6 and biased low on the other 7. At 1000 ms (one record)
all 13 qualify and agree closely with algorithm 91. Published as source `77d6a365`
(algorithm 93); Linux CI `38494407678` (3,719 tests, 427 intentional skips) and personal macOS
build `38495939393` pass, and the validated IPA is the single candidate in `final-ipas/whoop/testing/WHOOP-0.9.56-build89-77d6a365`
(`setup.md`). Akshat reports it installed and is testing it. The requested recovery promotion
follows the whole-app audit; Build 70 remains cached recovery in the meantime.

- [x] One shared beat-adjacency tolerance, `kBeatAdjacencyTolMs` = 1000 ms (analytics
  `util.dart`), for the nightly HRV, every rolling curve, PRSA, the irregular-rhythm screen and
  the `correctRr` re-anchor; regression tests rebuild record-stamped timing and fail at 250 ms.
- [x] `kAlgoVersion` 93: retained nights re-derive with the repaired rule.
- [x] Nothing the app shows or names says OpenStrap: app name, messages, permission prompts and
  every translation say WHOOP; exports are `whoop_export_*.db`, `whoop_days_*.db` and
  `whoop_csv/whoop_*.csv`; automatic backups go to `WHOOP Backups` as `whoop-*.osbk` (the old
  `OpenStrap Backups` folder is renamed once and its `openstrap-*` files stay recognised for
  retention and restore); logs are `whoop_sync.log`, `whoop_native.log` and `whoop_exits.log`
  (the old files are renamed once). Internal identifiers stay: the database file, Bluetooth
  restore identifier, background-task and channel names, package names, the Open Food Facts user
  agent and the upstream licence attribution.
- [x] Steps are phone only (Akshat: the wrist count is inaccurate): one switch, `kBandSteps`
  (off in the personal build), keeps band rows out of the day total, hourly graph, step calories,
  workouts and runs and stops the on-chip fallback; band rows stay stored. Time or a day the phone
  did not measure has no steps ("—"). Retained days re-derive under algorithm 93.
- [x] Live band streams are heart rate only (Akshat, Build 89): `kHighRateLive` off arms just
  the 1 Hz stream in the foreground and background; the 100 Hz motion, raw beat records and
  optical flood are never requested (their only readers — wrist steps, wrist cadence fallback,
  inactivity nudge, spot checks, paced breathing — are off or removed). Live HR, zones, wear and
  workouts are unchanged; the upstream build keeps the full set.
- [ ] Phone: live heart rate on Today and in a workout still updates; overnight history syncs;
  battery compared with Build 88.
- [ ] Phone: the Build 89 additions below — a finished workout with valid strain counts toward
  the day's strain (no forced number without qualified inputs), Food's week
  strip/calendar/calorie card, automatic counting and its actions, the 9:30 pm question and its
  buttons, the Labels bin, the Pushups card, Today chart scrubbing and the AI export file
  (`build-90-audit.md` "Build 89-specific phone pass").
- [ ] Phone: after install, the nightly HRV shows on recent nights (or its reason shows); text
  reads without strain on every tab; Files → WHOOP shows
  `WHOOP Backups` and the `whoop_*` logs with no OpenStrap-named file.
- [x] A missing nightly HRV says why (Akshat asked): on its Readiness row and on the HRV screen's
  empty Today card ("Too few clean beats: 5 of the 13 five-minute stretches it needs were
  clean", "No sleep was found last night…", "…too noisy…"), from the stored note (`hrvWhy`).
- [x] Legibility (Akshat: the thin gold food number and other text strained his eyes): hero
  numbers semibold in their contrast-solved ink, labels 12.5 pt semibold, body/caption and
  Material text medium weight; rendered screens checked.
- [x] Publication, CI/macOS build and testing IPA (Akshat's go-ahead after the items below).

### Build 89 additions requested on the installed Build 88 (approved, implemented in source)

Implemented, each with tests: P1-P6 as proposed (one period selector — Week · Month · 3 months
· Start, More for the rest — driving every card through `progressPeriod`; the answer card first;
one Body card with chips, chart, entries, add/settings and photos; Strength on the page's own
comparison; Goal in its own card); Pushups in its own panel with a Start pill; the Food card per
Akshat's reference (eaten / goal with left or over beside it, a striped-past-goal `GoalBar`, the
same on macro bars), the date above the title opening a month calendar and a Monday week strip
marking counted/logged/empty days; automatic day counting at half the goal plus the optional
9:30 pm question (`FoodDayReminder`, toggle in Food's targets); the label bin; Settings → Your
data → Export for AI analysis (`analysis_export.dart`); scrubbable Today heart-rate windows; and
the day strain floor (finished workouts' net TRIMP). Not phone-verified.

Akshat's decisions: item 4 option B (automatic counting plus an optional evening reminder);
item 6 the recommended Markdown file with food items up to 3 months; item 3 lead with calories
left; item 1 one period selector for the whole page.

No feature is removed by any item; every current number, chart and entry point stays reachable.

1. **Progress tab, end-to-end rework (P1-P6).** Audit of today's page, top to bottom: review
   tabs (Week/Month/Since start) with a hero and a verdict; a goal card with loose `+` and
   settings icons beside it; Measurement and Range drop-downs; the body chart with
   Start/Latest/Change/Total/Average; Strength; Food averages; Activity and recovery; weight
   Entries; Photos. What makes it hard to follow:
   - two independent time controls (review tabs and the Range drop-down) that silently disagree:
     the same page shows protein "162 g · 6 complete days" in the review and "162 g · 50 complete
     days" lower down, for different periods;
   - weight, waist, lifts, protein and calories appear twice, once per control;
   - the controls sit far from what they change (the Measurement drop-down above the chart, the
     add/settings icons beside the goal, Entries detached from its chart by three sections);
   - the verdict is a sentence of evidence rules rather than an answer, and the goal it is judged
     against sits in the middle of the page.
   Proposal:
   - P1 one period selector for the whole page (Week · Month · 3 months · Since start, with
     2 months/6 months/1 year/All under "More"); every section reads it, and each "before vs
     now" comparison is against the previous period of the same length;
   - P2 an answer card first: goal, a one-line answer (on track / not yet clear / off track),
     and what would settle it ("log your waist this week"), with the evidence rules one tap
     away;
   - P3 one Body card: metric chips (Weight, Waist, the other sites, Steps) inside the card
     above its chart, Start/Latest/Change below it, a collapsible list of entries, and
     "+ Add entry" and Photos inside the same card;
   - P4 Strength, Food and Activity & recovery as three consistently laid-out cards (label,
     number, what it covers) for the selected period, without repeating the answer card;
   - P5 goal details, measurement day and body settings together at the end;
   - P6 every period stated in plain words ("this week vs last week"), not raw date pairs.
2. **Pushups on Train.** Give the row its own paper card like the panels around it, with a clear
   Start button instead of grey text on the kraft.
3. **Food main card.** Lead with what is left: "850 left" as the hero (or "120 over" in the alert
   colour), a full-width bar of eaten against goal under it, and "1,450 eaten · goal 2,300"
   beside it; the maintenance line and the macro rows stay.
4. **Counting a food day without marking it every day (needs Akshat's decision).** Today a past
   day counts toward averages only when marked complete (D13, Build 88), so a forgotten mark drops
   a real day. Options:
   - A (recommended): a past day counts automatically once it looks finished — energy on every
     item and at least half of that day's calorie goal — and shows "counted automatically · mark
     as missing food" to exclude it; days below that stay out, with a one-tap "Count this day"
     in History. Marking stays available and always wins.
   - B: A plus an optional evening reminder ("Is today's food complete?") with one-tap actions.
   - C: every past day with food counts unless marked incomplete (simplest; a forgotten dinner
     then lowers averages and the food/weight maintenance estimate).
5. **Labels.** A bin icon to the left of each label's pencil in Manage labels; it asks "Remove
   'Protein' from 3 foods?" and removes the label only — the foods stay. Clearing the name keeps
   working.
6. **Export for AI analysis (needs Akshat's confirmation of shape).** Settings → Your data →
   "Export for AI analysis", made on demand and shared through the share sheet, so it takes no
   lasting storage (the temporary file is deleted after sharing). Recommended shape: one Markdown
   file with
   - a short header: what each column means, that "—" is not measured (never zero), which numbers
     are estimates, the goal, profile basics, and a suggested prompt;
   - range: 2 weeks, 1 month, 3 months, 6 months or Lifetime;
   - one row per day: weight, waist, calories, protein, carbs, fat, fibre, whether the day counted,
     steps, sleep, recovery, HRV, resting HR, strain, workouts;
   - weekly averages for the same columns, so Lifetime shows trends at a glance;
   - lift sessions (exercise, sets, top set, estimated 1RM) and body measurements;
   - individual food items only for ranges up to 3 months: they are most of the size and add
     little beyond a few months.
   Size: about 0.25 KB a day for the daily row; with food items about 1 KB a day. A lifetime file
   for a year without items is about 100 KB (roughly 30,000 tokens), which an AI chat reads
   comfortably.
7. **Today heart-rate chart.** Make 10 min, 1 hour and Day scrubbable with a finger (time and
   bpm under the finger), using the same chart as the full heart-rate screen; today all three are
   plain drawings with no touch handling.
8. **Found while auditing: Train's week panel Strain read 0.0 on a day with a 3.4-strain walk**
   (Akshat's screenshot); the same panel's own line says "strain 3.4 in total". Find why the
   day's strain line and the session total disagree and fix the source, not the label.

## Build 88 (`0.9.55`/`88`): Previously Installed, Superseded By 89

**State:** Akshat approved `build-88-proposal.md` with every recommendation (C1 note-only, C2
"—", C3 off, C4-C8 yes, C10 built-in review) and asked for one combined Build 88. All twelve
packages are implemented (algorithm 92) and published as source `0f48c56f`; Linux CI
`38329137774` (3,703 tests, 415 intentional skips) and personal macOS build `38329490196` pass,
and the downloaded IPA passes source/version, checksum, ZIP and payload checks. It is the single
candidate until Build 89 replaced its testing folder; `setup.md` owns the artifact evidence. `build-88-plan.md` owns the specifications, `bugs.md` what each repair closed and what is
still open, and `DESIGN.md` the locked visual system. Local full suite: 3,698 tests pass (420 intentional skips). Build 88 was installed and is now superseded by Build 89; complete phone verification remains open.

Done in source (each with tests):
- [x] **B88-01** temperature integrity: WHOOP 4 counts never publish temperature or feed
  anomaly/illness/glass box; Trends/Sleep/rough-night rows hidden; history kept.
- [x] **B88-02** load: net TRIMP over observed-day runs; strain target withheld (D3); one zone
  set for minutes and label; strain-dependent need and mover count observed days only.
- [x] **B88-03** HRV: timestamp-adjacent pairs and frozen window/night gates everywhere
  (headline, timeline, 24/7, daytime, PRSA, irregular rhythm); `ln_rmssd_v2` baseline; RSA/BRV/
  stress qualification; one HRR tau; label fixes.
- [x] **B88-04** sleep: relative stillness gate, Phillips SRI, night-time fallback, correction
  save blocked under 50%, Home bar on last night's need, "In bed at".
- [x] **B88-05** sync: no prior night as today; ownership wait capped at 20 s with a headless
  stop; BG expiry stops the drain; off-wrist link cap; frontier and burst evidence; background
  log lines; live speed over time, stop detection, "—" without a fresh fix (D5), moving-time pace.
- [x] **B88-06** energy and food: low-HR lifts, DST BMR, lift caps/overlap, partial-run steps,
  explicit completion (D13), "at least" totals, day-state calorie card, robust food/weight range.
- [x] **B88-07/08** strength and advice: one comparator with "not comparable"; recomposition
  needs waist and a comparable lift; protein from 5 complete days; floor and no-goal rules; Navy
  male-only and dated (D7); dated waist/tape windows; Monday weeks.
- [x] **B88-11** alerts: composite low readiness, quiet hours for every health finding (D4),
  one-sided anomaly, RHR-shift gap restart, import filters, bounded baselines.
- [x] **B88-12** C4 quality lines, C5 Status sync-health panel, C6 tape prompts/second reading
  (weigh-in time already stored), C7 range, C8 per-kind alert switches.
- [x] **B88-09** redesign: light kraft ground with cream 26 pt panels, family colours, hero
  number, paper tab bar and segmented control (all screens through the shared tokens); Today and
  Trends rebuilt to the locked mocks (tiles, 7-day bars, 30-day line plus average, 3-month weekly
  band, hatched gaps, NEW and amber absence); Flutter iPhone-size captures reviewed against the
  mocks (built-in degraded review, C10).
- [x] **B88-10** one `kAlgoVersion` bump to 92 with its changelog; retained days re-derive and
  the new HRV baseline never mixes in old-method nights.

Decided by Akshat ("take your call") and done in source:
- [x] Per-night CVHR chart removed from the breathing screen; the across-nights card stays
  (one night of pulse cycling means little; overnight HR stays on the Sleep lanes).
- [x] Strain: TRIMP uses the zones' max HR (observed ceiling once it reaches the age estimate,
  else the estimate) and weights each minute by the time it recorded (TRIMP is a time
  integral); the quiet baseline subtracts over the same covered minutes.
- [x] Fatigue keeps the 28-observed-day floor: its only reader compares it with fitness, which
  needs 28, so fatigue alone at 7 days would have no use.
- [x] Food colour darkened to `#A8730A` (3.46:1 on paper); secondary inks darkened to 6.1:1 and
  5.6:1 on the kraft; sleep stages re-toned (navy, steel blue, plum, clay), each 4.5:1+ on paper.
- [x] Food, Train, Progress, Sleep, Recovery and live run rebuilt to their mocks (hero number,
  label/chart/value lines, one panel per screen part) and visually checked at 1x, 2x, 3.1x and
  320 pt for blending text and overflow.

Open:
- [x] Beat-adjacency qualification on real nights: failed on the installed build (HRV
  absent on 6 of 13 nights); repaired in Build 89 above.
- [ ] **At install (Akshat asked to be reminded):** the live-speed constants on an outdoor walk
  and run, then the full lifecycle/background/soak matrix.
- [ ] **Prerequisites:** keep the installed app signed past 2026-10-17; take an encrypted
  off-phone backup before any Build 88 install.
- [x] Publication, CI/macOS build and testing IPA (Akshat asked for them).
- [ ] Verify Codex first-use hook trust (advisory tooling, not an app blocker).

**Not bundled:** personal quiet-HRR substitution, different recovery weights, Kalman smoothing, a
replacement TDEE anchor, ML/Cole-Kripke staging, the chest-strap kit (C9) and the raw optical
tail (C3 off). Accuracy gains remain unproven until reference evaluation.

## Build 87 (`0.9.54`/`87`): built, never installed, superseded by Build 88

**State:** Akshat requested an audit of installed Build 86 and a genuinely different,
user-friendly Build 87 without losing required features/data. `build-87-ui-plan.md` owns the
source/screenshot findings, detailed compositions, feature-preservation routes and acceptance
criteria. Akshat approved implementation of the full UI and queued sync scope. Local source,
full regression checks and real-height previews pass, including approved shortcuts, protein summaries and log-driven sync repairs. Published source `b0eee377` passes Linux CI `38156660026` (3,616 tests, 399 intentional skips) and personal macOS build `38156663594`. Downloaded source/version/checksum/ZIP/payload checks passed; it was never installed and Build 88 replaced its testing folder. `setup.md` owns the artifact evidence.
Physical background and structural design acceptance remain open.

- [x] Audit the 13 supplied phone screens against the five-tab UI and related source/data paths.
  Static findings are not a completed interactive/physical-device audit.
- [x] Document structural replacements for Today, Trends, Food, Train, Progress and live/detail
  flows, retaining every currently reachable unique metric and entry point.
- [x] Produce actual-height, real-shell populated/new-user/failed-family previews and core
  Walk/Lift/summary/body/photo flow renders with synthetic data.
- [ ] Obtain Akshat's approval of hierarchy and flows, not just colours; complete the phone
  Food add/edit, keyboard, accessibility and active-session return walkthrough.
- [x] Repair Progress's compressed date axis, mismatched long-history coverage,
  hidden partial-review evidence, incomplete workout breakdown and ambiguous period/read states.
  Weekly-block changes name their real earlier block; future readings/measurements stay out of
  current context, and separately dated neck inputs are identified on estimates.
  Clarify profile-only weight and diary versus macro completeness. Keep existing safety gates.
- [x] Implement flat/task-specific compositions, stable controls and concise copy, including the
  peaceful warm-graphite direction with richer emerald/turquoise/coral accents. Akshat rejected
  the initially muted colours as dull; palette acceptance remains open. Main metrics,
  all five tabs and existing entry/detail routes remain; large-text/first-viewport/source QA runs
  locally. Physical keyboard/VoiceOver/gestures and final design acceptance remain open.
- [x] Implement separately tested exact-input pure-calculation reuse (process-local, three-day
  bound, force/version invalidation, no cancelled worker publication) and current-link WRIST_OFF
  silence recovery (`background-sync-plan.md`, `bugs.md`). No formula, step ownership, durability
  or scheduling guarantee changes. CPU/freshness and off-wrist phone checks remain open.
- [x] Final local regression: 3,611 passed, 404 intentional skips; personal-profile layout/data/
  sync/token/contrast suite: 310 passed, plus two focused final checks for button contrast and
  the latest custom-date repair. Analysis: no errors/warnings, 133 informational lints;
  personal-iOS contracts (9), profile, package-pin guard and `git diff --check` pass.
- [x] Obtain Build 87-specific publication/CI/macOS/testing-IPA approval.
- [x] Publish reviewed source, pass CI/macOS compilation and validate/cache the testing IPA.
- [ ] Install Build 87 over the existing signed identity; verify data/pairing continuity and
  current-version refresh enrollment. Do not delete the app or promote the cache on installation alone.
- [ ] Complete real gym/background/soak tests before candidate acceptance.
  Installation/CI alone cannot pass structural design acceptance.

No feature removals, relaxed intake/signal gates, new permissions/network services, AkshatOS
cutover or signing-identity/recovery changes are selected. Build 86 and uninstalled Build 87 are superseded; installed Build 89 occupies testing pending promotion, and Build 70 remains cached recovery.

**Approved convenience additions, implemented and locally verified:**
- [x] Today HR 10-minute / 1-hour / Day views from actual recorded timestamps, preserving the
  full-day trace, gaps and freshness labels.
- [x] Direct portion editing from a Food diary row through the existing amount/save path;
  retain meal/group controls, missing-definition fallback and destructive confirmations.
- [x] Activity/date filters in All workouts, with clear reset and complete All/history access;
  filters must not alter saved data, streaks or calculation totals.
- [x] Repair Status/Today band-data age to use the advancing durable record frontier, not the
  launch-only sample. Distinguish queued from running calculation; read recent HR before derive.
- [x] Prime the bounded adapter-state read before cold connect and stop burst continuation when
  no new history records arrive, despite earlier cumulative connection totals. Preserve ACK order.
- [x] Show protein beside calories in diary meal/group totals, copy summaries and saved-meal
  rows, qualifying partial/missing nutrition without imputing zero. Shared historical date headers
  wrap at large text; primary action fills retain accent saturation with contrast-checked labels.
- [x] Read Today's served result and committed calculation time together, even if the later
  derive pass is cancelled before its aggregate freshness refresh.
- [x] Finish regression/render/static checks for the added shortcuts, protein and sync repairs.

`build-87-ui-plan.md` owns the boundaries. Akshat explicitly approved all three. Extended
regression and actual-height shortcut previews pass; phone verification remains required. Existing tab reselect-to-top and Status/freshness shortcuts are already present.

## Build 86: Previously Installed, Acceptance Gates Carried To 89

**State:** Akshat approved implementation of the whole build-86 scope below as **one build**.
Selected extras: repeat last set, rest timer, comparable records and independent photo
comparisons, plus start/end times, historical body/photo entry, measurement/range controls and a
screenshot-based MyFitnessPal import. The scope also covers weekly/monthly diet/body/strength
insights, navigation/speed/sleep/freshness repairs, safe deletion, custom food labels, both-way
serving equivalents, maintenance-based calorie warnings, general activity/rest protection and a
structural UI redesign. `build-86-audit.md` owns confirmed findings, additional risks and tests.
The confirmed fitness goal is recomposition: leaner while getting stronger. Build 86 was installed as confirmed by Akshat; Build 89 is now installed and its inherited phone gates remain open. Sideloadly records version `0.9.53`, completed
current-version automatic-refresh enrollment, no error, and expiry 2026-10-17 at 17:51 local.
This is installer evidence, not proof of a future unattended renewal or SideStore adoption.

**Akshat's decisions:**
- One build, not split releases.
- Imported or backdated past weights never change past calorie numbers: they are history-only
  and do not feed `ProfileHistory.on`, maintenance or workout pricing.
- SideStore pilot approved (section 10), with LocalDevVPN allowed on the phone as its installer
  helper.
- Open choices take the recommendations written in each section unless Akshat overrides them:
  personal `fetch`/`processing` modes added with bounded work; set logging for every existing
  lift type with tracking-only kept; ordinary Finish ends now and a forgotten-finish reminder opens
  a Now / Last set review; AkshatOS stays intact; Monday-Sunday closed-week reviews with Body's
  measurement weekday kept for its own blocks; same-day weight conflicts need explicit review.

**Implemented in source (`0.9.53`/`86`):** sections 1–9 below, the B86-01..16 repairs, the
Progress tab, and the additions Akshat asked for after the plan (listed below); checklist items
carry `[x]` when done in source and a note when partly done. A first build-86 push (`70adc902`,
Akshat's approval) passed Linux CI `38065480698` and personal macOS build `38065492927`; that IPA
was **held, not downloaded or installed**, because the structural redesign had been left out.
Everything since is committed on `main`; local validation: full suite 3,534 passed, 404
intentional skips, 0 failed; analysis has no errors or warnings; personal-iOS contract tests and
`personal_ios.py check` pass. Akshat reviewed the installed redesign and rejected its cosmetic-only
composition and Progress copy; the built replacement is in the Build 87 section above.
The Swift changes (Home region bridge, notification registrant and
delegate) compile only on the macOS CI. Private MyFitnessPal import generated and validated
locally (`../../health/fitness/data/whoop-body-history-import.json`).

**Moved to build 87 (Akshat's decision):** per-input calculation reuse in the background sync
(section 1), so build 86 can serve as the fallback if that change breaks sync.
Implemented in the Build 87 testing IPA: do not bounce the Bluetooth link for silence while its current-
connection wear evidence is `WRIST_OFF` (`bugs.md`, night of 9–10 Oct: 23 needless reconnects).

**Next gates:** publication, artifact validation and installation are complete; current-version
Sideloadly enrollment is corroborated. Confirm that a rollback-readable export was taken before
86 (format-2 exports are not readable by 85/70), then complete the phone checks below and phone
acceptance. Build 70 remains accepted recovery; do not promote 86 from installation alone.

**Phone checks after installing 86** (they cannot be tested on Windows):
- Back gesture: a left-edge swipe goes back on every pushed screen without fighting the Food day
  swipe or swipe-to-delete rows.
- Saved state: changing tabs keeps each tab's scroll position, Food's day and the Foods filter.
- A real gym session: log sets with the phone locked between them; check the vs-last-time line,
  Progress sheet, rest-timer and forgotten-workout notifications.
- Pushups: Start my day, a reminder and nudge on the lock screen, Done and Pause there without
  opening the app, then the app shows them once; Home auto-pause leaving and returning.
- A normal day of two-to-three-minute visits: Today fresh on open, band-data age honest.
- One Body entry with a photo, an encrypted export and a restore test.

Also in build-86 source, at Akshat's request (after the plan):
- **Pushups inside WHOOP** (section 7) with Home auto-pause; Akshat approved Always location.
- **Strength progress inside the live workout:** each exercise shows ahead/level/behind last
  time set by set as you log, the set to beat next, and a Progress sheet (best set per session as
  an estimated one-rep load on the same setup — ranking only, never a true max — sessions,
  heaviest load at each rep count, and a trend line that names a three-session stall).
  `lib/data/lift_progress.dart`.
- **Flexible goals:** the goal is chosen in Progress → Goal (Lose fat with a pace, Recomposition,
  Keep it off, Build muscle by training age, Get stronger at this weight), and the review judges
  the last two closed weeks against its weekly band and protein range; it suggests a 100–250 kcal
  change only with enough data, never below resting energy, never applied. `lib/data/goal_plan.dart`;
  `fitness-goal-research.md` owns the evidence.
- **Selected conveniences:** Jump to Today on every day stepper; Return to workout (the existing
  live-session bar on every tab, plus Today's plan row); the Syncing/Calculating/band-data line
  opens Status; Food days can be marked complete or incomplete by hand; Today's Body row says
  Measurement day and offers Measure; the measurement-day reminder's weekday and morning hour are
  chosen in Body settings.
- **Redesign, second pass:** warm stone palette and page light, Today's recovery hero with sleep
  and strain under it, a Today card of what the day still asks (steps, food, weigh-in/tape,
  Pushups, Resume/Start training), Food's Log again row, Train's Your week hero.
- Every search field (Foods, the food log, the saved-meal picker, the activity picker and the Lift
  exercise search) has a × that clears it in one tap, shown only while it holds text
  (`OsTextField.clearable`).
- Fibre is never left off: every compact macro line (meal cards, the meal page, the log-food list,
  pickers, Food history) prints `P · C · F · Fb` once any macro was logged, and a missing one reads
  `–` (`macroParts` in `food_picker.dart`). The day card's four totals do the same.

### 1. Background sync and fresh insights during brief daily use

**Implemented in build 86; physical acceptance open.** Target: Akshat's iPhone 17 /
iOS `26.6.2`, with only two or three minutes of app viewing per day. Keeping WHOOP visible,
continually refreshing or charging all day must not be required. The supplied gap's force-quit
state is unknown. `background-sync-plan.md` owns the public Apple sources, source findings,
capability boundaries, safety invariants and detailed acceptance checks.

Implementation checklist:
- [x] Resolve native lifecycle before scheduler/bootstrap work and guard every foreground-session
   entry. Coordinate queued native wakes with AppState so startup has one band owner.
- [ ] Cancel actual in-flight calculation on ordinary backgrounding; preserve committed results
   and requeue unfinished work without pruning, finalizing or marking cancellation successful.
   *The detached-pass cancellation and lock-refusal source gaps found in Build 87 were repaired
   by Build 88 B88-05 and carried into Build 89. This remaining checkbox is phone cancellation/
   requeue acceptance, not an unimplemented source repair; see `bugs.md`.*
- [ ] Keep short BLE wakes transfer/commit/ACK-first. Replace the fallback's unconditional full
   light derive with queued calculation; propagate expiration, retire old workers and bound
   ownership handoffs without overlapping ACKs or orphaned work. *Build 88 B88-05 repaired the
   unbounded foreground wait and headless-drain expiry gaps; Build 89 retains those repairs.
   Actual short-wake scheduling and ownership/expiry behaviour still need the phone pass.*
- [x] Superseded by Akshat's Build 89 decision: steps are phone only and the personal build arms
   only the 1 Hz heart-rate stream (`kHighRateLive` off), so there is no passive wrist-step or
   high-rate path left to preserve or profile. Active workouts keep live heart rate and zones.
- [ ] Reuse unaffected calculation, prioritize today/new sleep, and keep raw-data freshness
   separate from the input revision covered by an insight. Short-wake compute must be measured
   and genuinely bounded; the current one-day "light" pass does not meet that contract. *Source: today is derived first, BLE wakes queue work, and Today shows band-data age apart from the calculation time; per-input reuse ships in the validated Build 87 testing IPA; cold preparation/staging and short-wake CPU still need measurement on the phone.*
- [ ] Make cold foreground open/resume automatically coalesce catch-up, durable input publication
   and bounded recent-HR/today refresh. The latest ten minutes of recorded HR must not depend on
   pull-to-refresh or a whole historical derive; preserve gaps and separate Live from Recorded.
   Distinguish syncing/calculating from truly not recorded, with honest input age. *Source: recent recorded HR on open and per-commit revisions; on-phone timing still to verify.*
- [x] After capability approval, enable bounded `BGAppRefreshTask` and opportunistic `BGProcessingTask` in the
   personal flavor, with freshness work eligible without charging and expensive backlog work
   using charging as an extra opportunity. Repair expiration/single-completion/ownership first,
   then synchronize native/Dart registration, modes, payload transformation/validator and tests.
   These supplement BLE and foreground catch-up; Apple provides no fixed execution schedule.
- [ ] Add local native restoration/expiration and launch/build diagnostics, then verify ordinary
   locked two-hour/overnight use, brief visits, termination/range recovery and a 72-hour soak. *Source: native breadcrumbs in whoop_native.log; device verification open.*

Decided: implement the repair and add personal `fetch`/`processing` modes with bounded work.
No extension, App Group, HealthKit, cloud service or feature removal. If preserved wrist capture
itself still exceeds the measured budget, present the phone-absent step tradeoff for a separate
decision before changing its policy.

### 2. Lift Log inside the existing WHOOP workout

**Implemented in build 86; physical acceptance open.** Akshat wants
to explore one workout that behaves as WHOOP does now and also offers AkshatOS Lift Log's
features. `lift-log-integration-plan.md` owns the current-source findings, recommended flow,
parity inventory, timing conflicts, data import/recovery and tests. AkshatOS remains unchanged
until a separately approved transition; `../akshatos/hub-plan.md` records that boundary.

Accepted direction: choose a split or Empty workout in Lift setup, then use one WHOOP session ID,
clock, Pause/Finish and summary, with exercises/sets and previous performance inside the live
workout. Tracking without set logging remains possible; runs/walks retain their flow. Reuse the
existing Flutter strength/session foundation, but do not merely enable the old sets UI: it lacks
Lift Log's split/load-mode contract, and its row replacement does not delete omitted sets.

Implemented scope and remaining verification:
- [x] Preserve Lift Log's editable/flexible splits, all six load meanings and pounds, set edit/
  delete/Undo, complete same-mode previous performance, search/order/skips, history and recovery.
- [x] Make session-linked log writes awaitable, serialized and retryable across start, edits,
  zero-set finish, deletion and every stop/resume path; retain all old data with additive schema.
- [x] Show persisted Started time in live workouts and start/end in summaries across existing
  workout types. Preserve pause/overnight/date context and unknown/reviewed end semantics;
  never derive the end from active duration or reset the start when reopening.
- [x] Add confirmed repeat-last-set entry, an optional durable-deadline rest timer and
  context-qualified records. No prefilled set counts as performed; rest does not pause WHOOP.
- [x] Keep build-85 MET-only lifting calories, manual pauses and between-set rest unchanged.
  No fabricated total load, strength-volume calorie formula or added maintenance expenditure.
- [x] Coordinate the existing WHOOP quiet-HR nudge with Lift Log's one-hour no-entry reminder;
  resolve explicit Now versus Last set finish semantics before adding a background action.
- [x] Add validated/previewed local AkshatOS JSON import, origin-ID dedupe, reviewed linking to
  existing WHOOP workouts and load-mode-preserving JSON/CSV plus encrypted WHOOP recovery.
  Imported set-only history must not fabricate or double-count wearable metrics/calories. *Source: linking proposes the overlapping finished WHOOP lift session (one import per session, never one with sets) and asks; linked sets sit on the session, its strain/calories unchanged.*
- [ ] Cover feature parity, migration, delete-last-set, failures, relaunch/lock and notification
  races; verify an actual gym session without regressing the background-sync acceptance gates. *Source: domain, store, import and live-panel tests; the gym session and lock/relaunch checks need the phone.*

Decided (recommendations adopted): every existing lift type offers logging; tracking-only and
zero-set workouts stay valid; ordinary Finish ends now; a forgotten-finish reminder opens a Now /
Last set review; AkshatOS stays intact until import and combined-session phone acceptance. Repeat last set,
rest timer and comparable records are selected; RPE/RIR, warm-up flags, pinning, programming,
cross-mode tonnage charts, cloud sync, module removal and coaching-CSV activation are not.

### 3. Body and one recomposition Progress page

**Implemented in build 86; physical acceptance open.** Akshat wants
WHOOP to become his all-in-one body/fitness app, including AkshatOS Body's weight, measurements
and photos alongside lifting, food and wearable context. `fitness-app-plan.md` owns the whole-app
flow, evidence/comparison rules, current source gaps, import/recovery and optional future ideas.

Accepted overall direction, now in installed Build 86: Today / Trends / Food / Train / Progress,
with Body entry/history inside Progress. Feature phone acceptance remains open; the layout itself
was rejected. Local Build 87 preserves all reachable metrics in its replacement composition.
One `body_weight` path feeds Body, Food and Progress. One
Lift workout owns both sensor context and sets; no duplicate starts, calories or stores.

Implemented scope and remaining verification:
- [x] Preserve Body's daily weight, seven-calendar-day trends, measurement-week blocks, eight
  tape sites, edit/history, labelled estimates, front/side photos, reminder and exports. *Source: weekly blocks start on the measurement weekday with their change, on Progress and by month in Body history.*
- [x] Add/edit weight, tape and photos at a chosen past date; distinguish effective day from
  creation/import time, support multiple photos/day and keep photo deletion separate from weight.
- [x] Add measurement selector (Steps, Weight, Neck, Waist, Hips and remaining Body sites) and
  range selector (1 week, 1/2/3/6 months, 1 year, Since start, All). Show dated Start/Latest/Change
  for body readings and appropriate totals/coverage for steps; range/chart/entries must agree.
- [x] Provide two independent photo panels: select the active side and scrub a bottom dated
  thumbnail strip to choose its image without changing the other. Allow any two saved photos,
  optional same-pose filtering, date labels and swap; not only first/latest or an overlay slider.
- [x] Unify weight/height entry with WHOOP's dated profile rules; retain input units, original
  timestamps and IDs. Preview same-day/height conflicts; historical import must not become a
  current weigh-in or reprice captured workouts. Keep unknown/missing site data honest. *Source: an imported Body height that differs is offered (Use it / Keep mine) and saved through the dated profile, from today only.*
- [x] Show logged-set markers on the same workout's HR timeline, retaining gaps/clock uncertainty
  and late backfill. Set completion time is not measured set duration or per-exercise calories. *Source: a tick per logged minute on the summary HR trace (sets outside the trace are dropped), with a note that ticks are log times.*
- [x] Build one range/baseline Progress page: weight and waist, exercise-level comparable records, eligible
  food/protein, recorded activity and sleep/recovery, plus weekly and since-start observations.
  Show real dates/counts/coverage, partial-week labels and late revisions; no invented muscle
  gain, cross-mode tonnage, opaque score, automatic food targets or added lift maintenance.
- [x] Include explicit seven-calendar-day weight averages with observed-day counts, daily intake
  history, closed-week/calendar-month/since-start reviews, prior comparable periods and actual
  measurement dates. Align intake/estimated deficit with observed trends; compare waist/other
  tape sites and same-context strength without claiming proven muscle/fat change or causation. *Source: 7-day means with counts; Last week, Last month and Since start (first week against the last closed week) reviews.*
- [x] Add local evidence-based goal reviews (continue, insufficient data, review fueling/training/
  recovery, consider adjustment) with source windows/coverage and explicit user approval of any
  target edit. Keep calorie, protein and paired-maintenance denominators independent; unknown
  food is not zero. *Source: numeric guidance now follows the goal Akshat chooses (flexible goals above; `fitness-goal-research.md`).*
- [x] Add previewed/idempotent local Body JSON-plus-photos import and encrypted media-inclusive
  recovery. Current WHOOP database backups do not cover external photos; AkshatOS can omit/skip
  unavailable photo files. Missing media needs explicit review, not a silent complete migration.
- [x] During approved implementation, generate a versioned WHOOP import from the privately
  preserved MyFitnessPal screenshot source in `../../health/fitness/docs/myfitnesspal-import-source.md`.
  Preview/dedupe dated weights, original pounds, generated source IDs and baseline; handle existing
  same-day conflicts. Keep actual data/generated files outside public repos and CI. Photos will be
  attached manually to historical days; unsupplied tape, steps, food and HR remain absent.
- [x] Synchronize camera/picker privacy descriptions and personal payload validators before
  retained photos ship. Keep image work, imports and reports out of short BLE wakes.
- [ ] Cover merge/profile/calendar/coverage and corrupt/missing-media cases, then verify gym,
  body/photo/restore and brief-use background acceptance together on the phone. *Source: synthetic tests for imports, history-only pricing, media backup and photo encoding; phone checks open.*

Decided (recommendations adopted): full Body parity, Monday closed-week combined reports with
actual tape dates (Body's measurement weekday stays intact), explicit same-day conflict review,
history-only imported weights, and no AkshatOS removal before recovery/phone acceptance. Pinning, warm-up flags, RPE/RIR, scheduling, progression,
muscle-group charts and report export remain deferred; do not add them by enabling dormant UI.
Private coaching ownership and existing calorie calculations remain unchanged.

### 4. Navigation, live speed and complete-night charts

**Requested repairs; source findings in `build-86-audit.md` B86-01 to B86-04.**
- [x] Fix the Strain oldest-first/newest-first mismatch; left goes older, right goes newer,
  Today cannot advance into the future. Audit all day/chart/meal/history navigation contracts
  and test actual caller data rather than reversing every arrow indiscriminately.
- [x] Show fresh GPS Current speed from the existing tracker, separate from workout Avg. Handle
  accuracy, stationary zero, short-window smoothing, stale/error/pause/relaunch and km/h versus
  mph consistently. Measure filter responsiveness/battery during a locked walk; no promised
  fixed update cadence, fake location for sync or blanket Always request.
- [x] Read sleep signals over the complete onset-to-wake window across midnight, preserving
  original timestamps/quality/gaps and exact-day semantics elsewhere. Audit shared chart first/
  last points and cursor tolerances. Do not invent HRV or extend samples into missing periods.
- [ ] Verify open/resume recent recorded HR without manual pull, late backfill revision reloads,
  date rollover and a genuinely empty day; coordinate this with section 1 rather than a second
  independent sync service. *Source: recorded-HR tail and revision publishing; phone check open.*

### 5. Safe food/workout actions and portion/category clarity

**Requested changes plus source-audit failure risks; B86-05 to B86-09 and B86-12.**
- [x] Confirm saved diary deletion for both swipe and menu using shared `confirmRemove` behavior;
  keep entries on cancel/failure, prevent duplicate writes and retain Undo as extra protection.
- [x] Make saved diary grouping/reordering atomic; a multi-row move must not partially commit
  while reporting that the entire change failed. Preserve independent unsaved draft behavior.
- [x] Keep workout history expander fixed; move trash into a stable overflow menu. Add confirmed
  Delete to just-finished and existing summaries, with Discard for unsaved drafts kept distinct.
- [x] Make session/route/split/set deletion atomic and session-type-aware. Refresh summaries,
  comparable records, streaks and maintenance only after durable success; retain raw band history.
  Audit persisted start/end and pause/overnight retiming, failures and nested gesture hit targets.
- [x] Format portions both ways (named serving to g/ml and base amount to fractional serving),
  using explicit conversions only. Snapshot conversion provenance so editing/deleting My Food
  does not silently change old portions; preserve original inputs and nutrition precision.
- [x] Replace required predefined categories with create/reuse/edit/merge of personal labels.
  Retain existing stored labels, optional Uncategorised, readable filters and scan/manual parity.
- [x] Separate calorie goal progress from maintenance status across card/history/detail/reviews:
  above goal but at/below known Budget maintenance stays non-warning/green; red only above
  estimated maintenance. Preserve ACSM and mark absent/stale/partial estimates neutrally.
- [x] Audit reset/export/restore outcomes, including failure to delete backup files. New Body
  media, Pushups receipts, protection ledger and timers need complete recovery/reset coverage;
  never claim every copy/file was erased or restored when an operation failed. *Source: reset reports leftover backup and photo files with a retry, cancels every notification (lift, rest, Body), clears all prefs and tables and the in-memory set-log owner; the protection ledger, splits and Body weekday live in the database, so backups carry them; an active rest timer and reminders are deliberately not restored. Pushups receipts do not exist yet.*

### 6. General activity streak and sustainable rest

**Requested direction; exact policy still for review. B86-10 owns current source limits.**
- [x] Count completed lifting and other purposeful physical exercise alongside run/walk and
  step-goal days; dedupe activity on the same day and preserve existing awards/dated goal rules.
- [x] Add clearly labelled planned Rest and limited Life happens protection, with a recoverable
  ledger and separate counts for real activity versus preserved continuity. Do not fabricate
  exercise/steps/calories or count meditation/breathing as physical training.
- [x] Review exact allowance, retroactive use, qualification thresholds and Pushups contribution
  before implementing. *Decided (Akshat left it to judgment): at most 2 protected days per rolling
  7, at most 1 Life happens, none consecutive, Life happens only for yesterday; Pushups never
  counts toward the activity streak (it has its own).*
- [x] Avoid all-history/per-day query growth when adding sources; test overlap, edits/deletes,
  imports, timezone/DST, today-at-risk, exhausted protection and restored history. Pending sync
  is not proof of inactivity; reconcile late activity/protection without duplicate awards. *Source: one indexed sessions query per load; tests cover overlap, delete, late activity on a protected day, step-goal plus protection, month end/clock change, today open and the allowance.*

### 7. Pushups inside WHOOP

**Ported in build-86 source (Akshat's approval, including Always location).** `../akshatos/features.md`
owns parity; AkshatOS keeps its own Pushups unchanged until import and phone acceptance, and the
two apps do not sync. Code: `lib/data/pushups.dart`, `lib/data/pushup_reminders.dart`,
`lib/data/home_region.dart`, `lib/ui2/screens/pushups_screen.dart`, `HomeRegionBridge` in
`ios/Runner/AppDelegate.swift`.
- [x] Train → Pushups, Today's plan row with Start/Done, its own goal (captured per day) and
  streak, history by month, an end-of-day recap. A Done is one set: no reps, duration, HR or
  calories, and nothing feeds strain, maintenance or the activity streak.
- [x] Start/Pause/Resume/End, interval (whole minutes, only while no day is open), automatic
  ten-minute nudges, idle 9:00 invitation (only once Pushups has been used), notification taps
  open Pushups, Done/Pause on the notification without opening the app.
- [x] Pending budget: one ordinary reminder plus 29 nudges, inside iOS's 64 for the whole app,
  topped up from the saved anchor on every foreground pass; nothing else's requests are touched.
  Lock-screen actions run in a background isolate (plugin registrant and the notification-centre
  delegate set in AppDelegate), write an inbox file and move the reminders from a mirror of the
  open day; the app merges the inbox with receipts so one tap never counts twice.
- [x] Home auto-pause: one system-monitored region from a one-shot fix, 150 m default (50 m–1 km),
  Always asked for at setup; leaving pauses only a running day, arriving resumes only a day leaving
  paused, a manual resume outside suppresses repeat exit pauses until arrival, duplicates within
  two minutes ignored, health shown honestly. The Home point stays in preferences only (no
  backup) and is deleted when turned off or on reset.
- [x] Previewed, idempotent import of the AkshatOS backup (an open AkshatOS day is refused so no
  reminders restore running) and export in the same shape.
- [ ] Phone acceptance: locked/backgrounded/force-quit actions, Focus/Scheduled Summary, nudges,
  reconciliation after relaunch, Home events terminated/background, reboot before first unlock.

### 8. Structural UI redesign and whole-app convenience audit

**Implemented in the previously installed build 86; visual/structural acceptance failed.** Akshat's phone
screenshots and feedback reject the cosmetic-only feel and Progress's excessive sentences/noise.
Rendering without overflow is technical evidence, not design acceptance. No metric or entry point
was removed; the implementation checkmarks below do not mean the design is accepted.

- [x] Implement the approved genuinely different composition in Build 87:
  data-first Progress with dated trends, comparable strength and one selected-period review,
  compact goal/status, contextual Add and visible measurement/range selectors. Criteria and
  methodology remain in details; independent partial evidence no longer triggers repeated
  global insufficient-data panels. Safeguards and calculation gates are unchanged.
  `build-87-ui-plan.md` owns the replacement; structural acceptance remains open above.
- [x] Recompose Today/Food/Train around brief review, diary logging and Start/Resume in local
  Build 87. Preserve unique metrics, Budget/ACSM and existing entry points; no feature deletion
  is authorized. The installed Build 86 still has its rejected layout.
- [ ] Review with populated, partial and new-user examples plus real phone-sized first viewports,
  including Progress and the app shell; oversized full-page synthetic renders alone are insufficient.
  See `build-87-ui-plan.md` for the source/screenshot findings and limits of the current evidence.
- [x] Render the Build 87 hierarchy with the real five-tab shell, phone-height first viewports,
  scrolled content, diary/editing, Walk/Lift, Body entry and photo comparison. Synthetic
  fixtures cover populated/partial/new-user states and large text; physical flows and Akshat's
  design acceptance remain open. Build 86's oversized render was insufficient for that gate.
- [x] Use compact date/freshness/status and a useful HR canvas on Today, stable session controls
  and safe history on Train, diary-first Food with portions/maintenance context, and body/strength
  summary with integrated weekly/monthly review on Progress. No separate app-in-app shell. *Source: Today has a compact header with band-data age or Syncing/Calculating, recovery/sleep/strain in one card (stacked at large text), HRV and resting HR, a 112 pt HR canvas with hour marks, then steps/food, Body and maintenance. Food opens on one day card (calories, all four macros, fixed Add to <meal by time of day>), then the meals, then maintenance. Train shows Resume instead of Start while a session runs, history before the charts and one fixed options menu (Fix the times / Delete) per row.*
- [ ] Audit all routes/back gestures/day arrows, stable controls, hit targets, large text/small
  screens, safe areas, tab changes, selected day/filter/scroll state, permission/error/retry and
  loading/empty/stale/partial/offline states; compare screenshot/hit-target QA before release. *Partly: Today/Food/Train render without overflow at 1x and 2x, the 44 pt tap sweep passes on the gallery, large-text wrapping fixed in the maintenance and HR headers; back gestures and saved scroll/filter state need the phone.*
- [x] Repair weekly protein completeness/denominators and selected-window excluded-day counts
  (B86-11) before reusing the existing Week card for the combined insight engine.
- [x] Review optional conveniences. *Akshat chose Jump to Today, Return to workout, the
  pending-work line, Food-day completeness, the measurement-day shortcut and a chosen-weekday
  measurement reminder; all are in source (see the list at the top). Recent personal labels and
  review reminders were not chosen. Effort ratings, programming and the removed AI coach/journal/
  Live Activity stay out.*

### 9. Data-safety prerequisites found in the end-to-end audit

**Source findings B86-13 to B86-16 in `build-86-audit.md`.**
- [x] Add `body_weight`, `meal_template` and `live_coverage` to damaged-database salvage, plus a
  test that every schema table appears in salvage/import/export/wipe lists.
- [x] Keep imported/backdated weights history-only (decided): they must not change
  `ProfileHistory.on`, past maintenance or older workout calories.
- [x] Choose the photo picker/re-encoder (new dependency or native bridge) and a resumable or
  incremental encrypted media backup; measure backup time on the phone.
- [ ] Promote build 85 (or explicitly keep build 70) as rollback before any schema or backup-format
  change ships, and take a rollback-readable export first.

### 10. SideStore signing pilot (alongside build 86, not part of its code)

**Approved; `../akshatos/sidestore-evaluation.md` owns the pilot steps.** Akshat performs them on
the PC and phone. Sideloadly stays the active refresher until the pilot passes. Akshat wants it
run alongside Build 86: SideStore set up and AkshatOS moved first, WHOOP Build 86 installed with
Sideloadly, then WHOOP's refresh moved to SideStore after 86 has worked for a day or two, so a
signing failure and a Build 86 regression stay distinguishable. AkshatOS moves first; LocalDevVPN is allowed on the phone as SideStore's installer helper, never inside WHOOP.
- [ ] Before the pilot: verified WHOOP encrypted export copied to Windows and an AkshatOS full
  backup with photo count checked; record each app's signed identity and expiry.
- [ ] After the first SideStore re-sign of WHOOP: same final bundle ID, data intact, band still
  paired, automatic-backup passphrase still readable (keychain), Status shows the new expiry.
- [ ] Two unattended SideStore renewals away from the PC with advancing expiry and preserved data;
  then decide adopt, keep as fallback, or remove. Adoption updates `guides/IOS_SIDELOAD.md`,
  this file's refresh gates and the signing health check in the same change.

### Combined Approval And Release Gates

- [x] Plan reviewed; implementation approved as one build, with the decisions listed at the top
  of this section. Pushups and its Always location were approved afterwards.
- [x] Implement the approved build-86 scope together; run focused regressions, the full suite and
  personal-iOS payload/capability checks, and synchronize affected documentation.
- [x] Obtain separate publication/build authorization, then validate the replacement IPA's
  source, version, manifest, checksum and payload before installation.
- [ ] Complete feature and background phone acceptance before cache promotion; build 70
  stays recovery; build 86 is installed, not yet phone-accepted.

## Build 85 (`0.9.52`/`85`): previously installed, superseded by 86

Build-85 source `0.9.52`/`85` (commit `3c141b7a`) is published with Akshat's approval; Linux CI `37816259505` (3,430 tests, 395 intentional skips) and personal macOS build `37816260577` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. It was installed but not phone-accepted. Build 86 replaced its phone install and cache; Build 87 now occupies testing, and Build 70 stays accepted recovery.

Implemented as planned below; `build-85-audit.md` ("Implemented in build 85") lists every change.
Two deliberate deviations: the day timeline keeps carrying last night over into today (a test
pins it; it labels itself with its own day start), and the share card keeps pace for walks.
Phone checks: Lift setup says about 101 kcal per 30 active min at 80.5 kg and the live screen,
summary and Train list agree; Today shows "Updated hh:mm"; Day strain never shows yesterday's
number as today; Food → Foods, the log screen and the saved-meal picker filter by category once
two categories exist; a walk shows km/h; the maintenance sheet shows Budget and ACSM columns,
the stacked bar, Eaten vs Budget and the folded explanation; no refresh message appears.

Akshat's decisions on `build-85-audit.md`: lifting by exercise type only at 3.5 MET, heart rate as
context, one number everywhere, never in maintenance; keep the digestion floor with a cleaner line;
the two-column Budget (Method 1) | ACSM block everywhere; "Updated" times; Day strain never showing
yesterday as today; fix every stale/mismatched item; a complete UI makeover in one build (he
reviews on the phone, no before/after images); food categories that sync across Foods, the log
screen and pickers; remove the "Other totals update when the app is open." refresh note. Data
must stay exactly as calculated: logged foods, maintenance, digestion and steps unchanged except
where a decision changes them (lifting).
Plan:
1. **Lifting:** net (3.5 − 1) × kg × active hours (start to stop minus pauses) on setup preview,
   live, summary, Train list and the maintenance Lifting line; heart rate shown, never priced;
   no gross 6.0 fallback. Sets and rests are priced together: Compendium values are whole-session
   averages, and the band cannot see 15-second sets (wrist orientation once a second; heart rate
   lags a set by 20-60 s), so a split would be invented.
2. **Stale/mismatch fixes:** Day strain shows "not calculated yet" for today instead of the latest
   older day; Train list uses active time; Lifting footer wording; "normal range" only from 7 days;
   duplicated captions removed; "Updated hh:mm" stamps; sync-log counts labelled per connection;
   the background refresh note removed.
3. **Food categories:** `food_def.category` added in place (empty = Uncategorised, no schema
   bump); chosen in the food editor; filter chips on Food → Foods, the log screen's My foods and
   the saved-meal picker, all reading the same field.
4. **Makeover:** new shared design pieces (layered cards with hairline edge, section headers with
   overline, status chips, stat tiles, two-method block, stacked maintenance bar, comparison row,
   expandable "How it's worked out", updated stamp) and restructured Today, Food, maintenance
   sheet, Steps/Step calories, Train/workout screens, Trends and detail headers.
5. **Walks in km/h:** live, summary and history show a walk's speed as km/h (Strava's walking
   metric), runs keep pace per km; same distance and moving time, only the unit of the rate changes.
6. Tests for every calculation path touched; full suite; build.

## Build 84 (`0.9.51`/`84`): published and built, not reported installed (superseded by build 85)

Build-84 source `0.9.51`/`84` (commit `37241c1e`) is published with Akshat's approval; Linux CI `37780752762` (3,415 tests, 371 intentional skips) and personal macOS build `37780753121` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Its testing folder was replaced by build 85; `setup.md` retains reproduction evidence. The phone checks below carry forward to build 85.

Akshat asked for the refresh/background plan plus food by macro and lifting, with no stale data,
and reported Today's strain at 0.0 while Day strain showed a number. Implemented:
- **Stale Today numbers (root causes found):**
  - Screens re-read only on a revision bump, and a calculation pass bumped only at its end (a
    heavy pass is four days, up to a minute), so Today kept an early value (0.0 strain) while
    Day strain, read when opened, already showed the new one. Today's row landing now bumps at
    once (`_afterDrain` `onDayDone`).
  - The baseline rescan (up to 9 days of readiness) only called `notifyListeners`, so screens
    never re-read it; it now bumps the revision.
- **Background relaunches stay light:** a Bluetooth relaunch can reach Flutter as `inactive`,
  which `AppState` treated as opened, so each overnight relaunch ran the foreground session and
  full calculation. `_settleLaunchKind` asks UIKit (`appState` on the restore channel) before the
  session starts and logs `[launch] background|foreground (iOS state=…, Flutter lifecycle=…)`.
- **Pull-to-refresh** waits for today's row only (at most 15 s), then stops the spinner with
  "Still calculating; Today updates when it is done." if it ran over; older days finish behind.
- **Background offloads** are checked every 5 min (run at most every 15) instead of every 15,
  which let any other offload push the next to 30 min.
- **Exit reasons:** MetricKit's daily exit metrics (memory, background time limit, watchdog…)
  are appended to `whoop_exits.log` in Files → WHOOP (`ExitReasonLog`, Swift).
- **Food:** digestion per entry at the low end (protein 20%, carbs 5%, fat 0%, unknown 5%, capped
  at 20% of the entry), replacing the flat 10%; the sheet row reads "Digestion".
- **Lifting:** "Lifting (extra, not in maintenance)" in the maintenance sheet, from the existing
  per-session estimate less steps already counted, with "With lifting N kcal"; the total, cards,
  goal and history are unchanged.
Not in this build (judgment, recorded): today's calculation inside a background wake (fix 5; a
light pass took up to 57 s locked against roughly 10 s of background time), re-deriving only
changed days and an incremental cross-day pass (fix 4; deep engine change), the charger-only
`BGProcessingTask` (fix 6; capability change, iOS gives no schedule) and a bounded foreground-lease
wait (the 92-minute stall was a suspended process; a 15-min headless ceiling already exists).
Validation: 311 tests across the affected files pass (including `test/build84_test.dart` and the
exact digestion/lifting numbers); analysis of `lib` and `test` has no errors or warnings.
Phone checks: Today's strain matches Day strain right after a refresh; pull-to-refresh ends within
about 15 s; Food → Maintenance shows Digestion and, on a lifting day, the Lifting line; after a
night, `whoop_sync.log` shows `[launch] background` relaunches without heavy passes, and
`whoop_exits.log` appears after a day or two.

## Audit (not approved, keep for later): calibrated heart-rate + movement burn estimate

Akshat asked whether the earlier note (`workout-sync-audit.md`) about a calibrated HR-plus-movement
model is accurate and worth having. Audit only; nothing to build now (his decision).
- **The study ([Brage 2015](https://pmc.ncbi.nlm.nih.gov/articles/PMC4562631/), PLoS ONE):** 46
  adults, a chest-worn ECG + motion sensor (Actiheart), 14 days against doubly labelled water.
  Activity energy measured 66 kJ/kg/day. Error (RMSE, kJ/kg/day): movement only 24 (and 12 too
  low on average); HR only 37 group-calibrated, 32-34 individually calibrated; HR + movement 24
  group-calibrated, 20-21 individually calibrated (r 0.67). The note is accurate: combining helps
  and individual calibration helps more, but the combined model's gain from calibration was not
  statistically significant.
- **What that means in calories:** for a 75 kg person 20 kJ/kg/day is about 360 kcal/day of
  typical error averaged over two weeks, roughly 30% of activity energy, with a chest ECG strap.
  A single day, wrist optical HR and phone steps would be less accurate. Wrist devices are least
  accurate during resistance training ([O'Driscoll 2020 meta-analysis](https://bjsm.bmj.com/content/54/6/332)),
  which is the part this estimate would mainly add.
- **Calibration without running:** not a blocker. Brage's step and walk calibrations gave results
  similar to the treadmill, so brisk walks with phone steps/GPS or an 8-minute step test could
  calibrate it; runs are only one option.
- **Verdict:** a reasonable "rough burn" curiosity number, not a good basis for eating decisions.
  The app's food-and-weight maintenance (4-6 weeks of complete logging) is the better accuracy
  check and is already built; the conservative budget stays the planning floor. Revisit if Akshat
  wants lifting days shown as higher-burn days, or once he runs regularly.
- **If built later:** phone steps/GPS as the movement input (the band's 1 Hz gravity vector failed
  its own check: `branchedEnergyFusion` called 17-22% of labelled walks/runs non-locomotor);
  calibration from walks, a step test or runs; one answer per minute (movement when present,
  calibrated HR above the flex point only without steps, resting otherwise); lifting counted (his
  answer); shown separately, never moving the goal or the conservative budget.

## Earlier refresh repair: implemented subset and remaining scope

Build 84 added native launch classification, the 15-second today-result refresh wait,
five-minute background offload checks with a 15-minute floor, per-day UI refresh and a
separate MetricKit exit log. Build 85 retains them; these did not close phone acceptance.
The current plan above and `background-sync-plan.md` supersede the earlier repair proposal.
They cover startup races, running-worker cancellation, bounded ownership/expiration,
input-aware reuse and opportunistic insight processing. Do not arm a competing recovery
central while the restorable live central owns the band. Do not run the existing whole-day
"light" calculation merely because `beginBackgroundTask` was requested. The earlier blanket
force-quit/no-restoration claim is superseded by Apple's iOS 26 AccessorySetupKit contract.

## Plan: food by macro, lifting as an extra line (implemented in build 84)

Akshat's decisions after the two audits below: (1) replace the flat 10% food row with a
macro-based digestion cost on the conservative (lower-end) side; (2) show lifting as a separate,
clearly labelled extra line that never enters the conservative maintenance total. He asked for
documentation only while he looks into one more thing; no code, no build.

**1. Food row: lower-end digestion cost per entry** (`maintenance` in `lib/compute/profile.dart`
today takes `eatenKcal * 0.10`; `DayUpkeep` passes the day's kcal sum as `eaten`).
- Rates, the lower end of each published range: protein 20%, carbohydrate 5%, fat 0%; kcal of
  unknown composition 5% (the lower end of the 5-15% measured for mixed diets, Westerterp 2004).
  Energy from grams by label factors: protein 4, carbohydrate 4, fat 9 kcal/g.
- Per logged entry with kcal `K` and grams `P`, `C`, `F` (each may be missing):
  - `known = 0.20 × 4P + 0.05 × 4C` (missing grams count 0; fat adds 0);
  - all three present: `cost = known` (any kcal the macros do not explain, such as fibre,
    alcohol or label rounding, adds nothing);
  - any missing: `cost = known + 0.05 × max(0, K − energy of the macros present)`;
  - cap: `cost ≤ 0.20 × K` (no entry costs more than pure protein; covers label rounding);
  - entries without kcal add nothing (as today). Day cost = sum over entries; nothing logged = 0.
- Whey, shakes and other liquids use the same rates (digestion audit below). Fibre is not
  subtracted from carbs (labels differ; at most about 6 kcal on a 30 g fibre day); alcohol is not
  logged.
- Worked examples (each checked by script; current flat 10% in brackets):

  | Entry or day | Cost | (flat 10%) |
  |---|---|---|
  | Day: 2,500 kcal, 180 g P, 250 g C, 87 g F | 144 + 50 + 0 = 194.0 | (250.0) |
  | Day: 2,500 kcal at 15/50/35% (93.75 g P, 312.5 g C) | 75 + 62.5 = 137.5 | (250.0) |
  | Whey scoop: 120 kcal, 24 g P, 3 g C, 1.5 g F | 19.2 + 0.6 = 19.8 | (12.0) |
  | Quick add: 500 kcal, no macros | 0.05 × 500 = 25.0 | (50.0) |
  | 300 kcal with only 20 g P logged | 16 + 0.05 × 220 = 27.0 | (30.0) |
  | Olive oil: 120 kcal, 14 g F, 0 P, 0 C | 0.0 | (12.0) |
  | Powder labelled 100 kcal, 26 g P | 20.8 capped to 20.0 | (10.0) |

- Full-day check against the documented example (23 y, 80.5 kg, 186.69 cm, male): BMR
  1,861.8125 + steps 395.381 (15,000 steps) + food. Flat: 2,507.19 → 2,507. New with the
  180/250/87 day: 2,451.19 → 2,451 (−56). A normal 15%-protein 2,500 kcal day drops by 112.5.
- Effect to be aware of: this lowers maintenance on most days, most on low-protein days. It is
  computed when screens read the day, so past days' maintenance and history change too; no
  `kAlgoVersion` bump (not stored as a derived day metric). `maintenance()` needs the day's
  entries (or summed per-entry costs) instead of only `eatenKcal`; every `DayUpkeep` caller
  passes that.
- Sheet label: "Digestion (by macro, low end)" in place of "Food (10%)".
- Flat 10% versus this: 10% is the usual mixed-diet average and near the measured middle for his
  high-protein diet (a high-protein chamber diet measured 14.6%), so it is accurate on average
  but not a floor. Against the low end it can overcount by about 56 kcal on his 180 g-protein
  day and 112.5 kcal on a 15%-protein day; the low-end formula cannot overcount by those rates
  but probably undercounts by 2-5% of intake.

**2. Lifting: separate extra line, outside the total**
- Sessions counted: strength types priced by `conservativeMet` (weight training, bodyweight,
  functional, calisthenics, powerlifting). Per session the existing `otherWorkoutActiveKcal`:
  the lower of net Keytel at the session's mean HR over active minutes and (MET − 1) × kg × hours
  (MET 3.5 for weight training). Sum per local day; a session over midnight split by active
  minutes per day.
- Worked example (80.5 kg, 60 active min, mean HR 110, same profile): by MET (3.5 − 1) × 80.5 × 1
  = 201.25; by HR gross 8.3520 − resting 1.29293 = 7.0591 kcal/min × 60 = 423.54; the lower is
  201.25 → shown as +201.
- No double counting with steps: subtract the step calories of phone steps inside the session's
  active windows (1,000 gym steps = 26.36 kcal at 80.5 kg), floored at 0. Without per-window
  steps, show the line as approximate rather than guess.
- Shown only in the maintenance detail sheet as "Lifting (extra, not in maintenance) +201" and,
  under it, "With lifting 2,652" (2,451.19 + 201.25 with no phone steps in the session; with
  1,000 gym steps the line is 201.25 − 26.36 = 174.89 → +175, total 2,626); the Maintenance cards, the calorie goal and history keep the
  conservative number. Missing HR uses the MET value; missing weight shows no line.
- Tests to add: the table above and the lifting example as exact-number tests next to
  `test/walking_energy_test.dart` and `test/run_calories_test.dart`; metrics-map's calorie section
  updated when built.

## Audit (no decision yet): what the green maintenance number leaves out

Akshat asked what else adds to real maintenance beyond BMR + steps + runs + 10% of food.
Not counted, largest first for him (research in his chat; recorded here as the current view):
- **BMR equation error:** Mifflin–St Jeor lands within 10% of measured resting rate for most
  non-obese adults ([Frankenfield 2005](https://pure.psu.edu/en/publications/comparison-of-predictive-equations-for-resting-metabolic-rate-in-/));
  10% of his 1,862 is about ±190 kcal/day. Muscular people often run above it.
- **Lifting and other workouts:** excluded by design. Measured sessions run roughly 210-310 kcal
  gross ([AUT study](https://openrepository.aut.ac.nz/handle/10292/15675)), plus an after-burn of
  about 10-20% of that; the app already computes a conservative net value per session.
- **Non-step daily movement (NEAT):** standing, fidgeting, chores, carrying; the most variable
  part of daily burn ([Levine](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC6058072/)). Standing
  instead of sitting adds ~0.15 kcal/min ([Saeidifard 2018](https://mayoclinic.elsevierpure.com/en/publications/differences-of-energy-expenditure-while-sitting-versus-standing-a)),
  about 50-70 kcal per 6 h. Steps taken without the phone are also missed.
- **Digestion by macro:** protein costs more to digest than carbs or fat, but on his logged diet
  the difference from a flat 10% is about ±20 kcal (see the digestion audit below).
- **Cold, illness, dieting:** cool rooms add ~50-200 kcal/day; fever adds roughly 10% per °C;
  long dieting lowers burn (adaptive thermogenesis). Not reliably measurable by the app.
- **Catch-all:** the food-and-weight maintenance (4-6 weeks of complete logging) already includes
  every one of these; it is the right check on the green number.
Possible change, not approved: lifting as an optional, separately labelled addition.

## Audit (no decision yet): digestion cost by food type

Akshat asked whether whey, liquids, solids or food type change digestion cost (the 10% food row),
before deciding whether to implement it.
- **Per macro:** reviews rank alcohol > protein > carbohydrate > fat; a mixed diet costs 5-15% of
  intake ([Westerterp 2004](https://www.biomedcentral.com/1743-7075/1/5)). Commonly quoted ranges are
  protein 20-30%, carbs 5-10%, fat 0-3%. In a 24-h chamber, a high-protein/high-carb diet cost
  14.6% of intake versus 10.5% for a high-fat diet ([Westerterp 1999](https://doi.org/10.1038/sj.ijo.0800810)).
- **Whey versus other protein:** one crossover study found whey shakes raised digestion cost more
  than casein or soy (Acheson 2011), but a review found no clear evidence that any protein source
  costs more overall ([Bendtsen 2013](https://pmc.ncbi.nlm.nih.gov/articles/PMC3941822/)). Whey is
  absorbed faster, so its cost comes sooner, not clearly larger. Treat whey like other protein.
  Most of protein's cost is paid after absorption (building body protein, breaking down and
  burning the surplus amino acids, making urea), not by the gut's work, so a liquid that is
  absorbed faster still pays it. Fast whey is burned for energy more than slow casein (Boirie
  1997), which if anything adds cost. Short measurement windows (3-6 h) may miss the tail of slow
  proteins, which can make whey look higher than it is.
- **Liquid versus solid:** evidence is small and mixed. Eight men burned more after a blended meal
  than the same meal solid; a bar-versus-shake study in 29 men reversed by training group
  ([Ratcliff 2011](https://pubmed.ncbi.nlm.nih.gov/21411830)). No dependable liquid adjustment.
- **Whole versus processed:** a whole-food cheese sandwich cost 19.9% of its energy versus 10.7%
  for a processed one in 17 people ([Barr and Wright 2010](https://pubmed.ncbi.nlm.nih.gov/20613890/));
  one meal pair, not replicated as a rule, and the app cannot tell how processed a food is.
- **Bigger effect on the intake side:** whole almonds deliver about 20-30% fewer calories than
  label factors say ([Novotny 2012](https://pmc.ncbi.nlm.nih.gov/articles/PMC3396444)), and
  protein's usable energy is nearer 13 kJ/g than the label 17 kJ/g once digestion is paid. These
  change calories eaten, not burned, and are not in the label numbers he logs.
- **What a macro formula would change for him:** with midpoints (protein 25%, carbs 7.5%, fat
  1.5%), a 2,500 kcal day with 180 g protein, 250 g carbs and 87 g fat gives about 10.7% (267 vs 250
  kcal); a normal 15%-protein day gives about 8%, below the flat 10%. The quoted ranges span 195-340
  kcal for the same day, wider than the change. Midpoint tables also undercount measured mixed
  diets, so any formula would need anchoring to whole-diet chamber data.
- **Verdict:** real but small, about ±20 kcal/day against ±190 kcal of BMR error. Whey, liquid and
  processing effects are not supported well enough to model. If implemented: protein-weighted
  around 10% (anchored so a typical diet stays 10%, rising toward ~14% on high-protein days), flat
  10% for entries without macros, alcohol not tracked. Not approved.

## Build 83 (`0.9.50`/`83`): installed (Akshat's 7-8 Oct log came from it)

Build-83 source `0.9.50`/`83` (commit `cbaf93cd`) is published with Akshat's approval; Linux CI `37717941508` (3,408 tests, 371 intentional skips) and personal macOS build `37717959148` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Its former testing candidate was `../final-ipas/whoop/testing/WHOOP-0.9.50-build83-cbaf93cd`.

Approved by Akshat after the first build-82 phone log (`bugs.md`, "Background sync and slow
pull-to-refresh"); he has no other fixes for it. Implemented:
- **App log fixed:** every line starts with the local date and time to the millisecond, and lines
  are written one at a time, so overlapping writes no longer overwrite each other
  (`lib/sync/file_log.dart`, `test/file_log_test.dart`).
- **The sync no longer waits for data it never asked for:** after a reused connection, or once an
  earlier offload had ended, the history burst waited 60 s without asking the band and drained 0
  records. `_runSyncBurst` now asks the band whenever no offload is in flight, and asks once more
  if a wait it did not start ends empty.
Validation: the new log test, `today_refresh_test` and `ui2_router_test` pass; analysis has no
errors or warnings in the changed files.
Then: after an hour in the background and one pull-to-refresh, share `whoop_sync.log` to time
background syncs and each refresh stage before the refresh and background-sync fixes.

## Build 82: installed (Akshat), awaiting phone pass

Akshat approved the drag fix and the three friction fixes, plus a saved-meal flow check, and
later asked for build 82 to be built. Implemented:
- **Drag auto-scroll:** holding a row near the top or bottom edge scrolls the page (My foods,
  saved meals, the log screen, meal pages and the saved-meal editor). `DragEdgeScroll` in
  `lib/ui2/grammar.dart` re-aims after each step and replays the finger so the drop slot follows.
- **Ask before discarding:** Edit food, Quick add and the saved-meal editor ask "Discard changes?"
  (Discard / Keep editing) when something was typed, on every way out (pull, handle, ✕, tap
  above); an untouched sheet closes at once. The food sheets' route drag is off so nothing skips
  the question.
- **Food → Foods search:** filters saved meals and My foods by name (and brand); Build 90 supersedes the original filtered-drag restriction; dragging was off
  while searching, as on the log screen.
- **Saved meals, made consistent with foods:**
  - The editor's "Add a food" picker searches, shows each food's own serving line ("1 egg: 70
    kcal…", not "per 100 g"), and stays open to add several foods ("Done · 2 added").
  - On the log screen, tapping a saved meal logs it through the review, like tapping a food; the
    review links to "Edit saved meal".
  - Saved-meal rows show calories ("510 kcal · 2 foods · Breakfast") on Foods and the log screen.
  - The review names empty headings "No sub-heading", like the editor; editor and review copy is
    shorter.
  - One unit per food: a meal holding the same food twice (2 eggs and 50 g of egg) converts copies
    to one unit, in the editor and when saving from a meal card, instead of silently mis-scaling.
- **Diagnostics for background sync and slow refresh** (`bugs.md`): the iPhone app log now
  actually writes (`whoop_sync.log` in Files → WHOOP); pull-to-refresh logs each stage's
  finish time. Fixes for background spacing and the refresh spinner wait for that log.
Build-82 source `0.9.49`/`82` (commit `4b53abbe`) is published with Akshat's approval; Linux CI `37708103583` (3,406 tests, 371 intentional skips) and personal macOS build `37708104201` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Its testing folder was replaced by build 83 after Akshat installed it.
Phone checks: drag a bottom food to the top in one hold; pull down a typed sheet and see "Discard changes?"; search Foods; build a saved meal adding several foods; tap a saved meal on the log screen to review and log; after an hour in the background, share `openstrap_sync.log` and do one pull-to-refresh.
Validation: 12 affected test files (213 tests) pass, including `test/build82_test.dart` and a
Foods search flow test; analysis has no errors or warnings.

## Build 81: published and built, never installed (superseded by build 82)

Akshat installed build 80 and asked for a Quick add weight field, a review of the recovery score
(5 h 30 min still scored 88), sleep detection counting a cinema visit, and an end-to-end audit.
`build-81-audit.md` owns the findings, research, his decisions and the implemented list
("Implemented in 0.9.48/81"). Sleep detection is unchanged by his decision. The Live Activity is
removed: Sideloadly's free signing never provisions the extension (`bugs.md`).
Build-81 source `0.9.48`/`81` (commit `d44c989f`) is published with Akshat's approval; Linux CI `37699481094` (3,398 tests, 371 intentional skips) and personal macOS build `37699482851` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension in the IPA. Its testing folder was replaced by build 82.
Phone checks: Quick add shows all macros and a Weight (g) field; a weighed entry reads "· 250 g";
"Save to My foods" adds the food and links the entry; Readiness shows a filled ring and a Sleep
row in "What drove it", and a short night lowers the score; Sleep → Against your usual shows
Bedtime consistency after a week of nights; Recovery/HRV/resting HR/Sleep show "What moves it"
once a pattern has five mornings each side; on Monday the week card reads "Last week"; Status has
no Live Activity row and no black pill appears during a walk.

## Build 80: one serving line in the food editor, published, built and installed (Akshat)

Akshat installed build 79, reported the serving row misaligned ("Serving amount" wrapping) and
decided to remove the Other units section. Source `0.9.47`/`80` (`build-75-audit.md`, "Build 80")
aligns Amount · Unit · Weight (g) and drops Other units; per-gram foods with a named unit open on
their serving line. Phone checks: Edit food shows one level serving row and no Other units; the
chicken bites food reads 6 · pieces · 85.2 (edit to 85 if wanted); a per-gram food saved with a
unit (e.g. the sausage, if stored per gram) opens as 1 · Link · 71 and still logs in g and links.
Build-80 source `0.9.47`/`80` (commit `6dd75b2b`) is published with Akshat's approval; Linux CI `37565878253` (3,386 tests, 371 intentional skips) and personal macOS build `37565879521` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Tests before pushing ran on the affected food files only (127 tests); CI ran the full
suite. Installed; build 81 replaced its testing folder. The first build-80
run (`fbea4bb6`, alignment only) was cancelled before it produced an IPA.

## Build 79: published, built and installed (Akshat)

Akshat asked for labels such as "6 Pieces (85g)" to be entered as printed, without dividing.
Source `0.9.46`/`79` adds the serving weight beside a count serving, a count on other units and
the scan pre-fill (Other units removed in build 80); `build-75-audit.md` ("Build 79") owns the change. It includes everything in
build 78, which was never installed, so the build-78 phone checks below apply to build 79 too.
Akshat reports build 79 installed.
Build-79 source `0.9.46`/`79` (commit `4b7f5918`) is published with Akshat's approval; Linux CI `37563199102` (3,386 tests, 371 intentional skips) and personal macOS build `37563205812` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Tests before pushing ran on the affected files only, at Akshat's request (187 tests);
CI ran the full suite. Its testing folder was replaced by build 80.
Phone checks: a new food per `6` `piece` · `85` g at 140 kcal logs 3 pieces as 70 kcal and reads
"3 pieces · 43 g", and switches to g; reopening it shows 6 · piece · 85; the saved sausage still reads 1 link · 71 g.

## Build 78: published and built, never installed (superseded by build 79)

Akshat installed build 77 and approved build 78: two-unit portions, the one-press drag fix,
hiding the Training review, compact Train workouts with a monthly history, and conservative
calories for treadmill/other workouts. Build-78 source `0.9.45`/`78` (commit `1eae1fbc`) is published with Akshat's approval; Linux CI `37558355571` (3,380 tests, 371 intentional skips) and personal macOS build `37558356341` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Its former testing candidate was
the build-78 testing folder until build 79 replaced it. `build-75-audit.md` ("Build-78 audit and
implementation") owns the decisions, research and implemented list.
Phone checks: log the sausage as 3 links (reads "3 Links · 213 g", macros scale) and in grams;
a per-link food with "1 link weighs" switches to g; one hold drags into "No sub-heading";
Training review gone from Train/Settings; Recent shows five compact rows, All workouts groups by
month; a gym session shows a lower active figure than before; a treadmill session shows
distance-method calories.

## Build 77: build-76 follow-up, published and built

Akshat installed build 76; his follow-ups are recorded at the end of `build-75-audit.md`.
Build-77 source `0.9.44`/`77` (commit `2602cacf`) is published with Akshat's approval; Linux CI `37539992141` (3,375 tests, 371 intentional skips) and personal macOS build `37539992599` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Its former testing candidate was
It was the testing candidate until build 78 replaced it.
Phone checks: Calories "left" at the far right; no OpenStrap at launch; "No sub-heading" only
appears while dragging; pull an edit sheet down from mid-content and it closes.

## Build 76: build-75 follow-up, published, built and installed (Akshat)

Akshat installed build 75 and reported the follow-ups recorded at the end of
`build-75-audit.md`: float-noise numbers in Edit food, − / + step and hold-to-repeat, dragging
items between sub-headings (meals and saved meals) and the Calories card layout. Build-76 source `0.9.43`/`76` (commit `3f8ada60`) is published with Akshat's approval; Linux CI `37534408576` (3,373 tests, 371 intentional skips) and personal macOS build `37534409412` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. It was the testing candidate until build 77 replaced it;
install over build 75 with the exact final ID; `setup.md` owns the evidence. Build 75's phone
checks below carry forward to build 76.
Phone checks: Edit food shows 20, not 20.000000000000004; tap − / + = ±1, hold accelerates and
stops on release; drag an item into another sub-heading and back, on a meal and a saved meal;
Calories card reads eaten / goal with left on the right.

## Build 75: installed (Akshat), phone pass open

Akshat approved implementing the build-74 report together with decisions D1–D8 as
`0.9.42`/`75`; `build-75-audit.md` owns the decisions, root causes and the implemented list.
Source `0.9.42`/`75` (commit `1c203f17`) is published with Akshat's approval; Linux CI `37514558854` (3,369 tests, 371 intentional skips) and personal macOS build `37514599309` pass. Downloaded source/version, checksum, ZIP integrity and payload/extension checks pass. It was the
testing candidate until build 76 replaced it; `setup.md` owns the evidence.
Install over build 74 with the exact final ID. Build 70 stays the recovery build until build 75
passes the phone checks below and current-version enrollment.

Phone checks once installed:
- Walk: lock screen and Dynamic Island card appear; timer keeps counting while locked. If not,
  Settings → About → Status → Live Activity shows the reason; tap it for a one-minute sample.
- Trends Today/7/30/3 months: row numbers change with range; tapping opens the same range;
  every metric shows a day row with ‹ › without touching the chart; HRV/RHR/breathing/skin
  temperature rows open that night; Readiness has the same tabs and links.
- Re-tap each bottom tab: back to top; Food back to Today/today; Trends to 7 days.
- Food: drag order shared between Foods and Log; + opens the portion screen; saved-meal +
  review; sub-headings survive save → log; swipe either way deletes; meal cards show macros;
  Calories opens the whole day; egg chips 1–4 without repeats; − / + steps; a scoop measure
  shows "1 scoop · 29 g".
- Day breakdown shows only sleep, naps, workouts, band off and HR extremes; battery on Today.
- Existing data: saved foods keep their previous order after the first open; old saved meals
  still log under their name.

## Build 74: direct food-library scan replacement

The published/testing replacement adds Scan beside My foods → New. Scan reuses camera/consent/lookup, opens an
editable serving/nutrition review and saves directly to My foods only after confirmation.
The library flow never chooses a meal or writes diary entries; cancellation adds nothing.
Meal scanning uses the same editable review, then a portion/meal screen; only its explicit Log
button writes the diary. Saving the review alone only updates My foods. Saved barcode keys
update one food, preserve ancillary label data and work offline. Unknown/flagged/unreachable
lookups offer manual label entry; missing nutrients stay blank. Repeated library taps are guarded.
This addition is in the validated `0.9.41`/`74` replacement, source `ba5bb29f`. Local checks
pass (71 focused personal tests, eight iOS contract checks and analysis without errors/warnings).
Linux CI `37397127258` passes with test-only fixture repair `fa16be3c`; app and packaging inputs
match the compiled source. Personal macOS build `37395690305`, downloaded version/source/hash,
ZIP and payload checks pass. It was the testing candidate until build 75 replaced it.
`setup.md` owns exact run/artifact evidence. Recovery 70 stays; phone acceptance is pending.
Phone check: Scan → review → save/reload; camera/review cancel; rescan; manual fallback;
serving scaling and no unintended meal entry.

## Build 74: implemented combined repair and comparison

Source is `0.9.41`/`74`, algorithm 90, on Akshat's implementation approval.
`build-74-audit.md` owns the equations, source audit, Gemini-topic assessment and implemented
contract. Current validation is recorded in `setup.md`. Akshat approved public publication,
CI and the personal IPA build to the testing cache. Corrected source `ba5bb29f` is published to
`akshatksingh18/whoop`; Linux CI `37397127258` passes. The corrected packaging guard passes eight
contract checks. Personal macOS build `37395690305` passes; downloaded source/version, checksum,
ZIP and payload validation pass. Its former candidate was
`../final-ipas/whoop/testing/WHOOP-0.9.41-build74-ba5bb29f` until build 75 replaced it; Akshat
reports build 74 installed.

Implemented: shared future-time chart limits and units; permanent daily Steps/calorie browsing;
Step calories Today; selectable dated breathing and workout HR history; pause-clock alignment;
purple deep sleep; bounded revision-cached calorie history with independent food loading/error status; persistent
Budget/ACSM values using one movement ledger; accepted phone motion distance with labelled
fallbacks; descriptive active/daily energy labels; focused dated/session notification destinations;
retained weekly/training evidence; opt-in fortnightly training review with context matching,
consistency and supported best efforts; live measured cadence; optional workout context tags;
qualified post-session HR drift; narrow Run/Walk Live Activity with zone and last-km pace;
fresh ongoing-workout movement during foreground refresh; two-second deletion/Undo notices.
Budget/Weyand/run coefficients, full-day BMR and 10% logged-food allowance are unchanged.
HR energy remains analysis only. Missing comparison inputs stay unavailable, not zero.

### Release and phone gates

- Local release checks pass: 3,343 full-suite tests (376 intentional skips), 107 focused personal
  tests, eight packaging-contract tests and analysis without errors/warnings. Small/normal and
  enlarged-text layouts were inspected; generated screenshots were removed. Source commit
  `ba5bb29f` is reviewed and published; `setup.md` owns the complete evidence.
- Linux CI, personal macOS build and downloaded version/source/checksum, ZIP integrity and the
  single version-matched workout extension checks pass. Build 74 replaces the build-73 testing
  folder; `setup.md` owns the exact artifact and workflow evidence.
- Build 86 is installed (Akshat); confirm the same signed identity, encrypted history, decimals,
  saved foods/meals, band pairing and current-version automatic-refresh enrollment intact.
  The personal IPA has no extension from build 81; no Live Activity acceptance gate applies.
- Drag Today/Trends/Train daily Strain, heart-rate, Steps/calories and Wear to the right before
  midnight. No future selection/data; past dates, midnight rollover, gaps and VoiceOver remain
  usable. Breathing bars select their real dates, quality and coverage; failed reads offer Retry.
- Open Steps/calorie daily details and yesterday from visible navigation before touching graphs.
  Step calories opens Today; outer Trends remains Week. All readout units appear exactly once.
- Compare Budget/ACSM across Today, Food, its open breakdown, history/Weekly, live/finished
  run/walk, workout history and sharing. Manual refresh, food/profile edits and workout finish
  update dependents without reopening. Check missing distance/height/HR without hiding Budget.
- Walk indoors without Start, including short bouts/turns and carrying positions; check labelled
  phone motion distance versus a known route. Phone-left-behind wrist fallback must be honest.
  Recorded walking routes replace overlapping motion distance; calories are not added twice.
- Pause and continue walking: daily steps still count, session metrics freeze. Resume run/walk
  and confirm route/HR/cadence/readout alignment, fractional intervals and midnight ownership.
- Live cadence: phone-first measured steps/minute, wrist fallback, stale/absent readings and
  measured zero. Context tags persist/edit correctly; HR drift withholds weak/gapped comparisons.
- Delete food: Undo restores within the window; the bar disappears after two seconds and rapid
  deletions do not leave queued messages. No swipe is needed to dismiss it.
- Test cold/warm/foreground notifications with an old detail or keyboard-open form. Recovery,
  health, device, recap and idle-workout taps open exact dated/session evidence once. Unknown,
  deleted and expired records show a clear fallback; unsaved forms are preserved.
- Opt in to training-review notifications; inadequate data remains silent. Review shows matched
  dates/sessions/tags/coverage, recorded consistency, supported best efforts and measured cadence
  where available, with no causal fitness claim. Actual deliveries stay at least fourteen days apart.
- Workout Live Activity is removed from the personal build (build 81). Verify existing kilometre
  speech under screen lock, other apps, music/calls/headphones and pause/resume.
- Keep build 70 as recovery until complete device acceptance and current-version enrollment.
  Longer lifecycle/overnight/72-hour-soak and naturally elapsed unattended refresh gates remain.

Deferred after assessment: ghost routes, external weather, new zone calibration, automated
coaching and direct lock-screen pause/finish buttons. They need reliable comparison inputs,
new external integration approval or a separately verified native action contract. Zone and
last-km pace are implemented in the card. Existing personal-disabled prompts remain disabled.

## Build 72: UI, food reliability and Today refresh

Akshat approved implementing this scope together in one new personal iPhone build. Build 70
remains the accepted recovery build until the new candidate passes the phone and enrollment gates.

- Shared chart headers: full-width titles and wrapping selected values; preserve all metrics,
  units and explanations. Consistent deep-sleep colour; compact expandable explanatory text.
- Fresh launch opens Today; warm resume and explicit notification destinations remain intact.
- Food: My foods is the default picker; Scan opens the camera directly and reviews the product
  in the current meal/day. One manual quick-add form, including fibre and editing existing entries.
- History: calendar-month accordions, current month open, older months closed; browse retained
  records without a growing daily list. Compact rows and explicit chart range.
- Optional macros remain nullable and do not disqualify calorie summaries. Show logged values
  without inventing omitted macros; prioritise calories/protein. Zero entered explicitly is zero.
- Weekly energy summaries exclude unfinished and detectably incomplete days, name their coverage,
  and do not claim calculated kilograms of body fat. Missing meals cannot be inferred perfectly.
- Today/food summaries update automatically after writes, derived changes, foreground return and
  day rollover; no pull-to-refresh requirement or new iOS background capability.
- Today refresh reads today's phone steps before band sync and publishes measured counts without
  waiting for HR/sleep derivation. Today, Steps, Strain detail and today's chart point agree;
  measured zero is distinct from missing input. Await queue persistence and show timeout/read/held
  calculation messages. Short Today lists must also accept the refresh gesture.
- Fix backdated saved-meal timestamps, silent invalid inputs, overlapping saves, stale date reads,
  and loading/error states. Keep edits recoverable and give concise success/error feedback.
- Refine spacing, action consistency and restrained feedback using the existing dark design.
- Add meaningful widget/data regressions for chart readouts, food flows, monthly browsing,
  automatic refresh, date/save races and failure states. Inspect representative screenshots at
  small/normal widths and enlarged text, then run the release checks and one macOS IPA build.

The scope above is implemented in source `0.9.39`/`72` (algorithm 88; schema and capabilities
unchanged). The initial UI/food source `5c00c278` passed local release checks, Linux CI `37170843509`
(3,270 tests, 363 intentional skips) and macOS workflow `37171288516`. Its IPA is held before release:
Akshat subsequently reported Today refresh leaving steps stale on installed build 70. The combined
source passes all 3,274 full-suite tests (368 intentional skips), focused refresh regressions,
static analysis with no errors/warnings and all 7 personal-iOS contract tests.
The revised version is `0.9.39`/`72`. Akshat approved publishing source
`05c208c79fe61c35e8df587e7becfd59698cbf02` and its build records to public
`akshatksingh18/whoop`, running CI and building the combined replacement IPA. That source is
pushed; Linux CI `37173914511` passes (3,279 tests, 363 intentional skips).
macOS workflow `37174063547` passes. The downloaded IPA matches its manifest/checksum and
passes local payload validation. `setup.md` owns its source, hash and artifact evidence.
Akshat confirmed build 72 was installed; it was not phone-accepted. Build 73 superseded its
testing IPA after validation; subsequent candidates superseded it, with build 86 now installed.
The superseded build-71 artifact lacks the refresh fix; keep one install candidate.

## Build 73: approved combined repair

Source `0.9.40`/`73` (algorithm 89), commit `a49d7837`, is published with Akshat's approval
to public `akshatksingh18/whoop` and passes local release validation. Linux CI `37252915519`
and the single personal macOS build `37252925924` pass against that exact source. The downloaded
IPA matches its manifest/checksum and passes local payload validation. It replaced build 72 in
the single testing slot and is now superseded by validated build 74; `setup.md` owns its preserved
source/hash/workflow evidence. Build 70 remains accepted.
Akshat confirms build 73 is installed and initially looks good, with the Strain cursor issue above.
Its complete phone pass and current-version enrollment were not confirmed; gates carry into build 74.

- One fresh movement ledger feeds Today, Food, history, Weekly, Trends, Steps detail and an open
  maintenance sheet. Historical step charts prefer retained measured coverage over old derived
  counts; step calories use dated weight and the same run-step accounting as maintenance.
  Refresh publishes measured steps/Method 1 without waiting for HR derivation; food, profile and
  workout writes invalidate dependent reads. GPS buffers flush before a manual movement refresh.
- Streak: 10 active run/walk minutes OR the day's measured step goal. Dated targets apply immediately;
  the displayed target changes immediately even after earning. An earned threshold survives
  raising the target, but a measured count correction can revoke unsupported evidence. Overlapping
  recorded windows count once toward the ten minutes. Old step-only days have no invented targets;
  workout history remains.
- Positive overlapping phone measurements win. Finer phone windows supplement with accepted
  wrist-only gait; growing wrist spans replace prior partial counts, preserve cadence and split at
  local hour/midnight. Passive connected-band capture does not require Start. Offline WHOOP 4
  steps beyond Bluetooth range remain unavailable; source accuracy and battery need phone tests.
- Walking Method 1 = `(2.74 * steps * weight_kg) / 8368`; Running Method 1 retains the accepted
  distance/walk-break equation. Running steps are removed once from background walking, with
  overlapping sessions and midnight windows accounted for. Uncertain run-step overlap uses the
  larger movement estimate rather than adding unreduced step/run energy. Untrusted GPS climb
  is excluded from calorie additions; elevation still displays as measured route information.
- Net Keytel Method 2 is a comparison for both walk/run, subtracting BMR/1440 over measured active
  minutes only. Missing HR minutes stay missing. Active calories exclude resting already in BMR.
  Daily maintenance = full-day BMR + Method 1 movement + 10% logged food; the food goal is fixed.
- Pausing freezes session time, distance, HR/zone accumulation, steps and calories. Daily steps
  and daily walking calories continue. Active windows and recorded profile/weight persist in the
  lossless database backup. Late HR rescoring must retain the Method 1 primary calorie figure.
- Session-owned kilometre/pace cues retain milestones and actual kilometre crossing times.
  Personal background audio is enabled for real spoken cues, with music/call/route interruption
  handling. No silent keepalive; locked/background execution remains a physical-device gate.
- Cross-day insights rebuild independently from retained current inputs, with busy/history/failure
  states. Macro rows/icons all remain visible; omitted fields show zero logged and stay nullable.
- Profile decimal keyboards, full metric prefills and unchanged metric/imperial saves preserve
  precision. Food quantity and nutrient edit prefills preserve supplied decimals too. Dated weight
  anchors keep historical estimates stable; the food/weight inference needs an aligned interval
  of at least 14 complete intake days and 8 weigh-ins and is explicitly labelled an estimate.
- Food picker has only My foods (default) / My meals. Custom serving units and decimal amounts
  scale every supplied nutrient. Choose/create a meal heading before logging, including quick add,
  saved food/meal and scanning. Delete saved items in the picker by swipe or explicit action,
  preserving diary entries. Shared tap haptics and keyboard-safe close/drag headers cover forms;
  text prompts own their controllers until their closing animation ends.
- Nap corrections save and reproject immediately, including Sleep periods and the timeline;
  sleep coaching recalculates from retained results in the background, with durable retry status.
  Naps remains reachable when empty or without a main night. Restore works for legacy rejected
  windows and preserves the distinction between measured detection and a manual report.
- Trends opens on Week. Sleep/Strain Today reuse their full daily detail; measured HR, HRV and
  wear charts appear where available, with held-over dates labelled. Steps includes its hourly
  source graph inline. Step calories has a separate kcal trend using maintenance's walking term.

Local validation passes: 3,318 Flutter tests (368 intentional skips), 91 focused tests with
`PERSONAL_SIDELOAD=true`, all 7 personal-iOS contract tests, project/pin checks and representative
rendered layouts. Analysis has 60 infos and no errors/warnings. The daily details also fit a
320-point screen at 1.5x text. Linux CI passes 3,323 tests with 363 intentional skips; native
macOS compilation and downloaded IPA validation pass. Installation is confirmed; the complete
phone acceptance checklist is not yet passed.
`workout-sync-audit.md` records the build-72 evidence and repair contract.

Build-73 phone acceptance must cover:
- Same-identity install, retained food/templates/weights/steps, pairing and encrypted restore.
- Force-close from Food/Trends and relaunch into Today; warm resume retains the current screen.
- Sleep/Food chart readouts wrap at enlarged text; Deep matches the legend and Night details opens.
- Direct scan and denied-camera fallback, quick-add fibre/editing, optional blanks, explicit zero
  and Undo. Browse older history months and backdate a saved meal without changing its day/time.
- Locked and other-app kilometre cues, pause/resume, headphones, music, podcasts and calls.
- Phone carried/desk/absent, source handoff, local midnight, low wrist motion and range loss;
  compare connected wrist fallback against hand-counted steps and observe battery use.
- Step-only streak, exact threshold, raise/lower before and after completion, late steps/restart.
- Today manual/foreground refresh updates step kcal and maintenance in every open view; profile,
  meal and completed-workout changes update automatically, including Weekly and day rollover.
  Repeat with the band disconnected/slow; HR waits/errors remain explicit. Fixed food target stays unchanged.
- Run/walk live, finish, history/share and daily totals agree under the displayed rounding, with
  paused movement only in daily steps and no walking-workout double addition.
- Decimal profile saves, four macro rows, 2.5 custom servings, headings and picker deletion;
  cancel multi-input sheets with the keyboard open and check small/enlarged text.
- Rebuild insights without new band data; missing-history/busy/errors remain clear and retryable.
- Remove the only nap, immediately restore it, leave/reopen/relaunch, add/delete a manual nap,
  and retry a failed coaching update. Check all period totals agree before and after rebuilding.
- Trends opens Week; Sleep/Strain Today charts match Today drill-downs; Steps has its hourly
  graph without another tap; Step calories shows kcal with the same dated weight/run deductions.
- Completed current-version automatic-refresh enrollment before promoting the testing IPA.

A calibrated HR/movement hybrid or automatic budget adjustment remains outside this build.

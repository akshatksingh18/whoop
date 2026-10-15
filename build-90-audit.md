# WHOOP Build 89: Whole-App Audit And Complete Improvement Backlog

Method: independent dual-agent assessment (A: `/root/design_review`; B: `/root/technical_audit`) plus parent source tracing and targeted synthetic checks. Impeccable native critique/audit discipline; no web detector applies to Dart.

**Status:** original Build 89 audit plus the complete Build 90 worklist. Akshat approved
implementation and selected A overall with B's compact macro rows; engine/data and the full
approved UI are implemented in local source on `build-90-codex`. `todo.md` owns implementation,
commits and outstanding gates. Findings below describe the audited Build 89 unless explicitly
qualified; they do not override the accepted design in `DESIGN.md`. Local synthetic captures do
not establish phone/native or final cloud acceptance. Build 89 remains installed/testing,
not cache-promoted; Build 70 remains cached recovery.

## Current Visual Acceptance

Akshat clarified that **A overall + B's macro card means the whole B calorie/macro composition**:
calories remaining inside a ring, eaten and the fixed goal beside it, followed by four compact
macro rows. The earlier Codex source copied only B's rows and missed the selected ring. The
Food correction restores that component, removes the decorative plate/fork and redundant linear
calorie bar, and retains explicit over-goal, absent-goal, absent-intake and partial-total states.
The ring encodes the known remaining fraction of the fixed intake goal. Unknown/partial balances
do not draw an exact arc; the amount retains its bound. Exercise is not added to the intake goal.
Unknown nutrient bars are hatched and labelled not logged, not zero. Existing data/routes remain.

The rest of the quoted 24-item review is **not marked fixed**. Source checks apply to the Codex
UI carried into merged `build-90` (`e7af786e`); the correction stays on `build-90-codex` for Claude
to integrate. Akshat's mockup-first rule still governs further layout changes: show the proposed
whole affected pages beside current pages, including lower sections, before implementing them.
Keep large-text verification even when the main visual review uses standard text.

Findings retain Claude's original numbers:

1. **Confirmed layout:** Today action slots are Expanded, but Pressable's inner Align sizes the
   visible containers to content. Make the visible action fills occupy equal slots in the preview.
2. **Confirmed consistency:** Today's Food/Protein denominators use different unit copy and Steps
   omits its known target. Preview one consistent value/goal convention without inventing goals.
3. **Confirmed layout:** SubTabs uses content-width scrolling items even when three short options
   fit. Preview equal-width segments when they fit; retain scrolling when they do not.
4. **Confirmed type hierarchy:** EnergyComparison renders an absent estimate's word in the numeric
   style. Use a quiet absent-state label; retain the reason and other available method.
5. **Presentation choice:** Pin favourites is a standalone Align/Pill above Trends. Preview it in
   the header/section controls; retain pin selection and edit behavior.
6. **Confirmed layout:** Trends step-energy places the second estimate in MetricLine's narrow value
   column. Give the comparison full-width context; retain both methods, coverage and detail route.
7. **Confirmed wrapping risk:** estimate and missing-day coverage share one small string. Preview
   separate context lines or keep the count/unit together; never hide incomplete coverage.
8. **Resolved by the selected B card correction:** the thin plate line was an authored utensil,
   not lost data. The plate and utensil are removed with the old hero composition.
9. **Intentional current behavior, not a missing total:** meal headings show totals only for
   multi-item meals; a singleton shows its calories on its only item to avoid repetition. A
   consistent all-meal-heading alternative needs a preview that preserves each item's detail.
10. **Presentation choice:** Copy a day and Food progress remain functional standalone actions.
    Preview an anchored secondary-action group; do not remove either flow.
11. **Profile-gated, not a proved personal-build bug:** Training review is behind
    `!kPersonalSideload`. Confirm the actual personal build flag/native render before changing it.
12. **Evidence gap, not permission to invent dots:** week count reads repository sessions;
    streak dots read the local session/step ledger and require qualifying activity. The render
    harness injects repository workouts separately from that ledger. Align synthetic fixture
    sources and check real qualifying sessions on the phone; short/non-exercise sessions can
    legitimately count as logged sessions without earning a streak dot.
13. **Confirmed spacing:** the week panel leaves a divider after the streak even without a
    following run row. Preview conditional separators and tighter empty trailing space.
14. **Confirmed spacing:** Train wraps an embedded Pushups PlanRow in a normally padded Surface,
    adding padding to the row's own. Preview a compact wrapper with the same actions and touch size.
15. **Confirmed shared-source spacing:** the nonpersonal import card has no leading section gap.
    Add spacing in its preview; that card is excluded from the personal profile.
16. **Platform/fixture difference:** storeName uses `Platform.isIOS` and already says Apple Health
    on iOS. Windows renders take the Health Connect branch. The personal profile also hides this
    import card. Verify a native/profile capture; do not replace the shared Android label globally.
17. **Confirmed affordance issue:** Add body entry is active but uses BigButton's soft style.
    Preview a clearly active primary treatment; its save/navigation route remains present.
18. **Confirmed hierarchy issue:** Progress inputs are joined into one Text. Preview short labelled
    groups with explicit coverage, retaining all input facts and the context detail route.
19. **Confirmed layout:** Body comparison combines verbose dates/counts in one flexible column
    with a long before/after value in another. Preview full-width comparison rows with intact
    figures, dates and denominators at ordinary and large text.
20. **Precision choice:** Body milestone copy formats stored readings to two decimal places.
    Those are recorded values, not fabricated precision. Preview consistent overview rounding
    while preserving exact readings, comparison logic and history/edit precision.
21. **Confirmed unit inconsistency:** Progress context and input copy append % to recovery,
    whereas the shared recovery view presents the same 0–100 score without %. Correct display
    units consistently in the preview; do not change the stored score or calculation.
22. **Confirmed terminology:** Recovery uses readinessDetailTitle in its navigation/history copy.
    Preview Recovery consistently, retaining internal model names and all driver/method detail.
23. **Fixture plus copy issue:** the Sleep fixture includes aggregate stage totals without timed
    stage samples. Those are distinct capabilities. The current empty-hypnogram message claims an
    input was missing without proving that cause. Preview honest timeline-unavailable wording,
    keeping available aggregate totals, and separately verify native timeline availability.
24. **Presentation choice:** Fix sleep times is intentionally last and folded outside a panel.
    Preview it in a clear correction surface, preserving expand/collapse, validation and save.

No device-only outcome, reference staging accuracy or final build acceptance follows from this
review. The remaining presentation previews, cloud/native checks and phone matrix stay open.

## Evidence And Practical Limits

Source reviewed: app/packaging source `77d6a365`, documentation HEAD `ee2dd55c`, algorithm 93, schema 49; personal iPhone profile. Source verification and targeted checks: 2026-10-14. No actual health database, photograph, private log or recording was needed for the audit or sent anywhere.

- Fresh current-widget captures: all five main tabs, populated and empty Progress, upper and lower views, at 390 × 844 logical points and 1×/2× text; populated Progress additionally at 3.1×. Thirteen render cases passed their overflow assertions.
- Existing targeted Build 89 Food (6), analysis export (4), and phone-step (3) checks passed: 13 tests.
- Two temporary synthetic export observations reproduced defects: a saved backdated weight is omitted from the analysis file; export best-set/rep estimation disagrees with the shared app method.
- Two temporary iOS-platform gesture observations reproduced the Reduce Motion regression: normal edge-back returns; with Reduce Motion it does not.
- Total: 30 targeted checks. The observation tests intentionally assert the existing undesirable behavior; their passing result is evidence of the finding, not evidence of a repair.
- The full suite and native macOS build were not rerun. The recorded Build 89 Linux/macOS results remain the build evidence in `setup.md`; this documentation task changes no binary.

These are Flutter test-render captures with synthetic records, not iPhone or iOS Simulator screenshots. The harness uses Manrope under the SF-family name, mocked platform services and artificial safe-area insets. Injected Today data omits Body/Pushups/Train-or-Resume rows and WeekCard that the normal app can show. The normal Today screen is therefore longer than its capture. The fixture's apparent numerical discrepancies between independently seeded families are not real metric bugs.

The green rectangle in place of the empty Progress unit button is a missing test-font/platform artifact, excluded from production findings. Physical keyboard, VoiceOver, exact SF typography, native BLE, camera/share-sheet behavior, GPS, background execution, signing and battery were not tested here. No audit can certify that nothing is broken in every state. This report identifies observed problems, source-proven failure paths, and the remaining device checks separately.

Current local captures (legacy `b87` filenames, newly generated from Build 89):

- [Today](build/ui_capture/b87_today_1.0x.png), [Trends](build/ui_capture/b87_trends_1.0x.png), [Food](build/ui_capture/b87_food_1.0x.png), [Train](build/ui_capture/b87_train_1.0x.png), [Progress](build/ui_capture/b87_progress_1.0x.png).
- [Progress lower page](build/ui_capture/b87_progress_1.0x_lower.png), [empty Progress](build/ui_capture/b87_progress_empty_1.0x.png).
- [Food at 2×](build/ui_capture/b87_food_2.0x.png), [Train at 2×](build/ui_capture/b87_train_2.0x.png), [Progress at 2×](build/ui_capture/b87_progress_2.0x.png), [Progress at 3.1×](build/ui_capture/b87_progress_3.1x.png).

These generated files are local and replaceable; their paths are not a claim of permanently preserved phone evidence.

## Main Judgment

Keep the locked kraft/cream palette and metric-family colours. The strongest problem is hierarchy and task access. Repeated large summaries give checking readiness, logging dinner and reviewing a training block much the same composition. Another recolour would leave that problem intact.

Progress is the weakest tab. It combines reviewing a goal, inspecting many measurements, logging, comparing photos, inspecting strength, reviewing food/recovery and configuring a goal on one long page. Useful recorded observations compete with repeated eligibility messages. The first normal-size viewport contains period controls, “Not yet clear,” a rules paragraph, a huge average weight and unavailable Weight/Waist/Lifts rows. Actual Body entry is below it. At large text, even the recorded evidence leaves the first viewport.

Three strengths to retain:

1. The visual identity is coherent, with contrast-solved ink, semibold numbers and recognisable family colours.
2. Five stable top-level tabs and the shared live-workout return path provide a good navigation foundation. Existing food repeat/copy/portion flows, workout history filters and body/photo history should be reused.
3. There are real data-safety foundations: transactional session deletion, transactional food arrangement/portion writes, immutable versioned results, qualified averages, encrypted media export and honest absent-data handling. The findings below concern remaining consumer/error paths; they do not mean those foundations should be replaced.

## Provisional Review Scores

These are structured professional judgments over inspected source and renders, not measured usability or device certification.

| Nielsen heuristic | /4 | Main reason |
|---|---:|---|
| System status | 3 | Retry/freshness states exist; eligibility feedback can identify the wrong next action |
| Real-world language | 2 | Familiar tab names, but overlapping review concepts and comparison context |
| Control and freedom | 3 | History/edit/cancel routes; one reproduced accessibility back-gesture regression |
| Consistency | 2 | Strong palette; weaker period and interaction consistency |
| Error prevention | 3 | Existing safeguards, with a combined-form partial-save defect |
| Recognition over recall | 2 | Too much contextual interpretation and hidden action access |
| Efficiency | 1 | Frequent actions below tall summaries; large-text action labels fail |
| Minimalist design | 1 | Repeated evidence and oversized first viewports |
| Error recovery | 3 | Many retry paths; goal save and misleading partial-save feedback remain |
| Help | 2 | Details exist, but overview rules and generic advice add burden |
| **Total** | **22/40** | **Significant UX improvement needed** |

| Native dimension | /4 | Main reason |
|---|---:|---|
| Accessibility | 2 | Good targets/scrub semantics; broken numeric/action readability at large text |
| Performance | 3 | Isolate analytics and lazy tab start; all-history Progress reloads need profiling |
| Appearance | 3 | Coherent locked light identity; no new dark-mode requirement selected |
| Platform behavior | 2 | Stacks/sheets/safe areas, but Reduce Motion strips edge-back |
| Adaptivity | 2 | Overflow passes do not catch unreadable layouts; physical keyboard checks open |
| **Total** | **12/20** | **Acceptable with substantial work remaining** |

Progress fails six cognitive-load checks: single focus, useful chunking, hierarchy, sequencing tasks, shared comparison context and progressive disclosure. Body's chart/entries/photos grouping is an improvement. Ten Body metrics are reachable in a horizontal strip; this does not mean ten are visible at once. The five main tabs are valid peer destinations and need not be removed.

## Reliability Findings And Repairs

Severity here: P1 materially misleading behavior or major task/accessibility difficulty; P2 a local failure with a workaround or a product-policy limitation; P3 optional polish. No P0 data-loss or launch blocker was established within this scope.

### B90-01 — P1: A Body Form Can Save Before Reporting An Error

**Evidence:** source-proven; `lib/ui2/screens/progress_screen.dart:1876`–`:1949`, `lib/data/body_log.dart:245`–`:275`.

Enter a valid weight and an invalid waist (for example `abc` or an out-of-range tape value), then Save. `_save` writes weight and, for today, updates the calculation profile before `tapeReading` validates tape. The screen reports an error while the weight/profile have already changed. A later storage error can similarly produce “Not saved” after earlier writes succeeded.

**Repair:** parse and validate every field before any persistence; give the combined operation a clear transaction/reconciliation contract for weight, tape and profile changes. Preserve the draft on failure and accurately identify partial success if a single atomic operation is impossible. Photo tools currently commit immediately, so make their saved status explicit rather than implying the final Save owns them too.

**Acceptance:** invalid tape leaves weight/profile unchanged; injected measure/profile-write failures cannot claim nothing was saved; successful backdated entry keeps historical pricing unchanged; unit/date/edit/delete paths remain intact.

### B90-02 — P1: Deleting A Workout Does Not Invalidate Other Open Tabs

**Evidence:** source-proven call-path gap; `workout_screen.dart:2545`–`:2568`, `:2638`–`:2666`, `lib/data/db.dart:9221`–`:9241`.

History deletion clears the run cache, transactionally removes session/route/splits/sets/lift log and reloads local workout history. It does not publish the shared AppState/Nutrition revision used by already-open Progress, Food and Today. Their cached session counts or maintenance view can therefore retain the removed workout until another refresh event occurs.

**Repair:** one shared post-commit session-change publication used by deletion and other session edits. Invalidate the affected views only after durable success; retain deleted raw sensor observations. Audit summary/menu/swipe paths together.

**Acceptance:** open Food and Progress, delete today's run or lift in Train, revisit without pulling and see correct counts/context/maintenance; failed deletion preserves both records and the previous display. This does not authorize subtracting measured band load merely because a user removed a session label.

### B90-03 — P1: Reduce Motion Removes iOS Edge-Back

**Evidence:** reproduced by two synthetic iOS-platform navigation checks; `lib/ui2/theme.dart:615`–`:635`.

The `_Gated` transition wrapper returns the unwrapped child when motion is disabled. Flutter's Cupertino transition builder also supplies the back-gesture detector, so removing it removes edge-back. A normal push returns on an edge swipe; the same push with Reduce Motion enabled stays on the detail route.

**Repair:** preserve native gesture structure while suppressing the visual motion. Do not restore animation as the workaround.

**Acceptance:** enabled/disabled Reduce Motion both retain edge-back, explicit Back and sheet dismissal; real phone check includes Food day swipes and swipe-to-delete so gesture regions do not conflict.

### B90-04 — P2: A Failed Goal Save Can Stay On “Saving”

**Evidence:** source-proven failure path; `progress_screen.dart:3013`–`:3023`.

The button sets `_saving`, awaits `GoalPlan.save`, and has no error handler or finally reset. A persistence exception leaves the button disabled, with no meaningful retry state.

**Repair:** retain choices, reset busy state in finally, show a retryable save error and publish the goal change only after success. Include unmounted-screen handling.

### B90-05 — P1: AI Analysis Omits Real Historical Weigh-Ins

**Evidence:** synthetic store-to-file reproduction; `lib/data/analysis_export.dart:301`–`:305`.

The writer excludes every `historyOnly` weight. That flag intentionally prevents imported/backdated readings from repricing calories; it does not mean the weight is imaginary or unsuitable for a historical chart. A synthetic backdated reading exists in Body but its day disappears from the analysis file.

**Repair:** export observed historical readings with provenance; keep them excluded only from calculations whose contract requires that exclusion. Separate chart/history eligibility from calorie/TDEE-input eligibility.

**Acceptance:** manual backdated/imported/today weights appear with source and effective dates; pricing exclusion remains unchanged; the exported history agrees with Body.

### B90-06 — P1: AI Export Uses A Different Strength Estimator

**Evidence:** synthetic formatter reproduction; `analysis_export.dart:82`, `:208`–`:218`, compared with `lib/data/lift_progress.dart:20`–`:59`.

Export has its own unbounded Epley helper and picks a best set with it. It bypasses the app's 12-rep admission rule and setup-specific wording. In a synthetic example, the app selects `100 × 1`, while the export selects `95 × 2`. It also prints `estimated 1RM 166.7 lb/side` for `100 × 20`, where the app's score abstains. Plates-per-side and added load are not whole-system max loads.

**Repair:** reuse `bestSet`/`setScore`, show the raw best set and load meaning, qualify a permitted score as a rep-adjusted estimate on this setup, and abstain above the existing rep gate. Preserve equipment context.

### B90-07 — P2: Export Loses Macro Completeness And Keeps Temporary Files

**Evidence:** source-only; `analysis_export.dart:313`–`:320`, `:177`–`:195`, `:367`–`:373`, `lib/ui2/profile/data.dart:325`–`:371`.

The export retains a calorie floor flag but discards each macro's completeness/floor provenance. Its weekly protein average includes counted food days with any protein number, whereas the app's own nutrient mean excludes macro-incomplete days. A partial protein subtotal can therefore look like an ordinary total and distort the exported weekly average.

Separately, copy says “nothing is kept,” but the writer creates a temporary file/directory and the share caller never removes it. The OS may eventually reclaim it; immediate cleanup is not implemented. “Shared” also describes the share sheet returning, without distinguishing a dismissed sheet.

**Repair:** preserve per-nutrient completeness and denominators; label partial sums; clean up the generated analysis folder at the supported post-share lifecycle point, including failure/cancel. Use honest share-result copy and explain that a recipient's saved copy remains outside app cleanup. The app must not automatically upload this private export to an AI service.

### B90-08 — P1: Large Text Is Technically Contained But Unreadable

**Evidence:** fresh 2×/3.1× renders, source-supported; `nutrition_screen.dart:1504`–`:1548`, `workout_screen.dart:1077`–`:1106`, `progress_screen.dart:404`–`:493`, `app_shell.dart:153`–`:235`.

Food's `1,450` splits into `1,4` and `50` because the number shares a fixed row with the balance. Train's four fixed-width actions become `R…`, an effectively invisible Walk label, `Li…`, `O…`. Progress's 3.1× title becomes `Prog…`, and only navigation/comparison prose fits in its first viewport. Tab labels split inside words. All these cases passed the existing no-overflow assertion.

**Repair:** stack calorie values at accessibility sizes; keep each number as one readable unit; use a two-column or full-width workout-action layout; shorten/reflow header and period context; keep complete tab labels and selected-state semantics. Follow the user's text size rather than globally shrinking it to make the existing composition fit.

**Acceptance:** no split numeric tokens or ambiguous primary labels at normal, 2× and 3.1× text, narrow-phone and landscape sizes; real iPhone Dynamic Type/SF-font and VoiceOver checks. Snapshot/readability assertions supplement overflow tests.

### B90-09 — P2: Progress's Advice Can Name The Wrong Action And Period

**Evidence:** current render plus source; `progress_screen.dart:1284`–`:1318`, `:1018`–`:1095`.

The synthetic page has 59 recent weigh-ins but no valid earlier three-month comparison. It says “Weigh in on more mornings,” which does not identify or quickly repair that missing historical block. “No weight records in the earlier period” and a valid shorter-period action would explain the actual issue without inventing history.

The page's one selector drives descriptive sections, but the separate Goal card always uses its phase-specific closed-week window. The latter may be the correct policy; it must have its own visible comparison dates and must not imply it follows “3 months.”

**Repair:** generate blocker-specific next actions and separate descriptive review from qualified goal advice. An unavailable combined verdict must not hide useful weight/waist/strength facts.

### B90-10 — P2: Current Food Goal Can Reclassify Old Days

**Evidence:** deterministic source policy; `lib/data/nutrition_store.dart:645`–`:683`, AppState assignments at `:363`/`:1126`.

Automatic counting uses the current process-wide calorie target, not a frozen target for the old date. An unmarked 1,400 kcal day qualifies at a 2,300 kcal target but not at a 3,000 target. Changing today's target can therefore change old counted-day eligibility and averages without editing the day.

The half-goal rule itself is Akshat's approved convenience policy and is not called a defect merely for being heuristic. It can still count a lunch-only day over the threshold; automatic count is evidence of logging, not proof that all meals were logged.

**Decision needed:** use dated/frozen eligibility or explicitly accept retrospective reclassification. Recommended: preserve the qualifying target/provenance per date, keep manual overrides, and label “counted automatically” separately from user-confirmed completeness. Validate migration/backup semantics before choosing storage.

### B90-11 — P2: “Lossless Database” Copy Can Hide Missing Photos

**Evidence:** source/l10n; `lib/ui2/profile/data.dart:486`–`:518`, `:709`–`:713`, `lib/l10n/app_en.arb:449`, `:572`; `lib/data/media_backup.dart`.

Plain SQLite export is called a complete/lossless copy and “the only format” that restores to another phone. Body JPEGs live outside it. The encrypted export has a database-plus-photos path, while automatic in-container backups intentionally remain database-only.

**Repair:** label each format with what it includes, which importer accepts it and whether photos are present. Make the full encrypted media export the clear off-phone migration path; report included/missing photo counts. Keep automatic backup's container-loss limitation visible. No new destination or upload is proposed.

## Tab-By-Tab Design Proposal

### Today: Check, Then Act

Keep Recovery, Sleep, Strain, HRV/RHR, steps, Food, live/recorded HR, maintenance and existing details. Make the readiness block compact enough to expose daily actions. Directly below it show Log food, Weigh in/Measure and Start/Resume; keep Pushups reachable. Present steps/Food/maintenance once in the overview and let their routes carry the detail. Place the large HR explorer after the quick actions; retain 10 min/1 hour/Day and the scrubbable full-day chart. A concise sync/insight-age line opens the existing Status panel rather than adding another dashboard.

At large text the recovery hero should reflow into a compact readable result, not grow to consume the whole viewport. Important exceptions remain clear without stacking ordinary information cards ahead of the next action. Source: `home_screen.dart:957`–`:1050`, `:1958`–`:2022`, `today_plan.dart:126`–`:188`.

### Trends: The Best Existing Overview

Keep the grouped metric rows and qualified measured-day averages. Show actual range dates, units and a clear route affordance. Give values priority over fixed-width sparklines; preserve gaps. The 2× stacked layout works better here than elsewhere. Optional enhancement: let Akshat pin two or three metrics near the top, while keeping the complete list and findings reachable. Do not resurrect removed stress/temperature surfaces or turn findings into frequent alerts. Source: `health_screen.dart:273`–`:345`, `:425`–`:485`; `grammar.dart:3735`–`:3768`.

### Food: Meals Should Reach The First Screen

Keep the accepted eaten/goal + left/over pair, all four macros, fixed targets, maintenance pair, dates/week strip, direct portion edits, My foods/My meals, label/barcode review and copy/save flows. Reduce the height of the calorie/macro area; make the first meal and Add food visible sooner. Protein can be prominent while Carbs/Fat/Fibre remain in four slim value/target rows. The accepted A + compact B composition keeps all four macros visible without expansion; full item detail remains reachable.

The week-state circles need a discoverable short legend or tap explanation. Keep automatic/manual counting controls but shorten the status line. Singleton meals should not repeat the same totals in header, item and footer. Preserve every nutrient in detail. At large text stack numeric values and actions. Source: `nutrition_screen.dart:1251`–`:1299`, `:1416`–`:1548`, `:1578`; `food_diary.dart:170`–`:228`.

### Train: Start/Resume And Recent History First

Keep Run/Walk/Lift/Other, with a responsive two-column/full-width layout at large text. Resume outranks Start while a session runs. Put the most recent workout before the tall streak/strain material. Make Rest today look like an action. Keep Pushups as its own panel, but reduce its dominance over workout history. One compact weekly-load preview opens the existing chart/detail rather than duplicating it at full size. Preserve lift splits, load meanings, previous sets, rest timer, comparable records, running trends, safe history options and filters. Source: `workout_screen.dart:313`–`:419`, `:629`–`:657`, `:1077`–`:1106`.

### Progress: Three Outcome Rows And One Goal Verdict (Recommended)

The accepted composition prioritises goal outcomes over supporting inputs and uses the
fixed closed-week verdict. It is implemented in Build 90 source; native/device acceptance remains
open. The locked light palette stays.

1. **One goal card:** goal, days since activation, exact review/comparison dates, one verdict
   from the existing phase-specific closed-week goal check, and one short reason or actual
   missing requirement. Tap for the same verdict's evidence, Next and Change goal. Remove the
   duplicate arbitrary-period verdict presentation; do not introduce a second advice verdict.
2. **Three outcome rows:** Weight, Waist, Strength. Their overview figures/comparisons use
   the same goal-review window and label actual measurement dates/coverage. Weight and Waist
   open Body with the matching metric selected; Strength opens per-exercise detail.
3. **Compact inputs summary:** food/protein, recorded training/steps and measured sleep/recovery
   over that review window, opening the context detail. Use a short wrapping summary, not a
   forced single line. Calories/protein and sleep/recovery retain independent eligible counts.
4. **Visible Add body entry:** weight with Save near it, followed by optional tape/photo
   sections. Body settings, all history, photos/Compare and every existing capability remain
   in Body detail. No duplicate stores or generic goal percentage-complete bar.

**One authoritative verdict:** for a one-week goal phase, compare the last closed week with
the one before; for a two-week phase, compare the last two closed weeks with the preceding two.
Keep all existing waiting, coverage, nutrient and comparability gates. This is a presentation/
model-reuse proposal, not approval for a new goal formula or relaxed eligibility.

**History range is exploration:** retain all eight periods for charts and before/now detail
comparisons. Put a clearly labelled History range control with the exploration/detail area,
rather than presenting a header date picker that appears to change the goal verdict. Arbitrary
history comparisons show observations/directions, not another On track/Off track classification.
Changing that range does not change the verdict, its dates, outcome rows or inputs summary.

Inside Body/Strength/Context detail, retain B's earlier value → current value, actual dates,
change and scrubbable chart where meaningful. Strength has one same-context row per exercise;
the context page retains food/protein, workout types, steps, sleep/recovery and method notes.
Known readings remain visible when their comparison is absent. Do not create a strength score
or grade every decrease/increase as good/bad; preserve the locked colour system.

Missing-evidence copy must be actionable and specific: name each deficient week and its count,
not only the minimum across all weeks. A missing reading in a closed historical week cannot be
fixed by weighing in today. Offer entering an existing real reading or waiting for a new
qualified window; never imply the user should fabricate a retrospective measurement.

Direct links open the matching detail/section: Today Body/weight → Body Weight; Food's progress
link → context Food; Train strength → Strength; workout/steps comparisons → context Training.
Due measurement actions open entry directly. Existing logging/live-session routes retain their
jobs. Back returns to the originating screen with day, range, filter and scroll retained; dated
cross-tab contexts are visible and never silently rewrite the goal-review window or saved range.

Normal-text first-viewport composition and large-text readability require fresh phone-sized
previews before acceptance. Allow natural scrolling, full labels, intact numbers and 44-point
actions. This text proposal is not evidence that a candidate UI has been rendered or implemented.

**Preservation contract:** no unique metric or data-entry/history route is deleted. Body details retain kg/lb, Readings/7-day mean, Start/Latest/Change, reading counts, weekly blocks, all eight tape sites, qualified dated body estimates, history, backdated edits, independent photos and comparisons, reminders, journey start and height/profile route. Strength retains workout/set counts, per-exercise load/reps/context, comparison states, previous performance and existing history. Context retains calorie/protein averages with separate denominators, workout-type breakdown, steps total/average/covered days and chart, measured sleep/recovery, and links to Food/Trends/Train. Goal configuration retains all phases, pace/training-age choices, activation date, manual targets, closed-week advice and method/safety details. Underlying computation/storage stays intact.

Simplify Body entry too: weight and Save first; optional Measurements and Photos sections below. Combined-entry capability remains available. This must include B90-01's write-safety repair.

## Enhancements Worth Adding, In Order

### High Value: Reuse Existing Features Better

- **Direct action routes:** make Food/Body/workout summaries visibly tappable; consistently use chevrons or labelled actions. Do not build duplicate entry forms.
- **Useful comparison fallback:** a recorded-history-aware shorter-period option and blocker-specific action. Keep confidence/eligibility gates unchanged.
- **Selected-state accessibility:** announce the current range, selected Body metric, unit and goal option; existing Scrubber semantics are a good model.
- **Existing Status visibility:** a compact band-data/insight freshness entry on Today, opening the present sync-health detail.
- **Backup/export clarity:** included data/media counts, honest cleanup and provenance; the detailed analysis file should agree with the same data/model shown in the app.

### Optional New Scope: Useful After Simplification

1. **Pinned Trends metrics:** choose two or three favourites, retained locally; all others remain reachable.
2. **Previewed whole-day food reuse:** copy a prior day's meals with date/portion review and explicit Log. Meal copying/repeat logging already exist; this is a broader convenience, not a claim they are missing.
3. **Finished lift-set correction:** edit/delete a mistaken finished set in its session, with confirmation and recomputed comparable progress. Preserve the original wearable session times, raw band data and calorie policy; this reopens a previously deferred editing capability and needs its own persistence/recovery tests.
4. **Source-linked progress milestones:** show verified changes in a measurement or same-context best set with real dates. No generic muscle-gain score, causal claim or arbitrary achievement notification.

Warm-up flags and optional RPE/RIR can remain later ideas if logging friction still warrants them. Programming, global search, social/cloud features, more top-level dashboards, new speculative physiological scores and automatic calorie changes do not address the current problem. No new hardware, permission, service or AI upload is required for the recommended scope.

## Complete App-Wide Worklist (Every Release)

This is the consolidated response to Akshat's request for everything outstanding, regardless
of build number. The B90 identifiers above identify audit findings; they do not assign every
repair to Build 90. Confirmed source/render defects, design recommendations, inherited
investigations, device acceptance and optional features are separate work classes. None is
implemented or newly approved by this inventory.

### Confirmed Build 89 Findings

All eleven findings above remain open:

- **B90-01 Body write safety:** validate weight and every entered tape value before writes;
  coordinate weight/tape/profile persistence, preserve failed drafts and accurately report
  partial success. Explain that photo actions currently save independently.
- **B90-02 workout deletion freshness:** publish a shared change after the transaction so
  Today/Food/Progress and strength/activity/maintenance consumers drop stale cached results.
  Test every deletion route and failed writes; preserve the raw wearable observations.
- **B90-03 Reduce Motion:** retain iOS edge-back while suppressing motion, with explicit Back
  and sheet dismissal intact.
- **B90-04 goal save:** clear busy state on failure, preserve selections, offer Retry and
  guard disposal; publish successful state only after persistence.
- **B90-05 analysis weight history:** include real imported/backdated readings and their
  provenance while preserving their exclusion from dated calorie pricing/TDEE inputs.
- **B90-06 analysis strength:** use the app's best-set/comparison method, its rep gate and
  equipment/load meaning. Do not label per-side or added load as whole-system 1RM.
- **B90-07 analysis macro/share integrity:** keep individual nutrient completeness, floors,
  counted-day denominators and partial-total labels. Clean temporary analysis files at a
  supported share lifecycle point; distinguish success, cancellation and failure honestly.
- **B90-08 large-text readability:** prevent split Food numbers, abbreviated/invisible Train
  actions, truncated Progress labels and tab labels broken inside words. Reflow and expose
  selected-state semantics instead of shrinking away the user's chosen text size.
- **B90-09 Progress explanation:** remove competing verdicts/windows, show actual dates and
  exact deficient blocks/counts, and keep usable observations visible under partial evidence.
  A closed missing week needs a real existing historical reading or a future qualified window.
- **B90-10 food policy:** decide dated/frozen eligibility versus retrospective reclassification
  by today's calorie target. Keep manual overrides and the approved half-goal convenience;
  automatic counting must not imply that every meal was recorded. This requires a policy and
  migration decision rather than an unannounced formula change.
- **B90-11 backup descriptions:** distinguish SQLite/database-only, encrypted database-plus-
  photos, analysis and CSV exports; state restore support and included/missing photo counts.
  Explain that automatic in-container backups cannot recover an uninstalled app container.

### Every Tab And Shared Navigation

These are improvements to task hierarchy and existing routes; the source/render evidence and
preservation contract are in the Tab-By-Tab Design Proposal above.

- **Today:** compact Recovery/Sleep/Strain and HRV/RHR; expose Log food, Weigh in/Measure and
  Start/Resume earlier; retain Pushups. Show steps/Food/maintenance once, move the HR explorer
  after actions, retain its three windows/full-day scrubbing, and link a concise true
  data/insight-age line to Status. Reflow large text and give actionable exceptions priority.
- **Trends:** retain the complete metric list, qualified averages and findings; make dates,
  units and tap affordances explicit. Prioritise readable values over fixed-width sparklines,
  retain missing-data gaps and avoid adding noisy alerts or reviving removed surfaces.
- **Food:** bring the first meal and Add food earlier by compacting the calorie/macro hero.
  Keep eaten/goal and left/over, all four nutrients, dates/week/calendar, Budget/ACSM, direct
  portions, My foods/My meals, scanning and copy/save flows. Explain week-state dots, shorten
  counting-state copy and remove repeated singleton-meal totals. Any expandable nutrient
  presentation must keep full totals discoverable.
- **Train:** put Resume/Start first and recent workouts before tall streak/load sections;
  make Run/Walk/Lift/Other readable at large text and Rest today visibly actionable. Reduce
  Pushups' visual dominance without hiding it; make load preview compact and preserve chart,
  running trends, filters, safe deletion, all lift contexts, splits/previous sets/rest timer.
- **Progress:** one closed-week goal verdict with dates/reason/missing evidence, three aligned
  Weight/Waist/Strength outcome rows, compact qualified inputs and a visible Add body entry.
  Body, Strength and context details retain everything; all eight History ranges explore
  observations without creating another verdict. Quick weigh-in precedes optional tape/photos.
- **Progress presentation details:** no invented completion percentage or strength sparkline;
  real series only, known readings even without an earlier reading, and favourable colours
  only for supported progress toward the goal. Calories/steps are not inherently good/bad.
- **Contextual links:** Today weight opens Body Weight, Food opens context Food, Train strength
  opens Strength, activity/steps opens context Training, and a due measurement opens entry.
  Back preserves the origin's day/range/filter/scroll. Date context and saved history range
  must not silently change the authoritative goal window.
- **App-wide accessibility/states:** complete readable labels and atomic numbers at normal,
  2x/3.1x, narrow and landscape sizes; range/metric/unit/goal selection announcements,
  chart/readout semantics, 44-point actions, focus order and keyboard/safe-area clearance.
  Review loading, empty, partial, stale, failed, offline and live states, keeping retry,
  cancellation and unsaved drafts usable across sheets and routes.

### Inherited Measurement And Storage Investigations

These come from `bugs.md`, `metrics-accuracy-research.md` and the deferred boundaries of
`build-88-plan.md`. They are not all fresh Build 89 regressions. Reconfirm each affected current
path and freeze a test/reference method before changing outputs; keep hidden metrics hidden.

- **HRV/respiration:** Build 89 repaired the overly strict report-time adjacency tolerance.
  Still investigate corrected-NN continuity across actual dropouts, Lomb-Scargle power scaling
  under gaps and beat-sum versus wall-clock timing. Validate derived respiratory availability
  and precision with independent evidence; do not claim ECG-resolution timestamps or calibrated
  accuracy from the 13-night availability regression.
- **Sleep restlessness:** the map still uses absolute distance from 1 g; assess posture/scale
  sensitivity and align with observed motion evidence. This differs from the relative
  stillness breathing repair already shipped.
- **Sleep accounting:** reconcile sleep-debt carry-forward, the two awakening-count definitions,
  short REM lost by minimum-bout policy, unavailable cycles displayed as zero, and coverage
  admission in duration-dependent consumers. Confirm existing correction/nap/night-selection
  behaviour before any change; the longer-night preference is an accepted policy.
- **Sleep-stage validity:** stage cutoffs and WHOOP sensor transfer need independent reference
  validation. Preserve estimate wording; a new ML/Cole-Kripke model or retuning to expected
  percentages is experimental scope, not an established repair.
- **Travel/time:** audit retained-day re-derivation and sleep clock/bedtime-consistency semantics
  after timezone travel; current-zone grouping can shift historical day seams. Preserve tested
  local-date/DST arithmetic and distinguish original versus displayed timezone.
- **Quiet-day strain:** calibration bias is not resolved by hiding the target. Keep the
  prescriptive target withheld; assess the quiet-HRR model and dependent interpretation against
  measured evidence. The net/observed-day load, shared HRmax and minute-weighting repairs are
  already implemented and should not be relisted as missing.
- **Wear/coverage:** reconcile the two worn-minute definitions and distinguish record absence
  from confirmed off-wrist/charging where supported. Missing or delayed transfer alone is not
  proof the band was unworn.
- **Input retention/protocol:** investigate historical R10-lite HR reaching legacy samples but
  not the substrate, the latent 5-8 RR decode-count risk, unknown-version slow fields stored as
  zero, and stale legacy oxygen/temperature exports. These need current-path/provenance checks
  and observed fixtures; unsupported measurements must remain withheld. Green ADC is not
  retained and normal decoded retention is about three days, so unavailable old raw inputs
  cannot be replayed. Raw optical capture remains an explicitly deferred/off feature.
- **Transfer completeness:** WHOOP 4 burst-count shortfalls remain advisory. Use logged count,
  timestamp continuity and replay evidence to decide policy without endangering commit-before-
  verbatim-ACK. No data loss was established by this audit.
- **Timestamp meaning:** clarify effective diary date versus creation/log time for backdated
  Quick add and daily weight replacement. Do not imply an ordered measurement time when the
  current daily record represents the last saved value.
- **Estimate boundaries:** maintain visible limitations for Budget/ACSM, MET lifting, digestion,
  food/weight TDEE and Navy estimates. Historical weights used for charts may be excluded from
  pricing; tape/weight changes do not prove exact tissue change. Coefficients, readiness weights,
  calorie anchors and new sensors are not automatically reopened by a visual redesign.

### Performance, Device Workflows And Operational Acceptance

Performance concerns are profiling tasks until measured. Device checks below are outstanding
acceptance work; they do not imply every checked feature is currently broken.

- **Performance:** profile multi-year synthetic Progress load (all food/session/body/lift
  history), visited hidden-tab revision reloads, eager Body history, cold preparation/staging
  and repeated opens. Bound/reuse/paginate only where evidence warrants it; preserve full history.
- **Short background opportunities:** measure transfer-versus-compute scheduling, brief
  foreground catch-up, expiry/cancellation/requeue and safe ownership retirement. A background
  refresh window can be consumed by transfer before calculation; scheduling needs actual phone
  CPU/freshness evidence, not a guaranteed execution promise.
- **All data mutations:** verify Food add/edit/delete/copy/portion/labels and saved meals;
  Body add/edit/delete/units/date/photos/profile; goal changes; workout start/pause/resume/finish/
  retime/delete; imports and restores. Every affected tab/detail/export must agree after commit.
  Exercise validation/storage/share/photo failures, retries, disposal and draft preservation.
- **Build 89-specific phone pass:** recent nightly HRV/absence reasons and current recovery;
  HR-only live readings on Today and in workouts; overnight sync; phone-only steps and permission
  on/off/missing-versus-zero; battery versus Build 88; app/Files/log/backup naming and readable text.
  Also the Build 89 additions, none phone-verified: a finished workout with a valid session
  strain lifts the day's strain to at least that session's contribution (the net-TRIMP floor),
  while a workout without qualified inputs still adds nothing; Food's week strip, month calendar from the date, calorie
  card and goal bar; automatic past-day counting with Undo/Missing food/Count this day; the
  9:30 pm "Is today's food complete?" notification, its foreground Mark complete and Not yet
  actions, its toggle, and its place in the reminder budget beside Pushups; the Labels bin;
  the Pushups card on Train; finger-scrubbing on Today's 10 min/1 hour charts; and Export for
  AI analysis producing and sharing a readable file for every range.
- **BLE/lifecycle:** first pairing and denial/recovery, including Find my band, which has no
  recorded phone verification since the AccessorySetupKit descriptor crash repair (`bugs.md` "Active iPhone
  pairing crash"); repeated drains; locked/background
  two-hour and overnight intervals with short daily visits; range loss/return, Bluetooth changes,
  airplane/Low Power/Background App Refresh settings, off-wrist/charging, normal termination,
  force-quit separately, reboot/first unlock and resource pressure. Verify dated freshness,
  duplicate-free ingest/ACKs, recoverable interrupted work and no permanent latch/stall.
- **72-hour soak:** record durable-data and served-insight ages, sync/calculation progress,
  battery and exits in matching MetricKit windows. No crash loop, data loss, false freshness,
  repeated CPU/resource exits or UI-isolate stalls may be inferred away by passing unit tests.
- **Run/walk:** outdoor current-speed/stopping/stale-fix constants, pace/distance/steps, GPS
  permission/Precise Location recovery, route tail/sequence across pause/lock/relaunch and
  cross-midnight timing. Verify voice cues with lock, another app, music, calls and headphones.
- **Lift Log:** actual gym session, split/load-mode parity, previous sets, repeat confirmation,
  durable set edits/deletes/Undo, rest timer, forgotten-finish Now/Last set, zero-set finish,
  lock/relaunch and notification races; previewed idempotent import must not duplicate sensor
  sessions or calories.
- **Pushups:** locked actions, Focus/Scheduled Summary, reminders/budget, inbox deduplication and
  relaunch reconciliation; Home exit/arrival/manual-resume behaviour, denied location,
  background/termination and reboot. Keep AkshatOS intact until import and combined acceptance.
- **Food/camera/media:** real barcode/label/manual fallback and editing checks; physical
  keyboard/sheets, camera/photo selection/compare/delete, share success/cancel/failure and
  recipient consumption before cleanup. Full media restore must prove photo counts and identity.
- **Backup/migration/reset:** measured encrypted backup time/space/interruption, decrypt/import
  and restored DB/media parity; old/new format compatibility, salvage, additive upgrade,
  notification/rest-owner reconciliation and reset/deletion failure. Copy a verified full export
  off phone before container/signing/schema changes; a generated file is not a restore test.
- **Alerts:** actual quiet-hours/per-type controls, dated tap routes, alarm, dedupe and
  cancellation; verify the ring/driver/finding/notification agreement already repaired in source.
- **Signing/recovery:** the recorded Sideloadly expiry is 2026-10-17 17:51 local; confirm the
  installed Build 89's own expiry first and re-sign before it lapses, after an off-phone
  encrypted export. Verify installed Build 89 identity, source/version/expiry, current-version
  automatic-refresh enrollment and data/pairing/keychain preservation; natural unattended
  renewal cycles, threshold alerts, failure retry, USB/Wi-Fi recovery and controlled expiry.
  Build 89 recovery promotion is requested but pending; cached Build 70 remains the fallback.
  Keep schema-compatible backups and do not equate cached-artifact selection with phone acceptance.
- **SideStore pilot:** if continued, validate the same signed identity and backup-key readability,
  plus two unattended renewals away from the PC, before moving refresh ownership. Sideloadly
  remains active; this is operational pilot work, not a WHOOP runtime dependency.
- **Developer evidence:** render the actual production Today branches, real platform/font
  settings and populated/partial/failed states. Add meaningful readable-label/number, failure and
  consistency regressions; observation tests that confirm a bug are not regression fixes.
  Run full suites/analysis/native builds on Actions after implementation. The minimal Impeccable
  adapter/helper/first-use hook trust needs developer-tool review only; it is not an app blocker.

### Optional Features, Kept Separate From Repairs

All enhancement ideas from this audit remain in the inventory: pinned Trends metrics; previewed
whole-day meal copying; confirmed finished lift-set corrections; source/date-linked progress
milestones; optional warm-up and RPE/RIR fields if they reduce logging friction. Existing
repeat/copy/portion, set editing during a live workout, rest timers and comparable records should
be reused. Direct links, a shorter valid comparison fallback, selected-state announcements,
Status visibility and backup clarity are existing-feature improvements already listed above.

Deferred research ideas remain optional: personal quiet-HRR substitution, recovery-weight or
TDEE-anchor changes, Kalman smoothing, replacement ML/Cole-Kripke staging, a chest-strap reference
kit and raw optical capture. The raw tail remains off and new hardware is not required.
Three energy-research threads in `todo.md` remain undecided research, not missing features: a
calibrated heart-rate plus movement burn estimate (not approved); what the conservative
maintenance total leaves out; and food-type digestion adjustments. Macro-based low-end digestion
and the separate Lifting line already shipped in Build 84; only further refinement is open.
Programming, global search, social/cloud features, more dashboards, automatic calorie changes,
speculative physiological scores and reviving removed AI coach/journal/Live Activity are not
recommended additions for solving the audited usability problem. Any reopening requires its own
product/capability decision; no private-data upload is proposed.

## Proposed Build 90 Scope And Later Backlog

Recommendations, not accepted implementation:

1. Progress overview/detail restructure, one fixed-window verdict, exact missing-evidence copy,
   chart-only History range, quick weigh-in and contextual links; preserve every existing feature.
2. Required supporting reliability: B90-01 combined-form save safety, B90-02 cross-tab deletion
   invalidation, B90-03 back-gesture parity and B90-04 goal-save recovery.
3. Recommended correctness additions for Build 90: B90-05 historical weights in analysis export,
   B90-06 shared strength estimates, B90-07 macro qualification/share cleanup, B90-08 unreadable
   Food/Train/Progress large-text controls and shared selected-state semantics, and B90-11 honest
   database-versus-media backup descriptions. These repair existing behavior without bundling
   the other tabs' complete redesigns; they remain recommendations awaiting scope approval.
4. Decide B90-10 separately before changing dated food eligibility: freeze the qualifying
   target/provenance (recommended), or explicitly retain retrospective reclassification.
   Do not silently change the approved half-goal/manual-override policy.
5. Fresh populated/empty/partial/failed/large-text previews, source-to-export consistency,
   failure/retry and cross-tab-mutation regressions, plus actual phone workflow/media-restore review.

Later work remains an explicit backlog: Today/Food/Train/Trends complete composition changes
and unmeasured performance optimisation. The current plan recommends the correctness fixes above
for Build 90; none is implemented or approved merely by appearing here. Recommend one focused
visual change per subsequent release with
screenshots, subject to Akshat choosing that release sequence. The standing combined-build
preference is not overridden by a quoted third-party proposal.

Pinned metrics, whole-day food reuse, finished-set correction and milestones are deferred ideas,
not Build 90 scope. No release number, implementation, publication or dependency change is made.

No new metric formula is proposed. Most work is presentation, orchestration or export behavior. Review `kAlgoVersion` only if stored analytics outputs actually change; do not bump it for layout alone. Storage changes for dated counting/finished-set correction need additive migration, salvage/reset/export/backup coverage and clear activation gates.

## Verification Before Calling The App Accepted

- Source-to-display agreement after food add/edit/delete, body save/edit/delete, goal change, workout start/finish/retime/delete and restore. Exercise all entry paths rather than one screen.
- Validation-before-write; injected DB/photo/share errors; accurate failure wording, busy reset and draft preservation.
- All five normal/empty/partial/loading/stale/failed/live states; current font loading and platform flags in captures. Test actual production Today paths, not only injected summaries.
- Normal/2×/3.1× readable values/actions, narrow phone and landscape; actual iPhone text settings, selected-state VoiceOver, keyboard focus/safe area, cancellation and edge-back with/without Reduce Motion.
- Finished workouts and exports use the same strength comparator and nutrient denominators; historical measurement provenance survives while pricing exclusions remain.
- Actual phone gym/locked workout, Food kitchen logging, body/photo encrypted restore, automatic foreground freshness, range loss/return, ordinary termination and reboot/first unlock.
- Overnight/two-hour locked intervals and 72-hour soak with actual data age, calculation age, exits and battery. Snapshot correctness cannot certify BLE execution.
- Build 89's current-version signing enrollment, preserved identity/data/pairing and off-phone encrypted export before recovery-cache promotion. Natural renewal remains a separate gate from choosing a cached fallback.

Full suites/builds remain GitHub Actions work after approved implementation/privacy review; use only small targeted local checks. No local heavy run or mapping is left running by this audit.

## Decisions For Akshat

1. **Progress:** select the three-outcome/compact-inputs recommendation and single closed-week
   goal verdict, with History range restricted to chart/detail exploration. Not selected yet.
2. **Build 90 boundary:** Progress plus the save/refresh/back/export/readability/backup fixes
   recommended above; confirm any proposed later release sequence separately. No go-ahead yet.
3. **Food counting:** choose dated/frozen target evidence or explicitly retain the current policy
   before implementation. Other-tab complete redesigns and optional additions remain deferred.

After these are settled, implementation still needs the explicit go-ahead required by the project's plan-first agreement. The locked palette, five top-level tabs, underlying history and existing unique capabilities remain the default scope.

## Design References And Tooling Boundaries

[Apple Charts guidance](https://developer.apple.com/design/human-interface-guidelines/charts) supports chart clarity tied to context/task and accessibility descriptions; [Apple Tab bars guidance](https://developer.apple.com/design/human-interface-guidelines/tab-bars) supports stable peer-section navigation and weighing added navigation complexity. These are platform references, not evidence that the proposed WHOOP layout has passed a phone usability study. Source lookup used public indexed summaries; the documentation pages themselves require JavaScript in the text browser.

Impeccable native `shape`/`distill`/`layout`/`clarify` provide the design workflow; `harden`/`adapt` cover error/accessibility repairs, followed by a bounded `polish` pass after approved implementation. No browser overlay or web-detector pass is claimed. The pinned engine context ran directly after checksum verification; the PowerShell helper was blocked. It reported an outdated minimal product adapter, which remains a separate tooling choice, not an app blocker; no adapter/hook/trust changes were made.

Resolved composition: A calm framework with B compact macro rows; all UI source is assigned to Codex. Implementation and acceptance status live in `todo.md` and `DESIGN.md`. This audit does not reopen formulas, remove features, cut over AkshatOS ownership, move signing ownership or publish anything.

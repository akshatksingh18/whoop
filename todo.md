# WHOOP Build Plan And Verification

**State:** Akshat reports build `0.9.52`/`85` currently installed. Its complete phone pass and
current-version automatic-refresh enrollment are not confirmed; it remains in `testing`.
Build `0.9.37`/`70` remains the accepted recovery build. Akshat confirmed its phone check
(including build 69's) and current-version automatic-refresh enrollment at the existing signed
identity, with no error. The completed feature checklist is cleared; `CLAUDE.md` and
`metrics-map.md` describe shipped behavior, readiness baseline rules and known limits.

- Current sync evidence (`bugs.md`, "Background sync and slow pull-to-refresh"): real transfer
  gaps recover on foreground launch, although background offloads work in other periods.
  MetricKit confirms background CPU-limit exits for its 8 Oct reporting window, without
  timestamps tying them to individual gaps. Research/source tracing is complete in
  `background-sync-plan.md`; implementation and personal background-mode approval remain open.
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

## Build 86: implementation approved, in progress

**State:** Akshat approved implementation of the whole build-86 scope below as **one build**.
Selected extras: repeat last set, rest timer, comparable records and independent photo
comparisons, plus start/end times, historical body/photo entry, measurement/range controls and a
screenshot-based MyFitnessPal import. The scope also covers weekly/monthly diet/body/strength
insights, navigation/speed/sleep/freshness repairs, safe deletion, custom food labels, both-way
serving equivalents, maintenance-based calorie warnings, general activity/rest protection and a
structural UI redesign. `build-86-audit.md` owns confirmed findings, additional risks and tests.
The confirmed fitness goal is recomposition: leaner while getting stronger. Build 85 remains
installed until a build-86 IPA is published (separate authorization) and installed.

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

**Implemented in source (`0.9.53`/`86`):** sections 1–6, 8 and 9 below, the B86-01..16 repairs,
the Progress tab and Today's Body row; checklist items carry `[x]` when done in source and a note
when partly done. A first build-86 push (`70adc902`, Akshat's approval) passed Linux CI
`38065480698` and personal macOS build `38065492927`; that IPA was **held, not downloaded or
installed**, because the structural redesign (section 8) had been left out. Akshat chose to hold
86 and add it. The redesign and the remaining buildable items are now local commits on `main`
(not pushed): Today/Food/Train redesign, fibre on every macro line, set marks on the lift HR
trace, weekly Body blocks, since-start review, Body height offer on import, reviewed lift
linking, streak edge-case tests, band-data age on Today and the reset fix. Local validation: full
suite 3,499 passed, 400 intentional skips, 0 failed; analysis has no errors or warnings.
Rendered Today/Food/Train pages (`test/build86_redesign_render_test.dart`, synthetic data) were
sent to Akshat for approval. The Swift changes compile only on the macOS CI.
Not built: Pushups (exploration, needs the Home auto-pause decision), a numeric intake-adjustment
rule (needs Akshat's rule), the optional conveniences (proposals) and per-input calculation
invalidation (left unchanged: it is derivation-engine work that the plan gates on measuring
short-wake compute on the phone first). Private MyFitnessPal import generated and validated
locally (`../../health/fitness/data/whoop-body-history-import.json`). Next gates, in order:
Akshat approves the rendered redesign; his approval to push and rebuild 86; IPA validation;
promote build 85 (or keep 70) as rollback and take a rollback-readable export; install; phone
acceptance.

Also in build-86 source, at Akshat's request:
- Every search field (Foods, the food log, the saved-meal picker, the activity picker and the Lift
  exercise search) has a × that clears it in one tap, shown only while it holds text
  (`OsTextField.clearable`).
- Fibre is never left off: every compact macro line (meal cards, the meal page, the log-food list,
  pickers, Food history) prints `P · C · F · Fb` once any macro was logged, and a missing one reads
  `–` (`macroParts` in `food_picker.dart`). The day card's four totals do the same.

### 1. Background sync and fresh insights during brief daily use

**Approved for build 86; in progress.** Target: Akshat's iPhone 17 /
iOS `26.6.2`, with only two or three minutes of app viewing per day. Keeping WHOOP visible,
continually refreshing or charging all day must not be required. The supplied gap's force-quit
state is unknown. `background-sync-plan.md` owns the public Apple sources, source findings,
capability boundaries, safety invariants and detailed acceptance checks.

Implementation checklist:
- [x] Resolve native lifecycle before scheduler/bootstrap work and guard every foreground-session
   entry. Coordinate queued native wakes with AppState so startup has one band owner.
- [x] Cancel actual in-flight calculation on ordinary backgrounding; preserve committed results
   and requeue unfinished work without pruning, finalizing or marking cancellation successful.
- [x] Keep short BLE wakes transfer/commit/ACK-first. Replace the fallback's unconditional full
   light derive with queued calculation; propagate expiration, retire old workers and bound
   ownership handoffs without overlapping ACKs or orphaned work.
- [ ] Preserve passive wrist steps and active workouts. Remove invisible UI work and profile
   the high-rate path; no silent HR-only switch, sparse-step reconstruction or metric deletion. *Source: background UI notifications coalesce; high-rate-path CPU profiling still needs the phone.*
- [ ] Reuse unaffected calculation, prioritize today/new sleep, and keep raw-data freshness
   separate from the input revision covered by an insight. Short-wake compute must be measured
   and genuinely bounded; the current one-day "light" pass does not meet that contract. *Source: today is derived first, BLE wakes queue work, and Today shows band-data age apart from the calculation time; per-input invalidation is not changed (measure short-wake compute on the phone first).*
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
   locked two-hour/overnight use, brief visits, termination/range recovery and a 72-hour soak. *Source: native breadcrumbs in openstrap_native.log; device verification open.*

Decided: implement the repair and add personal `fetch`/`processing` modes with bounded work.
No extension, App Group, HealthKit, cloud service or feature removal. If preserved wrist capture
itself still exceeds the measured budget, present the phone-absent step tradeoff for a separate
decision before changing its policy.

### 2. Lift Log inside the existing WHOOP workout

**Approved for build 86; in progress.** Akshat wants
to explore one workout that behaves as WHOOP does now and also offers AkshatOS Lift Log's
features. `lift-log-integration-plan.md` owns the current-source findings, recommended flow,
parity inventory, timing conflicts, data import/recovery and tests. AkshatOS remains unchanged
until a separately approved transition; `../akshatos/hub-plan.md` records that boundary.

Accepted direction: choose a split or Empty workout in Lift setup, then use one WHOOP session ID,
clock, Pause/Finish and summary, with exercises/sets and previous performance inside the live
workout. Tracking without set logging remains possible; runs/walks retain their flow. Reuse the
existing Flutter strength/session foundation, but do not merely enable the old sets UI: it lacks
Lift Log's split/load-mode contract, and its row replacement does not delete omitted sets.

Proposed implementation checklist, conditional on approval:
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

**Approved for build 86; in progress.** Akshat wants
WHOOP to become his all-in-one body/fitness app, including AkshatOS Body's weight, measurements
and photos alongside lifting, food and wearable context. `fitness-app-plan.md` owns the whole-app
flow, evidence/comparison rules, current source gaps, import/recovery and optional future ideas.

Accepted overall direction: keep Today / Trends / Food / Train and add a planned Progress tab,
with Body entry/history inside it; no navigation has shipped. Preserve all reachable metrics.
One `body_weight` path feeds Body, Food and Progress. One
Lift workout owns both sensor context and sets; no duplicate starts, calories or stores.

Proposed implementation checklist, conditional on approval:
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
  food is not zero. Exact numeric guidance rules need review before activation.
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
- [ ] Review exact allowance, retroactive use, qualification thresholds and Pushups contribution
  before implementing. Candidate: one unplanned protected day per rolling week, no consecutive
  protections; this is a proposal, not an accepted rule. Offer weekly consistency as a candidate. *Implemented the proposed rule (at most 2 protected days per rolling 7, at most 1 Life happens, none consecutive); Akshat can change it.*
- [x] Avoid all-history/per-day query growth when adding sources; test overlap, edits/deletes,
  imports, timezone/DST, today-at-risk, exhausted protection and restored history. Pending sync
  is not proof of inactivity; reconcile late activity/protection without duplicate awards. *Source: one indexed sessions query per load; tests cover overlap, delete, late activity on a protected day, step-goal plus protection, month end/clock change, today open and the allowance.*

### 7. Pushup Reminder exploration inside WHOOP

**Requested exploration, not approved port/cutover.** `fitness-app-plan.md`, the audit and
`../akshatos/hub-plan.md` record the boundary; `../akshatos/features.md` owns full parity.
- [ ] Plan Train -> Movement breaks / Pushups, compact Today Start/Done access, its own goal/
  streak/history, and Progress context. A reminder day must not start a second workout clock
  or infer reps/duration/HR/calories from a Done tap.
- [ ] Map Start/Pause/End, interval/nudges, captured daily goal, protected action inbox,
  idempotent locked/cold Done/Pause, notification-tap routing, history/settings and recovery.
- [ ] Design one early WHOOP notification coordinator and shared pending-request budget for
  Pushups/rest timers/Body/existing critical alerts. Do not replace Flutter's delegate, cancel
  other modules' requests or promise indefinite ignored reminders from a finite queue.
- [ ] Resolve Home auto-pause explicitly: AkshatOS uses Always location, outside WHOOP's current
  personal contract. Decide optional capability/parity rather than silently dropping it or
  requesting it for walking. Preserve AkshatOS unchanged until a separately approved transition.
- [ ] Plan previewed/idempotent local import with no automatically restored active reminders;
  require recovery and phone-action acceptance and deliberate stopping of the old reminder
  batch before opting into the new one. No background two-app synchronization is proposed.

### 8. Structural UI redesign and whole-app convenience audit

**Implemented in build-86 source; rendered pages await Akshat's approval.** No metric or entry
point was removed.
- [x] Prototype brief Today review, diary/editing, Start/Resume Lift/Walk, Body historical/photo
  flow and one combined Progress review. Change hierarchy/composition and interaction, not only
  card colour/ring styling; retain every unique reachable metric and existing entry point unless
  Akshat approves its removal individually. *Source: rendered at phone width, 1x and 2x text, by `test/build86_redesign_render_test.dart`.*
- [x] Use compact date/freshness/status and a useful HR canvas on Today, stable session controls
  and safe history on Train, diary-first Food with portions/maintenance context, and body/strength
  summary with integrated weekly/monthly review on Progress. No separate app-in-app shell. *Source: Today has a compact header with band-data age or Syncing/Calculating, recovery/sleep/strain in one card (stacked at large text), HRV and resting HR, a 112 pt HR canvas with hour marks, then steps/food, Body and maintenance. Food opens on one day card (calories, all four macros, fixed Add to <meal by time of day>), then the meals, then maintenance. Train shows Resume instead of Start while a session runs, history before the charts and one fixed options menu (Fix the times / Delete) per row.*
- [ ] Audit all routes/back gestures/day arrows, stable controls, hit targets, large text/small
  screens, safe areas, tab changes, selected day/filter/scroll state, permission/error/retry and
  loading/empty/stale/partial/offline states; compare screenshot/hit-target QA before release. *Partly: Today/Food/Train render without overflow at 1x and 2x, the 44 pt tap sweep passes on the gallery, large-text wrapping fixed in the maintenance and HR headers; back gestures and saved scroll/filter state need the phone.*
- [x] Repair weekly protein completeness/denominators and selected-window excluded-day counts
  (B86-11) before reusing the existing Week card for the combined insight engine.
- [ ] Review optional conveniences: Jump to Today/calendar, pending-work drawer using existing
  Status, Return to workout across tabs, recent personal labels, explicit Food-day completeness,
  due-measurement shortcut and opt-in review reminders. These are proposals, not selected scope;
  effort ratings, programming and removed AI coach/journal/Live Activity remain deferred/removed.

Optional conveniences stay proposals; approval of build 86 does not remove features or authorize
publishing an app. Pushups (section 7) stays exploration until Akshat confirms a port and the
Home auto-pause capability choice.

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
the PC and phone. Sideloadly stays the active refresher until the pilot passes. Run it on the
current, unchanged installed IPAs (WHOOP 85, AkshatOS 34) before Build 86 is installed, so a
signing failure and a Build 86 regression are never tested at the same time. AkshatOS moves
first; LocalDevVPN is allowed on the phone as SideStore's installer helper, never inside WHOOP.
- [ ] Before the pilot: verified WHOOP encrypted export copied to Windows and an AkshatOS full
  backup with photo count checked; record each app's signed identity and expiry.
- [ ] After the first SideStore re-sign of WHOOP: same final bundle ID, data intact, band still
  paired, automatic-backup passphrase still readable (keychain), Status shows the new expiry.
- [ ] Two unattended SideStore renewals away from the PC with advancing expiry and preserved data;
  then decide adopt, keep as fallback, or remove. Adoption updates `guides/IOS_SIDELOAD.md`,
  this file's refresh gates and the signing health check in the same change.

### Combined Approval And Release Gates

- [x] Plan reviewed; implementation approved as one build, with the decisions listed at the top
  of this section. Pushups capability/parity remains open.
- [ ] Implement the approved scope together; run focused regressions, the full suite and
  personal-iOS payload/capability checks, and synchronize affected documentation.
- [ ] Obtain separate publication/build authorization, then validate the replacement IPA's
  source, version, manifest, checksum and payload before installation.
- [ ] Complete feature and background phone acceptance before cache promotion; build 70
  stays recovery and build 85 remains the installed candidate until a replacement is installed.

## Build 85 (`0.9.52`/`85`): installed (Akshat), awaiting phone acceptance

Build-85 source `0.9.52`/`85` (commit `3c141b7a`) is published with Akshat's approval; Linux CI `37816259505` (3,430 tests, 395 intentional skips) and personal macOS build `37816260577` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Akshat reports it currently installed. The sole testing candidate remains `../final-ipas/whoop/testing/WHOOP-0.9.52-build85-3c141b7a` until its phone pass and current-version refresh enrollment are confirmed; build 70 stays accepted recovery.

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
  are appended to `openstrap_exits.log` in Files → WHOOP (`ExitReasonLog`, Swift).
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
night, `openstrap_sync.log` shows `[launch] background` relaunches without heavy passes, and
`openstrap_exits.log` appears after a day or two.

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

Build-83 source `0.9.50`/`83` (commit `cbaf93cd`) is published with Akshat's approval; Linux CI `37717941508` (3,408 tests, 371 intentional skips) and personal macOS build `37717959148` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. The sole testing candidate is `../final-ipas/whoop/testing/WHOOP-0.9.50-build83-cbaf93cd`.

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
Then: after an hour in the background and one pull-to-refresh, share `openstrap_sync.log` to time
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
- **Food → Foods search:** filters saved meals and My foods by name (and brand); dragging is off
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
  actually writes (`openstrap_sync.log` in Files → WHOOP); pull-to-refresh logs each stage's
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
calories for treadmill/other workouts. Build-78 source `0.9.45`/`78` (commit `1eae1fbc`) is published with Akshat's approval; Linux CI `37558355571` (3,380 tests, 371 intentional skips) and personal macOS build `37558356341` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. The sole testing candidate is
the build-78 testing folder until build 79 replaced it. `build-75-audit.md` ("Build-78 audit and
implementation") owns the decisions, research and implemented list.
Phone checks: log the sausage as 3 links (reads "3 Links · 213 g", macros scale) and in grams;
a per-link food with "1 link weighs" switches to g; one hold drags into "No sub-heading";
Training review gone from Train/Settings; Recent shows five compact rows, All workouts groups by
month; a gym session shows a lower active figure than before; a treadmill session shows
distance-method calories.

## Build 77: build-76 follow-up, published and built

Akshat installed build 76; his follow-ups are recorded at the end of `build-75-audit.md`.
Build-77 source `0.9.44`/`77` (commit `2602cacf`) is published with Akshat's approval; Linux CI `37539992141` (3,375 tests, 371 intentional skips) and personal macOS build `37539992599` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. The sole testing candidate is
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
ZIP and payload validation pass. The sole candidate is
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
- Build 85 is installed (Akshat); confirm the same signed identity, encrypted history, decimals,
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
testing IPA after validation; subsequent candidates superseded it, with build 85 now installed.
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

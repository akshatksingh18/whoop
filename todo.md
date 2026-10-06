# Remaining WHOOP verification

**State:** Build `0.9.37`/`70` remains the accepted recovery build. Akshat confirmed its phone check
(including build 69's) and current-version automatic-refresh enrollment at the existing signed
identity, with no error. The completed feature checklist is cleared; `CLAUDE.md` and
`metrics-map.md` describe shipped behavior, readiness baseline rules and known limits.

- Build `0.9.40`/`73` is installed, confirmed by Akshat, and initially looks good. The Strain cursor
  still selects future times; `build-74-audit.md` records the wider graph/navigation/notification
  findings and calorie-model research, with the implemented build-74 scope below.
  The complete phone pass and current-version refresh enrollment are not confirmed.
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

## Build 77: build-76 follow-up (local source, not yet published)

Akshat installed build 76; his follow-ups are recorded at the end of `build-75-audit.md`.
Source `0.9.44`/`77` implements them locally; publication and the IPA need Akshat's go-ahead.
Phone checks: Calories "left" at the far right; no OpenStrap at launch; "No sub-heading" only
appears while dragging; pull an edit sheet down from mid-content and it closes.

## Build 76: build-75 follow-up, published, built and installed (Akshat)

Akshat installed build 75 and reported the follow-ups recorded at the end of
`build-75-audit.md`: float-noise numbers in Edit food, − / + step and hold-to-repeat, dragging
items between sub-headings (meals and saved meals) and the Calories card layout. Build-76 source `0.9.43`/`76` (commit `3f8ada60`) is published with Akshat's approval; Linux CI `37534408576` (3,373 tests, 371 intentional skips) and personal macOS build `37534409412` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. The sole testing candidate is `../final-ipas/whoop/testing/WHOOP-0.9.43-build76-3f8ada60`;
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
- Install over build 73 with the same signed identity; confirm encrypted history, decimals,
  saved foods/meals, band pairing and current-version automatic-refresh enrollment intact.
  The extension's free-team signing/refresh must work before cache promotion.
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
- Run/Walk Live Activity: locked screen/Dynamic Island, pause/resume, fresh/stale HR/pace,
  GPS loss, music/calls/headphones, end/discard, termination/recovery and exact-session tap.
  Native success is not proof of background delivery. Verify existing kilometre speech too.
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
testing IPA after validation; build 74 is now the candidate.
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

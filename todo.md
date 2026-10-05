# Remaining WHOOP verification

**State:** Build `0.9.37`/`70` remains the accepted recovery build. Akshat confirmed its phone check
(including build 69's) and current-version automatic-refresh enrollment at the existing signed
identity, with no error. The completed feature checklist is cleared; `CLAUDE.md` and
`metrics-map.md` describe shipped behavior, readiness baseline rules and known limits.

- Build `0.9.39`/`72` is installed, confirmed by Akshat, but not accepted. He reports background
  voice cues delayed until foreground and supplied sync/calorie/macro/profile issues. The current
  installed build-72 streak does not count step-only goal days. `workout-sync-audit.md` owns findings and proposed
  repairs; the approved build-73 implementation below passes local validation.
- Today refresh updating steps is confirmed on build 72. Maintenance consistency remains open:
  Akshat reports unchanged calories; the main Food card updates in an isolated real-repository
  probe, but an already-open maintenance breakdown remains stale. The report owns this distinction.
- Complete the broader physical-device matrix in `CLAUDE.md`, including locked/background route
  recording, range-loss restoration, system termination, overnight collection and the 72-hour soak.
- Verify naturally elapsed unattended refresh cycles, the alert thresholds, Wi-Fi/USB recovery
  and controlled expiry recovery. The previously forced-due refresh and current-version enrollment
  do not prove the long-term schedule.

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
passes local payload validation. It is cached as the single testing candidate; `setup.md` owns
the source, hash and artifact path. Akshat confirms build 72 is installed; installation alone does
not close its phone pass or current-version enrollment gates.
The superseded build-71 artifact lacks the refresh fix; keep one install candidate.

Before promoting build 72:
- Installation is confirmed. Confirm signed identity, data and pairing continuity separately.
- Force-close from Food/Trends and relaunch: Today opens. Warm resume retains the current screen.
- Scrub Sleep and Food charts: every selected value/unit is visible, including enlarged text;
  Deep matches the legend and Night details expands cleanly.
- Add from My foods; Scan goes directly to the camera/product review. Denied camera access offers
  Quick add. Check manual entry, fibre, blank optional macros, explicit zero, entry editing and Undo.
- Expand an older history month and backdate a saved meal; verify its day/time and summary coverage.
- Edit food and return to Today: Weekly updates without a pull; check foreground/day-rollover refresh.
- Walk with the phone, then refresh Today: its steps, step detail, today's chart and step-based
  maintenance update together. Repeat with the band disconnected/slow and check status messages;
  HR-derived figures need new band data and may wait during capture or a live workout.
- Today step-number refresh is reported working; verify the corresponding step kcal in Food,
  an open breakdown and history, including rounding and completed-run deductions.
- Confirm completed current-version automatic-refresh enrollment with no install error, then promote
  the one testing candidate and update the accepted-build ledger. Keep build 70 until these gates pass.

## Build 73: approved combined repair

Source `0.9.40`/`73` (algorithm 89) is implemented locally and passes release validation.
Public publication, CI and the single macOS IPA require separate named-destination approval.
Build 70 remains accepted; installed build 72 remains the cached testing artifact until replacement.

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
320-point screen at 1.5x text. No build-73 IPA or phone verification is claimed.
`workout-sync-audit.md` records the build-72 evidence and repair contract.

Build-73 phone acceptance must cover:
- Same-identity install, retained food/templates/weights/steps, pairing and encrypted restore.
- Locked and other-app kilometre cues, pause/resume, headphones, music, podcasts and calls.
- Phone carried/desk/absent, source handoff, local midnight, low wrist motion and range loss;
  compare connected wrist fallback against hand-counted steps and observe battery use.
- Step-only streak, exact threshold, raise/lower before and after completion, late steps/restart.
- Today manual/foreground refresh updates step kcal and maintenance in every open view; profile,
  meal and completed-workout changes update automatically. Fixed food target stays unchanged.
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

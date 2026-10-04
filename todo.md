# Remaining WHOOP verification

**State:** Build `0.9.37`/`70` is installed and accepted. Akshat confirmed the phone check
(including build 69's) and current-version automatic-refresh enrollment at the existing signed
identity, with no error. The completed feature checklist is cleared; `CLAUDE.md` and
`metrics-map.md` describe shipped behavior, readiness baseline rules and known limits.

- Get a separate result for spoken km cues with the screen locked; the personal profile has no
  audio background mode. Record the observed behavior before deciding on any capability change.
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
The refresh repair is not published or present in that earlier IPA; the revised version is `0.9.39`/`72`. A revised source commit and replacement personal
IPA need publication approval for public `akshatksingh18/whoop`; keep one install candidate.

Before promoting build 72:
- Complete Linux CI, one macOS personal IPA build, downloaded checksum and local payload validation.
- Install over accepted build 70 using the existing signed identity; confirm data and pairing remain.
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
- Confirm completed current-version automatic-refresh enrollment with no install error, then promote
  the one testing candidate and update the accepted-build ledger. Keep build 70 until these gates pass.

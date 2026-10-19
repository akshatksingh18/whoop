# Build history

The build-by-build notes `CLAUDE.md` carried through Build 94, moved here verbatim in Build 95
so `CLAUDE.md` states only the current state. History only: nothing here is current guidance,
and `setup.md` remains the owner of artifact and CI evidence.

**Status:** Active iPhone verification: Akshat reports Build `0.9.57`/`90` installed and being tested on
his iPhone 17 (iOS `26.6.2`), replacing Build 89. Build `0.9.58`/`91` (algorithm 97, branch
`build-91`) carries his first Build 90 findings, the Progress time rule and the triaged Codex
audit fixes (`todo.md` 3c-3e). Build 89 (algorithm 93, source `77d6a365`) is published; Linux CI
`38494407678` and personal macOS build `38495939393` pass; its IPA left the testing slot when Build 90's
validated candidate replaced it (reproducible from that run; moved to the Windows Recycle Bin, not
hard-deleted). It
repairs the nightly HRV his first Build 88 nights exposed, renames everything the app shows or
names from OpenStrap to WHOOP, makes steps phone-only and live streams heart-rate-only, reworks
Progress and the Food card, counts food days automatically and adds an AI-analysis export
(`todo.md` Build 89). Build 88 was the previous install. Akshat wants Build 89 as recovery after
the whole-app review; Build 70 remains cached recovery until that promotion. Build 90
(`0.9.57`/`90`, algorithm 96, schema 50) contains the engine/data work, approved research,
reviewed Progress/Body/Lift workflows and A overall with B's whole calorie/macro card, all on
`build-90`. Akshat's calorie decisions are in source: running Budget 0.17 mL/kg/m, Keytel
priced only inside its fitted heart-rate range, and stored workout calories that are the
active figure the screens show (`sessions.calories_basis`, with a selective repair of older
rows). The remaining Build 90 UI audit items are fixed. Claude now carries all remaining Build 90
work (Codex is no longer needed). Akshat's mockup picks are built: Recovery explains each input's
points against its usual range with a Recent HRV card (shared with the HRV page), and the food
screen shows what is left of the day after the amount being chosen, with "Fit what's left".
`todo.md` and `build-90-audit.md` own checks and the full-page review. Build 90 (source
`381dce57`, macOS run `38846696668`) is the installed build. Build 91 (source `40611c52`, macOS run `39086037034`) is installed. Build `0.9.59`/`92` (source `3c1cf3a8`, macOS run `39118323380`) fixed Codex's Build 91 re-audit findings and Claude's end-to-end sweep (`todo.md` 3g); it was never installed. Build `0.9.60`/`93` (algorithm 97, schema 50 with the additive `session_detail` table) fixes Codex's Build 92 interaction audit and its full-flow audit of `9b609cd9` (`todo.md` 3h); it was never installed. Build `0.9.61`/`94` (source `9d664632`, Linux CI `39172587592`, macOS run `39174734367`) carries Claude's whole-app end-to-end audit and cleanup, Codex's audit of that candidate and Akshat's Food delete/Quick add requests (`todo.md` 3i); its validated IPA is the single testing candidate `final-ipas/whoop/testing/WHOOP-0.9.61-build94-9d664632`, not yet installed. Local synthetic renders establish no phone
acceptance. Phone checks and acceptance remain open. Akshat rejects Progress's information overload;
structural design acceptance has failed. `build-87-ui-plan.md` owns the source/screenshot audit,
feature-preserving replacement composition and phone-sized review gates; `todo.md` owns the
Build 87 checklist. Akshat approved implementation, including a peaceful warm palette. Published
and built source `b0eee377` is `0.9.54`/`87`: warm graphite with richer emerald/turquoise/coral accents, task-specific compositions, dated Progress views,
per-input calculation reuse and wear-aware link recovery. The approved recent-HR, direct diary
portion editing and workout-filter additions, plus latest freshness/cold-connect/empty-burst
repairs and calorie/protein meal-group summaries pass local and cloud checks. Akshat approved
publication to the public `akshatksingh18/whoop` repo and the testing IPA. Source/version,
checksum, ZIP and personal payload validation passed; Build 87 was never installed and its
testing folder is superseded by the Build 88 candidate. `setup.md` owns artifact evidence. Sideloadly records current-version automatic-refresh enrollment, no error and
expiry 2026-10-17 at 17:51 local. Build `0.9.53`/`86` (source `651345e7`) passed Linux CI `38090036814` (3,539 tests, 399 intentional skips) and personal macOS build `38090037024`; the downloaded IPA matches its checksum and manifest and passes the payload validator. It was installed before Builds 88/89; its former testing folder is superseded by the validated Build 87 candidate. It brings bounded background sync with real calculation
cancellation and personal `fetch`/`processing` tasks, Lift Log inside the Lift workout, Body and a
  fifth Progress tab, the B86-01..16 repairs and the UI redesign rejected at structural acceptance. `todo.md` owns its
decisions, implemented/open items, phone checks and gates; `build-86-audit.md`,
`background-sync-plan.md`, `lift-log-integration-plan.md`, `fitness-app-plan.md` and
`fitness-goal-research.md` own their contracts. AkshatOS keeps its modules and entry ownership
until import and combined phone acceptance. Build-86 source also ports Pushups (with Home auto-pause), strength
progress inside the live workout, flexible goals and the optional conveniences Akshat chose; AkshatOS
Pushups stays installed and unchanged until import and phone acceptance. A SideStore signing pilot is approved
(`../akshatos/sidestore-evaluation.md`), with laptop setup reported; on-phone handover and renewal
remain unconfirmed. No refresh ownership changes were made by this check.

Build 88 (`0.9.55`/`88`, algorithm 92) is published as source `0f48c56f` with Akshat's
approval; Linux CI `38329137774` (3,703 tests, 415 intentional skips) and personal macOS build
`38329490196` pass, and the downloaded IPA passes source/version, checksum, ZIP and payload checks.
Akshat's screenshots show it installed; Build 89's candidate replaced its testing folder. Akshat approved `build-88-proposal.md` with every recommendation and
locked `DESIGN.md` (light kraft ground, cream panels, family colours). All twelve packages are in
source: temperature integrity, observed-day load and a withheld strain target, timestamp-adjacent
HRV with frozen gates, sleep/breathing coverage, sync freshness and lifecycle bounds, live speed,
food/energy completeness, strength and advice qualification, honest alerts, the good-to-have set
and the redesign (every main screen rebuilt to the locked mocks, visually checked for legibility). `todo.md` owns what is done and the open decisions and phone gates; `build-88-plan.md`
the specifications; `bugs.md` what each repair closed. Impeccable stays developer tooling only.
`metrics-accuracy-research.md` owns detailed evidence, including the expanded local HRV/strength
audit. Physical accuracy validation remains open; the indexed accuracy/design prompts are
reusable briefs, not authorizations.

Build `0.9.37`/`70` remains accepted after
Akshat confirmed the feature phone check and current-version automatic-refresh enrollment; it is
the recovery/refresh build in `final-ipas\whoop\backup\`. Build `0.9.39`/`72` was installed,
confirmed by Akshat, but was not phone-accepted and is superseded by the build-73 candidate.
The reported sync/voice/calorie/macro/profile
issues are audited in `workout-sync-audit.md`, with the approved step-goal streak extension documented there.
Today refresh updating steps is confirmed; maintenance consistency and the stale open breakdown
are addressed in build 73, pending its phone verification.
Source `0.9.40`/`73` (algorithm 89), commit `a49d7837`, is published with Akshat's approval and
passes local validation, Linux CI `37252915519` and personal macOS build `37252925924`.
The downloaded IPA matched its checksum/manifest and passed payload validation; its testing folder
was removed after build 74 validated. Its source/hash/workflow evidence remains in `setup.md`.
Akshat confirms build 73 is installed and initially looks good, but reports chart/navigation and
notification issues. Source `0.9.41`/`74` (algorithm 90) implements the approved coordinated
repair and persistent Budget/ACSM pair, with HR retained only for analysis. It includes accepted
phone motion-distance windows, focused dated notification routes, an opt-in local training review
and one workout-only Live Activity extension without App Groups. Live cadence, optional context
tags, qualified HR drift, recorded consistency/best efforts and fourteen-day notification spacing
are included. Foreground refresh re-reads session movement; deletion/Undo notices expire in two seconds. `build-74-audit.md` owns the
research/implemented contract; `todo.md` owns release/phone gates. Local validation passes:
3,343 full-suite tests (376 intentional skips), 107 personal-profile checks and eight personal-iOS
contract tests; analysis has 113 informational lints and no errors/warnings. Rendered layout checks pass;
Source `ba5bb29f` is published with Akshat's approval; Linux CI `37397127258` and personal macOS
build `37395690305` pass. Downloaded source/version, checksum, ZIP integrity and payload checks
pass, including the single version-matched workout extension. Akshat reports build 74 installed;
it was not phone-accepted. His first-use report (no Live Activity, Trends day/range navigation,
Food workflow, day-breakdown noise, calorie verification) is audited in `build-75-audit.md`,
which also holds his decisions D1–D8 and the implemented list. Source `0.9.42`/`75` (commit `1c203f17`) is published with Akshat's approval; Linux CI `37514558854` (3,369 tests, 371 intentional skips) and personal macOS build `37514599309` pass. Downloaded source/version, checksum, ZIP integrity and payload/extension checks pass.
Akshat reports build 75 installed and sent food-flow follow-ups. Build-76 source `0.9.43`/`76` (commit `3f8ada60`) is published with Akshat's approval; Linux CI `37534408576` (3,373 tests, 371 intentional skips) and personal macOS build `37534409412` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass.
Akshat reports build 77 installed. Build-78 source `0.9.45`/`78` (commit `1eae1fbc`) is published with Akshat's approval; Linux CI `37558355571` (3,380 tests, 371 intentional skips) and personal macOS build `37558356341` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Build 78 adds two-unit portions, one-press drag,
hidden Training review, compact Train history and conservative workout calories; it was never installed. Build-79 source `0.9.46`/`79` (commit `4b7f5918`) is published with Akshat's approval; Linux CI `37563199102` (3,386 tests, 371 intentional skips) and personal macOS build `37563205812` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Build 79 adds pack-printed servings ("6 piece · 85 g" without dividing); Akshat reports it installed. Build-80 source `0.9.47`/`80` (commit `6dd75b2b`) is published with Akshat's approval; Linux CI `37565878253` (3,386 tests, 371 intentional skips) and personal macOS build `37565879521` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass. Build 80 aligns the food editor's serving row and removes its Other units section. Akshat reports build 76 installed and sent follow-ups. Build-77 source `0.9.44`/`77` (commit `2602cacf`) is published with Akshat's approval; Linux CI `37539992141` (3,375 tests, 371 intentional skips) and personal macOS build `37539992599` pass; downloaded source/version, checksum, ZIP and payload/extension checks pass.
Akshat reports build 80 installed; its follow-up requests (Quick add weight, recovery inputs, sleep detection, full-app review) are audited in `build-81-audit.md`. Build-81 source `0.9.48`/`81` (algorithm 91) implements his decisions: Quick add weight/all macros/Save to My foods, sleep as a fifth readiness input, the Readiness ring fix, What-moves-it from logged data, bedtime consistency, the Monday last-week card, shorter text and removal of the never-working Live Activity extension; sleep detection is unchanged. Build-81 source `0.9.48`/`81` (commit `d44c989f`) is published with Akshat's approval; Linux CI `37699481094` (3,398 tests, 371 intentional skips) and personal macOS build `37699482851` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension in the IPA. Build 81 was never installed. Build-82 source `0.9.49`/`82` (commit `4b53abbe`) is published with Akshat's approval; Linux CI `37708103583` (3,406 tests, 371 intentional skips) and personal macOS build `37708104201` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build 82 adds page-scrolling drag, a discard guard on edit sheets, Foods search, the saved-meal flow fixes and a working iPhone app log (`todo.md`); Akshat reports it installed. Build-83 source `0.9.50`/`83` (commit `cbaf93cd`) is published with Akshat's approval; Linux CI `37717941508` (3,408 tests, 371 intentional skips) and personal macOS build `37717959148` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build 83 time-stamps the app log, stops overlapping log lines overwriting each other and makes the history sync ask the band when no transfer is running. Build-84 source `0.9.51`/`84` fixes stale Today numbers (revision bump when today's row lands and after the readiness rescan), keeps iOS Bluetooth relaunches on the light background path (UIKit launch state), ends pull-to-refresh once today is calculated, checks background offloads every 5 min, logs MetricKit exit reasons to `openstrap_exits.log`, prices digestion by macro at the low end and adds a separate Lifting line (`todo.md`). Akshat's build-83 log shows build 83 installed. Build-84 source `0.9.51`/`84` (commit `37241c1e`) is published with Akshat's approval; Linux CI `37780752762` (3,415 tests, 371 intentional skips) and personal macOS build `37780753121` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build-85 source `0.9.52`/`85` (`build-85-audit.md`, `todo.md`) implements Akshat's audit decisions: one MET-only lifting number everywhere, day measures that never borrow another day, food categories, walks in km/h and a full UI makeover. Build-85 source `0.9.52`/`85` (commit `3c141b7a`) is published with Akshat's approval; Linux CI `37816259505` (3,430 tests, 395 intentional skips) and personal macOS build `37816260577` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build 84 was not reported installed; build 85 replaced its testing folder.
Build 85's testing folder was superseded by Build 86, Build 87 and now the Build 88 candidate above;
`todo.md` owns the gates. `setup.md` owns
artifact evidence. The replacement includes direct My foods scanning and shared editable meal-scan
review, manual fallback and confirmation before persistence/logging. CI passes at test-only repair
`fa16be3c`, whose app/packaging inputs match IPA source `ba5bb29f`. `todo.md` owns phone gates.
Broader lifecycle, background and multi-cycle signing gates remain before daily-use activation.

Build 65 was installed after a clean same-identity reinstall. A passphrase-encrypted build-63 export was restored into an
isolated test install before the old container was removed, then restored into build 65; Akshat
confirmed the recovered app works. Build `0.9.34`/67 was accepted and is now superseded by build 70; build 63 (sanitized-history
source `7132d2ab29a007da9e650ef802e7340a0cf39677`) is superseded.
The initial roughly-6,000-versus-200 step mismatch was the disabled **This phone → Steps** setting;
enabling it verified that the direct `CMPedometer` path imports iPhone steps. The profile still
deliberately excludes the Apple Health aggregate. Build 65 retains the personal GPS/Oura changes
from the uninstalled build-64 artifact and records zero-step phone windows so confirmed phone
stillness can veto low-density wrist false positives. Build 64 is superseded and must not be
installed. Build 65 passed the macOS workflow, payload validator, downloaded SHA-256 check, fresh
install, encrypted restore, and launch checks. A temporary bundle-ID copy also installed
successfully, proving the IPA/framework payload is installable. A backup/delete/clean-install/restore
cycle with automatic refresh enabled created a completed scheduled registration and Akshat confirmed
the data works. The original refresh failure was isolated to Sideloadly v0.60's **Use automatic
bundle ID** path: the same production overwrite reached 100% when that option was disabled and the
exact final ID `com.akshat.personal.whoop.5564K8D4SV` was entered. Its signing time advanced and data
and band pairing remained intact. A controlled forced-due daemon cycle then refreshed WHOOP over
Wi-Fi with USB disconnected and no GUI/manual refresh command; the health task logged `REFRESHED`
and `ENROLLED`, and the subsequent real-app launch confirmed its data and band connection intact.
The next naturally elapsed cycle, About/version, phone-step retention, GPS and background behavior
still need confirmation.
Keep phone steps enabled for normal iPhone-carried use; WHOOP 4 band-only historical data is too
low-rate for honest all-day step reconstruction. Background/recovery, GPS, and other device gates
remain before daily use. Android development is out of scope.
Superseded `0.9.33`/`66` (commit `648c1b2e`) passed the Linux test suite, macOS workflow,
downloaded-checksum and payload-validation gates. It was installed over build 65 but never promoted;
it is no longer cached and is reproducible from its workflow record in `setup.md`. It simplifies the UI:
Nerd stats, the Wellness tab, the journal, water logging and Health → Labs are removed, and Vitals
is folded into Overview. It adds a scrubbable all-day heart-rate chart, a cleaner Sleep screen and a
rebuilt Nutrition log (saved meals, foods by grams, macros, month history), and keeps the sleep-breathing card and the
training-load part of sleep need. It also adds the Status screen with 48 h/24 h
signing-expiry alerts, encrypted automatic backups, GPS route-recording hardening, and the iOS
restore-wake reconnect fix recorded in `bugs.md`. Its unverified device behavior remains part of
the current candidate's acceptance checks; installation alone did not verify those features.
Accepted `0.9.37`/`70` (commit `d8fc8eea`) is **installed and phone-accepted**
(Linux tests and the macOS workflow passed; the IPA matches its SHA-256 and passes the validator;
cached under `final-ipas\whoop\backup\WHOOP-0.9.37-build70-accepted`). Akshat confirmed the
phone check, including build 69's, and completed automatic-refresh enrollment for `0.9.37` at
`com.akshat.personal.whoop.5564K8D4SV` with no install error. `testing\` now holds the uninstalled Build 90 candidate; earlier candidates are superseded.
It adds:
- **Charts:** the 30-day drag bug is fixed. The dotted version marks sat on top of the chart and
  swallowed touches. In the personal build those marks, the locked-range line and the Worn bars are
  gone.
- **Sleep:**
  - The stage names appear once, and the drag readout in the header carries bpm, HRV and temp.
  - Overnight signals are three clean rows.
  - Naps moved in from Trends.
  - The breathing-pattern screen is a single card.
  - "Fix sleep times" is folded.
- **Skin temperature:** charted from this band's nights.
- **Readiness:** the earlier read/baseline audit (`metrics-map.md`) found no defect in the
  headline baseline read; it did not validate the temperature channel (open Build 88 repair). The
  Build 88 second-pass audit found that the on-screen breakdown and the Low readiness alert use a
  different model (`bugs.md`, B88-11). The history is coloured bars with a
  per-day reason, and it shows why breathing was not counted.
- **Steps, phone first:** `resolveDaySteps(phoneFirst: kPersonalSideload)`; build 70 uses `kAlgoVersion` 87.
  Build 89 source goes further: phone only (`kBandSteps` off in `lib/build_profile.dart`).
- **Runs:** medal pins on the map, phone steps and cadence (plus a chart), and spoken km cues (the
  native `SpeechBridge`, no new dependency).
- **Food:** a MyFitnessPal-style diary:
  - day navigation and swipe;
  - meal cards with copy from / copy to / save meal;
  - a meal page with sub-groups (the new `food_entry.grp` column, added in place) and
    swipe-to-delete;
  - a log screen with search, tabs and sort;
  - food detail with % of goals and "often eaten with";
  - named quick add.
- **Food history:** maintenance history for every day with a chart and weekly totals, a body weight
  log (new `body_weight` table) and maintenance measured from weight change.
- **Today:** a weekly card, and an evening protein-left line on Food.

Source `0.9.39`/`72` adds full-width wrapping chart readouts, matching deep-sleep colours,
expandable night details, Today on fresh launch, My foods by default and direct barcode scanning.
Food history is grouped by calendar month. Quick add includes optional fibre and editing; omitted
macros remain untracked and explicit zero remains zero. Weekly energy summaries use completed days
and explain exclusions. Today/food cards reread after committed food changes, foreground refresh
and day rollover. Validation, save guards, transactional meal logging, latest-read guards and
retryable failures protect these flows. The new widget/data regressions also cover cold/warm
navigation, failed writes and historical meal timestamps. Build 72 includes the fixes for the former Windows test
failures, including leaked ZIP file handles and DST calendar-age arithmetic. `kAlgoVersion` is 88
so retained movement results can recompute; no schema or personal capability change is required.
Build 72 aligned the excluded Widget/Watch version metadata to `0.9.39`/`72`; build 73 aligns it to `0.9.40`/`73`. Build-72 local full-suite validation
passes (3,274 tests, 368 intentional skips); analysis has 58 infos and no errors/warnings, and all
7 personal-iOS contract tests pass. Initial source `5c00c278` is published; its Linux CI and macOS
build pass. The additional refresh source reads phone steps before band catch-up, exposes measured
steps without waiting for derivation, awaits the calculation queue and shows timeout/failure/hold
messages. The full suite and focused regressions pass. Akshat approved public publication and
the replacement IPA; source `05c208c7` is pushed. Linux CI `37173914511` passes (3,279 tests,
363 intentional skips); macOS workflow `37174063547` passes. The downloaded build-72 IPA
matches its manifest/checksum and passes the local payload validator. Akshat confirms installation,
but it was not phone-accepted; build 73 replaces its testing artifact. Its source/hash/workflow
evidence remains in `setup.md`, with reported issues in the audit. Do not install build 71.
`setup.md` owns the artifact evidence.

`schemaVersion` is unchanged (both build-70 storage pieces are additive, on the open path).
Superseded `0.9.36`/`69` (commit `5747dd35`) was **built, validated and installed** (Akshat's
screenshots showed its features; its phone check passed as part of build 70's)
(Linux tests and the macOS workflow passed; the IPA matches its SHA-256 and passes the validator;
no longer cached after build 70 replaced it in the testing slot). It adds, on Akshat's
decisions (`metrics-map.md` describes the shipped behavior):
- **Run calories:** two numbers. **From distance** (Method 1: 0.005 × kg × (0.143 × metres run +
  0.1 × metres walked + 0.9 × metres climbed), with walk breaks split out by GPS speed).
  **From heart rate** (Method 2: Keytel minus resting, per minute). Shown as one number when within
  50 kcal.
- **Maintenance:** a Running row (Method 1 only). The steps taken during runs come off the Steps
  row, read from the phone over the exact run window. Tapping the card opens a plain detail sheet.
- **Runs without GPS:** distance, splits and cadence come from the phone's motion data (7-day
  window, saved per session; native `motionWindow` on the phone-steps channel).
- **Train:** Run · Walk · Lift · Other; a movement streak (10+ minutes of run/walk); draggable strain and
  weekly-distance bars; a strain tap opens that day, with day arrows. Best times are 1K, 5K, 10K and
  half marathon only (a hidden 3K feeds the 5K prediction).
- **Charts:** a shared finger cursor with the date and value in the chart header.
- **Pull to refresh** on every tab: band sync, phone steps, then a wait for today's derive (60 s cap).
- **Steps screen:** the stretch list is removed.
- **Sleep:** the Tonight section, Today's bedtime card and the wind-down reminder are removed. The
  hypnogram is clearer.
- **Breathing rate:** the Trends row is hidden when it was measured on fewer than half of the last
  30 nights.

`kAlgoVersion` and `schemaVersion` are unchanged (all of this runs in the screen layer and app
preferences).
Superseded build `0.9.35`/`68` (commit `284fff83`) was **installed** over build 67. Akshat reports the run screen
working on his first run after installing it. Runs recorded before then show no splits because
they have no saved GPS route, which is expected. Build 69 replaced it in the testing slot; it is
reproducible from its workflow run (`setup.md`). It adds: daily maintenance calories as a floor (BMR + step calories + 10% of logged food, `metrics-map.md`); a dark-only palette (one colour per pillar); a Strava-style run screen (Apple Maps route via a MapKit snapshot, best efforts and PRs against earlier runs, a rule-based verdict, splits, pace / heart-rate / elevation charts on one finger cursor, pace zones); running trends on Train; live heart rate on Today with the scrub stopping at the current time; decluttered Strain and Readiness screens; GPS jitter smoothing and stop-aware moving time; and a refresh of phone steps and today's numbers on every open and every 5 minutes while the app is open. **The map is the app's first regular network use besides barcode lookup:** MapKit fetches tiles for the run's area from Apple, approved by Akshat.
Superseded build `0.9.34`/`67` (commit `b7414f03`) was **installed and accepted**: Akshat reported it working (band sync, a GPS run, the new layout), supporting its promotion at the time. Akshat installed it over build 66 with Sideloadly 0.70.1. WHOOP installs can sit at "Installing 88%" (43 minutes when left alone). The cause is not established. What is observed on build 67: it happens in both automatic and exact bundle-ID mode, with the phone unlocked, and even when the app was swiped away beforehand; opening WHOOP and swiping it away released the stuck install at once, twice. `guides/IOS_SIDELOAD.md` owns the procedure. Sideloadly's record showed 0.9.34 at `com.akshat.personal.whoop.5564K8D4SV` with a completed automatic-refresh registration and no error (automatic mode at acceptance). Linux
tests and the macOS workflow passed, the downloaded IPA matches its SHA-256 and passes the payload
validator, and it was cached as the accepted build under
`final-ipas\whoop\backup\WHOOP-0.9.34-build67-accepted` until build 70 replaced it; it is no longer
cached and is reproducible from `setup.md`. It redesigns the app as
four single-page tabs (Today · Trends · Food · Train) with flat rounded cards and short labels, and
removes the screens listed under "Simple day-to-day UI" below; `metrics-map.md` owns the layout
and the list of metrics still stored but no longer shown. The reported sync, GPS run and new layout
are phone-verified; the broader lifecycle and signing gates remain open.

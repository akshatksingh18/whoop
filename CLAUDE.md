# WHOOP BLE Companion

One local Git monorepo, based on OpenStrap, for pairing with a WHOOP 4.0 sensor over Bluetooth
LE, decoding the raw protocol, and computing recovery/strain/sleep metrics locally — no WHOOP
subscription and no app backend.

- The Flutter `edge` app lives at the repository root.
- `packages/protocol/` contains the BLE codecs at the exact revision the imported app used.
- `packages/analytics/` contains the local metric engine at the exact revision the imported app
  used.

The monorepo preserves all three upstream histories. Its personal `origin` is the public
<https://github.com/akshatksingh18/whoop> repository on Akshat's main account. The former local bare
repository remains available as the `local-backup` remote; the three official OpenStrap sources
remain fetch-only named upstreams.

**Status:** Active iPhone verification — build `0.9.37`/`70` remains accepted after
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
Akshat reports build 80 installed; its follow-up requests (Quick add weight, recovery inputs, sleep detection, full-app review) are audited in `build-81-audit.md`. Build-81 source `0.9.48`/`81` (algorithm 91) implements his decisions: Quick add weight/all macros/Save to My foods, sleep as a fifth readiness input, the Readiness ring fix, What-moves-it from logged data, bedtime consistency, the Monday last-week card, shorter text and removal of the never-working Live Activity extension; sleep detection is unchanged. Build-81 source `0.9.48`/`81` (commit `d44c989f`) is published with Akshat's approval; Linux CI `37699481094` (3,398 tests, 371 intentional skips) and personal macOS build `37699482851` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension in the IPA. Build 81 was never installed. Build-82 source `0.9.49`/`82` (commit `4b53abbe`) is published with Akshat's approval; Linux CI `37708103583` (3,406 tests, 371 intentional skips) and personal macOS build `37708104201` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build 82 adds page-scrolling drag, a discard guard on edit sheets, Foods search, the saved-meal flow fixes and a working iPhone app log (`todo.md`); Akshat reports it installed. Build-83 source `0.9.50`/`83` (commit `cbaf93cd`) is published with Akshat's approval; Linux CI `37717941508` (3,408 tests, 371 intentional skips) and personal macOS build `37717959148` pass; downloaded source/version, checksum, ZIP and payload checks pass, with no app extension. Build 83 time-stamps the app log, stops overlapping log lines overwriting each other and makes the history sync ask the band when no transfer is running. Build-84 source `0.9.51`/`84` fixes stale Today numbers (revision bump when today's row lands and after the readiness rescan), keeps iOS Bluetooth relaunches on the light background path (UIKit launch state), ends pull-to-refresh once today is calculated, checks background offloads every 5 min, logs MetricKit exit reasons to `openstrap_exits.log`, prices digestion by macro at the low end and adds a separate Lifting line (`todo.md`).
The sole testing candidate is `final-ipas\whoop\testing\WHOOP-0.9.50-build83-cbaf93cd`, not installed yet;
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
`com.akshat.personal.whoop.5564K8D4SV` with no install error. `testing\` now holds build 83,
not installed yet, awaiting the complete phone pass and current-version enrollment.
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
- **Readiness:** the end-to-end audit (`metrics-map.md`) found no bug. The history is coloured bars with a
  per-day reason, and it shows why breathing was not counted.
- **Steps, phone first:** `resolveDaySteps(phoneFirst: kPersonalSideload)`; build 70 uses `kAlgoVersion` 87.
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

## Files
- `todo.md` — build-74 release/device gates, build-73 phone checks and remaining lifecycle/refresh checks; read before
  further verification or planning a new build. Source behavior and limits live here and in `metrics-map.md`.
- `build-81-audit.md` — installed-build-80 audit: Quick add weight, recovery-score inputs (no sleep
  input today) with WHOOP/Oura/Garmin research, sleep-detection false positives (unused HR
  baseline, block joining), deep-sleep confidence, whole-app bugs/visual/wiring review and
  feature proposals, Akshat's decisions and the implemented build-81 list; read before changing build 81.
- `build-75-audit.md` — installed-build-74 findings: Live Activity scope/diagnostics, Trends
  range/day navigation and links, bar-to-line charts, tab re-tap, Food ordering/serving/saved-meal
  workflow, day-breakdown noise and calorie verification; Akshat's decisions D1–D8 and the
  implemented build-75 list with deferrals; read before changing build 75.
- `build-74-audit.md` — installed-build-73 chart, navigation, notification and workout findings;
  primary calorie research, assessment of the pasted brainstorming, implemented ACSM/Live
  Activity/fortnightly-review contract and acceptance tests; read before changing build 74.
- `workout-sync-audit.md` — current build-72 sync, background voice, workout/calorie, macro,
  profile-precision and step-goal streak findings, research, reproductions and the approved repair contract;
  read before changing calculation, sync or step policy.
- `metrics-map.md` — every metric the app stores, where each appears, the Sleep screen's sections,
  and current layout decisions; read before adding, moving or removing any screen.
- `setup.md` — current public-GitHub/local-backup/upstream remotes, imported revisions, Windows
  validation, installed personal-iPhone candidate, and remaining migration/device decisions.
- `bugs.md` — retained Android reconnection evidence plus active iPhone CoreBluetooth and verified
  iPhone-pedometer step-source behavior.
- `README.md` — preserved upstream product reference with a personal-fork status banner and clear
  distinctions between upstream distribution/features and the installed but unverified profile.
- `guides/IOS_INSTALLATION.md` — selected minimal personal versus full source-signed iOS build
  profiles, capability boundaries, and build acceptance requirements.
- `guides/IOS_SIDELOAD.md` — accepted Windows Sideloadly installation, refresh monitoring, backup,
  expiry recovery, two-app portfolio, and fallback-signer workflow; initial installation is complete,
  while refresh and recovery validation remain pending.
- `../final-ipas/whoop/` (sibling folder, outside this repository) — the stable release cache:
  `backup\` holds the current accepted build, `testing\` a candidate awaiting its device pass.
  `../final-ipas/README.md` owns the model; excluded from the workspace OneDrive backup the same way
  every `personal-project/` subfolder is, and not tracked in Git.
- `.github/workflows/personal-ios.yml`, `tool/personal_ios.py`, and
  `tool/personal_ios_accepted_builds.json` — manual public-repository macOS build, deterministic
  personal-profile transformation, payload validation, manifest/checksum, and the accepted-build
  identity ledger that prevents version/build reuse.
- `.claude/skills/ponytail/SKILL.md` — upstream implementation discipline; read it before changing
  application or package behavior.
- `pubspec.yaml` and `pubspec.lock` — Flutter dependencies; protocol and analytics resolve through
  tracked paths inside this monorepo.
- `lib/`, `test/`, `android/`, `ios/`, and `assets/` — the imported OpenStrap edge application.
- `packages/protocol/` — imported OpenStrap protocol source, tests, license, and original history.
- `packages/analytics/` — imported OpenStrap analytics source, tests, anonymized upstream fixtures,
  license, and original history. The restored real-night regression fixture is the public upstream
  fixture introduced by OpenStrap analytics PR #21, not an Akshat export.
- `packages/upstream-revisions.yaml` — reviewed protocol and analytics source revisions used by
  the algorithm-version guard test.
- `LICENSE` and `NOTICE.md` — OpenStrap edge licensing and attribution; package licenses remain in
  their respective package folders.

## Repo layout
- `lib/ble/` — Bluetooth + sync
- `lib/data/` — local storage + the repository seam the UI reads from
- `lib/compute/` — runs the analytics pipeline, writes results
- `lib/state/` — AppState, the one source of truth
- `lib/ui2/` — every current screen
- `packages/protocol/lib/` — protocol framing and record decoders
- `packages/analytics/lib/` — recovery, strain, sleep, and related formulas

## Environment
- Dev machine: Windows laptop, no local Mac
- Intended primary daily-use device: iPhone via the minimal Sideloadly-sideloaded release IPA;
  build 70 is installed and accepted. Enabling **This phone →
  Steps** on build 63 verified direct iPhone-pedometer import; recheck that setting and behavior on
  the current candidate. Apple Health’s aggregate is deliberately not read. Band reconnection, installed About/
  profile details, complete sync/background behavior, GPS, and same-ID refresh remain unverified.
- Personal platform scope: iPhone only. Preserve the imported Android source as upstream/reference
  code, but do not spend implementation or validation effort on Android unless Akshat reopens it.

## Personal iPhone deployment plan

This is the durable free-compatible plan for making the iPhone the primary WHOOP device. The
accepted portfolio is standalone WHOOP plus the native AkshatOS hub (its modules are listed in
`../akshatos/hub-plan.md`): two free-signing slots. `../akshatos/hub-plan.md` owns that packaging. WHOOP remains an
independent Flutter app/process, not embedded in the hub; no paid tier, rotation, or identity
migration is required by this decision. Seven-day profiles and the refresh/recovery rules remain.
Akshat has activated iPhone implementation. The personal flavor exists in source, its first
macOS-built candidate was installed and exposed the malformed AccessorySetupKit descriptor crash.
The bridge is now fixed. The accepted build is `0.9.37`/70, cached at
`D:\AI Important Files\personal-project\final-ipas\whoop\backup\` (`setup.md` owns the location).
`0.9.31`/64 passed automated checks but was superseded without installation.
Previously installed `0.9.32`/65 adds the confirmed-phone-stillness step guard. Neither is cached any more:
`testing\` holds the validated build-74 candidate, and older candidates are reproducible from their workflow
runs recorded in `setup.md`. Build 65's encrypted restore, launch, scheduled
enrollment and exact-final-ID same-app refresh work. Install stalls once blamed on the automatic
bundle-ID path happen in both modes and their cause is open (`guides/IOS_SIDELOAD.md`); the health
check now accepts either mode for WHOOP.
History/data, exact signed identity, pairing preservation, manual recovery, and a controlled
forced-due Wi-Fi daemon refresh are verified. Daily-use activation still requires the remaining
About/version, phone-step-retention, GPS/background, naturally elapsed refresh, and physical-device
evidence below.

### Current feature limits

- Build-73 source uses session-owned voice cues with explicit background audio. Locked-screen,
  other-app, music/call/headphone behavior needs the phone acceptance pass; build 72's delay is
  the reported baseline, not evidence that build 73 works on hardware.
- Run/walk Budget/ACSM estimates and separate net HR analysis share active windows and recorded profile inputs.
  The equations remain conservative budgeting estimates, not guaranteed physiological minima.
  Unknown movement/HR stays absent or labelled partial; no lifting calories enter maintenance.
- All macro rows remain visible. Nullable omitted values display zero logged; no nutrition is
  inferred. Decimal profile inputs preserve precision and refresh dated calculation dependencies.
- Nap edits update lists, Sleep periods and the timeline from one durable ledger before the
  independent retained-history coaching rebuild finishes. Empty days retain Naps; manual reports
  and detector proposals remain distinct. Build-75 source shares Today · 7 days · 30 days ·
  3 months between Trends (opening on 7 days) and every metric, carries the range into the
  metric and shows a dated day row on every metric; Sleep/Strain/Readiness Today reuse their
  full detail, Steps has its hourly graph inline and Step calories its own kcal trend.
- Build-73 local validation passes: 3,318 Flutter tests (368 intentional skips), 91 focused
  personal-profile checks and all 7 personal-iOS contract tests. Analysis has 60 infos and no
  errors/warnings. Rendered layouts and small-phone/enlarged-text regressions pass. Linux CI passes
  3,323 tests with 363 intentional skips; native macOS compilation and downloaded IPA validation
  pass. Installation is confirmed, with the future-time Strain cursor defect reported; the
  complete phone pass remains open. `build-74-audit.md` and `todo.md` own the implemented coordinated
  chart/navigation/notification repairs, calorie comparisons and optional lock-screen feature.
- A day earns a movement streak through 10 active run/walk minutes or its dated measured step goal.
  Goals before migration are unknown; historical workout evidence is preserved.
- Connected wrist fallback captures accepted high-rate gait without Start, supplements separately
  measured phone-absent time and never overrides positive overlapping phone measurements.
  WHOOP 4 recorded history cannot recover accurate offline steps beyond Bluetooth range. Passive
  background battery/coverage and accuracy against counted steps remain physical-device gates.
- Workout profiles/weights are captured; daily history uses dated anchors. Food/weight inferred
  maintenance requires aligned complete intake, at least 14 interval days and 8 weigh-ins, and
  remains approximate because weight includes water and the 7,700 kcal/kg conversion is approximate.
- Build 70's map/medal and phone-motion feature check passed as reported; broader route/restoration,
  system termination, overnight collection, 72-hour soak and natural signing refresh remain open.

### Chosen delivery model and non-negotiable constraints

- Ship WHOOP as a normal, standalone Flutter **release/AOT** iPhone app in a standard unsigned
  `.ipa`, then let Sideloadly sign and install it directly from the Windows laptop with Akshat's
  free Apple Personal Team. Do not use a Flutter debug build for daily use: debug builds require
  Flutter/Xcode to relaunch from the home screen.
- WHOOP uses one slot and the native AkshatOS hub uses a second; the third is
  unallocated. Sideloadly has no phone-side host. AltStore/SideStore would use a further slot and
  require an explicit workflow choice; neither is needed. Preserve WHOOP's independent lifecycle,
  minimal personal flavor, encrypted exports, and stable identity rather than embedding it in the hub.
- Do not put the daily app inside LiveContainer and do not add StikDebug, LocalDevVPN, JIT,
  injected tweaks, or a Sideloadly-specific runtime dependency. Those add failure surfaces and
  cannot be trusted to preserve WHOOP's entitlements or CoreBluetooth background restoration.
- Free Personal Team profiles expire after seven days. The installation therefore still depends
  on Apple's signing service, even with Local Anisette; no stock-iPhone build change removes that
  Apple dependency. The reliability goal is early refresh, independent verification, and a tested
  recovery path rather than pretending the profile is permanent.
- Sideloadly is a replaceable installer, not part of the app architecture. Apple can change
  authentication, pairing, or provisioning behavior and temporarily break it. Keep the artifact
  standards-compliant and portable so a maintained replacement signer can install the same IPA.

### Current authoritative references

- Re-check Apple's account documentation before deployment. It currently allows up to ten App IDs
  and three devices, both expiring after seven days, plus three installed apps per device and
  seven-day provisioning profiles:
  <https://developer.apple.com/help/account/basics/about-your-developer-account/>.
- Re-check Sideloadly's official FAQ and changelog before activation and after an iOS, Apple-login,
  or Apple-device-component change. They document current iOS support, background refresh,
  same-bundle overwrite behavior, Wi-Fi/USB caveats, retries, and recent authentication fixes:
  <https://sideloadly.io/faq.html> and <https://sideloadly.io/changelog>.
- Preserve WHOOP's CoreBluetooth design against Apple's documented background/restoration model;
  background wake opportunities are bounded and state restoration must rebuild the real central
  manager rather than assuming continuous execution:
  <https://developer.apple.com/library/archive/documentation/NetworkingInternetWeb/Conceptual/CoreBluetooth_concepts/CoreBluetoothBackgroundProcessingForIOSApps/PerformingTasksWhileYourAppIsInTheBackground.html>
  and <https://developer.apple.com/documentation/corebluetooth/central-manager-state-restoration-options>.
- Flutter's release-mode AOT behavior, rather than debug/JIT behavior, is the basis for a standalone
  home-screen app:
  <https://docs.flutter.dev/resources/faq>.

### Personal-sideload build contract

The dedicated personal-sideload build/configuration is implemented by `PERSONAL_SIDELOAD`,
`tool/personal_ios.py`, and `.github/workflows/personal-ios.yml`. The script transforms
only the ephemeral build checkout, with drift guards, instead of mutating the general source target
ad hoc or relying on Sideloadly to repair an over-entitled bundle.
The personal artifact must have these properties:

- Keep the root iPhone `Runner` and all local BLE, SQLite, analytics, UI, local-notification,
  import/export, and Files-sharing functionality. Build it with the Flutter version deliberately
  pinned in `.github/workflows/build.yml` (currently 3.41.6), using a release equivalent of
  `flutter build ios --release --no-codesign --dart-define-from-file=.env`.
- Keep `UIBackgroundModes` value `bluetooth-central`, the Bluetooth usage strings, the generated
  AccessorySetupKit service/name declarations, and the `BleRestoreManager` bridge. Preserve the
  stable `openstrap.ble.restore` restoration identifier, the saved band UUID, the deferred
  first-pairing central creation, and the existing handoff to the normal Flutter drain path.
  CoreBluetooth wakes are bounded opportunities, not a promise of continuous execution; every
  drain must retain the commit-before-ACK and resumable-cursor invariants documented below.
- **The GPS experiment is reopened, on an explicit decision — Akshat runs and wants a traced
  route.** `NSLocationWhenInUseUsageDescription` and the `location` background mode are back in
  `personal_ios.py`'s personal `Info.plist`; `NSLocationAlwaysAndWhenInUseUsageDescription` stays
  forbidden — authorization is While-In-Use only, matching `lib/gps/gps_source.dart`'s own design,
  which relies on the background mode rather than Always to keep a run tracked with the screen
  locked. `tool/test_personal_ios.py` enforces both halves.
  - **Code audit hardening (in build 66, not device-verified):**
    - A re-armed recorder (a run resumed after the app was killed, or a retry after a location fix)
      continues after the stored `workout_route` sequence. Before, it restarted at 0 and overwrote
      the start of the route.
    - "Recording route" shows only while fixes are actually accepted; otherwise the screen says
      "Waiting for GPS".
    - iOS Precise Location off gets its own fixable reason.
    - Returning from Settings retries a blocked route.
    - The buffered tail is flushed when the app goes to the background.
  - **Buildable, not yet verified**: the
  permission, battery, background, and stop-semantics evidence this reopening still calls for needs
  a real outdoor run on the phone, not a code review. Do not describe route tracking as accepted
  until that pass happens and is recorded here.
- Build 73 adds `audio` to the personal background-mode contract for genuine workout speech.
  It keeps While-In-Use location authorization and adds no HealthKit, App Group, companion,
  processing/fetch or silent audio keepalive. The payload validator enforces this mode set.
- **Akshat does not own an Oura ring**, so the upstream adapter, protocol, and derivation seams stay
  for merge value but are unverified here. The personal build hides the Oura pairing row behind
  `kPersonalSideload`; the full upstream-capable build retains it. This is an explicit unsupported-
  hardware product decision, not an AccessorySetupKit limitation: Oura pairing uses the direct BLE
  sensor path rather than the primary-WHOOP AccessorySetupKit picker.
- **Simple day-to-day UI is an explicit product decision.** Akshat removed three surfaces from the
  app source:
  - **Nerd stats** (`Investigate`). Metric drill-downs now end at the metric detail screen.
  - **The Wellness tab.** This took Mind, Recovery drivers, Habits, Medication and Cycle with it; the
    shell has four tabs.
  - **Water logging** on Nutrition.

  Medication and water reminders are forced off at load, so anything an older build armed is
  cancelled. Their Settings switches and the Cycle-tracking switch are gone. Daily check-in and
  wind-down entry points are also removed by the later journal and Sleep decisions below.

  **Selection rule:** keep what serves Akshat's goals (lifting, running, sleep, recovery) and drop
  noise and redundant manual entry. Food and body weight are deliberately logged by hand in WHOOP;
  lifting sets are logged in AkshatOS. `metrics-map.md`
  lists everything stored, where it appears, and current layout decisions.
  - **Journal removed** at Akshat's request, and the daily check-in is forced off. No Home or
    Readiness entry and no findings screen; a rough-night card on Sleep states the measurements and
    never asks for tags. `journal_compose.dart` stays only because it hosts shared input widgets
    (`OsTextField`, `FieldStepper`).
  - **Build 67 redesign** (source `0.9.34`), Akshat's "cleaner, minimalist, no paragraphs" ask:
    - **Tabs:** Today · Trends · Food · Train, each one scrolling page (`ShellDomain` keeps the
      `home/health/nutrition/workout` names). Dark cards are flat; the tab bar is a floating pill.
    - **Today** (`home_screen.dart`): recovery ring with HRV and resting HR, sleep and strain
      cards, live heart rate over the all-day heart-rate line (opens the scrubbable chart), steps
      and maintenance. The greeting, "Today's plan" and (source 69) the bedtime card are gone.
    - **Trends** (`health_screen.dart`): one row per core metric with Today / 7 days / 30 days / 3 months (7 days by default; build-75 source),
      then the illness watch / findings. Naps are on Sleep from source 70. Explore, Beats, Body clock, the Stress row and
      the Consistency cards were removed; their metrics are still computed and stored.
    - **Train** (`workout_screen.dart`): Run / Walk / Lift / Other (Walk from source 69), the
      run-or-walk streak, 7-day strain bars, running trends, recent sessions.
      Fitness/fatigue/form, the kg-lifted chart, morning-after and overreach cards, the mascot
      card and the share button were removed. **Lifting sets are not logged**: in the personal
      build `Track.sets` activities run as a timed session (`archOf`), because Akshat logs lifts
      in AkshatOS Lift Log. `strength_set` rows and the sets UI stay in source for a possible
      later migration into WHOOP.
    - **Settings:** one list opened from Today (`MoreSettings`); the profile hub, AI coach, AI
      briefings, language picker and paced-breathing screen were removed. In the personal build
      the Automation group, app-icon row, add-a-sensor row and the movement-nudge and step-goal
      notifications are hidden (the two notifications are forced off at load).
    - **Kept on purpose:** the band alarm and barcode scanning (Open Food Facts; accuracy still to
      be checked on the phone against real labels).
  - **Kept in minimal form:**
    - **Breathing pattern in sleep:** `sleep_breathing.dart`, one tap below Sleep, showing the
      across-nights card only.
    - **All-day heart rate:** a scrubbable minute-by-minute chart (`DayHeartCard` in
      `day_timeline.dart`), reached from the heart-rate card on Today. It reads the day bundle's permanent per-minute `hr_curve`.
  - **Sleep cleanup:**
    - Stages and the deep-sleep usual row show counted minutes and % of sleep, which sum to total
      sleep, in place of wide ranges.
    - The title date is readable.
    - The sleep-window correction card sits last.
  - **Labs** (manual lab entry) was removed. Naps stays reachable even on an empty day, so the
    last removal can be restored and a missed nap can be logged.
  - **Nutrition rebuilt** (`nutrition_screen.dart`, `food_picker.dart`), in the MyFitnessPal shape.
    Akshat logs meals here.
    - **Today:**
      - Calories left = the typed goal − food; exercise is never added back.
      - Protein, carbs, fat and fibre against typed targets.
      - Breakfast, lunch, dinner and snacks, each with its own Add.
    - **Adding food:**
      - From saved meals (`meal_template`, one tap writes an entry per food).
      - From his own foods (`food_def`, typed once from a label and stored per 100 chosen units,
        grams by default, with links/slices/cups/ml/custom units and fractional amounts supported).
        Logging scales every supplied nutrient; saved diary amounts remain editable.
      - Or by quick add / barcode (the existing sheet).
    - **History:** calendar-month accordions; each day opens for late edits.
    - **Foods:** manage foods and saved meals.
    - **Goals:** five targets, typed once; the app never changes them.
  - **Calories:** maintenance is a conservative budget estimate: resting (Mifflin–St Jeor), plus steps outside runs
    (Akshat's step formula), plus runs by distance (source 69), plus the low-end digestion cost of logged food
    by macro (build 84; flat 10% before). Lifting shows as a separate sheet line, never in the total. It is shown on
    Today and Food, never moving the goal. Build 74 keeps Budget and ACSM distance comparisons
    side by side, with net heart-rate energy reachable separately for analysis. The band's
    heart-rate active and total kcal are still stored. Apple Health energy was
    considered and not pursued: with no Apple Watch it would only repeat phone-step motion.
    HealthKit stays excluded; `metrics-map.md` owns the calorie method.
  - **Left out as noise:**
    - extra HRV numbers, awake breathing rate, and per-day coverage/algorithm version;
    - guided breathing, and (source 69) the Sleep Tonight section, the bedtime card and the
      wind-down reminder: sleep need and bedtime are still computed but not shown;
    - medication, habits, cycle, water and labs.

  Removed UI surfaces retain their underlying computation and stored history, and git history
  holds the removed screens. Build 70 also adds food sub-groups/body weight storage and changes
  personal step resolution to phone-first (`kAlgoVersion` 87).
- The initial personal profile removes `processing`/`fetch` modes, BG task identifiers,
  native registration, and Dart scheduling. They remain optional future experiments, never
  correctness requirements.
- Default the personal flavor to local-only operation: no health-data contribution, no required
  companion/backend URL, no automatic OTA dependency, and no automatic Firebase Analytics,
  Performance, or Crashlytics collection. In particular, do not carry the current release
  workflow's `ENABLE_HEALTH_DATA_CONTRIBUTION=true` into the personal artifact. BYOK/other network
  features may remain manual opt-ins only if the app works fully with networking disabled and no
  secret is baked into the IPA.
- Strip the Watch companion from the IPA, as the current tag workflow already does. Keep its
  source target for a possible future fully source-signed build, but do not package it for free
  re-signing: its companion bundle-ID cross-reference is not safely rewritten by generic
  sideloaders.
- No app extensions (from build 81). Builds 74–80 shipped one workout Live Activity extension,
  but Sideloadly's free signing provisions only the app's own App ID, so iOS killed the extension at launch on a code-signing check (CODESIGNING "Invalid Page") and it never drew; `build-81-audit.md` holds the evidence. The personal IPA embeds no extension, `NSSupportsLiveActivities` is
  forbidden, the Dart side requests no activity and Status shows no Live Activity row. The source
  extension stays for the full upstream-capable build. Compile out general home, sleep, battery
  and breathing widgets and all App Group bridges/entitlements. Reopening any extension needs an
  installer that provisions its App ID.
- Remove HealthKit entitlements and hide/compile out Apple Health reads and writes in the initial
  personal flavor. Preserve manual profile entry and all band-derived metrics. HealthKit may be
  reintroduced only as a separate, later capability experiment after the exact free Personal Team
  profile produced by Sideloadly is inspected and install, permission, read, write, refresh, and
  upgrade behavior all pass. Never ship `com.apple.developer.healthkit` when the installed profile
  does not grant it.
- Use a minimal Runner entitlement set that exactly matches the profile after the exclusions
  above. Bluetooth background mode and local notifications belong in configuration/permissions;
  do not invent entitlements for them.
- Package a conventional `Payload/Runner.app` IPA with no signing credentials, provisioning
  profile, personal health data, database, BLE capture, API key, injected dylib, or installer
  metadata. Inspect the payload before release and fail if `Watch/`, any app extension,
  unexpected entitlements or secrets remain.

### Bundle identity, upgrades, and data continuity

- The personal app's iPhone display/bundle name is `WHOOP`. Its permanent source bundle identifier
  is `com.akshat.personal.whoop`; its verified installed signed identity is
  `com.akshat.personal.whoop.5564K8D4SV`. For every refresh and upgrade, use the same Apple Account,
  retain that exact final signed identity and keep the separate automatic-refresh control enabled.
  WHOOP accepts either bundle-ID mode: in exact mode turn **Use automatic bundle ID** off and
  enter the final ID; in automatic mode verify the result is the same final ID. Never accept a new random identifier
  merely to make an installation succeed.
- The personal iPhone build uses the black-and-white circular mark in
  `ios/Runner/Assets.xcassets/AppIconPersonal.appiconset`; the general upstream target retains its
  existing `AppIcon` artwork.
- Keep the existing source version rules: every new binary gets the correct `pubspec.yaml`
  version/build number and passes the release guards. Code upgrades change the version, never the
  bundle identity. `tool/personal_ios_accepted_builds.json` records accepted version/build pairs;
  `personal_ios.py check` refuses to build one again. Do not uninstall the existing app for a normal
  refresh or upgrade; install over it with the same Apple Account and bundle ID so iOS retains the
  app container, pairing state, database, and preferences.
- Treat overwrite preservation as a tested behavior, not the only backup. Sideloadly's cached IPA
  and signing state are replaceable; health history is not. An accidental uninstall, changed
  bundle ID, device restore, or failed signing migration can still orphan the container.
- **Settings → About → Status** (`lib/ui2/profile/status.dart`) is implemented in build 66, not yet device-verified.
  - It reads the installed `embedded.mobileprovision` expiry (`lib/platform/signing_profile.dart`).
  - It also shows the newest band data, automatic-backup state, build version, and the source commit
    (`SOURCE_REVISION`, written into `.env` by `personal-ios.yml`).
  - Local alerts fire **48 and 24 hours** before expiry. Akshat dropped the 72-hour one; the Windows
    health check owns the earlier warnings.
  - The alerts are re-armed from the installed profile at launch and on every foreground return, and
    they open the Status screen.
  - They supplement, not replace, Windows-side verification.

### Building and caching the IPA

- macOS/Xcode is required only when source changes require a **new** unsigned IPA. Re-signing the
  already-built IPA every few days happens entirely from Windows and must not rerun Flutter,
  Xcode, CocoaPods, or the analytics pipeline.
- The chosen build host is the public GitHub repository's manual macOS workflow,
  `.github/workflows/personal-ios.yml`. It uses Flutter 3.41.6, injects no backend/Firebase
  secrets, applies the personal transform, validates the IPA, and uploads a 14-day artifact
  with a source/capability manifest and SHA-256. The existing tag workflow remains the
  upstream-capable release path and must not supply this personal artifact. GitHub/macOS is a build
  dependency only when code changes, not a runtime or routine refresh dependency.
- Cache the current signed-input IPA on Windows in a stable, non-temporary directory outside Git.
  The cache is exactly two slots, owned by `../final-ipas/README.md`: `backup\` holds the one
  accepted build and `testing\` holds at most ONE candidate. Downloading a new candidate deletes the
  previous one in the same step; never leave superseded builds beside it. Each cached build keeps
  its filename/version, SHA-256, source commit and capability manifest, and `setup.md` records the
  run and hash of every build so a removed one can be reproduced. Do not rely solely on Sideloadly's internal
  cache or a GitHub Actions artifact-retention window.
- A new IPA is promoted only after payload inspection, hash recording, a fresh-device install,
  an in-place upgrade test, and signing-health results of `ENROLLED` for the exact signed identity and
  current version plus `IDENTITY` in either permitted WHOOP mode (`../akshatos/scripts/signing-apps.json`).
  A one-off install that launches is not enough. The
  previous known-good IPA remains available until the new build passes the soak and refresh gates.

### Windows signing and refresh automation

- Install Sideloadly only from its official distribution, enable **Local Anisette**, enable Apple
  device Developer Mode/trust, use iTunes to enable **Sync with this iPhone over Wi-Fi**, enroll
  WHOOP for automatic refresh, and run the Sideloadly daemon at Windows sign-in. Sideloadly currently
  warns that wireless discovery can occasionally require iTunes to be open or the iPhone screen to
  be on, and some Windows pairing errors require the web/non-Microsoft-Store Apple components.
  Re-check these transient setup details after tool updates. Local Anisette removes reliance on
  Sideloadly's remote Anisette server but does not remove communication with Apple's signing servers.
- Never place the Apple Account password, a 2FA code, signing material, or an app-specific password
  in this repository, a PowerShell script, task arguments, or plaintext logs. Use the installer's
  supported credential storage and Windows protections. Preserve signing continuity with the same
  account unless a deliberately tested migration is necessary.
- Do not schedule one attempt exactly every seven days. Run a local health check daily (48 hours
  is the maximum acceptable gap) that confirms the daemon is running, the iPhone has recently been
  seen over trusted Wi-Fi or USB, and a successful refresh is recorded. Start the refresh window
  with at least three full days remaining so Apple downtime, a sleeping laptop, travel, or a Wi-Fi
  pairing failure has several retry opportunities.
- Sideloadly describes the daemon as acting when apps are "near expiry" but does not document a
  user-configurable threshold. If the three-day health check has not observed a new expiry, use the
  supported **Refresh All Apps Manually**/normal same-IPA install path. Do not make an unsupported
  GUI script the only recovery mechanism or let it report success without device-install evidence.
- Use proof of success from the installed provisioning expiration and/or Sideloadly's explicit
  success record. A daemon process, opened GUI, cached-file timestamp, or scheduled-task exit code
  alone is not proof that the phone received a new profile. Keep a compact current-state log with
  last success, new expiry, device, bundle ID, and IPA hash; do not store credentials or health
  data in it.
- Raise a persistent local Windows notification when no verified success exists by the
  three-days-remaining threshold, escalate at two days, and require the USB recovery path inside
  the final 24 hours. Test alerts by forcing each threshold; silent monitoring is not monitoring.
  If Sideloadly exposes no supported command interface for a forced early refresh, keep its daemon
  as the refresh mechanism and let the scheduled task verify/alert—do not build brittle blind GUI
  automation that reports success without evidence.
- Keep the trusted USB cable as the deterministic fallback when Wi-Fi discovery fails. After every
  installer or Apple-device-component update, verify one USB refresh and one Wi-Fi refresh before
  relying on unattended operation again.
- Refreshing the unchanged IPA must not change app code or local data. New source builds are a
  separate upgrade workflow and always require the in-place data-preservation test below.

### Backups and recovery

- Before first use, before every new-IPA upgrade, before any bundle/signing migration, and at least
  weekly during daily use, create the app's existing passphrase-encrypted full database export and
  copy it off the iPhone to a local Windows backup location. Record the passphrase safely outside
  the repository; there is intentionally no recovery if it is forgotten.
- Restore-test an encrypted export before making the iPhone authoritative, and repeat after a
  backup-format or schema change. A successfully written file is not a proven backup until the
  current app can decrypt, import, and reconcile it without overwriting measured days incorrectly.
- Automatic backups are **encrypted** from build 66 (`lib/data/auto_backup.dart`), not yet device-verified.
  - They run on foreground when due, Daily or Weekly, and are off until Akshat sets a backup
    passphrase under **Your data**. The passphrase is kept in the iOS keychain
    (`lib/data/backup_passphrase.dart`).
  - Each run gzips a `VACUUM INTO` snapshot and seals it as an `OSBK` file (`backup_crypto.dart`).
  - The file is decrypted and compared before it is published; the work runs on a worker isolate.
  - The newest 5 go to `OpenStrap Backups`. Plaintext automatic backups are no longer written, and
    old ones are deleted after the first encrypted success.
  - A restore uses the existing **Import a file** path with the passphrase.
- **Still not off-device:** the backup folder is inside the app container and is deleted with the
  app. The manual off-phone copy to Windows (Files / iTunes File Sharing) is still required.
  Encryption uses pure-Dart AES-GCM at about 1.5 MB/s, so a large database takes a while. It needs a
  measured on-phone run and a restore test.
- Never uninstall WHOOP merely because its profile expired. Preserve a verified encrypted export
  while the app still opens, then install the cached IPA over the existing container with automatic
  bundle-ID rewriting off and exact final ID `com.akshat.personal.whoop.5564K8D4SV`. That path is
  proven to advance signing while preserving data and pairing. Backup/delete/clean-install/restore
  remains the fallback only if exact-ID container-preserving recovery fails.

### Physical-device validation matrix

The simulator and a successful build are insufficient for a BLE health app. Run this matrix on
the actual primary iPhone and WHOOP 4.0 band against a release build, with the official WHOOP app
fully quit so it does not own the peripheral:

1. **Artifact/install:** verify the payload exclusions, first Sideloadly install, Developer Mode
   and trust flow, cold launch from the home screen, offline launch, permission prompts, hidden
   HealthKit/widget/Watch surfaces, and exact installed bundle identity/profile expiry.
2. **First pairing:** verify the iOS AccessorySetupKit picker, Bluetooth permission denial and
   recovery, profile entry without HealthKit, full initial drain, correct local computation, and a
   successful encrypted export.
3. **Normal connection:** test foreground sync, screen lock, app backgrounding, Bluetooth
   off/on, airplane mode, Low Power Mode, charging/non-charging, repeated reconnects, and multiple
   drains without duplicate ACK/data or notification re-fire.
4. **Range and restoration:** take the band out of range, wait for disconnect recovery to arm,
   return in range while the app is backgrounded/locked, and prove CoreBluetooth restoration wakes
   the normal resumable drain. Repeat after ordinary system termination if reproducible. Record
   manual swipe-to-force-quit separately: iOS may suppress background relaunch until the user opens
   the app again, which must be documented rather than misdiagnosed as a crash.
5. **Lifecycle:** test app termination and relaunch, iPhone reboot, band reboot, phone storage
   pressure, an overnight background interval, daylight-saving/time-zone changes, and the next
   supported iOS update. After an iOS update, redo pairing/reconnect/restoration and refresh checks
   before declaring compatibility.
6. **Soak:** run at least 72 continuous hours including normal phone use, multiple out-of-range
   events, overnight collection, daily derivation, notifications, and local diagnostics. There
   must be no crash loop, wedged reconnect latch, permanent stale state, UI-isolate stall, data
   loss, or fabricated metric. The active reconnection issue in `bugs.md` must be reproduced and
   resolved or conclusively shown not to affect this iOS path before promotion.
7. **Refresh:** refresh the unchanged cached IPA over Wi-Fi and USB with at least three days left;
   verify the new profile expiry, launch, band pairing, database row counts/key samples, settings,
   and latest sync are preserved. Then exercise all alert thresholds and one failed-network retry.
8. **Expiry recovery:** before live history becomes authoritative, deliberately let a controlled
   profile expire, confirm the expected launch failure, re-sign the same IPA with the same account
   and bundle ID without uninstalling, and verify full data/pairing recovery.
9. **Upgrade:** install a newer versioned IPA over the old one; verify schema migration,
   provisioning, pairing, raw ledger, derived history, encrypted export/restore, background BLE,
   and rollback/recovery using the previous artifact and backup. Never use a downgrade that would
   violate schema or version invariants merely to prove the installer works.
10. **Installer disruption:** simulate the daemon stopped, Windows rebooted, phone unseen on
    Wi-Fi, USB-only recovery, and Sideloadly temporarily unavailable. Confirm alerts arrive early
    and the standard IPA remains usable by the chosen backup signer without changing its bundle
    identity. Activating AltStore/SideStore requires a documented workflow/slot check and verified
    encrypted backup/restore; the selected two-app model does not require removing either app.

### Activation phases and acceptance gates

1. **Scope locked:** target Akshat's iPhone only. Preserve the imported baseline, public origin,
   upstream histories, algorithm/version invariants, Android source as reference, and `bugs.md`
   evidence; Android fixes, builds, and device validation are not part of the personal roadmap.
2. **Lock decisions:** bundle ID `com.akshat.personal.whoop` and the public-GitHub macOS build
   source are locked. GPS route tracking was initially excluded and is now reopened — see the
   engineering-invariants bullet above for the exact scope and what is still unverified. Before
   installation, record the Apple Account/team
   continuity choice, Windows artifact-cache path, encrypted-backup destination, and exact alert
   behavior without credentials or personal data. The installed set is standalone WHOOP plus the
   native AkshatOS hub under free signing.
3. **Build the personal flavor:** the core entitlement/extension/location/network exclusions,
   packaging checks, and tests are implemented. A local installed-profile expiry/status surface
   remains desirable but does not block producing the first controlled candidate.
4. **Produce and inspect one candidate:** build, cache, hash, Sideloadly signing, and installation
   are complete. Import the Android encrypted backup before pairing, then pass exact installed
   identity/profile, pairing, offline, backup, and core BLE tests. Home-screen presence alone is not
   an acceptance gate.
5. **Pilot daily use:** pass the full lifecycle/restoration matrix and 72-hour soak, then pass an
   unchanged-IPA refresh and new-IPA upgrade with data preservation. Android is not an acceptance
   dependency or active fallback for this pilot.
6. **Prove the signing loop:** pass at least two consecutive unattended refresh cycles, alert
   escalation, USB recovery, and the controlled expired-profile recovery. Do not make the iPhone
   authoritative before the encrypted restore test also passes.
7. **Activate daily use:** only after all gates pass may the project status move from active iPhone
   implementation planning to an active iPhone pilot or daily-use status. Keep periodic backups,
   early refresh verification, and regression checks after Sideloadly, Apple-device-component,
   Flutter/Xcode, or iOS changes.

### Documentation and workflow synchronization

`setup.md`, `README.md`, `bugs.md`, and both iOS guides distinguish the personal plan,
the current upstream-capable source, iPhone-only scope, implemented build profile, and unexecuted
verification. The first macOS build, Windows download, Sideloadly signing, and installation are
complete; history migration and the remaining device gates remain.

As implementation proceeds, update all affected sources in the same coherent change:

- Record the artifact/cache/backup paths, exact source/hash manifest, Sideloadly settings,
  monitoring/alerts, and current physical validation in `setup.md` and the guides as they become
  real.
- Keep `.github/workflows/personal-ios.yml` manual, public-repository-only, minimal, and distinct from the
  existing tag release workflow; update the transform and contract tests whenever the Xcode project
  moves.
- Make `ios/Runner/Info.plist`, entitlements, signing configs, Xcode targets, and feature flags enforce
  the chosen capability profile together; remove omitted feature UI/bridges rather than shipping
  misleading controls. Keep generated AccessorySetupKit entries generated and update guard tests.
- Update `CLAUDE.md`, `README.md`, `bugs.md`, setup/guides, workflow/configuration notes, and relevant
  tests whenever a gate becomes implemented or verified. Promote new caveats into their owning
  source of truth and remove superseded planned wording in the same change.

## Working agreement
- **Before removing any feature, screen or tab, audit what only it shows and ask Akshat.** List
  every metric, insight or entry point that would become unreachable, and say whether it is a
  primary WHOOP/wearable metric (recovery, strain, sleep, HRV, heart rate, breathing, stress,
  steps, workouts) or redundant with another screen. Get Akshat's yes per item before deleting it.
  He often wants redundant features gone, but never a core metric lost by accident. Removing a UI
  surface must not stop the underlying computation or storage unless he asks for that too.
- **Plan first, build on the go-ahead.** For a multi-feature request Akshat wants the plan written
  into `todo.md` (with recommendations and the decisions he must make) and no code changes until he
  says go. Once approved he prefers everything in one build. He wants calorie and step numbers
  checked against his own worked examples (`test/run_calories_test.dart`), not just plausible.
- Keep this as one repository. Route byte/protocol work to `packages/protocol/`, metric work to
  `packages/analytics/`, and app/flow/storage/UI work to the root app areas.
- Preserve the algorithm-version rules below: any analytics output change must still be
  reviewed with the matching `kAlgoVersion` decision even though no external package pin changes.
- Treat upstream updates as deliberate reviewed imports; never replace a local package with a
  floating branch dependency.
- Personal product work is iPhone-only. Do not delete the imported Android target merely to narrow
  scope: it is not packaged into the IPA, and retaining it avoids an unrelated destructive diff and
  preserves upstream merge/reference value. Do not build, debug, or extend it unless Akshat reopens
  Android scope.
- Any material platform, capability, entitlement, BLE/background, storage, build/signing, status,
  or deployment decision must update this file and every affected current-state supporting
  document—especially `setup.md`, `README.md`, `bugs.md`, the iOS guides, workflow/configuration
  notes, and recovery instructions—in the same change. Preserve the boundary between accepted
  personal-iPhone plan, current upstream-capable source, implemented personal flavor, and verified
  physical-device behavior.
- **Whenever a new project-owned file or top-level source area is added**, add a bullet under
  `## Files` in the same edit. Files inside an already-indexed imported source area do not need
  individual bullets.
- **Sync documentation locally as work happens; do not commit or push it on its own.** Akshat's
  standing correction (given for `akshatos/`, applies here the same way): a commit-and-push per doc
  note or small script tweak is redundant ceremony. Keep files current locally the whole time —
  that is not optional — but the threshold to commit is a real implementation change, not an
  accumulation of notes. Batch related small changes and commit them together once there is one, or
  push only when Akshat explicitly says to. The one exception is something he needs in hand right
  away.

## Engineering architecture, invariants, and review guidance

Reviewer context. This doc drifts from code between edits — check
`kAlgoVersion` (`lib/compute/derivation_engine.dart`), `schemaVersion`
(`lib/data/db.dart`), and the `version:` line in `pubspec.yaml` directly
rather than trusting a number written here. Where a source comment disagrees
with an implementation, **the implementation wins** — header comments here go
stale (e.g. `lib/compute/substrate.dart`'s file header still describes a
wake-to-wake day model that `calendarDays()` no longer implements; it walks
local midnight to local midnight). The same drift applies to §2's table and
every line-number citation in §3 below — line numbers move on every edit,
symbol names don't; verify against the source, not this doc.

### Project and source-area boundaries

A Flutter app for a reverse-engineered WHOOP 4.0 band. **Fully on-device,
local-first**: BLE offload → SQLite → on-device analytics → UI. No backend owns
user data. Network use is limited to OTA update pointers, opt-in
telemetry/Crashlytics, and BYOK LLM calls.

One monorepo, strict source-area separation — put work in the right tree:
- `packages/protocol` — bytes: GATT, framing, CRC, opcodes, record decode.
- `packages/analytics` — metrics: HRV, sleep staging, readiness, strain.
- the root app (`lib/`, platform folders, and app config) — flows, BLE link
  management, storage, UI.

New opcode/record → protocol. New metric → analytics. New screen/flow/table →
the root app. A change implementing a metric inside `lib/compute` is in the
wrong source area unless it is pure orchestration.

### Architecture map (`lib/`, well over 200 files — these five are the biggest by far)

Line counts drift constantly; don't trust a number here, `wc -l` the file.

| file | owns |
|---|---|
| `data/db.dart` | `LocalDb`: schema ladder (`onUpgrade`), all CRUD, coach views |
| `compute/derivation_engine.dart` | `DerivationEngine`, `kAlgoVersion`, day scheduling, isolate offload |
| `state/app_state.dart` | `AppState` ChangeNotifier — BLE↔DB↔UI orchestration |
| `ble/ble_engine.dart` | GATT connect/drain/history-sync state machine |
| `data/local_repository_impl.dart` | read seam: `day_result`/`metric_series` → screen shapes; zero compute on read |

- `ble/` — engine + `ble_state.dart` **pure policies**: `ReconnectPolicy`,
  `SeqAllocator`, `DrainStopEvaluator`, `RecordGate`, `CounterRegressionDetector`,
  `AckRetryPolicy`, `ChunkFailureLedger`, `DeriveDebouncer`, `AlarmPayloads`,
  `AlarmConfirmation`.
- `sync/` — `sync_policy.dart` **pure policies**: `ClockRef`/`ClockPolicy`,
  `BackfillPolicy`, `MarginalRadioDetector`, `FrameCorruptionDetector`,
  `PostBondTimeoutLoopDetector`, `BondRefusalGiveUp`, `EmptySyncTracker`,
  `StuckStrapDetector`; plus background/headless entries and OTA.
- `compute/` — `substrate.dart` (**single** raw→`Substrate` decode point +
  `calendarDays()` day model), `onehz_pipeline.dart` (pure, isolate-safe per-day
  pipeline), `crossday_pipeline.dart`, `derivation_engine.dart`.
- `data/` — `db.dart`, read seam, `day_label.dart` (the *only* day-label helper).
- `notify/` — `notification_center.dart` is the **single emitter**;
  `fired_keys.dart` is the persistent fire-once guard.
- `coach/` — read-only SQL over allow-listed `v_*` views behind a deny-list guard.
- `ui2/` — 66 files (`lib/ui` was deleted in the UI rebuild): `ui2/theme.dart`
  and `ui2/grammar.dart` (design system), `ui2/charts.dart`, `ui2/screens/`
  (shared metric/trend IA), plus `ui2/onboarding/`, `ui2/activity/`,
  `ui2/profile/`.
- Also `ai/` (BYOK), `gps/`, `health/` (HealthKit/Health Connect export),
  `telemetry/` (opt-in), `widget/` (App-Group snapshot for WidgetKit/watch).

**Storage.** Durable ledger: `decoded_onehz` (1 Hz, `UNIQUE(rec_ts)`,
INSERT-OR-REPLACE) + `decoded_rr` (beats, cascades on eviction) + `raw_archive`
(never pruned; undecodable/unknown-version records) + `raw_records` (retained as
replay/debug ledger and upgrade fallback) + `events`/`band_events`. Derived
output: versioned **immutable** `day_result` (PK `day_id, algo_version`) and
`metric_series` (PK `date,key`, REPLACE).

**Bug-density hotspots** (fix-titled commit churn, last 300 commits):
`state/app_state.dart` 30 · `data/db.dart` 25 · `compute/derivation_engine.dart`
24 · `data/local_repository_impl.dart` 17 · `ble/ble_engine.dart` 12 ·
`main.dart`+`app.dart` 19. Treat diffs in these with extra scrutiny.
`pubspec.yaml` has high raw churn but most of it is release version bumps — not
a hotspot.

### Hard invariants — violating these is a P0 regression

1. **Commit before ACK.** In the history-sync drain (`ble/ble_engine.dart`)
   decoded rows + cursor commit in one transaction *before*
   `buildHistoryResultOk` echoes the verbatim 8-byte HISTORY_END token. The band
   trims flash on ACK. Reordering, or echoing a regenerated/mangled token, causes
   permanent data loss or an infinite re-flood. Never ACK a partial chunk.
2. **`decoded_onehz` stays INSERT-OR-REPLACE keyed on `rec_ts`.** INSERT-OR-IGNORE
   breaks counter-reset recovery. Evicting a row must delete that counter's
   `decoded_rr` beats in the same batch.
3. **Never fabricate a metric.** Absent input ⇒ null / `Metric.absent` / "—". No
   imputation, no substituted defaults, no deriving one metric from another as a
   fallback. Most-violated rule in the repo (§4.1).
4. **Bump `kAlgoVersion`** (`compute/derivation_engine.dart`) whenever any
   analytics *output* changes, including a change under `packages/analytics`.
   Rows are immutable per version; without a bump nothing recomputes. Add a
   changelog entry above the constant.
5. **A bump citing a package change must include that source change.** Verify the
   monorepo commit actually contains it. v43's changelog described an analytics
   fix its dependency pin never contained; the bug stayed live three releases
   and only shipped at v46.
6. **In-tree packages are reviewed commits, never floating dependencies.**
   `ref: main` on analytics shipped main-thread ANRs into 0.9.13/0.9.14. Keep
   the tracked `packages/` sources, `packages/upstream-revisions.yaml`, and path
   dependencies in the same history.
7. **Day labels are LOCAL.** Always `todayLabel()` / `dayLabelOf()` from
   `data/day_label.dart`; never `DateTime.now().toUtc()...substring(0,10)`. Epoch
   timestamps (rec_ts, session bounds, prune cutoffs) are absolute — do not
   "fix" those to local. Day-length arithmetic must not assume 86400 s (DST).
8. **One source per concern.** One raw decode point (`substrate.dart`), one sleep
   segmentation, one readiness, one frame-ingest path (`RecordGate`), one
   notification emitter (`NotificationCenter.emit`). A second path is the bug.
9. **Never prune raw/decoded for a day that is not fully derived.** `day_result`
   has a `partial` column because days with good headline scalars but a failed
   second-half compute were finalized and pruned — unrecoverable. `raw_archive`
   is never pruned.
10. **Heavy compute never on the UI isolate.** Staging/derivation goes through
    `Isolate.run`; analytics ambient globals do not cross the boundary and must
    be re-armed inside the closure.
11. **Migrations additive and idempotent.** `onUpgrade` is a sequential
    `if (oldV < N)` ladder; `onOpen`'s `_repairOpenSchema` re-runs creators so
    same-version merged builds self-heal. Migrations run inside `openDatabase`
    under iOS's CPU watchdog — keep them cheap. `PRAGMA journal_mode=WAL` must go
    through `rawQuery` (it returns a row; `execute` bricks iOS Darwin sqflite).
12. **Headless/background sync serializes through `HeadlessSyncGate.tryRun`** —
    skip, don't queue.
13. **The coach reads only allow-listed `v_*` views** — never `decoded_*`,
    `raw_*`, or base tables.
14. **Live high-rate streams (0x28/0x2B/0x33) are never persisted** — RAM-only.
15. **Dangerous opcodes are never auto-sent** (`dangerousCmds`, gated in
    `ble/ble_engine.dart` wherever a write checks it): force-trim, reboot,
    power-cycle, firmware load.

### Recurring bug patterns — what actually ships broken here

#### 4.1 Fabricated / non-abstaining metrics ("honesty" violations)
The project has an explicit never-impute rule and keeps breaking it. Instances:
two copies of a `100 - readiness` stress fallback; RHR falling back to daytime HR
("Readiness 100" ten minutes after first wear); literal `"null"` rendered for
oxygen dips; a skin-temp section gated on `spo2` presence; `StageBars` drawing an
*invisible gap* for an absent sleep stage; pace showing absurd numbers instead of
"—"; a false empty state instead of a retryable error; Bluetooth-off reported as
"no strap found". One is still open: stress shows a confident score on ~20 min of
data.
**Ask on any metric diff:** what does this return when the input is missing or
thin? Anything other than null/"—"/an honest low-confidence envelope is a bug.

#### 4.2 Readiness / recompute-idempotence — the largest single cluster
Eight distinct fixes and four sequential attempts at one user-visible symptom.
Readiness recomputes on *every* BLE drain against a moving 28-day baseline, so
any non-idempotent step corrupts it: duplicate-day appends into the baseline
(MAD == 0 ⇒ robust z abstains ⇒ blank ring), rebuilding on persist but not on
read, withholding a score while the overnight builds but not preventing a
ready→ready drift, flashing a stale value before today settles, and saturation
bouncing the ring to 100.
**Ask:** if this runs three more times today with slightly more data, does the
persisted scalar stay stable? Does it append where it should replace?
**Footgun:** `LocalDb.metricSeries(limit: n)` is `ORDER BY date ASC LIMIT n` =
the **oldest** n. For a trailing window use `trailingSeriesValues(key, n)`.

#### 4.3 Sticky boolean latches never reset on the failure path
Self-identified as recurring in the repo's own commit messages ("same shape as
the foregroundActive bug from a couple days ago"). A flag is set, an error path
returns early without clearing it, and sync wedges until force-close. Known
instances: `foregroundActive`, `markForegroundIntent`, `_offloadActive`,
`_drainingOffloadFrames` (no `try/finally`), a sticky standard-HR fallback that
silently zeroed step calibration, and trusting a stale `isConnected`.
**Ask:** every flag set in this diff — is it cleared in `finally`, on timeout, and
on the give-up branch?

#### 4.4 Heavy compute on the main/UI isolate → ANR, jank, stuck launch
Recurred one build apart: `cardioStager`'s per-30s Lomb–Scargle on the main
isolate (Android ANRs every ~30 s), then the *entire second half* of
`_derivePreparedDay` running on the UI isolate for the foreground pass that fires
on every sync. Also: app freezing during backfills, unbounded pre-`runApp` inits
stalling launch, a dark-mode rebuild storm starving background BLE.

#### 4.5 `context` / Provider used after `await` or after unmount
Repeated crash source: `Provider._inheritedElementOf` null in `dispose`,
`context.read` in `dispose`, bare `Navigator.pop()` after an `await`, missing
`mounted` guard on a post-navigation reload.

#### 4.6 Notification re-fire, dedupe race, and gating bypass
Call sites promised "at most once per day" with nothing enforcing it, so
derivation re-runs re-fired them across illness, anomaly, temperature, readiness,
HR-shift, recovery-ready, step-goal and auto-workout alerts. Then the stress
screen called `NotificationService.presentEvent` **directly**, bypassing both the
prefs gate and the new dedupe guard. Then a TOCTOU race let two overlapping
`emit()`s both pass `hasFired`.
**Flag:** any direct call into `NotificationService` that skips
`NotificationCenter.emit`, and any check-then-record without the lock.

#### 4.7 Capability wired into one call path but not all N
The most damaging instance: `FirmwareAwareR24Decoder` existed but was not wired
into all three decode paths (`ble_engine.dart`, `db.dart`, `substrate.dart`), so
a real user's 88-byte v12 records were 100% silently archived — total sync
outage. Also: HealthKit export gated on `day_result` and never session-triggered
(a workout finished offline never exported); auto-detected workouts never
reaching the `sessions` table, invisible to both AI Coach and Health export.
**Ask:** how many call sites exist for this concern, and does the diff cover all
of them?

#### 4.8 UTC-vs-local and day-boundary math
Fixed, then reintroduced *in the same file* (SRI's hypnogram grid used raw UTC
time-of-day right below the fix for that exact mistake), then again in the
`v_sessions` view (AI Coach mis-dated workouts). Also: day math assuming 86400 s
breaking on DST, a briefing greeting "morning" in the afternoon, sleep not
detected in non-UTC timezones, and an alarm armed in the phone's clock frame
instead of the strap's RTC frame so it never fired.

#### 4.9 Package revisions / lockfile / release metadata
Four separate passes. Committed path `dependency_overrides` broke a release;
`pubspec.lock` resolved a package via a stale local path; floating `ref: main`
rode analytics v42 into 0.9.13; a PR bumped `kAlgoVersion` while the lock still
pinned the pre-fix analytics commit, requiring a manual merge-order gate; and
`0.9.17+1` shipped versionCode 1 → `INSTALL_FAILED_VERSION_DOWNGRADE`, making
the release uninstallable.
This monorepo tracks protocol and analytics under `packages/` and resolves both
through paths in `pubspec.yaml`; the package trees and app therefore move in the
same Git history. Do not use `pubspec_overrides.yaml` or restore floating Git
refs for them. Keep `pubspec.lock` consistent with those paths. `version:` must
always keep its `+BUILD` suffix, and the iOS widget/watch
`MARKETING_VERSION`/`CURRENT_PROJECT_VERSION` are bumped manually and drift.

#### 4.10 Duplicated / inconsistent values across screens
Today showed strain/sleep/stress twice; a week-load wheel duplicated the strain
figure; the steps figure disagreed across screens through three separate
unification attempts and is still being fixed; two different HRV baselines both
labeled "baseline" on one screen.

#### 4.11 Chart / hypnogram render regressions
`Hypnogram.plot` lost its `RepaintBoundary` in a refactor and stayed lost through
three rewrites before being restored. Also recap scrub-marker misalignment,
`GanttPainter` needing restoration, and `RangeError` from unpadded substrate
fields. Rendering regressions here surface as test failures rather than obvious
visual bugs — check whether removed wrapper widgets were load-bearing.

### How to review this repo

**CI does run on PRs.** `.github/workflows/test.yml` runs `flutter analyze` +
`flutter test` on every pull request and on push to `main`.
`.github/workflows/build.yml` (the APK/IPA release) is the one gated to
`push: tags: ['v*']` — it doesn't touch PRs. `test/` is large and not flat
(it has `adapters/`, `support/`, and other subdirectories alongside the
top-level test files). Several regression tests are named for the bug they pin
(`readiness_flash_test`, `readiness_freeze_test`, `readiness_saturation_test`,
`readiness_baseline_pollution_test`). A behavior change with no accompanying
test is a real finding — CI passing doesn't mean the right test exists.

`analysis_options.yaml` is stock `flutter_lints`: no custom rules, no excludes,
no strict language modes.

**Deprioritize:** formatting, import ordering, naming style, `const`
constructors, string-interpolation preference, missing dartdoc, "extract a
widget", and general Flutter/Dart idiom advice not tied to a behavior change.

**Prioritize:** the invariants in §3, the patterns in §4, absent-input handling on
every metric path, idempotence under repeated derivation, flag reset on failure
paths, transaction ordering and durability around BLE sync, isolate boundaries,
migration safety, and anything that could display a number the data does not
support.

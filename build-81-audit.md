# Build-81 audit (from installed build 80)

Akshat installed build 80 and asked for: a weight field in Quick add; how the recovery score is
made, what it should include, and why a 5 h 30 min night still scored 88; why a cinema visit
and lying in bed awake count as sleep, and how deep sleep was judged "typical"; and a general
end-to-end audit (open bugs, UI problems, how it looks, how it is wired, improvements and
features from the data the app already has).

**Status:** Audit and plan only; no code changed. Akshat's decisions are recorded at the end
("Decisions (Akshat)"); the Live Activity root cause needs phone data before any fix. The evidence comes from source reading, screens
rendered on Windows with test data (dark theme, phone width), and the research listed at the end.

## 1. Quick add has no weight

**Finding.** Quick add (`QuickAddSheet`, `lib/ui2/screens/food_diary.dart`) takes a name,
calories and macros. Each diary entry already has a quantity and unit, but Quick add leaves the
quantity empty, so a quick-added item can never show "250 g".

**Proposal.** Add an optional **Weight (g)** field beside Calories. It is stored as the entry's
amount in grams, and the row reads "Protein shake · 250 g" like every other entry. It is for
reference only: it does not scale the macros you typed. Optional extra: a **Save to My foods**
switch (off by default) that turns the entry into a saved food with that weight as its serving,
so the next time it can be logged by grams.

## 2. Recovery score

**How it works now** (`packages/analytics/.../wellness/readiness_composite.dart`):
- **Inputs and weights:** four overnight measurements. HRV 40%, resting heart rate 30%,
  breathing rate 20%, skin temperature 10%.
- **Your own baseline:** each night is compared with your own last 28 nights, and each input
  needs at least 14 of them. An input that is missing is dropped and the other weights scale up.
- **The scale:** the weighted comparison is turned into 0–100. A night exactly at your usual
  level scores 50. About two standard deviations better than usual scores about 88.
- **No sleep input:** sleep duration, sleep debt and yesterday's strain are **not** inputs.

**Why 5 h 30 min still scored 88.** The score only looks at heart signals. A night where HRV is
well above your usual level and resting HR is below it scores high however short it was. One
likely reason HRV looked good is that a short night is mostly early-night sleep. Early-night
sleep is mostly deep sleep, where HRV tends to run high, so a short night's average is not
like-for-like with full nights. This is a hypothesis. Readiness → **What drove it** for that day
would show which input pushed the score up.

**What other trackers include** (research below):

| Input | This app | WHOOP | Oura Readiness | Garmin Training Readiness |
|---|---|---|---|---|
| HRV vs own baseline | yes (40%) | yes, dominant | HRV balance (multi-week) | HRV status |
| Resting HR | yes (30%) | yes | yes, plus recovery index (sleep time after HR bottoms out) | via recovery time |
| Breathing rate | yes (20%) | yes | — | — |
| Skin temperature | yes (10%) | — (shown separately) | yes | — |
| Last night's sleep | **no** | yes: sleep performance (asleep ÷ need) | yes | yes |
| Recent sleep debt | **no** | through sleep need | sleep balance (2 weeks) | sleep history (3 nights) |
| Recent training load | **no** | through sleep need | activity balance, previous day | acute load, recovery time |

WHOOP reports that HRV carries most of the predictive value and that sleep matters less, but
sleep is still in the score. Every major tracker includes last night's sleep; this app does not.

**Proposals.**
- **R1 — add sleep sufficiency (recommended).** Add last night's asleep time ÷ sleep need as a
  fifth input. The app already computes sleep need in the Sleep Coach, but does not show it. A
  short night then pulls the score down in proportion, and "What drove it" names sleep. Before
  release it would be checked against worked examples, e.g. your 5 h 30 min night. Suggested
  weights: HRV 35%, resting HR 25%, sleep 20%, breathing 12%, temperature 8%. If no sleep is
  detected, the input is dropped, as today.
- **R2 — recent sleep debt and training load (not recommended yet).** Garmin and Oura add these.
  They overlap with R1 and with HRV, and would make the score harder to explain. Revisit after R1
  has run for a few weeks.
- **R3 — like-for-like night HRV (optional, smaller).** Measure HRV over a comparable part of
  every night, e.g. the first four hours of sleep, so short and long nights compare fairly.
- **History:** past scores stay as they were. Each day's readiness is stored when computed; only
  nights still held in raw data, about the last three days, and future nights would use the new
  formula. A one-off recalculation of older days from stored nightly values is possible, but is a
  separate decision.

## 3. Sleep detection: the cinema, lying in bed awake, and deep sleep

**How the night is found now** (`advanced_stager.dart`, `segment.dart`, `substrate.dart`):
1. **Search window:** from noon the day before up to now.
2. **Candidate blocks:** a block counts when the wrist is still at least 70% of the time over
   15 minutes and its average heart rate is at most 5% above the **median heart rate of that
   whole window**.
3. **Joining:** blocks less than 60 minutes apart are joined into one night.
4. **Choosing the night:** the night is the joined block with the most sleep, with a bonus for
   sitting near your usual mid-sleep time. It must be at least 3 hours long. Blocks centred
   between 11:00 and 20:00 face an extra test.
5. **Staging:** inside the chosen window, stages compare each 30 seconds with that night's own
   heart rate.

**Why sitting in a cinema or lying in bed awake counts.** Sitting still in the evening with a
calm heart rate passes step 2, because "within 5% of the day's median" is a loose test. A
daytime heart-rate baseline is built and passed to the sleep code, but the code never uses it;
the source comment says so (`segmentSleep`: "hrBaseline is CURRENTLY UNUSED"). So the start of
the night is never checked against the drop in heart rate that real sleep onset brings. Once a
still, calm stretch is inside the window, staging compares it with the window's own heart rate,
so a calm awake start reads as light sleep. This is a known weakness of movement-based sleep
detection: it catches sleep well but often misses quiet wakefulness. Adding heart rate helps.

**Why it corrected itself by the afternoon.** The night is recalculated on every sync. The most
likely sequence: when you first looked, the band had not yet sent the whole night, so the
calculation ran on partial data and the cinema block was the best candidate. Once the full night
arrived, the real 00:30–06:00 block won on asleep minutes and timing. This fits the code but
cannot be proven from here. If a short, still, calm gap separates a cinema block from real
sleep, it can still be joined into the night (rule 3).

**Deep sleep around an hour in 5 h 30 min.**
- **It is plausible.** Deep sleep is concentrated in the first third of the night, while REM
  builds up towards morning. A night cut short loses mostly REM and keeps much of its deep sleep.
- **"Typical" compares minutes, not percentages.** It sets the night's deep minutes against your
  own last 28 nights, so an hour can be typical even on a short night.
- **Treat stage minutes as rough.** The app's own wrist staging scores a four-stage agreement of
  only κ 0.13 against lab sleep studies on held-out data (`cardio_stager.dart`). The code already
  flags deep sleep as low-confidence. Total sleep and timing are far more reliable than the
  deep/REM split.

**Proposals.**
- **S1 — heart-rate-confirmed sleep start (recommended).** Use the unused baseline plus your own
  sleeping heart rate from recent nights. The night starts only once heart rate has dropped
  towards your sleeping level. Still-but-awake time before that, like a film or lying in bed on
  your phone, stays outside total sleep. The window can still show when you lay down.
- **S2 — no joining across an awake gap (recommended).** Two blocks are not joined when heart
  rate between them stayed at waking level, so the walk home from a cinema keeps it separate.
- **S3 — "Was this sleep?" prompt (recommended).** When the night starts 90 minutes or more
  earlier than usual, the Sleep screen asks once. One tap trims the start to the point where
  heart rate dropped. This uses the existing "Fix sleep times" override, so it is stored and
  respected on every recalculation.
- **Phone signals (not proposed).** iOS gives this app no way to see screen use (Screen Time
  data needs a capability free signing does not grant). The phone's stillness and step counts
  cannot tell scrolling in bed from sleeping.
- **History:** S1 and S2 change the analytics, so the algorithm version goes up. Nights still in
  raw data (about three days) and all future nights are recalculated; older nights keep their
  stored values.

## 4. Whole-app audit

### Bugs found
- **B1 — Readiness ring is empty (confirmed in render).** The Readiness screen's ring draws only
  its grey track. The arc is painted with a fully transparent base colour plus a gradient, and
  Flutter applies the base colour's transparency to the gradient too (`Ring` with
  `solid: false`, `lib/ui2/charts.dart`). Today's ring is drawn solid, so it looks right. The
  same faded style is used by the between-sets rest timer, which the personal build does not
  show. Fix: give the faded arc an opaque base colour.
- **B2 — Sleep start is not checked against heart rate.** See §3.
- **B3 — "What moves it" can never appear.** Metric screens have a "What moves it" section
  (e.g. "late meal: +2.1 bpm resting HR"). It is fed only by journal tags, and the journal was
  removed from the personal build, so for you it is permanently empty.
- **Open phone checks:** the Live Activity (lock-screen banner) diagnostics added in builds
  75–78 have not been reported back; Status → Lock screen · Live Activity would show the cause if
  it still fails. The build-78–80 checks in `todo.md` are also still open.
- **Code health:** the app code analyses with no errors or warnings, only 113 style notes. Build 80
  passes the full Linux suite (3,386 tests).

### How it looks (rendered at phone width, dark)
- **What works:** Today, Trends, Sleep and Readiness are clean and consistent. They use flat
  cards, one colour per area, large numbers and short labels.
- **Too much text:** the live workout screen ("Budget uses distance; ACSM uses distance. Both
  exclude resting energy already in BMR.", plus a paragraph under cadence), the maintenance
  sheet's closing paragraph, and the weight card's instructions. These go against the "no
  paragraphs" direction.
- **Unclear label:** the Today strain card reads "Today's target 11.4 met". "met" can be misread
  as the unit MET. Proposed: "Target 11.4 · reached".

### How it is wired
- **One source per concern:** one sleep segmentation, one readiness and one maintenance
  calculation. Screens read stored results; nothing on screen recomputes.
- **Stored but never shown:** much is computed and stored but not shown. That includes sleep need
  and debt, sleep regularity, bedtime consistency, breathing variability, heart-rate dip and
  training load. They are the cheapest source of new features because their history already
  exists.

### Improvements and features from data already collected
- **F1 — Recovery with sleep:** R1 above.
- **F2 — Sleep-start fix and "Was this sleep?":** S1–S3 above.
- **F3 — "What moves your recovery":** replace the dead journal source (B3) with patterns from
  what you already log: last meal time, day's calories and protein, evening workouts, strain,
  bedtime and steps. Example: "Nights after eating past 22:00: resting HR +3 bpm (9 nights vs
  31)". Shown with counts, worded as patterns rather than causes, and only once there are enough
  nights of each.
- **F4 — Weekly summary:** a Monday card on Today for the past week. Average recovery, sleep and
  strain; steps; eaten vs maintenance; and weight trend. One card, no paragraphs.
- **F5 — Bedtime consistency:** a row in Sleep → Against your usual, using the sleep-regularity
  data already computed.
- **F6 — Shorter copy:** trim the wordy spots above and fix the strain-target label.
- **F7 — Quick add weight:** §1.

## Decisions for Akshat
1. **Quick add:** weight field only, or weight plus "Save to My foods"? *Recommended: both, the
   save switch off by default.*
2. **Recovery:** add sleep sufficiency (R1)? *Recommended: yes, with the weights above.* Like-for-
   like night HRV (R3)? *Recommended: later, after R1.*
3. **Past recovery scores:** leave them as recorded, or recalculate history from stored nightly
   values? *Recommended: leave them; new formula from build 81 on.*
4. **Sleep detection:** S1 + S2 (heart-rate-confirmed start, no joining across awake gaps)?
   *Recommended: yes.* S3 "Was this sleep?" prompt? *Recommended: yes.*
5. **Bug fixes B1 and F6 copy trims:** *Recommended: include.*
6. **Features F3 (what moves your recovery), F4 (weekly card), F5 (bedtime consistency):** which,
   if any, in build 81? *Recommended: F3 and F5; F4 optional.*

## Research sources
- WHOOP recovery inputs and weighting:
  <https://www.whoop.com/thelocker/how-does-whoop-recovery-work-101/>,
  <https://www.whoop.com/thelocker/podcast-40-whoop-recovery-maximize-readiness/>,
  <https://www.whoop.com/ca/en/thelocker/adding-respiratory-rate-to-recovery>
- Oura readiness contributors: <https://ouraring.com/blog/readiness-score/>,
  <https://support.ouraring.com/hc/lv/articles/5949130374547-Glossary>
- Garmin Training Readiness:
  <https://www8.garmin.com/manuals/webhelp/GUID-31D23DBB-57C2-4DF7-A0C9-8D1A00AB4BE7/EN-US/GUID-C21BE0C8-A08E-4DA1-B6C6-2E0E2DDDB372.html>
- Movement-based sleep detection misses quiet wakefulness; heart rate improves wake detection:
  <https://pmc.ncbi.nlm.nih.gov/articles/PMC4139737>,
  <https://www.dovepress.com/actigraphy-based-sleep-detection-validation-with-polysomnography-and-c-peer-reviewed-fulltext-article-NSS>,
  <https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7889416/>
- Deep sleep concentrated early; restriction cuts REM first (studies disagree on how much deep
  sleep is kept): <https://pmc.ncbi.nlm.nih.gov/articles/PMC2635586>,
  <https://dx.doi.org/10.1093/sleep/16.2.100>

## Decisions (Akshat)
- **Quick add:** weight field plus a **Save to My foods** switch (off by default). Also show all
  macros (protein, carbs, fat, fibre) on the sheet directly — no "Other macros (optional)"
  dropdown, which no other screen uses. Blank still means not tracked.
- **Recovery:** Claude's judgment → R1 as proposed (sleep sufficiency as a fifth input; HRV 35,
  resting HR 25, sleep 20, breathing 12, temperature 8); R2/R3 not now; past scores left as
  recorded.
- **Sleep detection: no change in build 81.** Akshat looked at 00:00 and slept at 00:30, so the
  wrong night was the provisional answer before the real night existed; the afternoon
  recalculation was right. Because detection works on finished nights, and night-time awakenings
  must keep working, Akshat chose not to touch it (S1–S3 and the provisional hold are dropped).
  Changes could only be checked against synthetic nights and the one public real-night fixture,
  not his own nights.
- **Bugs and wording:** fix the Readiness ring (B1); shorten the wordy screens and the strain
  target label (F6), Claude's judgment on wording.
- **What moves it:** Claude's judgment → replace the journal source with F3 ("What moves your
  recovery" from logged meals, workouts, bedtime and steps), on Recovery, HRV, resting HR and
  Sleep; shown only with enough nights, with counts, as patterns not causes.
- **Bedtime consistency (F5):** yes.
- **Weekly card (F4):** yes — one Monday card on Today comparing the past week with the week
  before: recovery, sleep, strain, steps, eaten vs maintenance, weight trend.
- **Live Activity:** still not showing on build 80. Evidence so far:
  - **Phone:** iPhone 17, iOS 26.6.2; WHOOP's Live Activities switch and lock-screen access are on.
  - **App side works:** Status reads On; on resume it reported "Updated" (iOS already held a WHOOP
    activity), and the one-minute sample reports "Started". ActivityKit accepts and keeps the
    activities, yet nothing is drawn on the lock screen.
  - **The shipped extension is correct:** the build-80 IPA's `OpenStrapWidgetExtension.appex`
    (`com.akshat.personal.whoop.activity`, widgetkit point, iOS 17 minimum, 0.9.47/80) contains
    exactly the workout Live Activity, with attribute types identical to the app's.
  - **Sideloadly keeps it:** it does not drop plugins (`drop_plugins = 0`), has App IDs to spare
    (9 remaining) and installed at the exact final ID with no error.
  - **Dynamic Island:** an empty black pill appears when the sample runs. iOS holds the
    activity, but nothing is drawn inside it.
  - **Root cause (crash report `OpenStrapWidgetExtension-2026-10-07-155134.ips`, 0.9.47/80,
    iPhone18,3):** iOS kills the extension the instant it launches, before any of its code runs:
    `EXC_BAD_ACCESS (SIGKILL)`, termination namespace **CODESIGNING**, indicator
    **"Invalid Page"**, no images loaded. It is signed as
    `com.akshat.personal.whoop.5564K8D4SV.activity`, team `5564K8D4SV`, development category, on
    a device with the code-signing monitor active. So the failure is the extension's signing as
    installed, not the app code, the banner design or iOS settings.
  - **Ruled out:** missing extension, dropped plugins, attribute mismatch, missing widget in the
    bundle, missing header space for a signature (12 KB free), and the absence of a build-time
    signature (the main app has the same unsigned layout and launches fine).
  - **Signing evidence (Sideloadly 0.70.1 log, build-80 reinstall, exact-ID mode):** Sideloadly
    looked up and provisioned **one** App ID only ("Using app ID "WHOOP" with id 63422US4TQ"),
    with no App ID or profile for the extension. The extension
    (`com.akshat.personal.whoop.5564K8D4SV.activity`) is therefore signed under the app's
    profile, whose identifier does not cover it, and iOS's code-signing check kills it at launch.
    **Confirmed root cause:** the installer does not provision the extension, not app code.
  - **Both bundle-ID modes fail:** the pasted log was already an automatic-mode install ("will
    mangle bundleID"), and the exact-mode installs of builds 74–80 never showed the banner either.
    Sideloadly 0.70.1 with this free account provisions only the app's App ID in either mode, so a
    Live Activity cannot render through this installer.
  - **Recommendation for build 81 (needs Akshat's yes, per the feature-removal rule):** drop the
    Live Activity. Remove the extension from the personal IPA and the Status "Live Activity" row,
    and stop the app's start/update calls. Only the never-working lock-screen banner becomes
    unreachable: no metric, workout recording, voice cues or notification is affected. The
    alternatives are leaving the empty Dynamic Island pill, or a different installer (AltStore /
    SideStore), which is outside the two-app plan.

## Implemented in `0.9.48`/`81` (approved by Akshat)
- **Quick add:** protein, carbs, fat and fibre all sit on the sheet in two-column rows (the
  "Other macros" dropdown is gone). An optional **Weight (g)** is stored as the entry's amount
  and shows on the row; it scales nothing. A **Save to My foods** pill (off by default, new
  entries only) also saves the entry as a food: per that weight in grams, or one serving without
  one, and links the entry to it. It needs a name.
- **Recovery (algorithm 91):** sleep is a fifth input, scored against your own trailing
  `tst_min` nights (shortfall in full, surplus capped at +1 z). Weights are HRV .35, RHR .25,
  sleep .20, breathing .12, temperature .08 in both the score and the "What drove it" breakdown,
  which gains a Sleep row linking to the Sleep metric. Worked check: a 5 h 30 min night against a
  7 h usual takes more than 15 points off an otherwise strong night. Older stored scores keep
  their formula.
- **Readiness ring:** the faded arc paints with an opaque base colour, so the Readiness screen's
  ring draws again (confirmed in a render).
- **What moves it (personal build):** patterns from logged meals, workouts, strain, steps and
  bedtime replace the journal source on Recovery, HRV, resting HR and Sleep
  (`lib/data/recovery_movers.dart`).
- **Bedtime consistency:** a row in Sleep → Against your usual (spread of the last 14 bedtimes).
- **Monday card:** on Mondays the Today week card shows last week (Monday–Sunday): recovery,
  sleep, strain and steps averages with their change from the week before, the deficit, km and the
  weight change; other days it stays "This week".
- **Shorter text:** live workout and run calorie notes, the cadence card, workout setup notes,
  the maintenance sheet and the weight card; Today's strain reads "Target 11.4 · reached".
- **Live Activity removed:** no extension in the personal IPA, `NSSupportsLiveActivities` and the
  workout marker forbidden, the validator refuses any app extension, no activity is requested and
  the Status row is gone.
- **Sleep detection:** unchanged, as decided.
- **Validation:** the 68 affected test files (1,020 tests, 90 intentional skips) and the personal-
  profile gate pass locally, plus the eight personal-iOS contract tests and analysis (no errors or
  warnings); Linux CI runs the full suite on push.

# Build 90 Research Pass: Brief For The Research Agent (Codex)

**Status:** The first pass is done (`build-90-research.md`). Akshat reassigned it to Claude
because Codex's usage was exhausted, so Claude is the single research agent for Build 90; read
"Codex" below as whichever agent holds that role. Reuse this brief for any follow-up pass.
A prompt, not findings and not implementation approval.

You are the only agent doing internet research for Build 90. Claude is working on the app's
screens in a separate branch at the same time. This pass is research and analysis only.

## Ground rules (read first)

1. **Instructions.** Read the workspace root `CLAUDE.md` (especially the Data egress policy),
   then this project's `CLAUDE.md`, then `todo.md` (Build 90 section), `build-90-audit.md`
   ("Complete App-Wide Worklist", "Inherited Measurement And Storage Investigations"),
   `metrics-accuracy-research.md`, `metrics-map.md`, `build-88-plan.md`, `bugs.md` and
   `background-sync-plan.md`. `metrics-accuracy-research.md` is the completed Build 88 desk
   research: build on it, verify it and extend it. Do not redo it from zero, and say where
   you confirm, correct or supersede it.
2. **Files.** Create exactly one new file, `build-90-research.md`. Do not edit any other
   tracked file, source code or test. Do not commit and do not push; Claude reviews and
   commits it. Personal-data-derived numbers (see rule 4) go only in `build/research-local/`,
   which Git ignores.
3. **No private data leaves this PC.** Search queries, URLs and anything sent to a website
   must be generic and public ("Lomb-Scargle unevenly sampled HRV normalization"), never
   Akshat's values, dates, logs, database contents or file names. Public reading and
   downloading of papers and documentation is pre-approved.
4. **Local data, local only.** Where a question needs evidence from Akshat's own recordings
   (for example how often a record type or RR count occurs), you may read local exports or
   logs on this PC, but write the counts only to `build/research-local/`, and in
   `build-90-research.md` say only what kind of evidence it was and what it decided.
5. **If internet access fails, stop and report it.** Never answer a research question from
   memory and present it as researched.

## The standard Akshat set

Akshat wants every number in the app to be precise and defensible, with no assumptions. For
each question:

- **Every constant needs a basis.** Either a primary source (with the exact table, equation or
  figure it comes from), a derivation you show, or a test against data. If none exists, say so
  plainly. The app must then abstain ("—") rather than guess.
- **Source quality, in this order:** standards and consensus documents (Task Force of the ESC/
  NASPE 1996 for HRV, AASM scoring manual, ACSM equations, the 2024 Adult Compendium of
  Physical Activities); peer-reviewed primary studies and meta-analyses (PubMed, PMC, Google
  Scholar, journal sites, IEEE Xplore, arXiv for methods); official platform documentation
  (Apple Developer docs and WWDC sessions, Dart/Flutter API docs, IANA tz); the protocol's
  public reverse-engineering sources (the OpenStrap upstream repositories this monorepo
  imports, and other public WHOOP 4 protocol work). WHOOP's own public support/Locker
  articles describe intended behaviour but are not ground truth. Blogs, forums and AI
  summaries are leads only: trace them to the primary source or discard them.
- **Search broadly.** Use several databases and sites per question, not the first result.
  Look for disagreeing evidence on purpose and report it. Prefer validation studies that
  match this hardware (wrist PPG plus accelerometer, 1 Hz heart-rate records with reported
  RR) and say when a study's population or device does not transfer.
- **Record for every source:** full citation, link, year, population/device, the number you
  used and where it appears in the source, and the access date. Keep quotes short.

## Questions

Each question names the current code. Read it before researching. Line numbers drift, so use
symbol names. For every question, give the verdict format at the end of this file.

### A. Heart and HRV

- **A1. Beat continuity after dropouts.** Build 89 accepts beats as adjacent within 1000 ms
  (`kBeatAdjacencyTolMs`, analytics `onehz/util.dart`) because WHOOP 4 beat timestamps carry
  the 1 Hz record's phase, not the beat's own time. `correctRr` (analytics) re-anchors
  across gaps. Question: how should RMSSD and the corrected NN series treat genuine dropouts
  under record-stamped timing? Does a 1000 ms tolerance bias RMSSD, and how would we bound
  that? Cover artefact-correction methods (for example Lipponen and Tarvainen 2019),
  the Task Force rules, and minimum clean-data requirements for 5-minute and nightly RMSSD.
  Keep the 1000 ms rule unless evidence shows a better one.
- **A2. Frequency-domain methods under gaps.** `hrv_freq.dart`, `resp_rate.dart`,
  `cardio_stager.dart` and `cardiac_coherence.dart` use Lomb-Scargle. Question: the correct
  power normalisation for unevenly sampled, gapped RR series (Laguna et al. 1998 and later
  work); whether to time the series by beat-sum or wall clock; and the minimum coverage for a
  valid LF/HF or respiratory estimate. Which current outputs are affected?
- **A3. Which outputs each A1/A2 issue reaches.** Trace every consumer (nightly HRV, rolling
  curves, PRSA, irregular-rhythm screen, respiration, staging, coherence) and say whether a
  change touches a headline number (needs Akshat's approval) or only a secondary one.

### B. Sleep

- **B1. Restlessness.** The restlessness map tests absolute distance from 1 g. Question: is
  that valid across postures and sensor scale? Compare actigraphy definitions (ENMO, MAD,
  van Hees HDCZA, Cole-Kripke, Sadeh) and pick one with a cited threshold, or say what
  measurement would set it. Keep separate from the shipped relative-stillness breathing rule.
- **B2. Sleep accounting.** Settle with sources: how sleep debt should carry forward (and
  over how many nights); one definition of an awakening (AASM wake-bout rules); whether short
  REM bouts may be removed by a minimum-bout rule; how to show sleep cycles when they cannot
  be determined (absent, never zero); and the minimum recorded coverage before a duration
  (total sleep, stage minutes) is shown. Code: `stager.dart`, `crossday_pipeline.dart`,
  `derivation_engine.dart`, `sleep_detail.dart`.
- **B3. Stage validity.** What can wrist PPG plus accelerometer staging honestly claim?
  Collect validation studies of comparable devices against polysomnography (agreement,
  kappa, per-stage bias). Judge the current stage cutoffs against them. Recommend keep,
  change (with exact values and source) or "needs reference recording". Do not tune to
  expected stage percentages.

### C. Time, minutes and travel

- **C1. Travel and time zones.** Akshat travels. Define exactly how a day is grouped when the
  phone changes zone: which zone a recorded day belongs to, how a night that crosses a zone
  change is assigned, how re-derivation of a retained day must not move its edges, how
  bedtime consistency and sleep regularity (Phillips et al. 2017 SRI) are computed across
  zones, and how DST nights of 23 or 25 hours count. Research the platform facts: what iOS
  exposes (`TimeZone`, significant time change notifications), what Dart's `DateTime` can and
  cannot do without the IANA tz database (`package:timezone`), and how Apple Health and other
  wearables record zone per sample. Output a precise storage rule (for example store the IANA
  zone and UTC offset per day) and the edge cases a test must cover.
- **C2. Minutes worn.** Two definitions exist (`metric_series` counts minutes with any record;
  the day wear block bridges runs). Give one definition with a cited basis (wear-time
  literature for wrist devices, such as Choi et al. 2011 and Troiano et al. 2008, adapted to a
  1 Hz record stream), including how a gap is classified and how charging and confirmed
  off-wrist events (`band_events`) separate "off" from "not yet transferred".
- **C3. Timestamps that mean two things.** Settle the meaning of a food entry's time (when
  eaten versus when logged, for backdated Quick add) and of a day's weight when it is
  re-entered (first, last or a defined morning reading). Compare conventions (Apple
  HealthKit sample start/end dates, common diary apps) and recommend one.

### D. Strain and load

- **D1. The quiet-day baseline.** Strain subtracts a population quiet heart-rate-reserve
  baseline (`q = .20`, see `quietHrr` in `lib/compute/` and `build-88-plan.md` D3). On a
  long quiet day it can cancel real workout effort; Build 89 added a session net-TRIMP floor.
  Research TRIMP (Banister, Edwards, Lucia), heart-rate-reserve definitions (Karvonen), how
  resting/quiet baselines are justified, and whether a personal quiet baseline is better
  supported. Give the exact rule and the data it needs. The strain target stays withheld.

### E. Band data, decoding and transfer

- **E1. Older R10-lite heart rate.** Historical R10-lite HR reaches legacy `samples` but not
  the analytics substrate (see `ble_engine.dart`, `adapters/_registry.dart`,
  `compute/substrate.dart`). Establish from the public protocol sources what R10-lite records
  contain, whether their HR is equivalent to the 1 Hz substrate input, and the safe way to
  bring it in (dedupe against existing seconds, provenance). Measure locally whether it occurs
  in Akshat's data (rule 4).
- **E2. RR values per record.** The decoder accepts up to 8 RR values; only up to 4 are
  observed. Confirm the record layout from the protocol sources and decide: cap at 4, or a
  validated 5-8 path. Akshat has decided to cap at 4 unless the layout proves otherwise.
- **E3. Unknown values.** Unconfirmed record versions store `skin_temp_raw` and `spo2_*` as
  0. Confirm which fields are unverified per record version; Akshat has decided they become
  blank (NULL). List every consumer and export that must treat them as absent, including the
  legacy `odi_per_hour`/`spo2` rows that must leave the CSV export.
- **E4. Short bursts.** WHOOP 4 sets `burstCountGateEnforced: false`, so a burst shorter than
  its announced count is committed and acknowledged. From the protocol sources: what the
  burst count means, whether a short burst is resent, and what policy keeps
  commit-before-acknowledge intact (invariant 1 in `CLAUDE.md`) while not losing data.
  Say what log evidence would settle it.
- **E5. Retention and the green optical signal.** Decoded data is kept about three days and
  green ADC is decoded but never stored. Research what stored green PPG would enable (for
  example respiration from PPG; Charlton et al. reviews), its storage cost per day from the
  record layout, and recommend keep-off or store, with the reason.

### F. Background execution on iOS

- **F1. Time budgets.** From Apple's documentation and WWDC sessions: what
  `BGAppRefreshTask`, `BGProcessingTask`, CoreBluetooth background wakes and state
  restoration actually guarantee on iOS 26, including AccessorySetupKit behaviour after
  force-quit and after reboot. Define what the app must measure on the phone (transfer time
  versus calculation time per wake) and what instrumentation Build 90 should add. Build on
  `background-sync-plan.md`.

### G. Energy, food, body and strength estimates

For each, check the constant in the code against its source and correct any mismatch. Also
state the estimate's real uncertainty for the on-screen wording.

- **G1.** Run and walk energy (ACSM metabolic equations; the Budget method in
  `metrics-map.md`).
- **G2.** Lifting at 3.5 MET and calisthenics at 3.8 MET (`conservativeMet`,
  `lib/compute/profile.dart`) against the 2024 Adult Compendium codes.
- **G3.** Digestion cost by macro (protein 20%, carbs 5%, fat 0%, unknown 5%) against
  thermic-effect literature (for example Westerterp 2004). Then the parked question: is a
  food-type adjustment (whole versus processed food, fibre) supported well enough to add?
- **G4.** The food/weight maintenance estimate: the 7,700 kcal per kg figure, the Theil-Sen
  trend and its 14-day/8-weigh-in gates, against energy-balance models (for example Hall et
  al.) and the water-weight literature.
- **G5.** The US Navy body-fat equation (Hodgdon and Beckett 1984): exact form, units,
  populations and error, and when the app must abstain.
- **G6.** Strength: the rep-adjusted estimate used for comparisons (Epley up to 12 reps,
  `setScore` in `lib/data/lift_progress.dart`) against one-rep-max prediction studies.
  Bodyweight sets have no load and stay estimate-free; do not add a bodyweight-load model.
- **G7.** The parked calibrated heart-rate plus movement burn estimate (for example Keytel et
  al. 2005, flex-HR, combined HR and accelerometer models): what accuracy is achievable on
  this hardware, and is it worth building. Recommendation only.

### H. GPS live speed

- **H1.** The live-speed filter (time constant about 5 s, stop detection, stale-fix rules).
  From Core Location documentation and GNSS speed-accuracy studies, give defensible values and
  the outdoor test that confirms them.

### I. Deferred experiments

- **I1.** For each deferred experiment in `build-88-plan.md` ("Deferred Experiments": personal
  quiet-HRR, readiness weights and gates, Kalman weight smoothing, replacement TDEE models,
  ML or Cole-Kripke staging, new stress/spectral thresholds), say whether published evidence
  is strong enough to change the app now, what data would be required, and your
  recommendation. No change is made by this pass.

## Verdict format for every question

Write one section per question ID, in this order:

1. **Question** in one sentence.
2. **Current behaviour:** the code symbol and file, and the exact constant or rule today.
3. **Evidence:** the sources, each with what it found and how well it transfers to this
   hardware. Include conflicting evidence.
4. **Answer:** one of *Definite* (sources agree; give the exact rule or value), *Conditional*
   (correct only under stated conditions), or *Needs measurement* (name the exact phone
   measurement or reference recording that would settle it).
5. **Recommendation:** keep, or change to an exact value or rule with its derivation.
6. **Impact:** every consumer it changes, whether a headline number moves (needs Akshat's
   per-item approval), whether `kAlgoVersion` must change, and the effect on stored history
   (only retained inputs can be recomputed; nothing is invented).
7. **Tests:** the regression tests that would prove the implementation.
8. **Confidence:** high, medium or low, and why.

Open `build-90-research.md` with a short summary table (ID, answer type, recommendation,
needs approval yes/no) and end it with a source list and the access dates.

## When you finish

Report to Akshat in plain words: which questions are definite, which need his approval
because a headline number would move, which need phone measurements, and anything you could
not research. Claude then reviews the file for privacy, commits it with the Build 90 work, and
the engine implementation follows from your verdicts.

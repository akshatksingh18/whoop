# Build 88 Actionable Plan

**Status:** Implemented, published, built and previously installed as Build 88 (algorithm 92,
schema 49), now superseded by installed/testing Build 89 (algorithm 93). `todo.md` and `setup.md`
own execution/artifact evidence; physical accuracy and the complete phone acceptance remain open.
The specifications below preserve the approved Build 88 contract and its baseline findings;
baseline descriptions are not an inventory of unfixed Build 89 defects. Per-night CVHR removal,
strain max-HR/minute rules, contrast, screen rebuild and the fatigue floor are settled in
`todo.md`. Build 89 supersedes HRV adjacency and the food-counting convenience. The complete
current repair/verification backlog is in `build-90-audit.md`.

[todo.md](todo.md) owns execution status; [research](metrics-accuracy-research.md) owns detailed
evidence and attachment reconciliation; [bugs.md](bugs.md) owns confirmed defects.
[Metric map](metrics-map.md) and [accuracy brief](metrics-accuracy-research-prompt.md) describe
current code, not the proposed corrected behavior. [Tooling setup](impeccable-setup.md) owns
the pinned installation, hook trust and native limitations.

## Decisions And Boundaries

- **Approved temperature presentation:** hide unsupported WHOOP 4 rows in Trends and Sleep;
  retain stored history. Remove the invalid field from physiological calculations, not its bytes.
- **Approved HRV presentation:** primary estimate only in headlines and readiness. If it fails,
  show unavailable; offer clearly labelled secondary estimates in details. Keep the five-minute
  sleep-session RMSSD mean as primary, with its continuity/coverage defects repaired.
- **Required design method:** installed Impeccable native/iOS playbooks, task-first Operate mode,
  concept review before code. Replace hierarchy as well as colours; preserve the five tabs and
  all required data, logging, live, history, settings and recovery routes.
- **Approved integrity/UX policies:** health findings respect quiet hours; hide the uncalibrated
  prescriptive strain target while retaining recorded strain as an estimate; intake advice and
  food/weight TDEE required explicitly completed food days in Build 88. Those policies were
  implemented; Build 89 subsequently adds approved automatic counting with manual overrides.
- **Decision Register:** D1-D13 below records settled Build 88 choices. It does not request a
  new implementation approval or reopen those policies. New build scope remains separate.
- No automatic calorie targets, guessed temperature, exact muscle/fat scores, hidden metric
  revival, new sensor permissions, cloud dependency or guaranteed background cadence.
- No data upload or public publication is authorized by this planning/tooling task.

## Decision Register (Akshat)

This is the scope/decision register, not a claim that implementation specifications or testing
are complete. D2 is engineering-owned: propose explicit gates and fixtures, then review the
availability tradeoffs with Akshat rather than asking him to invent scientific constants.
| # | Decision | Where | Options |
|---|---|---|---|
| D1 | Which packages enter Build 88 | all | Settled 2026-10-12: B88-01..11 including the structural redesign, plus selected B88-12 items |
| D2 | Frozen gates: load gap, HRV window/night, RSA/BRV/stress duration and coverage | B88-02/03 | Settled 2026-10-12: the rules in `build-88-proposal.md` section 2 |
| D3 | Quiet-day strain | B88-02 | Settled: withhold the target until calibrated; retain strain as an estimate. Personal quiet-HRR experiment is deferred |
| D4 | App quiet-hours exceptions per alert type | B88-11 | Settled: all health findings respect quiet hours; explicitly armed band alarm stays separate. No iOS Critical Alert capability |
| D5 | Live speed when no fresh fix | B88-05 | Settled: "—" for current speed; average shown separately |
| D6 | Historical weight ownership | B88-06 | Already settled: imported/backdated weights appear in charts and seven-day means, but not pricing or food/weight TDEE. Reopen only on an explicit new request |
| D7 | Navy estimate for female/other/unknown sex | B88-07 | Settled: none (single male user); male formula only |
| D8 | Bounded raw optical tail | B88-01/12 | Settled: off |
| D9 | B88-12 good-to-have items 1-8 | B88-12 | Settled: items 1-6 yes; item 7 (strap) deferred; item 8 (raw tail) off |
| D10 | Design direction and palette | B88-09 | Settled and locked 2026-10-12 (`DESIGN.md`): C deep kraft, E jewel colours, G big numbers, single panel, tiles, Trends bars at 7 days and lines at 30 days/3 months; full screen set approved |
| D11 | Finish reviewer | B88-09 | Settled: built-in degraded review, no extra agent |
| D12 | Implementation go-ahead and the one `kAlgoVersion` bump | B88-10 | Settled 2026-10-12: go-ahead for one combined build, `kAlgoVersion` 92 |
| D13 | Food-day completeness evidence | B88-06 | Settled for Build 88: explicit completion. Build 89 subsequently adds approved half-goal automatic counting and manual overrides; the dated-target issue is B90-10. An evening entry alone is not proof; partial logs remain useful |

Hook-install authorization is already present in Akshat's direct chat request to install automatic
hooks and executable tooling. The provider-required `.codex/hooks.json` is a tool manifest, not
an independent instruction tree. Host trust/automatic delivery is still a separate check; do not
ask again whether the installation itself was requested.

## Readiness Check

**Source/release gates passed; physical acceptance remains open.** This checklist describes
the implementation/validation contract, with shipped status in `todo.md`. Unselected new
estimators and personal physiological accuracy require separate evidence. No audit can certify
that no undiscovered bug exists.

- **Core versus extras:** baseline absence explanations, safe sleep-correction refusal and honest
  incomplete-food handling are core correctness work. Rich quality rows, expanded previews,
  sensitivity ranges and new control panels are optional B88-12 enhancements.
- **Freeze before code:** for each changed metric specify input admission, units, time/gap rules,
  qualification, exact absence reasons, baseline age/compatibility and dependent consumers.
  Add a failing-current/passing-candidate fixture. This includes strain-dependent sleep need and
  movers: hiding a strain target alone does not remove the underlying calibration bias.
- **Design acceptance:** palette/fact cards alone do not meet Akshat's structural redesign request.
  Review actual phone-sized task compositions with charts, diary rows, navigation and live controls
  using synthetic values. Then freeze the design and its feature-preservation route map.
- **Validation:** decoder-to-storage, derive-to-repository, UI/notification agreement, interrupted
  transfers, exports/restores and in-place upgrade have exact gates in B88-10. Native gestures,
  background reliability and personal physiological accuracy remain real-device/reference tests.
- **Not blockers:** buying a chest strap, capturing new optical bytes, installing a finish-review
  agent or making the web detector audit Dart are not prerequisites for deterministic repairs.
  Use the disclosed native review route. They cannot be used to claim ECG/PSG-grade accuracy.

## Prerequisites Outside This Plan

- **Signing.** The latest recorded installed profile expires 2026-10-17 17:51 local (`setup.md`);
  this is not a fresh on-phone expiry check. Confirm current Status and a renewed profile through
  the active signer before the recorded deadline; a Build 87 installation alone is not evidence
  of future renewal. Preserve signed identity, pairing and data; no installer change is selected.
- **Current phone baseline.** Verify the carried-forward B88-05 repairs on installed Build 89
  before tuning from phone evidence. Build 87 was never installed and is superseded; its old
  installation is not a prerequisite for current acceptance.
- **Encrypted backup first.** Take an encrypted export, copied off the phone, before any Build 88
  install. Its validation and backup rules are in `CLAUDE.md`.

## Execution Order

1. **Integrity:** B88-01 and B88-03, then B88-02; fix invalid inputs and false continuity.
2. **Alerts and freshness:** B88-11 and the B88-05 source defects (prior night shown as today,
   dropped jobs). These affect visible data and the app's quiet-hours policy.
3. **Interpretation:** B88-07/B88-08; fix false strength/tissue conclusions and preserve partial data.
4. **Availability/accounting:** B88-04, the rest of B88-05, and B88-06; verify existing repairs
   before tuning.
5. **Design:** B88-09 concept work can start alongside analysis; production UI waits for selection.
6. **History/release:** B88-10 contracts apply throughout; finish source and physical verification.
   B88-12 items enter only when selected.

Deterministic repairs have exact pass/fail invariants. New physiological estimators remain
experiments until independent reference evaluation supports them. Better data handling does not
establish a precision percentage or equivalence to WHOOP's proprietary model.

## Work Packages

### B88-01: Refuse Unverified Temperature (R01)

**Change:** gate by verified device family/channel at the decode-to-metric boundary. WHOOP 4's
deprecated `skinTempRaw` must produce no temperature metric, baseline enrollment or readiness,
anomaly, illness, coaching, export or notification contribution. Audit all consumers, not just
the score weight. Use existing available-input readiness renormalization and eligibility;
do not change weights/gates, suppress HR/RR/motion sleep data or disable the RHR-only CUSUM.
Hide the approved Trends/Sleep rows. Retain raw fields/columns and immutable legacy outputs.

**Done when:** changing only unknown WHOOP 4 counts cannot change any physiological output or
alert; temperature is absent on every current consumer path; retained history survives.
Unknown slow fields, `skinContact` and `ppgRedIr` are not replacement sensors.

**Second-pass scope additions** (`bugs.md` temperature section):
- **Consumers.** The consumer list must include `tempIllnessFlag` and `multivariateAnomaly`, which
  are currently fed a z-score they refuse, plus glass-box |z|, the rough-night card, the
  critical "Skin temperature elevated" alert, CSV metric history and imported `skin_temp_z` values.
- **History.** Original optical frames cannot be replayed to discover a replacement channel.
  Retained decoded inputs can still support qualified recomputation; already-pruned history cannot.
  Refuse WHOOP 4, unknown-family and imported temperature by family/source in every cross-day
  reader of stored scalars, not only in the new derive.
- **Raw-byte capture (decision for Akshat).** Optionally capture a bounded, opt-in rolling raw
  optical tail (inner 64-90) for future channel research. That costs storage, and is not a
  temperature fix.

### B88-03: Timestamp-Aware Primary HRV (R04/R07)

**Confirmed:** `sleepSessionWindowedRmssd` buckets timestamps then discards them before cleaning;
two intervals 298 seconds apart can contribute the same RMSSD as intervals one second apart.
One surviving difference can qualify a window. This synthetic behavior is not an estimate of
error on the user's nights. Primary cleaning is local-median/Malik-style; secondary cleaning
uses a different path. Do not silently replace both with a new cleaner.

**Change:** preserve report-time/dropout boundaries before successive differences. Handle multiple
intervals sharing a report second without claiming ECG-resolution beat times. Define window and
night eligibility from usable continuity, coverage, artifact burden and qualifying windows.
Freeze numeric gates before code as explicit engineering policies, test sensitivity/retained
coverage, and do not describe them as clinically validated constants. A two-isolated-beat night
must not qualify. A confidence floor cannot substitute for eligibility.

Serve one primary identity in headlines, readiness, drivers and histories. Keep labelled
secondary results separately; never backfill the primary baseline from them.

**Done when:** sparse/gapped/rejected-run fixtures abstain, genuinely continuous fixtures retain
correct units/math, shared report seconds do not create fabricated timing, and repeated derive
is idempotent. Changed qualification/method history does not enter an incompatible baseline.
ECG agreement and physiological threshold calibration remain separate reference gates.

**Second-pass scope additions** (`bugs.md` "Timestamp-Blind Beat Differencing"):
- **Every differencing path.** Apply the same gap rule to the irregular-rhythm screens, PRSA, the
  sleep `hrv_timeline`, the 24/7 `hrv_day`, daytime HRV and the one-beat 1000 ms re-anchor bridge,
  not only the primary.
- **No silent fourth estimator.** Remove the Sleep HRV row's fallback to the mean of timeline
  points. Correct the `hrv_cv` method label.
- **Respiration.** RSA's whole-night gap-inflated Nyquist refusal, the BRV artifact bypass and
  stress publishing from 30 beats need explicit duration/coverage qualification, frozen before
  code like the HRV gates. Repairing them may change readiness's breathing availability, so it
  belongs in the same version decision.
- **Labels and secondary outputs.** Name Sleep's "Heart rate X average · lowest Y" fields truthfully
  (lowest 30-minute RHR versus 1st percentile), time the nadir correctly, fix the stress spec's
  "resting window", stop rendering per-night CVHR, and remove the discarded duplicate HRR tau.
  Treat Lomb-Scargle absolute power scaling under gaps, and the beat-sum versus wall clock, as part
  of the spectral gate.

### B88-02: Unknown Load Is Not Rest (R02)

**Change:** remove null-to-zero densification from `_denseDailyTrimp` and all load consumers.
Recommended policy for selection: load states qualify on contiguous eligible calendar-day
segments; a gap withholds dependent comparisons until re-enrollment under an explicit policy.
Preserve real observed zeros. Merely decaying an EWMA through a missing day still assumes zero
and is not the repair. Freeze coverage/initialization requirements before code; no invented
HR-derived muscular load or injury-risk score.

**Done when:** all-null, known-null-known, skipped dates, partial coverage, genuine rest,
initialization and DST have distinct correct outcomes; dependent sleep need/targets/overreach
never present unknown days as observed recovery.

**Second-pass additions** (`bugs.md` "Quiet-Day Strain Inflation"):
- **Gross TRIMP.** CTL/ATL currently use gross TRIMP, so wear minutes alone move load, and imported
  days enter as zero-TRIMP rest. Both belong in the gap/eligibility policy.
- **Quiet-day strain (settled, D3).** `quietWakingHrr = 0.20` is a documented directional
  inflation for the upstream corpus whose quiet HRR exceeded that constant. Its source notes
  report 6.93–12.14/21; this is not a measurement on Akshat's current nights or a universal idle score.
  It reaches Today's strain target, the strain-14+ mover and sleep need. Akshat selected
  withholding the prescriptive target until calibrated while keeping the recorded score as an
  estimate. Qualify strain-dependent sleep need/movers explicitly; target hiding alone is not
  their calibration. The personal `dailyQuietWakingHrr` model remains a deferred experiment.
  Test all target surfaces, including Today and Strain details; no changed score coefficient is
  selected by this presentation decision.
- **Smaller fixes.** Zone/TRIMP HRmax mismatch, duplicate zone definitions and single-sample
  minutes are deterministic consistency fixes.

### B88-07: Comparable Strength And Qualified Advice (R03/R09)

**Change:** distinguish improved, unchanged, declined and incomparable lift comparisons.
`progress_review.dart` must not call `better=0/worse=0` improvement. The high-rep
`liftTrend` fallback must compare reps at the same load/context or abstain, not mark a
heavier/fewer-rep set down from reps alone. Preserve existing 1-12-rep Epley eligibility, load
meaning/equipment, raw logs and context; a score for plates/added weight is not whole-system 1RM.

Replace `goal_plan.dart::waistFast` tissue attribution in both advice branch and copy with
qualified same-site observations. Review Navy sex/date eligibility, intake-floor eligibility and
extra-exercise advice at the floor; a fixed intake floor is not evidence of adequacy. Sparse or
conflicting data must not suggest an intake change. Manual goals stay manual.

**Done when:** identical sets, changed-load high reps, mixed/declining/incomparable sessions,
bodyweight records, plateau advice, noisy waist, dated neck/waist, sparse intake and floor cases
pass. Imports/backdating and independently selected photo comparisons remain intact.
Optional effort fields are separate scope, not a prerequisite for these repairs.

**Second-pass additions** (`bugs.md` "Food Completeness, Body Estimates, Strength Comparisons And
Goal Advice"):
- **Navy estimate.** Gate it by sex. The female form can use the existing `hips` tape site, and
  other/unknown sex gets no estimate unless Akshat chooses otherwise. Add plausibility bounds and
  a neck-age limit, and date both sites.
- **Floors.** Normalise the sex check, run the floor check even without a target, and qualify the
  floor copy.
- **Protein advice.** Size it from a counted set of protein-complete days.
- **Comparisons.** Bound waist and tape comparisons to dated windows and match the weight window.
  Use one strength comparator, the same in Review and live, with real regression states. Keep the
  `waistFast` cut out of below-band lean gain.
- **Wording.** Soften the phase copy and the "On track for recomposition" / Navy wording to
  observation language.

### B88-08: One Useful Progress Review (R10)

**Change:** retain seven-calendar-day observed weight means and counts. Closed weekly/monthly
reviews qualify weight/waist, comparable lifts, logged intake/protein, activity and sleep/recovery
independently. Missing lifts or food must not hide a usable weight/measurement comparison.
Separate per-family observations from the more demanding combined goal/advice verdict.

The Review tab already keeps independent stats under "Partial evidence". The remaining work is
(a) a recomposition verdict that uses waist and comparable lifts rather than weight rate alone,
with absent data not counted as "no progress", (b) aligned Monday weeks, and (c) day-state-aware
calorie cards and "at least" meal totals.

Show values, dates/counts and one short supported conclusion; put methods, exclusions and
coverage explanations in details. Do not conclude that diet caused exact tissue loss or that
tape growth is muscle. Preserve general-activity/Pushups streaks and labelled protected rest.

**Done when:** populated, partial, conflicting, new-goal and empty periods remain useful and
honest, comparisons use matching closed periods, and unchanged strength never becomes a gain.

### B88-04: Sleep And Breathing Coverage (R05/R10)

**Change:** trace early-night absence through ingest, preparation, HR/RR admission, window
alignment, saved results and rendering. Display early HR when recorded; keep HRV/respiration gaps
when their own inputs fail. Fix proven window/rendering defects without forcing stage proportions,
painting missing sleep or importing unvalidated Cole-Kripke thresholds.

**Done when:** observed, unobserved, off-wrist, cross-midnight/DST, corrected sleep and nap-only
cases retain honest boundaries and all manual routes. PSG is needed for staging accuracy;
independent respiration is needed for respiratory precision.

**Second-pass findings to include** (`bugs.md` "Sleep Regularity, Breathing Lane"):
- **Breathing lane.** The absolute 0.02 g stillness gate on posture-dependent gravity is the
  likely main cause of missing breathing points. Use a relative per-window or per-night reference
  as `cardioStager` already does, and test retained coverage.
- **SRI.** It must pair all-day sleep/wake epochs 24 h apart with unobserved epochs excluded, not
  in-window minutes with unobserved counted as asleep.
- **Fallback nights.** Hold them to an explicit minimum duration and time-of-day rule rather than
  bypassing the 3-hour gate.
- **Night selection.** Test replacement of an earlier selection by a better-supported or manually
  corrected main night, including a later shorter candidate. A longer-night preference alone is
  not a defect, and a later longer candidate is not the failing case identified in `bugs.md`.
- **Manual correction.** When a correction falls below the 50% observed floor, say so before
  saving; never imply it sets duration.
- **Home ring and onset.** The ring must use the need of the night it measures, and onset/latency
  should say whether it comes from in-bed or first sleep.
- **Stage cutoffs** are tuned to normative proportions (held-out κ 0.132 on another sensor's
  features). Present stage minutes as estimates, and keep any re-tuning an experiment requiring
  PSG, never re-anchored to "normal" percentages.

Second-pass tests:
- an SRI hand-computed fixture (shifted bedtime lowers it; unobserved time is excluded);
- breathing-lane retention on synthetic still windows at 0.93/1.00/1.07 g;
- a fallback night outside the allowed duration or clock window;
- a different eligible later night replacing an earlier selection even when shorter, while
  a pruned replay of the same night cannot erase richer data; retain the already-working longer
  candidate and manual-override controls;
- a correction below 50% observed warning before save;
- the Home ring using the measured night's need.

### B88-05: Sync Freshness And Live Speed (R06)

**Change:** test Build 87's existing cold-connect, durable-frontier freshness, bounded cancellation,
same-input reuse and wear-aware link repairs before adding more. Separate last committed record,
current live HR, served calculation and queued/running/failed status. No pull-to-refresh should be
required to start normal foreground catch-up. Verify read-after-commit without repeated heavy work.

Record reconnect/transfer progress, commit frontier, derive start/cancel/finish, served version
and display age in bounded local diagnostics. Measure GPS fix age and accepted-fix-to-display
latency during speed changes/stops. Current speed already has accuracy admission, causal EMA,
5 m location filtering and a 10-second stale gate; tune only from measured evidence. Do not
promise one-second callbacks. Current source shows the session average, labelled "avg", whenever
fresh speed is unavailable (`live.dart`). **Decision for Akshat:** keep that labelled fallback, or
show "—" until a fresh fix arrives. Either way, it must never be labelled as current speed.

Live-speed source items, from the second pass (`bugs.md` "Energy, Steps, Live Speed"):
- Use a per-second rather than per-fix EMA (the current lag is about 33 m of travel).
- Add explicit stop detection when fixes cease under the 5 m filter.
- Tighten the fallback for position-derived speed.
- Use moving-time average pace.

Choose constants only after measuring on the phone.

**Done when:** brief daily opens, locked/background workouts, off-wrist/range loss, cancellation,
ordinary termination, reboot/first-unlock and force-quit are separately tested; overnight and
72-hour soak document actual freshness and CPU/power results. Preserve commit-before-verbatim-ACK,
single ownership, skip-not-queue headless gating and bounded iOS work. No new entitlements assumed.

**Source defects to repair before phone tuning** (`bugs.md` "Overnight Freshness And Sync
Lifecycle Gaps"):
1. Derive `overnight_day` with the same has-sleep rule `_latestBundle` uses, and refresh overnight
   state when a night's row commits, so prior nights never read as today and committed nights are
   not hidden.
2. A pass refused by the engine lock must requeue, not complete.
3. Detached rescan/reanalyze/override/nap passes join background cancellation.
4. Reset background flags on `openSession`'s early returns.
5. Give foreground ownership acquisition a deadline with coordinated retirement. BG expiry must
   stop the headless drain at a safe protocol boundary before the gate releases the band.
6. Do not let future-margin or capture-time-fallback timestamps raise the `rec_ts_hw` frontier.
7. Decide whether WHOOP 4 burst shortfalls stay advisory, using logged evidence rather than an
   assumption.

Each of items 1-6 needs a deterministic regression first:
- a `NO_SLEEP_DETECTED` today with an earlier scored night;
- cancellation before the freshness refresh;
- a lock-held pass;
- a busy `openSession`;
- an expiry during a headless drain;
- a future or ≤0 timestamp.

Each must fail on Build 87 source and pass after the repair.

**Diagnostics package (local, bounded, no new capability):**
- Route headless/BG/restore/background-derive lines to the file log, with stage timestamps (wake,
  connect, burst, each commit, ACK, history end, job queued, calculation start/cancel/finish,
  Today read) joined to the native launch ID.
- Log lock-refused passes, the stop source per cancellation, burst shortfall with timestamp
  continuity, and frontier advances from fallback timestamps.
- Snapshot scheduler/gate/ownership on resume and pause.
- Cap `openstrap_exits.log`.
- Record Background App Refresh and Low Power Mode state at launch.

### B88-06: Nutrition And Energy Accounting (R08)

**Change:** audit dated profile/weight, gross/net units, run/step overlap, pauses/midnight,
known versus missing macros, TEF and complete/partial days. Keep Budget/ACSM separate, manual
targets, maintenance-based warning semantics, calorie/protein group summaries, bidirectional
portions, custom categories, direct edits and safe deletion. Food/weight TDEE stays a qualified
secondary estimate, not a precise maintenance measurement or automatic target anchor.

**Done when:** worked-example/dated/unit/overlap/zero-missing fixtures match across Today, Food,
history and Progress; import-only historical weights do not reprice old calories or feed dated
pricing/TDEE inputs. No coefficient, lifting-credit or automatic target change is bundled.

**Build 88 completion contract (D13; extended by Build 89):** advice and food/weight TDEE used explicitly marked-complete
days with known required nutrients. Reuse existing durable `food_day_mark` evidence; an automatic
evening timestamp is not equivalent. Preserve earlier explicit marks, partial logs and unknown
macros; do not bulk-promote automatically classified legacy days. Test dinner-only, missing kcal,
missing protein, explicit Complete/Incomplete, edits after marking and closed-period eligibility.
Explain excluded days in details without reinstating Progress's wall of text.
Build 89 adds the approved half-goal automatic counting and manual overrides; it does not make
a partial nutrient total complete. Current dated-target reconciliation is B90-10 in the audit.

**Audit completed (second pass).** All coefficients, gates and worked examples match source;
import-only weights already never price a day. Edge cases to select (`bugs.md` "Energy, Steps,
Live Speed"):
- **Overlap rule.** Any run-step coverage shortfall switches the whole day to `max(walk, run)`
  (−161 kcal in the worked example). Use the covered portion instead of an all-or-nothing switch.
- **DST.** Scale BMR to 23/25-hour days.
- **Lifting line.** Respect `end_ts_fabricated` and de-duplicate overlapping lifts in the separate
  lifting line.
- **Low-HR sessions.** Review `min(MET, HR)` admission when motion/context supports exercise and
  HR is unreliable. A real observed rest interval may legitimately have zero above-rest energy.
  Do not force a positive calorie value from missing/conflicting inputs or silently add new credit.
- **Steps.** Review the phone-hour/wrist-density policies against counted-step tests.
- **Food/weight estimate.** Add a leverage/spread gate and a displayed uncertainty interval. Record
  weigh-in time if "morning" is to be claimed. Keep the settled historical-weight ownership in D6;
  clarify its calculation exclusion without removing the entry from chart history. Fix the flat-slope "0.00 kg"
  wording.
- **Day completeness.** A default 19:00 stamp for past-day dinners, or one late entry, must not
  auto-complete a day. Quick add on a past date needs one consistent `atTs` meaning.
  `CalorieCard` must respect day state.
- **Climb terms** stay inert until a trusted climb source exists. Barometric relative altitude would
  be a new input requiring approval.

### B88-11: Honest Health Alerts And One Readiness Explanation (New)

Evidence lives in `bugs.md` under "Health Alerts …" and "Readiness Explanation …".

**Change:**
- **Alerts.** Fire "Low readiness" from the headline composite, with its eligibility rules, instead
  of the deprecated glass-box score. Treat yesterday's unfinalized row as unsettled for detector
  inputs. Make the anomaly detector directional, or label it two-sided. Pass dates to the RHR-shift
  detector. Correct the illness finding text, which mentions HRV although the detector is RHR-only.
- **Explanation.** Show the composite's own stored driver contributions under the ring, use one
  band scheme, and bound the "28 nights" baseline by calendar age. Do not apply the whole-bpm RHR
  quantum as though the continuous 30-minute mean were an integer sample. Its noise/quantum
  floor is a D2 quality-policy review, not a proven rounding bug or permission to shrink the
  floor arbitrarily; preserve reported precision and test score stability/coverage before tuning.
- **Filters.** Apply import/foreign-family filters to every cross-day consumer and to mover
  exposures.

**Approved policy:** all health findings respect the app's quiet hours. Source currently assigns the
internal `NotifPriority.critical` to every aggregate; this is not Apple's Critical Alert API.
The iOS sink uses default `DarwinNotificationDetails`, requests ordinary authorization and has
no Critical Alerts entitlement in the personal build. It does not establish Focus/mute bypass
or actual phone wakeups. Use normal/off health findings that respect quiet hours, keeping
an explicitly armed band alarm distinct. Adding Apple's Critical Alerts capability is out of scope.

**Done when:** a lone partial or unsettled day, a good-direction anomaly, a pre-gap RHR window and an
imported day each produce no alert. The ring, explanation, findings log and notification agree on
one score. Every health type is suppressed during quiet hours; test boundaries and preference
persistence. Do not change unrelated device/signing policies or the armed alarm through a global
override toggle. Repeated derive stays idempotent with no re-fire.

### B88-12: Good-To-Have Additions (Selection Needed)

These come from the consolidated analyses and use only existing capabilities unless marked
otherwise. Each needs Akshat's selection.
1. **Data-quality line per metric (details only).** Coverage, method identity and the absence
   reason from B88-10 provenance, so "unavailable" explains itself without adding headline copy.
2. **Sync health panel in Status.** Last wake, connect, commit, calculation and Today read, with
   ages, from the B88-05 diagnostics, alongside bounded log export.
3. **Measurement protocol prompts.** Same-site tape guidance, an optional repeat reading and the
   stored weigh-in time, so "morning" trends and tape changes are comparable.
4. **Expanded correction preview.** A before/after timeline and coverage preview. The basic
   guard explaining/refusing insufficient observed coverage is already core B88-04, not optional.
5. **Food/weight estimate with a range.** Gate it robustly and show an interval, still never
   driving targets.
6. **Per-type alert controls** (normal/off and any approved app quiet-hours exceptions), following
   B88-11; never advertise unsupported iOS Critical Alerts.
7. **Optional reference validation kit (new hardware).** A standard BLE chest strap such as a
   Polar H10, read through the existing standard heart-rate-service decoder (`hrs.dart`), as an
   opt-in reference recording to measure our RR/RMSSD/RHR error on Akshat's own nights. It requires
   buying the strap, a consent/storage decision and a separate validation protocol; it is not a
   daily dependency.
8. **Bounded raw optical tail** (B88-01 option) for future channel research.

### B88-09: Structural Design With Impeccable

Use [the full design brief](ui-design-research-prompt.md) and installed native playbooks:
critique/shape, distill/clarify, layout/colour, adapt/harden/polish. Review two or three materially
different phone-sized compositions with synthetic data before production code, including Today,
Progress, Food, Train and a live state. Seek rich separated accents, crisp dark-neutral contrast
and a peaceful warm feel without milky overlays or another recolour. Akshat now pins a warm
light-brown background with data on top (light appearance), which supersedes the earlier
brown/orange-wash caution. The Impeccable direction board and options are in
`build-88-proposal.md` section 5.

Preserve reachable metrics/features and familiar iPhone navigation. No unique feature removal
without approval beyond the already selected temperature rows. Keep charts and key observations
prominent, repeated explanatory copy in details, fixed stable controls and destructive actions
separate from expand/collapse. Retain start/end times, completed-workout Delete confirmation,
repeat-set and rest-timer workflows.

**Done when:** Akshat approves hierarchy and palette, then real phone-sized populated/empty/
partial/stale/failed/live, large-text, keyboard/safe-area, semantics, date-arrow and navigation
checks pass. The Impeccable web hook skips Dart; CLI success is not Flutter visual validation.
[impeccable-setup.md](impeccable-setup.md) owns installation and first-use hook trust.

**Concrete Impeccable route for this Flutter iPhone app** (checked against installed skill 4.5.2):
1. Load context once per session with `impeccable context`. It reads `product.md` (platform `ios`)
   and the iOS reference.
2. Run `shape` for task discovery per tab, in Operate mode.
3. Run `new-work` for the replacement visual world. The build is code-led with no image comps: no
   image-generation tool or API is approved, so direction cards carry palette chips and facts. These
   alone are insufficient: preview-only Flutter renders must also show materially different actual
   task compositions before production UI approval; do not settle D10 on swatches. The
   direction board is served by `impeccable serve-question` on localhost and opened in the in-app
   browser; no upload is involved.
4. After Akshat picks a direction, write `DESIGN.md` (none exists yet) as the accepted contract and
   map its tokens into `lib/ui2/theme.dart`/`grammar.dart`.
5. Read `craft-floor.md` before each UI edit, and follow `ios.md`: safe areas, the system tab bar,
   44 pt targets, text scaling, consistent interactive roles and the existing coherent icon system.
   Separate vivid metric/status colours from the interactive tint; a single tint is not a reason
   to make the app monochrome or dull. No new icon/font library is required by this planning task.
6. The skill's iOS verification assumes `xcrun simctl`, which this Windows machine lacks. Substitute
   Flutter render/golden captures at iPhone 17 logical size with synthetic data (the existing
   `build87_redesign_render_test.dart` pattern), in dark mode and at large text. Add Akshat's real
   phone screenshots, and say which source produced each piece of evidence.
7. The `impeccable-finish-reviewer` agent is not installed. Either approve installing the pinned
   upstream agent definition, or run the bundled `reference/degraded/finish-reviewer.md` in a fresh
   session and disclose it.
8. Close with `audit` (native variant), `harden` and `polish`, in at most two batched capture
   rounds.

## B88-10: Data And Delivery Contract

- Reuse existing `Metric` envelopes/day JSON where practical. For changed families persist
  source/device family, method/algorithm identity, units/window, input revision, observed coverage,
  artifact/gap qualification and explicit absence reason. New columns only if required.
- Analytics output changes require `kAlgoVersion` review/bump. No version bump is made by this
  plan; UI-only work does not silently change formulas. Expected classification for the single
  Build 88 bump decision:
  - **Change stored outputs** (bump required): B88-01, 02, 03, 04, 11 (alert inputs and baseline
    bound) and the B88-06 overlap/DST/lifting/food-estimate items.
  - **App/read-layer logic only:** most of B88-05, B88-07 and B88-08, with their own regression
    tests.
  - **Presentation:** B88-09 and simple explanatory/preview views. Stored weigh-in time, completion
    evidence, per-type persisted alert preferences, raw capture and reference recording are not
    presentation-only: review their storage/lifecycle/backup contracts if selected.

  Because `metric_series` is unversioned, every changed key needs the compatibility rule below. Migrations remain additive/idempotent,
  cheap at open and separate from isolate-based recomputation.
- Preserve immutable `day_result` history. Inspect retained inputs before recalculation: usual
  decoded retention is three days behind the data edge; legacy `raw_records` is dropped;
  `raw_archive` is incomplete and old v20 frames are thinned. No months-long replay promise.
- `metric_series` is not algorithm-versioned. Do not use legacy/fallback or old gap-contaminated
  HRV as compatible new-method baseline merely because the date/key matches. Read provenance from
  versioned results where available, define compatibility explicitly and allow honest warm-up.
  Unaffected compatible RHR/sleep/respiration histories need not be discarded.
- Keep legacy/unrecomputable scores identifiable and out of falsely fresh corrected outputs.
  Do not erase old data or fabricate input to recover a baseline. Preserve imports, portions,
  dated profile semantics, encrypted export/restore and pairing/signing identity.
- Input hygiene (`bugs.md` "Input Retention And Wear Accounting Limits"):
  - feed historical R10-lite HR into the substrate if its prevalence is material;
  - unify the two `worn_min` definitions;
  - separate off-wrist, charging and undelivered time using the stored wrist/charging events;
  - cap accepted RR count at the observed 4, or validate counts 5-8;
  - write NULL, not 0, for unconfirmed-version optics;
  - exclude legacy `odi_per_hour`/`spo2` rows from CSV history;
  - record the zone per day so travel cannot shift retained re-derives.
- Preserve transaction/cursor-before-ACK, pruning protection for unfinished derivation, RAM-only
  live high-rate streams and bounded local diagnostics. No raw-storage expansion is assumed.
- Before tuning, freeze independent reference/holdout design and error, bias, coverage/abstention,
  false-alert and latency measures. Vendor/ECG/PSG studies do not transfer accuracy to our parser;
  correlation alone is insufficient. Reference collection/model use needs separate consent.
- Run focused and full tests, analysis, all-five-tab/detail/logging/backup/settings smoke checks,
  source/packaging review and physical tests. Publication/build/testing-IPA and in-place phone
  acceptance are separate gates. Preserve the accepted recovery IPA.

## Deferred Experiments

Personal quiet-HRR instead of current `q=.20` (B88-02 option b, if selected, runs as one of these
experiments), new readiness weights/gates, Kalman weight
smoothing, replacement TDEE models, ML/Cole-Kripke stages and new spectral/stress/MDC thresholds
require selected experiments and independent evaluation. Do not add artificial leg-day penalties,
diagnostic AF/apnea/SpO2, guessed temperature or exact muscle/fat estimates.

The detailed [claim reconciliation](metrics-accuracy-research.md#supplied-ai-analyses-claim-reconciliation)
preserves useful suggestions from both attachments and explains why unsupported parameters,
hardware assumptions and claimed error bars were not accepted as implementation facts.

# Coverage closure and reachability

**Status:** Coverage toward 100% is resumed. The working algorithm-101 Sleep repair
and later restore/reset work pass full candidate74. This is a closure map, not a completed resolved call graph.
No source is excluded. Behavior-neutral scaffolding cleanup and the separately approved
dormant API removal are accounted for separately from new executed-line gains.

The latest fully green source is candidate74:48,470/50,624 (95.75%;2,154 misses).
The table refers to current74; re-match changed files before applying ranges.
Re-match source before using ranges. This remains a closure map, not a complete resolved
call graph. No retired route is reactivated merely to execute its code.

| Area | Purpose and callers | Candidate-74 verified misses | Next proof |
|---|---|---:|---|
| `local_repository_impl.dart` | Shared stored-data readers used by active screens | 117 | Absence, provenance, failure/retry and correction agreement across readers |
| `derivation_engine.dart` | Foreground/headless calculation, staging and publication | 135 | Real worker ownership, retained-input boundaries and refusal/retry |
| `ble_engine.dart` | Peripheral frames, sync lifecycle and durable ACK path | 129 | Remaining accepted/refused/late frame and lifecycle paths |
| `app_state.dart` | User commands, lifecycle and calculation scheduling | 112 | Actual commands and cross-tab revision/failure behavior |
| `local_repository.dart` | Compiler-enforced abstract repository API;55 methods remain after approved spot retirement | 0 | No executable-default gap; audit concrete implementations and interface dispatch |
| `ui2/charts.dart` | Shared active chart rendering and interactions | 16 | Actual inputs, gestures, gaps and boundary labels |
| `theme/tokens.dart`, `theme/theme.dart` | Theme/type/platform helpers | 89 | Identify active platform paths versus definitions with no executable behavior |
| `today_plan.dart`, `home_screen.dart` | Retained planning/Home composition and actions | 76 | Preserve actions, uncertainty and day provenance |
| `db.dart` | Shared SQLite transactions, imports, recovery and reads | 45 | Transaction failures and exact recovery; updated source needs fresh LCOV |
| `journal_compose.dart` | Shared `WhoopTextField` serves Food, Lift, Progress and Nutrition; tag vocabulary serves the active rough-night report | 169 | The personal Sleep host supplies `ask: never`, gating the rough-night journal question/editor route. Preserve active shared inputs and report; audit remaining constructors before any per-item deletion proposal |

A current74 source-matched AST index assigns gaps in66 files to594 enclosing declarations.
The prior seven-file/163-declaration inventory remains retained. Exact line lists/source hashes are retained in the local-only checkpoint's
`cov52-function-gap-map.json`. This is a declaration index, not resolved callers,
redundancy classification or new test execution. The largest BLE entry includes Android-only
priority work; other entries include dormant UI helpers. Audit actual shipped callers before
writing tests or proposing separate removals. The two approved painter retirements account
for54 formerly unexecuted instrumented lines (23 dashed-ring,31 scatter), not54 new hits.

The prepared121-check batch reaches139 distinct matching misses in focused local LCOV,
including active asynchronous readers, rank/goal/window/refusal controls and legacy scope
selection. Seven actual worker cases remain cloud-only. These are provisional gains;
the table above stays at full74 until combined verification. AppText, protection writers
and coherence remain unchanged while their independent deletion decisions are pending.

For every remaining range, record the containing function, concrete callers/entry points,
user-visible purpose, existing check and the missing behavior. Classify it as active and
testable, native/device-only, definition/export without executable behavior, or unreachable
after a documented feature removal. Syntactic name matches alone do not prove reachability.
Before any proposed deletion, list every unique metric, insight and action that would become
unreachable and obtain Akshat's per-item decision. No deletion is authorized by this map.

The four unimported files in the diagnostic inventory are `build_profile.dart`,
`migration/legacy_names.dart`, `ui2/screens/screens.dart` and `ui2/ui2.dart`. Audit constants,
exports and actual executable paths separately; importing a file is not functional coverage.
Native Swift/OS restoration, real Bluetooth, notifications, keyboard/VoiceOver, signing and
phone recovery require separate acceptance even at 100% instrumented Dart line execution.

Keep all retained skips visible. Run full tests/analysis/packages/captures on Actions from a
privacy-reviewed parentless candidate; verify LCOV against its exact production-source hashes.
Never push private ancestors, captures or local recovery evidence. `todo.md` owns sequencing
and `coverage-audit.md` owns verified measurements. Native/IPA stays held until coverage closes.

The first caller trace confirms `SleepDetail` → `RoughNightCard(ask: never)`; the report
remains active while `_question` and its `JournalCompose` route are outside that personal
host's state. This is not permission to remove the whole file: its shared input widget and
tag vocabulary have active callers. Base repository defaults throw `UnimplementedError`;
trace concrete overrides and alternate/test implementations before changing that contract.

A two-file Dart AST trace confirms all 56 base repository methods have explicit concrete
implementations in `LocalRepositoryImpl`, including all 53 fail-fast placeholders. The only
production subclass is that concrete reader. The working cleanup now declares the complete
production contract abstract and retains partial-reader behavior in shared test support.
All 20 affected test readers preserve their overrides; an AST comparison proves every one of
the 56 signatures/default bodies unchanged, and 13 existing targeted reader/Sleep checks pass.
Missing production implementations now fail at compile time. No metric, action, route,
storage or calculation is removed. This removes unused production scaffolding, not failed
cases or a coverage exclusion. Report the reduced executable denominator separately from
new executed lines. Candidate70 passes5,492 full app checks/429 retained skips, both packages and analysis,
plus73 focused checks. The denominator loses113 lines; other files gain10 net executed lines,
while11 previously executed base defaults move to test support. Candidates68/69 predate
this cleanup. The separately approved spot-check retirement now leaves55 contract methods.

## Parked live services: per-item deletion decisions

A complete source-name search finds no production caller of either public API below. The
only occurrences are their contract, concrete implementation, partial-test default and old
comments. AppState explicitly removed the never-started spot-check state machine; no screen
starts it. These are dormant future API hooks, not current phone features. Do not activate
or add tests merely to execute their lines. Akshat approved the spot-check item; its API/adapter retirement passes full74.
The separate coherence item is still pending, so its API/shared decoder remain.

| Item | Exact proposed removal | What becomes unreachable | What stays |
|---|---|---|---|
| Parked live HRV spot-check API | `LocalRepository.spotCheck`, concrete/test defaults and `_spotCheckCompute` | Calling this dormant service to return ad-hoc RMSSD, SDNN, mean HR, beat count and confidence from a supplied live frame list. There is no current app screen/route/caller to lose. Future restoration would need a new orchestration API. | Overnight HRV/Recovery, saved results, raw history, all protocol/analytics algorithms and BLE streams. No database field or export is deleted. |
| Parked guided-breathing coherence API | `LocalRepository.breathingCoherence`, concrete/test defaults and `_breathingCoherenceCompute` | Calling this dormant service for a live coherence ratio, score, peak frequency, beat count and confidence. There is no current app screen/route/caller to lose. Future restoration would need a new orchestration API. | The existing Breathing pattern in sleep report, breathing-session history/table/export, library cardiac-coherence calculation and BLE streams. No database field or export is deleted. |

`_decodeLiveRr` is shared only by those two functions. Remove that private adapter only if
both item removals are approved; keep it when either API stays. All package source, versions,
physiological formulas, algorithm 101/schema 50 and persisted-name migration gates stay intact.
Preserve the current code in the verified private all-refs archive before any removal. Verify
all remaining references, analysis and the full Linux suite afterwards. Count this separately
as removed unreachable scaffolding, never as newly tested lines or a restored feature.

Journal input widgets, numeric fields/tag analysis and cycle APIs require their own caller
trace. Their apparent gaps do not authorize whole-file deletion: active shared controls and
retained historical data must remain. No decision about those areas is requested yet.

## Dormant chart primitives: separate deletion review

Exact whole-source/type-name and constructor searches find no production or test constructor
caller for `DashedRing` or `Poincare`. Each appears only as its own painter declaration and
repaint type and explanatory source comments. Dart AOT has no reflective factory
in this app that constructs either by name. Other gallery painters have explicit callers and
are not part of this proposal. This is a bounded reference audit, not a complete call graph.

| Per-item decision | Exact proposed removal | What becomes unreachable | What remains |
|---|---|---|---|
| Dormant dashed-ring painter | `DashedRing` class, its paint/repaint implementation and matching obsolete docs | Directly constructing this unused segmented calibration-ring graphic | Current Home calibration explanations/rings, stored baselines, confidence/progress states, ordinary Ring/MacroRing and all active actions |
| Dormant Poincare painter | `Poincare` class, its paint/repaint implementation and matching obsolete docs; imports only if no other use | Directly constructing this unused NN-pair scatter with identity line/grid | All NN/HRV calculations, SD1/SD2 data/readers, overnight HRV/Recovery, active charts and exports; no current screen/action uses this renderer |

Akshat independently approved both removals. The two classes and their now-unused
PointMode/typed-data imports are removed; all other painters/callers and analytics remain.
Full74 verifies both removals; exact54-line denominator accounting is recorded above. Do not
instantiate inactive renderers just to raise execution, delete underlying algorithms/data,
remove shared point/typed-data imports used elsewhere, or count deletion as newly tested lines.

## Uncalled helper APIs: per-item review

Whole-production-source type/member searches find no caller of `AppText` or either
StreakProtection writer. The active app uses ui2 `F` styles and buildWhoopTheme; streaks read
existing protection through StreakProtection.read. No reflective dispatch constructs these
APIs. Their recovery source is already in the private all-refs bundle. Both proposals below
remain unchanged until separate decisions; no deletion is inferred from the coverage target.

| Item | Exact removal proposal | Lost capability | Retained behavior/data |
|---|---|---|---|
| Unused AppText style API | AppText class, private _barlow/_tnum and twelve static styles; stale header description updated | Directly requesting the uncalled hero/display/metric/metricSm/h1/h2/title/body/bodySoft/label/caption/overline styles | Every rendered ui2 F style, all fonts/assets, _manrope, buildWhoopTheme, ThemeController, platform transitions and current layouts |
| Uncalled streak protection writers | StreakProtection.protect, clear and their private _write helper only | Programmatically creating/removing an unexposed Rest/Life-happens protection day through those dormant wrappers | StreakProtection.read, its existing key/history, export/import/reset, protectionRefusal/pure algorithms and current streak calculation/display; no historical protection is erased |

These reduce dormant implementation, not newly tested lines. The journal editor and shared
inputs need a separate deeper reachability review; they are outside these two decisions.

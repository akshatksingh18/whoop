# Coverage closure and reachability

**Status:** Coverage toward 100% is resumed. The working algorithm-101 Sleep repair
and later restore/reset work pass full candidate79. This is a closure map, not a completed resolved call graph.
No source is excluded. Behavior-neutral scaffolding cleanup and the separately approved
dormant API removal are accounted for separately from new executed-line gains.

The latest fully green source is candidate79:48,643/50,582 (96.17%;1,939 misses).
The table refers to green79; re-match changed files before applying ranges.
Re-match source before using ranges. This remains a closure map, not a complete resolved
call graph. No retired route is reactivated merely to execute its code.

| Area | Purpose and callers | Candidate-79 verified misses | Next proof |
|---|---|---:|---|
| `local_repository_impl.dart` | Shared stored-data readers used by active screens | 117 | Absence, provenance, failure/retry and correction agreement across readers |
| `derivation_engine.dart` | Foreground/headless calculation, staging and publication | 104 | Real worker ownership, retained-input boundaries and refusal/retry |
| `ble_engine.dart` | Peripheral frames, sync lifecycle and durable ACK path | 129 | Remaining accepted/refused/late frame and lifecycle paths |
| `app_state.dart` | User commands, lifecycle and calculation scheduling | 109 | Actual commands and cross-tab revision/failure behavior |
| `local_repository.dart` | Compiler-enforced abstract repository API;53 working methods after approved spot/postJournal/postJournalMetrics retirements (full79 has55) | 0 | No executable-default gap; audit concrete implementations and interface dispatch |
| `ui2/charts.dart` | Shared active chart rendering and interactions | 16 | Actual inputs, gestures, gaps and boundary labels |
| `theme/tokens.dart`, `theme/theme.dart` | Theme/type/platform helpers (AppText retired) | 59 | Identify active platform paths versus definitions with no executable behavior |
| `today_plan.dart`, `home_screen.dart` | Retained planning/Home composition and actions | 76 | Preserve actions, uncertainty and day provenance |
| `db.dart` | Shared SQLite transactions, imports, recovery and reads | 44 | Transaction failures and exact recovery; updated source needs fresh LCOV |
| `journal_compose.dart` | Shared inputs serve Food, Lift, Progress and Nutrition; the developer gallery's rough-night example still reaches the real editor | 169 | Personal Sleep uses `ask: never`. The gallery is a separate actual caller and confirmed sample-write leak; repair/review its state boundary before any editor retirement |

A retained74 source-matched AST index assigns gaps in66 files to594 enclosing declarations.
The prior seven-file/163-declaration inventory remains retained. Exact line lists/source hashes are retained in the local-only checkpoint's
`cov52-function-gap-map.json`. This is a declaration index, not resolved callers,
redundancy classification or new test execution. The largest BLE entry includes Android-only
priority work; other entries include dormant UI helpers. Audit actual shipped callers before
writing tests or proposing separate removals. The two approved painter retirements account
for54 formerly unexecuted instrumented lines (23 dashed-ring,31 scatter), not54 new hits.

The132-check batch passes full79 and executes173 more lines than74; its42-line dormant
cleanup is separate. The next33 controls have41 unchanged-source hits and16 unchanged-line
mappings from positive source-compatible probes; new/changed handlers/instrumentation are
not projected into an old denominator. These stay provisional until combined verification.
The optional clock/platform-policy defaults remain DateTime.now/Platform.isIOS with exact
reverse proofs. Six background controls cover hold/coalescing, external/running cancellation,
requeue, capture and restart over real SQLite; OS wake/budget acceptance remains separate.
The new fixture respects existing light→heavy coalescing. Preserve its initial wrong premise
and corrected proof; do not call it a product bug. postJournal's approved removal removes two
unexecuted lines, not new execution. The approved metrics-wrapper removal preserves all retained tokens; the deletion wrapper/coherence stay.

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
tag vocabulary have active callers. The production repository contract is abstract; partial
test defaults throw `UnimplementedError`. Trace concrete and test implementations separately.

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
this cleanup. The separately approved spot-check retirement left55 contract methods on full74; the approved
postJournal/postJournalMetrics retirements leave53 in the working tree, pending combined verification.

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
APIs. Their recovery source is already in the private all-refs bundle. Akshat separately approved both proposals. Only the listed nodes are removed; no deletion
is inferred from the coverage target. All retained source tokens are identical, and21 existing
theme/streak checks pass. Full verification of the changed sources remains pending.

| Item | Exact removal proposal | Lost capability | Retained behavior/data |
|---|---|---|---|
| Unused AppText style API | AppText class, private _barlow/_tnum and twelve static styles; stale header description updated | Directly requesting the uncalled hero/display/metric/metricSm/h1/h2/title/body/bodySoft/label/caption/overline styles | Every rendered ui2 F style, all fonts/assets, _manrope, buildWhoopTheme, ThemeController, platform transitions and current layouts |
| Uncalled streak protection writers | StreakProtection.protect, clear and their private _write helper only | Programmatically creating/removing an unexposed Rest/Life-happens protection day through those dormant wrappers | StreakProtection.read, its existing key/history, export/import/reset, protectionRefusal/pure algorithms and current streak calculation/display; no historical protection is erased |

The approved changes remove42 formerly unexecuted instrumented lines (30 styles,12 writers),
zero previously executed lines. This reduces dormant implementation, not newly tested lines. The journal editor and shared
inputs need a separate deeper reachability review; they are outside these two decisions.

## Developer gallery: reachable legacy editor and sample-write leak

Concrete caller chain: Settings' developer-mode gallery row → GalleryScreen → Components →
galleryCases/extraCases → RoughNightCard(`ask: on`) → real mergeJournalTags or Add how much →
JournalCompose → shared repository/SQLite. The normal Sleep host forces `ask: never`, but
that does not make the constructor unreachable across the app. A private actual-GalleryScreen
probe confirms a synthetic example tag lands in saved journal history. `bugs.md` owns the
failure and review plan. Original evidence remains local; the121-check public batch is separate.
No gallery or Journal behavior is changed, no feature is deleted and this failure is not a
coverage gain. Shared input widgets, retained journal data/exports and the rough-night report
remain required regardless of the eventual gallery decision.

## Uncalled legacy journal wrappers: separate removal decisions

A complete production-source name/call search finds no caller or tear-off of the three
wrappers below. Matches are their abstract contract, concrete implementation, shared test
fallback and one explanatory comment. The current Gallery-reachable JournalCompose instead
uses getJournalDay/getJournalMetrics/getJournalFields, saveJournalEdit and postCustomJournalField.
Keep that real editor, its conflict checks, vocabulary and every saved row. Akshat separately approved
postJournal and postJournalMetrics; both are removed. The deletion wrapper remains pending.

| Separate item | Exact proposed removal | Capability that becomes unreachable | What stays |
|---|---|---|---|
| postJournal — approved and removed | Contract, concrete forwarding writer and test fallback | Calling the dormant whole-day tag/note replacement API. No current screen or route calls it. | Active mergeJournalTags/saveJournalEdit, journal rows/notes/tags and backup/reset/export. |
| postJournalMetrics - approved and removed | Contract, concrete clamping writer and test fallback; reword saveJournalEdit's comparison comment | Calling the dormant whole-map numeric replacement API. No current screen or route calls it. | Active conflict-aware saveJournalEdit keeps its own identical clamp and explicit-zero/time handling; field definitions, numeric history and algorithms remain. |
| deleteCustomJournalField | Contract, concrete forwarding delete and test fallback | Calling the dormant repository deletion wrapper. No current screen offers this action. | postCustomJournalField, editing/reading existing definitions, LocalDb's stored-data method, all custom values/history/export/reset. No definition is deleted. |

The approved postJournal removal accounts for2 previously unexecuted instrumented lines
on matching78. AST comparison proves every retained token unchanged across contract, concrete
reader and test fallback;35 retained editor/store/repository checks pass. The separately
approved postJournalMetrics removal preserves all other AST tokens and passes25 editor/metric
store checks, retaining clamp, zero/time and conflict handling. The deletion wrapper remains
unchanged. Final accounting must separate cleanup from new execution. Each
remaining item needs Akshat's own decision before deletion. Existing pending
coherence review is separate and is not asked again. getJournalInsights and cycle wrappers
also have no current production caller, but produce distinct dormant reports/writes; their
scope still needs its own complete retained-data/outcome audit. Do not activate them for
coverage or infer permission to delete them from this wrapper review.

## Saved-session connection help

Before repair, ActivitySummary Overview._noHrCard and Graphs._graphs → openProfile → EditProfile
was an active wrong destination, not an unreachable helper. Akshat approved both callbacks
to existing MyDevices/My sources. The same six public cases fail on old source and pass after;
50 summary checks and12 actual viewports preserve State/tab/date/Back/SQL and thermal/short
exceptions. session-band-route-review.md owns the19 Before/Proposed pages. Only the import/
two callbacks changed; other openProfile callers and Settings editing remain. Combined proof
is pending. Existing large-text help ellipsis/Save/status wrapping stays separately open.

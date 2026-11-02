# Coverage closure and reachability

**Status:** Coverage toward 100% is resumed. The working algorithm-101 Sleep repair
needs full cloud verification. This is a closure map, not a completed resolved call graph.
No source is excluded or removed to improve the percentage.

The last fully green checkpoint is candidate 58: 48,104/50,449 (95.35%). The newer
candidate-67 failed-run inventory has 2,333 misses across 50,702 instrumented lines;
it is diagnostic evidence, not a promoted green result. Match source hashes before
using a range. The current Sleep repair changes several of those source files; its updated ranges require the next artifact.

| Area | Purpose and callers | Candidate-67 diagnostic misses | Next proof |
|---|---|---:|---|
| `local_repository_impl.dart` | Shared stored-data readers used by active screens | 137 | Absence, provenance, failure/retry and correction agreement across readers |
| `derivation_engine.dart` | Foreground/headless calculation, staging and publication | 137 | Real worker ownership, retained-input boundaries and refusal/retry |
| `ble_engine.dart` | Peripheral frames, sync lifecycle and durable ACK path | 129 | Remaining accepted/refused/late frame and lifecycle paths |
| `app_state.dart` | User commands, lifecycle and calculation scheduling | 112 | Actual commands and cross-tab revision/failure behavior |
| `local_repository.dart` | Shared repository API and default implementations | 104 | Audit concrete overrides/callers before classifying redundant defaults |
| `ui2/charts.dart` | Shared active chart rendering and interactions | 70 | Actual inputs, gestures, gaps and boundary labels |
| `theme/tokens.dart`, `theme/theme.dart` | Theme/type/platform helpers | 89 | Identify active platform paths versus definitions with no executable behavior |
| `today_plan.dart`, `home_screen.dart` | Retained planning/Home composition and actions | 76 | Preserve actions, uncertainty and day provenance |
| `db.dart` | Shared SQLite transactions, imports, recovery and reads | 38 | Transaction failures and exact recovery; updated source needs fresh LCOV |
| `journal_compose.dart` | Shared `WhoopTextField` serves Food, Lift, Progress and Nutrition; tag vocabulary serves the active rough-night report | 169 | The personal Sleep host supplies `ask: never`, gating the rough-night journal question/editor route. Preserve active shared inputs and report; audit remaining constructors before any per-item deletion proposal |

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
production subclass is that concrete reader; partial test readers still inherit placeholders
and three useful fallback helpers. Those bodies are scaffolding, not missing product work.
A proposed cleanup keeps every method/signature and all concrete behavior, makes the
production contract abstract, and moves partial-reader defaults to test support. This would
make missing production implementations a compile-time failure. It removes no metric,
action, route, storage or calculation; record its changed executable denominator separately
from genuine new executed-line gains. No such refactor is implemented in candidate69.

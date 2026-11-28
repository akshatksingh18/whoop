# Coverage verification

**Status:** 100% handwritten Dart line execution is verified on main `71621b83` (48,386/48,386,
7,262 passed, 377 skipped, [run 46098522214](https://github.com/akshatksingh18/whoop/actions/runs/46098522214)),
after the 3r removals and the `LocalDb` store splits through `CursorStore`, with no exclusions,
new skips or retired-feature activation. Two clock-dependent tests are pinned so the proof holds
at any CI start: a tomorrow-dated test in `localized_day_controls_test.dart` runs
`day_steps.dart`'s hours-after-now blanking loop, and `today_body_recovery_navigation_test.dart`
pins the tape day to tomorrow so a Saturday run (the default measurement weekday) still sees the
tape row. The detailed proof below was first established on main `aacaed47`. 100% instrumented Dart execution certifies no radio, sensor or OS
delivery; native and physical acceptance stay separate (`bugs.md`, `todo.md`).

## Current proof

Fully verified [Linux run 45814713906](https://github.com/akshatksingh18/whoop/actions/runs/45814713906)
for parentless candidate 182 (`e576ccdb3a691e8c384f8baa4d1eb0c3086398d4`), source `521e8795`.
Candidate 183 (`aacaed47`, the same code plus the proof docs) repeated the full verification in
[run 45821624488](https://github.com/akshatksingh18/whoop/actions/runs/45821624488) and became
GitHub main; main's own [run 45831515081](https://github.com/akshatksingh18/whoop/actions/runs/45831515081)
again executes 49,366/49,366:

- handwritten Dart execution **49,366/49,366 (100%, 0 misses)**; the one `dart format` pass split
  branches onto their own lines, so counted lines rose, and the nine it exposed are now tested or
  restructured;
- 839 files, 7,348 tests passed and 429 existing skips retained;
- both package suites, `flutter analyze` (no findings, infos fatal) and the
  `dart format --set-exit-if-changed` check passed;
- raw worker receipts, merged LCOV, source hashes, the caller graph and every rendered page
  state were independently checked against candidate 178 through the test-folder move map:
  no hit lost on an unchanged file, no case lost, six cases added and no page added or removed.
  Candidate 178 was itself checked against 176; its retired cases belong to the removed live
  wrist pedometer, HR-only mode and uncalled helpers (`coverage-map.md`).

## How coverage is measured

All of it runs on GitHub Actions (`.github/workflows/test.yml`, `workflow_dispatch`):

| Scope | What it does |
|---|---|
| `full` (default) | Plans six cost-balanced shards (`tool/coverage_shard_plan.py`, `tool/coverage_test_costs.json`), runs each serially with `--coverage`, then `tool/coverage_shards.py merge` requires every exact-source shard and unions their LCOV for that one tree. |
| `serial-full` | One serial run of the whole suite: the reference when a shard result is in doubt. |
| `caller-map` | `tool/coverage_callers.dart` resolves method, constructor, operator and tear-off references for every authored declaration. It maps callers only; it never proves coverage or approves removal. |

`tool/coverage_gaps.py` lists every unexecuted line from the merged LCOV without hiding source;
files with no LCOV record (const-only or export-only libraries such as `build_profile.dart`,
`migration/legacy_names.dart`, `ui2/ui2.dart`, `ui2/screens/screens.dart`) are reported
separately. The same workflow renders the canonical synthetic pages (`UI_CAPTURE=true`) and runs
the Python tool tests.

## Rules for a coverage claim

- A score belongs to one exact source tree. Never union hits from an older, failed or prototype
  run into a new total.
- No exclusions, new skips, fake producers or activating a retired mode to reach a line.
- A line that cannot run in production is restructured with unchanged output, or removed with
  the gates in `rules.md`; it is never hidden from the denominator.
- Test real missing, refused, retry, disposal and ownership boundaries alongside success, and
  keep existing assertions.
- Timing-sensitive branches (current hour, weekday, date) take a fixed clock so a hit does not
  depend on when CI runs.
- Locally, run only targeted test files; a local LCOV can guide work but certifies no score.

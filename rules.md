# Codebase rules

What every change must keep true. [context.md](context.md) explains how the app fits together;
`CLAUDE.md` owns the session, branch and push agreement. When a rule here and the code disagree,
stop and ask rather than pick one.

## Data integrity (a violation is a P0 regression)

1. **Commit before ACK.** In the history drain (`lib/ble/ble_engine.dart`) the decoded rows and the
   cursor commit in one transaction before the verbatim 8-byte HISTORY_END token is echoed. The
   band trims its flash on ACK. Never ACK a partial chunk and never regenerate the token.
2. **`decoded_onehz` replaces** on `(device_id, ts_ms)`. Evicting a row deletes that counter's
   `decoded_rr` beats in the same batch.
3. **Never fabricate a metric.** Missing, thin or invalid input stays null, `Metric.absent`, "—" or
   a labelled estimate with its reason. No imputation, substituted defaults or one metric standing
   in for another. Ask of every metric diff: what does this return with no input?
4. **Never prune raw or decoded data for a day that is not fully derived.** A partial scalar does
   not finalize a day. `raw_archive` holds only undecodable frames; it is not a backup.
5. **Migrations are additive, idempotent and cheap:** a sequential `if (oldV < N)` ladder plus
   `_repairOpenSchema` for same-version repair. `PRAGMA journal_mode=WAL` goes through `rawQuery`.
   Never move a live SQLite file without its WAL state.
6. **Reset** runs entirely inside `CalculationStore.resetWith`, through native and preference
   completion and capture/derive shutdown. No re-entry and no restoring an anchor after a wipe.

## One source per concern

7. One raw decode point (`lib/compute/substrate.dart`), one sleep segmentation, one readiness, one
   frame-ingest path (`RecordGate`) and one notification emitter (`NotificationCenter.emit`, with
   a persistent fire-once key). A second path is the bug.
8. A new decoder or capability is wired into **every** call path for that concern
   (`ble_engine.dart`, `db.dart`, `substrate.dart`). Count the call sites before and after.
9. Day labels are local: use `todayLabel()` / `dayLabelOf()` from `lib/data/day_label.dart`. Epoch
   timestamps stay absolute. Never assume a day is 86,400 s.
10. Keep effective, eaten, recorded and logged provenance distinct.

## Runtime safety

11. Heavy analytics never runs on the UI isolate. Use `Isolate.run` and re-arm analytics ambient
    state inside the closure.
12. Headless and background syncs go through `HeadlessSyncGate.tryRun`: skip, never queue.
13. Every flag a change sets is cleared in `finally`, on timeout and on the give-up branch. A late
    result is dropped once a newer owner holds the resource.
    Schema, media and backup mutations handle failure, retry and cancellation, and bump the
    revision only after commit.
14. No `context` or Provider use after an `await` without a `mounted` check, and none in `dispose`.
15. High-rate live data stays in RAM. The live band stream is heart rate only and steps come only
    from the phone.
16. Dangerous opcodes (trim, reboot, power cycle, firmware load) are never sent automatically.

## Versions

- **`kAlgoVersion`** (`lib/compute/derivation_engine.dart`) is bumped, with a changelog entry above
  the constant, whenever any analytics output changes, including a change under
  `packages/analytics`. Stored results are immutable per version. A pure rename needs no bump.
  Update `packages/algorithm-contract.json` and run `python tool/algorithm_contract.py`.
- **`schemaVersion`** (`lib/data/db.dart`) is bumped only with a new ladder step.
- **`version:`** in `pubspec.yaml` always keeps its `+BUILD` suffix; every new binary gets a new
  build number. `tool/personal_ios_accepted_builds.json` refuses reuse.
- `packages/protocol` and `packages/analytics` are tracked path dependencies. No floating Git refs
  and no `pubspec_overrides.yaml`.

## Change gates (need Akshat's decision)

- **Removing a feature, screen or API:** first list every metric, insight and entry point that
  would be lost, and say whether each is a core metric (recovery, strain, sleep, HRV, heart rate,
  breathing, steps, workouts) or redundant. Hiding UI never authorizes stopping computation or
  storage. Zero static callers alone does not prove something is redundant.
- **UI behaviour or layout:** complete synthetic Before/Proposed full-page mockups and Akshat's
  choice before code. Follow `DESIGN.md`.
- **Calculation or output:** a separate reviewed version decision. Keep the approved running,
  walking, lifting, digestion and Recovery methods; the withdrawn awake 1.2 multiplier stays
  withdrawn. Parked treadmill, calorie and Food-default proposals in `todo.md` are not permission.
- **Platform scope:** iPhone only, release/AOT, empty entitlements. No Android, Watch, extensions,
  HealthKit, App Groups, Firebase, OTA, coach, silent audio or installer runtime dependency. The
  approved native profile (AccessorySetupKit, Bluetooth, GPS, Home region, voice, BG scheduler) is
  enforced by `tool/personal_ios.py`.
- **Cleanups keep behaviour identical.** A cleanup that changes behaviour is a feature change and
  takes the gates above.

## Tests and coverage

- Handwritten Dart coverage stays at 100%. A behaviour change comes with a test that would fail
  without it; keep old assertions unless the behaviour they pin is deliberately removed.
- Fixtures are synthetic. Never use real health data, recordings or personal measurements.
- Locally run only quick, targeted tests. Full suites, `flutter analyze` and coverage run on
  GitHub Actions (`test.yml`); never merge old or failed LCOV.
- CI fails on any analyzer finding, infos included, and on `dart format` drift in `lib`, `test`
  and `tool`. Put a new test beside the `lib/` area it exercises and reuse `test/support/` fakes.
- Synthetic tests prove no physical radio, sensor or OS behaviour. Phone acceptance is recorded in
  `bugs.md` and `todo.md`.

## Privacy and publishing

- `origin` is public. Before any push, review the outgoing content and history for personal data,
  secrets, Apple team IDs and private paths. Pushes follow the gate in `CLAUDE.md`.
- Never commit Akshat's local tooling (`.impeccable/`, `.claude/skills/impeccable/`, `.codex/`,
  `tool/impeccable-hook.ps1`) or anything under `build/ownership-checkpoint/`.
- Verify an encrypted off-phone export and restore before an upgrade or any identity, schema or
  format change.

## Documents

- `CLAUDE.md` indexes every project file under `## Files`. Each fact has one owner; link rather
  than copy.
- Write current state, not history. Remove superseded wording in the same change; Git keeps the
  history.
- Plan multi-part work in `todo.md` with the decisions Akshat must take.

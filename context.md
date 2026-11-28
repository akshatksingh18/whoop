# Codebase context

Read this first in a new session: what the app is, how data moves through it, where each concern
lives and where to add something. [rules.md](rules.md) owns what must never break; the documents
linked below own the details.

## What it is

A personal iPhone app (Flutter, release/AOT, sideloaded) for a WHOOP 4.0 band, forked from
OpenStrap. It talks to the band directly over Bluetooth LE, stores everything in on-device
SQLite and computes recovery, strain, sleep, HRV and the related metrics locally.

- **No backend:** no account, telemetry, OTA or LLM calls. Barcode lookups (Open Food Facts) and
  map tiles (MapKit) are the only optional network requests.
- **iPhone only:** Android, Watch, app extensions, HealthKit, App Groups and Firebase are removed.
- **Steps come from the phone** (`CMPedometer`). The live band stream is 1 Hz heart rate only.
- **Versions** are read from source, never from docs: `version:` in `pubspec.yaml`, `kAlgoVersion`
  in `lib/compute/derivation_engine.dart`, `schemaVersion` in `lib/data/db.dart`.

## Data flow

```
band (BLE) ──► lib/ble ──► lib/data (SQLite ledger) ──► lib/compute ──► day_result / metric_series
   ▲             │              ▲                            │                 │
   │       live HR (RAM)        │ phone steps, GPS, food,    │ packages/       ▼
   └── ACK after commit         │ body, manual entries       │ analytics   lib/data/local_repository_impl
                                                                                │ (read seam)
                                         lib/state/app_state.dart ◄─────────────┘
                                                    │
                                                 lib/ui2 (screens)
```

1. **Connect and drain** (`lib/ble/ble_engine.dart`). The engine pairs (iOS AccessorySetupKit),
   connects, streams live HR and drains the band's flash history. Each history chunk is decoded
   by `packages/protocol` and committed with its cursor in one transaction **before** the
   HISTORY_END ACK, because the ACK lets the band trim its flash.
2. **Store** (`lib/data/db.dart`). Decoded 1 Hz rows land in `decoded_onehz` and beats in
   `decoded_rr`; undecodable frames go to `raw_archive`. Phone steps (`live_coverage`), GPS
   routes, food, body, sessions and manual entries have their own tables.
3. **Derive** (`lib/compute/`). `substrate.dart` is the single decode point from stored rows to a
   per-day `Substrate`. `derivation_engine.dart` schedules days, runs the per-day pipeline
   (`onehz_pipeline.dart`, off the UI isolate) and cross-day work, and writes immutable
   `day_result` rows keyed by `(day_id, algo_version)` plus `metric_series`. The formulas live in
   `packages/analytics`.
4. **Read** (`lib/data/local_repository_impl.dart`). Turns stored results into screen shapes and
   computes nothing on read.
5. **Orchestrate and show.** `lib/state/app_state.dart` is the single ChangeNotifier wiring BLE,
   storage, derivation, phone sensors, workouts and notifications. `lib/ui2/` holds every screen.

**Background:** iOS wakes the app through CoreBluetooth restoration (`lib/ble/ios_ble_restore.dart`,
`ios/Runner/BleRestoreManager.swift`) and two BG tasks (`lib/sync/ios_bg_task.dart`). Headless
drains serialize through `HeadlessSyncGate`. Heavy derivation waits for the foreground or a
processing task (`lib/compute/derive_scheduler.dart`).

## Source areas

| Area | Owns |
|---|---|
| `packages/protocol/` | Bytes: GATT profiles, framing, CRC, opcodes, record decoders. Pure Dart. |
| `packages/analytics/` | Metrics: HRV, sleep staging, readiness, strain, energy. Pure Dart. |
| `lib/ble/` | Link state machine and drain (`ble_engine.dart`); pure policies in `ble_state.dart`. |
| `lib/sync/` | Sync policies (`sync_policy.dart`), headless/BG entries, paired device, file log. |
| `lib/data/` | `db.dart` (schema ladder, SQL) and its per-concern stores (`notif_fired_store.dart`, `sleep_nap_store.dart`, `journal_store.dart`, `sleep_override_store.dart`, `workout_route_store.dart`, `session_store.dart`, `workout_suggestion_store.dart`, `step_coverage_store.dart`, `sync_ledger_store.dart`, `diagnostics_store.dart`, `compute_job_store.dart`, `metric_series_store.dart`, `compute_freshness_store.dart`, `series_reencode_store.dart`, `sleep_intermediate_store.dart`, `storage_retention_store.dart`, `frozen_headline_store.dart`, `cursor_store.dart`, `device_store.dart`, `observation_store.dart`, `day_result_store.dart`, `day_provenance_store.dart`, `backup_import_store.dart`), read seam, backups, food/body/lift stores, `day_label.dart`. |
| `lib/compute/` | Substrate, pipelines, derivation engine and scheduler, sessions, streaks, upkeep. |
| `lib/state/` | `AppState` and its small helpers; the one source of truth for the UI. |
| `lib/notify/` | `NotificationCenter.emit` (the single emitter), fire-once keys, alert policies. |
| `lib/gps/` | Route recording, run/walk measurements, splits, best efforts. |
| `lib/platform/` | Native channels: phone pedometer, motion activity, signing profile. |
| `lib/import/` | Encrypted backup and third-party export importers. |
| `lib/ui2/` | Design system (`theme.dart`, `grammar.dart`, `charts.dart`), `screens/`, `activity/`, `profile/`, `onboarding/`. |
| `ios/Runner/` | Personal Runner: `AppDelegate.swift` bridges, BLE restore, BG scheduler. |
| `tool/` | Algorithm contract, coverage/caller tooling, personal iOS transform/validator. |
| `test/` | Flutter tests in folders that mirror `lib/` (`test/data/`, `test/ui2/screens/`, ...), named for what they check; `test/contracts/` holds cross-cutting source rules and `test/support/` shared fakes. Fixtures are synthetic only. |

The largest files, and the most bug-prone, are `app_state.dart`, `db.dart`,
`derivation_engine.dart`, `ble_engine.dart` and `local_repository_impl.dart`. Review changes there
with extra care.

## Where to add something

| Change | Where | Also |
|---|---|---|
| New opcode or record | `packages/protocol` | Wire it into **every** decode path (`ble_engine`, `db`, `substrate`). |
| New or changed metric formula | `packages/analytics` | `kAlgoVersion` bump + changelog; update `packages/algorithm-contract.json`. |
| New stored data | `lib/data/db.dart` | Additive, idempotent `if (oldV < N)` step + `_repairOpenSchema`; add the table to the backup/restore and wipe lists. |
| New derived value | `lib/compute` (orchestration only) | Absent input stays absent; repeated derivation must be idempotent. |
| New screen or UI change | `lib/ui2` | Full-page Before/Proposed mockups and Akshat's choice first; follow `DESIGN.md`. |
| New notification | `lib/notify` | Only through `NotificationCenter.emit` with a fire-once key. |
| New native capability | `ios/Runner` + `tool/personal_ios.py` | Keep the approved capability profile; update the payload validator and its tests. |

Every change keeps handwritten Dart coverage at 100% ([coverage-audit.md](coverage-audit.md)).
Plan first in [todo.md](todo.md).

## Build, test and release

- Day-to-day checks are quick targeted tests locally. Full suites, coverage and analysis run on
  GitHub Actions (`.github/workflows/test.yml`, `package-tests.yml`).
- The iPhone IPA is built by the manual `personal-ios.yml` workflow and sideloaded with
  Sideloadly. [setup.md](setup.md) owns toolchain, identity, release and recovery;
  `guides/IOS_INSTALLATION.md` and `guides/IOS_SIDELOAD.md` own payload and signing continuity.

## Document map

| Document | Owns |
|---|---|
| [rules.md](rules.md) | Invariants, gates and working rules. |
| [todo.md](todo.md) | Open work, decisions and proposals. |
| [metrics-map.md](metrics-map.md) | Every metric: readers, absence/estimate rules, calorie methods. |
| [bugs.md](bugs.md) | Known defects and physical acceptance. |
| [setup.md](setup.md) | Toolchain, checkout, identity, release, recovery. |
| [coverage-audit.md](coverage-audit.md), [coverage-map.md](coverage-map.md) | Coverage proof; function/caller audit and removal decisions. |
| [DESIGN.md](DESIGN.md) | Locked visual system and tokens. |
| `*-review.md`, `*-plan.md` | One approved change or open proposal each; indexed in `CLAUDE.md`. |

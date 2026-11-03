# WHOOP companion

Akshat Kumar Singh's personal iPhone project for training, food, sleep and recovery.
The Flutter app talks to a WHOOP band over Bluetooth, stores its data in SQLite and
computes estimates on the phone. There is no app account, subscription or backend.
It is not affiliated with WHOOP, Inc. Estimates do not claim parity with its algorithms.

## Features

- Today: recovery, sleep, strain, live and recorded heart rate, phone steps and daily actions.
- Trends and Sleep: dated history, input-quality explanations, estimated stages, naps and corrections.
- Food: editable meal diary, saved foods/meals, portions, optional barcode lookup, fixed goals
  and separate maintenance estimates. Exercise never increases the typed food goal.
- Train: GPS runs/walks, splits and voice cues; timed lifting with editable sets and previous
  performance; Pushups and a recorded-activity streak.
- Progress: dated body measurements/photos, comparable strength history and qualified goal reviews.
- Recovery: passphrase-encrypted exports, photo-inclusive manual backups and local restore.

Project work includes the personal iPhone build profile and payload validator, phone-step
ownership, integrated food/body/lifting workflows, dated data provenance, safer mutation and
restore flows, the five-tab interface and expanded regression/visual coverage.

## Build the personal iPhone app

Use the Flutter version pinned in `.github/workflows/test.yml` (currently 3.41.6).
Protocol and analytics resolve from the tracked `packages/` folders. Run
`python tool/algorithm_contract.py` and `python tool/personal_ios.py check` for quick contracts.
Full analysis, suites and synthetic page captures run through the manually dispatchable
Linux `test.yml` workflow. The manually dispatched `personal-ios.yml` macOS workflow creates
an unsigned release IPA, validates its payload and records its source/version/checksum.
Native builds are currently held until the coverage gate in [todo.md](todo.md) is resolved.

[Installation](guides/IOS_INSTALLATION.md) explains packaging and device acceptance;
[sideloading](guides/IOS_SIDELOAD.md) explains signing continuity and recovery.
Never uninstall or change the installed app identity just to install an update.

## Data and limitations

Storage and analytics stay on the phone. Optional Open Food Facts lookup sends a scanned barcode; Apple Maps
snapshots use route coordinates. These requests disclose those inputs to their providers.
Automatic backups remain inside the app container: copy a verified encrypted full export off
the phone for independent recovery. Do not publish health exports, logs, recordings or signing material.
Software checks do not certify physical accuracy, background delivery or phone acceptance.

## Source layout

`lib/` owns app/storage/UI orchestration; `ios/` the Runner app; `packages/protocol/` BLE
framing/decoding; `packages/analytics/` pure metric methods; `test/` synthetic regressions;
`tool/` build, coverage and contract helpers. [CLAUDE.md](CLAUDE.md) owns engineering rules,
[metrics-map.md](metrics-map.md) behavior and [todo.md](todo.md) the current backlog.

MIT: [LICENSE](LICENSE), with package licenses in their source folders.

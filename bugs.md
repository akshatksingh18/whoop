# Remaining reliability investigations

**Status:** COV-46's final-tail, backup-feedback and dialog-lifetime repairs pass full Linux
run [40807926057](https://github.com/akshatksingh18/whoop/actions/runs/40807926057), including COV-47 and the first 83 COV-48 controls; all three retained UI regressions are enabled and pass. The existing heart fixture
is corrected for minute rollover, with no production chart change. Remaining coverage,
physical acceptance, the enlarged name helper and ownership migration stay open.

- Background startup now checks band/generation ownership after its async waits. COV-45's
  cancellation/normal-path controls pass full Linux run 40585719502. This does not certify
  physical restoration.
- Backup keychain failure feedback is preserved: `_run` now replaces a note only when the
  nested action returns nonempty text. The shared fix covers passphrase, cadence and Back up
  now. Cancellation clears stale feedback at action start; refusal does not enable backups.
  The retained failure regression is enabled. Complete before/after pages and limits are in
  `reliability-ui-review.md`; full Linux verification passes and physical keychain acceptance
  remains open.
- Band-name editing now uses a framework-owned form controller through route exit instead of
  disposing an external controller immediately after pop. Validation, actions and wording stay
  the same. Both retained Save regressions pass full Linux verification; cancellation, reopen, retry and late
  completion after host disposal have controls. Before/after host/dialog pages match exactly.
  The existing 2x helper-text truncation is separately open; do not call it resolved.
- Final step tails now reset counters synchronously, then serialize immutable snapshots with
  recovery and minute publication. The existing gain-applied checkpoint is acknowledged before
  final SQLite replay, retained on refused first/later midnight writes and cleared only after
  acknowledged banking. Refused checkpoint writes fall back to SQLite; if both stores refuse,
  the tail stays in RAM for retry. Process death while neither store accepts writes cannot be
  made durable. Reset drains writers before wiping. Existing keys, shape, gain and row identity
  remain. All refusal/retry/reset controls pass full Linux verification; actual reconnect/
  kill/power-loss behavior still needs phone acceptance.

- Live/headless event-write error observation is repaired in source, awaiting combined CI.
  Both `LocalDb.insertEvent` callers now observe/report a failed Future through their existing
  local logger. The database still rethrows non-closed failures to awaited callers, alarms
  remain immediate and durable historical commit/ACK is unchanged. Four new real SQLite
  refusal controls pass for foreground/headless event and mirror inserts. Prior evidence,
  duplicate-free retry, exact headless ACK/cursor/queue cleanup and failure diagnostics remain.
  The three-file cohort passes 14 checks; the unchanged original private negative source now
  passes too. Keep `cov48-live-event-refusal-reproducer_test.dart`, its original failed log and
  `cov48-live-event-repair-confirmation-targeted.log` local. No phone crash, refused-byte
  durability or complete area coverage is claimed; no failure is hidden by a skip.

- A synthetic COV-47 probe reproduces an ancient-upgrade retention gap: the pre-v19
  raw replay ignores undecodable historical rows, then drops `raw_records`. The decoded
  timestamp/fallback contract has separate passing controls; that does not resolve unknown-row
  retention. Preserve the failing source and log in ignored recovery evidence
  (`cov47-legacy-unknown-retention-reproducer.dart`, `cov47-ladder-b-targeted.log`).
  A focused preservation repair and regression are still required before claiming all migration
  paths complete. Current schema-50 ingest and existing archives are not changed by this probe.

- An authored COV-48 historical What-changed reproduction loses valid earlier history after
  a later algorithm boundary. `getChart` returns the global version-break list;
  `collectSweepSeries` takes its latest break without restricting it to the shown day. An
  April 7 break reduces the April 6 comparison from 20 earlier observations to 0, although
  the day's value remains present. The UI's existing absence reader can then report that it
  is still learning. This is a synthetic reproduction, not a claimed phone observation.
  Preserve `cov48-future-algorithm-break-reproducer_test.dart` and
  `cov48-future-break-repro-targeted.log` locally. Review the shared as-of-day cutoff and its
  historical finding/preview implications before repair; retain global chart metadata and
  the rule against comparing across a boundary that actually precedes the shown day. Four
  positive historical-loader controls pass separately; the failure is not counted as coverage
  or hidden with a public skip. No production/scientific method or version changes here.

- Food's general Log food meal default is user-reported and uninvestigated. Trace every entry
  point and existing cutoffs before proposing a fix; preserve explicit/manual meal and viewed date.
- Import-encoding routing is repaired in source, awaiting combined CI. The shared journal
  reader decodes bytes with strict UTF-8 so malformed text yields FormatException; a genuine
  file-read failure still yields FileSystemException. Its only production caller, the mixed
  importer, can then use the existing lenient vendor route instead of aborting after earlier
  files committed. Six new checks preserve original bytes, valid Unicode/BOM/quoted notes,
  unchanged I/O failures and earlier groups when vendor handling succeeds or refuses. They
  pass with four existing partial-import checks. The unchanged private Latin-1 reproduction
  also passes (`cov48-latin1-repair-confirmation-targeted.log`); retain its original failing
  source/log. Vendor character replacement behavior is unchanged; no Latin-1 reconstruction,
  atomicity across every selected file or complete import coverage is claimed.
- Food's separate day-page layout repair is approved as option A and implemented. Five
  targeted width/text cases pass, including the enabled 3.1x regression; actual full pages match
  the approved previews. Headings, date controls and full unknown-energy text remain reachable.
  `food-layout-review.md` owns the evidence; full Linux run 40483497760 passes. Native/phone
  acceptance remains open.
- COV-43 reproduces two existing orphan-checkpoint loss paths after refused SQLite writes:
  finalizing an empty stream erased the checkpoint, and a new counting minute replaced it.
  Shared recovery now banks old bytes before clearing/replacement; a failed replay retains them.
  Old snapshots replay before fresh publication so counts do not regress. Nine targeted cases
  pass locally and in full Linux run 40483497760. Fifteen additional shared-host/live controls cover saved entry,
  finish/retry and pause/profile preservation; these are verification of existing behavior,
  not newly discovered app defects. COV-46 extends preservation to the final tail while retaining
  synchronous counter reset and serialized immutable publication.
- BLE/background reliability needs real pairing/denial/range-loss/restoration/short-wake/expiry
  evidence. Unit tests do not establish overnight delivery, freshness or freedom from CPU exits.
- The authored R10 eight-beat frame is accepted by `realtimeRr` but loses its beat block in
  historical `parseR10Lite`: the latter uses R24's four-beat ceiling. The engine then supplies
  an empty RR list for that frame. Preserve `cov47-r10-eight-beat-reproducer_test.dart` and
  `cov47-r10-eight-repro-targeted.log` locally; the named revision-10 case proves the realtime
  decoder retains all eight before the historical assertion fails.
  Review the shared R10 count contract, immutable algorithm/version implications and durable
  ingest before changing package output. Passing four-beat and revision-12 padding controls
  do not resolve this discrepancy or certify historical phone data. No package behavior or
  digest/version is changed for COV-47.
- Legacy gen5 `0x93` clock augmentation is repaired in source, awaiting combined CI. It now
  honors the protocol's revision-1 layout guard before interpreting an unset epoch. Seven new
  controls cover revisions 0/7/255 refusing correction and current opcode-11 layout/status
  behavior on both generations. The public file passes 16 checks; the unchanged private
  revision-7 reproduction passes too, for 17 targeted checks total. Its original source and
  failed log stay local; new proof is `cov48-legacy-clock-guard-a-targeted.log`. Documented
  revision-1 unset correction, gen4 status policy, current gen5 opcode 11 and package output
  are unchanged. This is not a claimed physical clock/alarm acceptance result or a complete
  BLE-coverage claim; no algorithm/schema/metadata change.
- GPS, speech, Pushups region/notification behavior, media restore and signing continuity retain
  their phone acceptance gates. No cached artifact is promoted by a source-only check.
- COV-40 fixes two existing sync-state repair defects in source: current cursor writes now
  follow cursor repair, and ambiguous non-keyed quarantine copies retain both tables. Nine new
  regressions plus the existing ladder pass (25 checks), and full Linux run 40449039544 passes.
  Retained legacy quarantine rows need an independently reviewed reconciliation before removal;
  no automatic merge or import of those ambiguous rows is claimed.
- The persisted-name migration is not implemented. Legacy database, backup, UUID and OS-owned
  identifiers remain compatible; no schema/version/algorithm bump has been made for cleanup.
- Scientific validation, retained-history/time-zone and missing-input boundaries remain tracked
  investigations. Do not treat an old reproduction as an unfixed current regression without tracing it.

Exact historical reproductions, private device observations and earlier repair evidence remain
in the local-only pre-fresh-start archive. Preserve those records; do not publish raw logs or
personal measurements to make public CI reproduce them.

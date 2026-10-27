# Remaining reliability investigations

**Status:** COV-46 implements three authorized reliability fixes after reproducing the failures
and reviewing complete-page synthetic UI prototypes. The first combined run failed an existing
chart fixture at a minute rollover; the repairs passed individually. A test-only correction
and three aged-snapshot controls pass locally; a full rerun remains. COV-45 run 40585719502 remains the last fully verified checkpoint. Remaining coverage,
physical acceptance, the large-text name helper and ownership migration remain open.

- Background startup now checks band/generation ownership after its async waits. COV-45's
  cancellation/normal-path controls pass full Linux run 40585719502. This does not certify
  physical restoration.
- Backup keychain failure feedback is preserved: `_run` now replaces a note only when the
  nested action returns nonempty text. The shared fix covers passphrase, cadence and Back up
  now. Cancellation clears stale feedback at action start; refusal does not enable backups.
  The retained failure regression is enabled. Complete before/after pages and limits are in
  `reliability-ui-review.md`; full CI and physical keychain acceptance remain separate.
- Band-name editing now uses a framework-owned form controller through route exit instead of
  disposing an external controller immediately after pop. Validation, actions and wording stay
  the same. Both retained Save regressions are enabled; cancellation, reopen, retry and late
  completion after host disposal have controls. Before/after host/dialog pages match exactly.
  The existing 2x helper-text truncation is separately open; do not call it resolved.
- Final step tails now reset counters synchronously, then serialize immutable snapshots with
  recovery and minute publication. The existing gain-applied checkpoint is acknowledged before
  final SQLite replay, retained on refused first/later midnight writes and cleared only after
  acknowledged banking. Refused checkpoint writes fall back to SQLite; if both stores refuse,
  the tail stays in RAM for retry. Process death while neither store accepts writes cannot be
  made durable. Reset drains writers before wiping. Existing keys, shape, gain and row identity
  remain; actual reconnect/kill/power-loss behavior needs phone acceptance.

- Food's general Log food meal default is user-reported and uninvestigated. Trace every entry
  point and existing cutoffs before proposing a fix; preserve explicit/manual meal and viewed date.
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

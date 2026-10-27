# Remaining reliability investigations

**Status:** Existing repairs and controls through COV-42 pass combined Linux verification. Remaining coverage,
physical acceptance and ownership migration remain open; see `todo.md` and `coverage-audit.md`.

- Food's general Log food meal default is user-reported and uninvestigated. Trace every entry
  point and existing cutoffs before proposing a fix; preserve explicit/manual meal and viewed date.
- Food's separate day-page layout repair is approved as option A and implemented. Five
  targeted width/text cases pass, including the enabled 3.1x regression; actual full pages match
  the approved previews. Headings, date controls and full unknown-energy text remain reachable.
  `food-layout-review.md` owns the evidence; combined Linux and phone acceptance remain open.
- COV-43 reproduces two existing orphan-checkpoint loss paths after refused SQLite writes:
  finalizing an empty stream erased the checkpoint, and a new counting minute replaced it.
  Shared recovery now banks old bytes before clearing/replacement; a failed replay retains them.
  Old snapshots replay before fresh publication so counts do not regress. Nine targeted cases
  pass; combined CI is pending. Separately investigate current-tail banking failures together
  with reconnect generation ownership before changing synchronous counter reset behavior.
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

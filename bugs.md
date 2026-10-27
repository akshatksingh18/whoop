# Remaining reliability investigations

**Status:** Existing repairs and controls through COV-41 pass combined Linux verification. Remaining coverage,
physical acceptance and ownership migration remain open; see `todo.md` and `coverage-audit.md`.

- Food's general Log food meal default is user-reported and uninvestigated. Trace every entry
  point and existing cutoffs before proposing a fix; preserve explicit/manual meal and viewed date.
- COV-41 confirms a separate Food day-page layout defect: `DayFoodPage._meal`'s heading row
  overflows right by 150 px at 430 px width and 3.1x text with authored mixed/unknown meal totals.
  The same heading also overflows 85 px at 320 px/2x. The regression stays explicitly skipped;
  this is not a passing acceptance result. Full-page review also shows clipped `Calories unknown`
  and awkward date wrapping. Complete Before/A/B previews in `food-layout-review.md` preserve
  every total, uncertainty label, heading and navigation action. Approval is pending; production
  UI is unchanged. Exact reproductions and previews remain in ignored recovery evidence.
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

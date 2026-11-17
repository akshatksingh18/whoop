# Session split preservation:repair and version review

**Status:** Confirmed synthetic failure;production unchanged. Approval is pending.

## Confirmed behavior and scope

The shared saved-session reader/re-score updates sessions.trace_samples and the ordinary
summary/trace first. It then freezes per-kilometre rows separately. If that second SQLite
transaction refuses its write,its old split rows survive,but the already advanced trace
sample count makes the next read skip the freeze. Correct split history can remain missing
until retained pulse input is pruned. Two exact known/unknown-altitude regressions reproduce
this;the same two healthy-input controls pass. These are authored protocol-decoded R24
observations and synthetic GPS coordinates,not real captures or location records.

The frozen split table is a forward-looking archive. No current app screen calls its
workoutSplits reader;existing database tests do. This finding does not mean the current
workout page displays a wrong split chart. All existing source observations remain intact.
No UI layout,navigation,text or feature removal is proposed,so there is no changed page to
preview. Native/phone acceptance and the IPA hold remain separate.

## Proposed shared repair

1. Stage the same existing kilometre split calculation before committing a new trace.
   Preserve current no-route/no-split absence decisions and all formulas. A preparation
   failure must leave the old completion marker eligible for retry.
2. Allow LocalDb.setSessionScores to commit its session summary/trace/completion marker
   and the staged split replacement in one SQLite transaction. Keep the existing
   default for callers without staged splits. Reuse the existing split row writer via
   one private DatabaseExecutor helper;do not duplicate the table format or calculations.
3. Preserve current row/window ownership guards. Only replace child rows when the owning
   session update succeeds. A refused insert rolls the whole transaction back,retaining
   the old session row and all old splits. A later ordinary read/sweep can then retry
   because it never falsely marked the new trace complete.
4. Retain all raw/decoded input,route points,unknown altitude/HR values,unrelated rows,
   profile/formula choices and stored formats. Clock evidence is never deleted to force
   a retry. No new schema field,background timer or durable job type is required.

Only the existing shared repository writer calls setSessionScores in production. Retain
its existing database-average assertions and all other callers' default behavior.

## Output and version decision requested

Proposed:algorithm103,protocol1.0.1,schema50 and app0.9.69+102 stay. The healthy-input
calculation and split bytes stay identical;this fixes commit/retry preservation after a
write refusal. No approved energy,HRV,Recovery,sleep or workout formula changes. This is a
separate explicit output/version decision under CLAUDE.md;do not implement before approval.

## Required verification

- Preserve both exact original refused-write negatives and both healthy controls.
- Refused first or later split insert preserves the complete old session/split state;
  retry after clearing the refusal matches the healthy result and then stays idempotent.
- Include absent/known altitude,existing and absent prior splits,no-route/no-split cases,
  a refused session write and a removed/moved owner. Preserve all inputs/unrelated rows.
- Keep current average-null protection and shared session/route/re-score regressions.
- Only bounded targeted local probes;full analysis/suite/source-role/hit/case retention and
  current-only LCOV run on Actions in the next consolidated candidate after privacy review.
- No new skip,exclusion,old assertion weakening or credit from failed/private/prototype LCOV.

Exact source/preimages,positive controls and negative logs remain in the registered
ignored recovery checkpoint. This review owns the proposed repair;bugs.md owns the open bug.

# Late history-end ownership:preservation review

**Status:** A synthetic real-queue reproduction confirms both profiles can advance an unbanked
trim token after a completed transfer. A minimal private prototype passes16 targeted
controls. Akshat approved the repair/version plan;the reviewed shared return is
implemented in the working branch. No phone data or physical radio was involved.

## Confirmed boundary

A real START/record/END commits one observation before its successful result. COMPLETE
correctly requests a follow-up round;the band's next empty START/COMPLETE finishes that
round. A later END with a different eight-byte token then reaches the existing
metadataWhileNotSyncing diagnostic,but execution continues into trim handling.

In six matched baseline cases (gen4 counts zero/one and gen5 count zero,both marker
orders),the stored trim cursor changes from the banked token to the
new token without any new observation being committed. This could let the band trim
bytes the phone never banked. No actual data loss or phone reproduction is claimed.
Gen4's advisory count policy is intentional;turning its count gate on is not the fix.
The original gen5 count-one control instead sends a safe FAILURE result. Its first
fixture incorrectly counted that as a successful trim;the exact log/source remain
private,and that fixture limit is explicit. Do not infer every result frame is an ACK.

## Approved implemented shared repair

In BleEngine._handleSyncMarker's HISTORY_END arm,return immediately after the existing
metadataWhileNotSyncing diagnostic when no history task is active. Keep the existing
pre-START/gen5 guard and all active-task validation,commit-before-ACK,retry,quarantine,
clock and ownership checks unchanged. Do not change HISTORY_COMPLETE handling.

This is one return in the existing shared guard. An inactive marker cannot commit a
new trim cursor,send a successful or failure result,create a misleading chunk ledger
row,or invoke the active-task recovery ladder. Existing observations/cursors/acked
ledger rows stay. Buffered records remain available for the existing later commit/replay path;the band
retains everything this marker did not trim. Actual historical-data input re-arms the
task in _enqueueOffloadFrame,so this guard must not suppress its valid bank-before-ACK
path. Do not fabricate an inactive-with-tail state by mutating that producer.

What becomes unavailable is processing a HISTORY_END as a trim request while there
is no active history task. This is the erroneous path being repaired. No screen,
metric,calculation,history reader,normal sync entry point or navigation action retires.
No UI layout,copy or route changes are proposed,so there is no changed page to preview.

## Approved output and version decision

Keep algorithm103,protocol1.0.1,schema50 and app0.9.69+102. This fixes task ownership and
data preservation;formulas,healthy active-task results,wire formats and stored formats
stay. The repository's CLAUDE.md requires this separate output/version review for
the approved production repair. Native/IPA stays held;physical acceptance remains separate.

## Verification and implementation plan

The detached local-only prototype passes eight completed-marker controls:both profiles,
announced counts zero/one and both END/COMPLETE orders. They retain the old trim cursor,
decoded/sample/archive rows,original successful ACK and original acked ledger row,
with no new inactive-token ledger entry. Four actual idle-watchdog/automatic-retry
controls also pass,including a late record and pre-START END followed by valid replay.
Four further post-completion-data controls pass:actual historical input re-arms
ownership,the next valid ACK follows its SQLite commit,and COMPLETE retains the data
without trimming a new token when it arrives first. The existing five-second request
floor and actual empty continuations remain. No private latch is assigned and no retired
mode is activated.

The matched baseline confirms six actual cursor failures. Two gen5 count-one cases
retain the cursor and send a safe failure result;they are controls,not data-loss failures.
All eight proposed inactive-END contracts pass in the private repair,alongside four
actual watchdog/retry controls. Keep that distinction when reporting the evidence.

Combined verification is complete;physical acceptance remains open:

- Keep every exact original source/log and all failed/prototype LCOV private.
- Retain the now-passing post-completion data controls and their actual re-arm boundary;
  active-task END,absent/unknown fields and old acked rows remain intact.
- Apply only the reviewed shared return,promote the synthetic regressions,run quick
  targeted checks/analysis and retain all old source roles,hits,cases and assertions.
- Privacy-review one parentless combined candidate for full Linux verification and
  current-only LCOV. No private ancestor,main rewrite,ref deletion or native dispatch.

Exact original negatives and private prototype proof live in the registered ignored
ownership checkpoint. coverage-audit.md owns accepted coverage;bugs.md owns acceptance.

The working checkout matches the private repair exactly. All16 targeted checks pass;
changed-test analysis is clean with one retained BLE constructor-style info. All2,384 old
BLE emitted roles map one-to-one;no old role retires. Strict143 verifies all28 combined controls,all719 old tests/cases/assertions and every old
source role/hit. Ten old misses execute;no counters/cases retire. coverage-audit.md owns proof.

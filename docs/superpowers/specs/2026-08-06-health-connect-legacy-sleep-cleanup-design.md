# Health Connect Legacy Sleep Cleanup Design

## Problem

The dedicated Android writer correctly inserts one `SleepSessionRecord` with
all normalized stages, but its replacement deletion is limited to the new
session's exact start and end times. A legacy one-stage record can begin before
that interval and overlap it. For example, a stale `23:34–02:55` fragment is
not removed when the recomputed session is `01:36–08:20`. Health Connect keeps
both records, and consumers such as Google Health can continue to select the
legacy fragmented night.

A Google account change does not remove these records because Health Connect
storage is local to the Android device.

## Chosen design

For Android sleep replacement, derive a local sleep-day cleanup interval that
runs from noon to noon and fully contains the new parent session. Delete
OpenStrap-owned `SleepSessionRecord` values in that interval, then insert the
single normalized parent session.

For a normal overnight session ending before local noon, the interval is local
noon on the preceding calendar day through local noon on the end date. If the
session ends at or after noon, the upper boundary moves to the following local
noon. If an unusually long session starts before the calculated lower boundary,
the lower boundary is extended to the session start so the parent itself is
always covered.

The boundaries are calculated with `ZoneId.systemDefault()` and local calendar
dates rather than adding a fixed 24 hours, so DST transitions remain correct.
Health Connect automatically restricts app-initiated deletion to records owned
by the calling package; sleep records written by other apps are not affected.

## Data flow

1. Dart normalizes and validates the parent session and stages as today.
2. The typed MethodChannel sends the same parent payload.
3. The Android writer calculates the local noon-to-noon cleanup interval.
4. It deletes OpenStrap-owned `SleepSessionRecord` values in that interval.
5. It inserts exactly one parent with all ordered, clipped, positive-duration,
   non-overlapping stages.
6. Any delete or insert exception, or an insert count other than one, returns
   `false` and preserves the existing retry/failure behavior.

Apple Health remains unchanged.

## Testing

Add a regression test for a recomputed `01:36–08:20` session with a stale
legacy record beginning at `23:34`. The test must first fail because the current
exact-session cleanup starts at `01:36`, then pass with cleanup boundaries that
include `23:34` while still containing the new parent.

Existing tests continue to verify one parent call, stage normalization,
midnight crossing, serialization, idempotent replacement, and false-result
propagation. Run formatting, focused health tests, `flutter analyze`, the full
test suite, and an Android release build before device installation.

## Scope

Only the Android typed sleep-session cleanup and its regression coverage change.
No database, analytics, BLE, Apple Health, Google Health, or unrelated export
behavior is modified.

# `isGen5` inventory — DATA vs BEHAVIOUR

Every band-specific branch in `lib/ble/ble_engine.dart`, classified — and, as
of the D4/D9 wave, **the DATA half is done**: it lives in `BandEntry` /
`BandWireCommands` in `lib/ble/adapters/_registry.dart` and the code around it
is unconditional.

Line numbers are against `ble_engine.dart` at **6,844 lines** (post-split).
Re-derive them before acting — this file rots, and the previous revision's
numbers had drifted by +21 to +23 while claiming 30 occurrences when there
were 44.

**DATA** — the branch chooses a *value*: an opcode, a payload, a delay, an
offset, a flag. It belongs in the registry entry; the code around it becomes
unconditional.

**BEHAVIOUR** — the branch chooses a *different sequence of operations*: an
extra handshake step, a different decoder, a different failure policy. It
belongs in an adapter — except there is no adapter to put it in: the
`run(BandLink)` move was DECLINED (ASSUMPTIONS G1–G4), so behaviour stays in
the engine, deliberately, and this file no longer pretends otherwise.

**Counts, re-derived: 24 `isGen5` reads left in the engine, from 44.**
Sixteen logical sites moved to the table; what is left is 9 BEHAVIOUR sites,
4 already-table-driven policy arguments, 3 log strings, and 1 site the previous
revision misclassified.

---

## MOVED — the table (16 sites)

Every value is transcribed verbatim from the arm it replaced and pinned in
`test/band_registry_test.dart` ("the gen4/gen5 arm of every branch that moved").

| Line | Site | Field it reads now | gen4 → gen5 |
|---|---|---|---|
| 2125 | pre-registration pause | `BandEntry.preRegistrationDelay` | `Duration.zero` → 600 ms |
| 2323 | post-registration pause | `BandEntry.postRegistrationDelay` | `Duration.zero` → 500 ms |
| 2436 | `_bootstrapSetClock` | `BandEntry.setClockDriftGated` | `false` → `true` |
| 2575 | keep-alive live re-arm | `BandWireCommands.r10R11Realtime` | `0x3F` → `null` |
| 3224 | `_offloadPayload` | `BandWireCommands.offloadBody` | `[0x00]` → `[]` |
| 3457 | console-log line | `BandEntry.logsConsoleOutput` | `false` → `true` |
| 4600 | `gateEnforced` | `BandEntry.burstCountGateEnforced` | `false` → `true` |
| 5853 | `getStrapName` | `getAdvertisingName` + `…Body` | Harvard/`[0x00]` → custom/`[rev1]` |
| 5867 | `setStrapName` | `setAdvertisingName` | Harvard → custom (body shared) |
| 5878 | `getHello` | `hello` + `helloBody` | Harvard/`[0x00]` → `0x91`/`[0x01]` |
| 5919 | `enableLiveStreams` R10/R11 | `r10R11Realtime` | send → omit |
| 5933 | `enableLiveStreams` optical | `opticalDataIsLiveToggle` | `true` → `false` |
| 5938 | `enableLiveStreams` log | `opticalDataIsLiveToggle` | string unchanged |
| 5971 | `enableHrOnlyLive` | `r10R11Realtime` | send → omit |
| 5989 | `disableLiveStreams` | `r10R11Realtime` | send → omit |
| — | the two delays themselves | `kGen5Pre/PostRegistrationDelay` | moved out of `BleEngine` into `_registry.dart`; one copy, not two |

**Two of these are the rows marked DO NOT UNIFY, and they still are.**
`setClockDriftGated` and `burstCountGateEnforced` are `false` on WHOOP 4 because
its unconditional SET_CLOCK is the proven flow and an enforced burst gate on a
band whose count semantics nothing has pinned is a permanent stall (15 failures
→ abort → Stuck). Moving a flag is not flipping it; both comments travelled with
the field and are repeated on the field's own doc.

## BEHAVIOUR — stays in the engine (9 sites, 11 reads)

| Line | Site | What actually differs |
|---|---|---|
| 2353 | `_readGen5Hello()` in `_bootstrapAfterRegistration` | An extra handshake round-trip with its own link-death abort, ordered before the clock read. |
| 2459 | `_readAdvertisingNameGen5` | A gen5-only setup command with its own "not a readiness gate" failure semantics. |
| 2486 | `_maybeStartBatteryPackFollowUp` | A gen5-only background task with its own retry schedule and once-per-session latch. |
| 3625–3664 | historical record dispatch | `decodeGen5HistoricalSample` vs the gen4 version-routed chain, and which kinds fall through to `raw_archive`. |
| 5124 | `enableGen5DeepBuffers` | A gen5-only multi-frame `SET_FF_VALUE` sequence behind the one audited `allowDangerous: true`. |
| 5150 | `sendInit` | Two INIT state machines in one method. Biggest single item — **and it writes host connection-priority state**: its `finally` clears `_connectSetup`, and a throw above that clear leaves the link pinned at setup priority for the whole connection with `_applyLinkPriority` early-returning forever. That is host state; it does not become data. |
| 5724 | `setAlarm` pre-arm | gen5 issues SET_CLOCK + a 120 ms settle before arming. A sequence, not a payload. |
| 5823 | `runAlarm` | Opcode swap **plus a computed body** — see below. |
| 5888 | `buzzPattern` | Opcode swap **plus a computed body** — see below. |

## NOT MOVED, and why — the honest boundary

**`runAlarm` (5823) and `buzzPattern` (5888) — DATA that a `const` table cannot
hold.** Both pick opcode *and* body. gen5's body is
`AlarmPayloads.gen5MaverickBuzz()`, a computed list; `kWhoopGen4`/`kWhoopGen5`
are `const`, so a field could only hold the twelve bytes transcribed into a
second place — which is exactly the duplication a named constant exists to
prevent. Moving the opcode alone would leave the body branch anyway, so both
stay whole.

**The four `AlarmPayloads` discriminators (5746, 5809, 5842, and `setAlarm`'s
own 5723) are already table-driven.** They are not branches in the engine; they
are one named ARGUMENT to a pure policy in `ble_state.dart` that already selects
by band. Widening `isGen5:` to take the entry moves no decision, and that file is
owned elsewhere. Left alone.

**Three reads are log text only** (5343/5354 `SET_CLOCK (gen5)`, 5754/5758 the
alarm log, and the live-stream log now keyed off `opticalDataIsLiveToggle`).
Changing them changes a user-visible log line with no wire meaning.

**`_maybeAugmentClockEpoch` (6196/6197/6213) is NOT a band branch — the previous
revision got this wrong.** It reads `op == Cmd.getClockGen5` on the *received*
response, not `session.band`, and edge sends `Cmd.getClock` (11) on both bands.
It mirrors protocol's own `control.dart:928` (`op == Cmd.getClockGen5 ? 3 : 2`).
Keying the offset off the session band would change behaviour for a `147` reply
on either link and would diverge from the parse it exists to patch. Left as is,
and it is the "1 offset" the old breakdown expected.

## What this wave actually cost

One new type (`BandWireCommands`, eight fields), five new `BandEntry` fields,
two constants relocated. No new mechanism, no capability booleans about our own
features, no command DSL: `r10R11Realtime` being `null` is an ABSENT COMMAND,
not a `supportsX()` claim, and it is the only field that decides whether
something happens rather than what gets sent.

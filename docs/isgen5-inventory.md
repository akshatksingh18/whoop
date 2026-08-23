# `isGen5` inventory — DATA vs BEHAVIOUR

Every band-specific branch in `lib/ble/ble_engine.dart`, classified. This is the
spec for the next wave (change-list D4/D9); **the split itself is not done here**.

Line numbers are against `ble_engine.dart` at the end of Phase 4 wave 1
(6,818 lines). Re-derive them before acting — this file rots.

**DATA** — the branch chooses a *value*: an opcode, a payload, a delay, an
offset, a flag. It belongs in the registry entry / `BandProfile`, and the code
around it becomes unconditional.

**BEHAVIOUR** — the branch chooses a *different sequence of operations*: an
extra handshake step, a different decoder, a different failure policy. It
belongs in the adapter (`run(BandLink)`).

**Counts: 30 sites — 21 DATA, 9 BEHAVIOUR.**

---

## DATA (21)

| Line | Site | The value that differs | Note |
|---|---|---|---|
| 2103 | `_bootstrapAfterRegistration` pre-registration pause | `kGen5PreRegistrationDelay`, gen4 = none | A per-band `Duration`, zero on gen4. The pause code is already shared. |
| 2299 | `_bootstrapAfterRegistration` post-registration pause | `kGen5PostRegistrationDelay` | Same shape as above. |
| 2411 | `_bootstrapSetClock` | whether SET_CLOCK is drift-gated or unconditional | Two-state policy flag. The gate (`BootstrapClockGate`) is already pure and shared; only "does this band use it" differs. **gen4's unconditional write is deliberate** — the comment says the gen5 evidence does not transfer. Carry the flag, do not unify the behaviour. |
| 2549–2557 | keep-alive live re-arm | which command re-arms live: IMU toggle vs `sendR10R11Realtime 0x01` | A per-band "live re-arm command set". |
| 3204 | `_offloadPayload` | `[0x00]` vs `[]` | Pure payload. Already centralised — the cleanest DATA site in the file. |
| 3436 | console-log line | whether this band's console output is logged | Debug-visibility only. NOTE the gate is not describing the wire: protocol's `decodeFrame` produces `console_log` for `PacketType.consoleLogs` on BOTH bands (`control.dart:1352`), so a gen4 strap emitting one is silently suppressed here. A per-band "log the console" bool, or just delete the gate. |
| 3643 | `kKnownRecordVersions` membership | the record versions this band's decoder claims | Per-band set, today a gen4-only global. See BEHAVIOUR/3603 — the two move together. |
| 4578 | `gateEnforced = session.band.isGen5` | whether `expectedPacketCount` is trustworthy enough to gate a burst | One bool. **Do not flip gen4's** — an enforced gate on gen4 stalls the drain permanently (comment at 4572). |
| 5321, 5332 | `setClock` | *nothing but the log string* | The body is byte-identical on both. This branch can be deleted outright and the label read from `BandEntry.label`. |
| 5724, 5732, 5736 | `setAlarm` payload + log | `AlarmPayloads.setPayloadForBand(isGen5:)` | Already delegated to a pure policy in `ble_state.dart`; the policy takes `isGen5:` and would take the entry (or a payload-shape field) instead. Sibling-owned file — coordinate. |
| 5787 | `getAlarm` payload | `AlarmPayloads.getPayloadForBand` | Same as above. |
| 5801 | `runAlarm` | opcode + payload (`runHapticPatternMaverick` vs `runAlarm`) | Opcode swap. The "do NOT stop haptics first" note is a comment, not a code difference. |
| 5820 | `disableAlarm` payload | `AlarmPayloads.disableForBand` | Same as 5724. |
| 5828 | `getStrapName` | opcode + payload | Opcode swap. |
| 5844 | `setStrapName` | opcode | Body identical on both — the comment says so. |
| 5853 | `getHello` | opcode + payload (`0x91`/`[0x01]` vs Harvard/`[0x00]`) | Opcode swap. |
| 5864 | `buzzPattern` | opcode + payload; gen5 ignores `pattern` | Opcode swap plus "this band has one fixed waveform" — a payload fact. |
| 5894, 5907, 5912 | `enableLiveStreams` | which toggles are in the ON set | A per-band command LIST, not a branch. **Carries a real footgun**: `enableOpticalData` is the SAVE-to-history toggle on gen5 (comment at 5900). The list is the safety boundary. |
| 5951 | `enableHrOnlyLive` | which toggles are in the OFF set | Same list shape. |
| 5967 | `disableLiveStreams` | which toggles are in the OFF set | Same list shape. Three sites, one per-band list. |
| 6170, 6187 | `_maybeAugmentClockEpoch` | GET_CLOCK opcode; body offset `3` vs `2` | Offset + opcode. Exactly the D3 shape already moved into `BandEntry` for the historical-record offsets. |

## BEHAVIOUR (9)

| Line | Site | What actually differs |
|---|---|---|
| 2328 | `_readGen5Hello()` inside `_bootstrapAfterRegistration` | An extra handshake round-trip with its own link-death abort, ordered before the clock read. gen4 has no equivalent step. |
| 2434 | `_readAdvertisingNameGen5` | A gen5-only setup command with its own "not a readiness gate" failure semantics. |
| 2461 | `_maybeStartBatteryPackFollowUp` | A gen5-only background task with its own retry schedule and once-per-session latch. |
| 3604–3643 | historical record dispatch | `decodeGen5HistoricalSample` vs the gen4 version-routed chain, and which record kinds fall through to `raw_archive`. The core adapter responsibility. |
| 5102 | `enableGen5DeepBuffers` | A gen5-only multi-frame `SET_FF_VALUE` sequence behind the **one audited `allowDangerous: true`**. Whatever holds it must keep the dangerous-opcode block's carve-out explicit and single. |
| 5128–5181 | `sendInit` | The whole handshake: gen5 = CLIENT_HELLO already done + `GET_DATA_RANGE` + `SEND_HISTORICAL_DATA`; gen4 = the 5-packet INIT loop. Two different state machines sharing one method. **Biggest single item.** |
| 5701 | `setAlarm` pre-arm | gen5 issues a SET_CLOCK + 120 ms settle before arming; gen4 does not. A sequence, not a payload. |
| 5146–5161 | gen5 deep-buffer ordering inside `sendInit` | Config flags must land *before* the offload trigger. An ordering constraint that only exists on one band. |
| 6396 | `DrainController.onArchiveHistorical` reads `inner[1]` | Left as-is deliberately: per MULTIBAND_PLAN §3.1 `DrainController` stays in `ble_engine` as the **gen4 adapter's private collaborator**. Its WHOOP assumptions are correct where they are; it should be named honestly, not made band-generic. |

---

## What this inventory says about the next wave

1. **21 of 30 are opcode/payload/offset/delay values.** Most of the `isGen5`
   surface is not behaviour at all — it is a table. A `BandEntry` that carries
   an opcode map, three command lists (live-on / live-off / re-arm), two
   durations and three bools erases two thirds of the branches without an
   adapter existing.
2. **Three of the nine BEHAVIOUR sites are one thing**: the gen5 setup
   sequence (2328, 2434, 2461). They are ordered steps of one handshake that
   gen4 does not have.
3. **The alarm payload sites already have the right shape** — a pure policy in
   `ble_state.dart` taking a band discriminator. Widening `isGen5:` to the
   entry is mechanical; that file is owned elsewhere, so it needs coordinating,
   not redesigning.
4. **Two branches must NOT be unified** even though they look like duplication:
   the gen4 unconditional SET_CLOCK (2411) and the gen4 advisory-only burst
   count gate (4578). Both comments record a failure that flipping them caused.

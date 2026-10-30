# Historical R10 beat-count repair

**Status:** Akshat approved the exact count repair, protocol 1.0.1 and algorithm 100 plan.
Implementation and targeted checks pass; combined verification remains open. Schema 50, scientific
coefficients, app metadata and native/phone gates remain unchanged. Independent coverage continues.

Some revision-10 packets can carry five to eight beat intervals. The existing realtime
decoder accepts up to eight, but historical sync's `_r10Rr` rejects the entire beat block
above four. The retained authored reproduction supplies eight intervals (800–807 ms):
`realtimeRr` returns all eight, while the historical engine supplies an empty RR list.
This is a synthetic byte-contract reproduction, not a claim about Akshat's phone recordings.

The approved implemented decoder edit is in `packages/protocol/lib/src/control.dart`:

```diff
- if (declared == 0 || declared > kMaxRrPerRecord) return const [];
+ if (declared == 0 || declared > kMaxRrPerR10) return const [];
```

Reuse the existing R10 constant (eight). Keep the four-slot ceiling for revisions 12/24
and compact `0x28` frames, the current signed interval reads, 200–2500 ms value gate,
declared-count bound and complete-slot length checks. Keep timestamps, counters and
unknown accelerometer channels unchanged. No motion or calorie estimate is introduced.
The shared helper also feeds the existing `decodeFrame` live DTO's `rr_ms` field; that caller
now receives the same accepted eight-slot list. A dedicated parity control covers this
caller as well as historical parsing and the separate realtime decoder.

| Authored R10 declared count | Previous historical beat output | Approved historical beat output |
| --- | --- | --- |
| 0 | Empty | Empty |
| 1–4, all valid complete slots | Declared valid intervals | Same intervals |
| 5–8, all valid complete slots | Empty | Declared valid intervals, matching realtime |
| More than 8 | Empty | Empty |
| 5–8 with a truncated last slot | Empty | Only complete, plausible slots, as the existing realtime decoder does |
| Out-of-range signed interval | Omitted | Still omitted |

The approved storage consequence is explicit: R10 has no mapped accelerometer payload,
so it is intentionally excluded from `decoded_onehz`. When accepted intervals exist, the
existing store writes them to `decoded_rr`. Historical sync still treats the current
header/heart-rate sample as decoded when the beat list is empty, so the original R10 bytes
do not enter the unknown-frame archive merely because this count guard discarded beats.
The normal durable commit/trim path can therefore finish without those intervals. Changing
the count guard prevents this omission for newly decoded qualifying packets. It cannot
reconstruct intervals already trimmed from the band when no original bytes remain locally.
Do not promise recovery from the compact sample row or pruned data.

Approved version treatment:

- Increase protocol package `1.0.0` to `1.0.1`, keeping the path dependency and lock together.
- Increase app `kAlgoVersion` from 99 to **100**, with the output-change entry beside that
  constant and a reviewed protocol digest/description in `packages/algorithm-contract.json`.
  The analytics package source/digest and scientific coefficients stay unchanged.
- Keep database schema 50 and persisted names. This is no database-structure migration.
- Preserve prior version evidence, archives and recovery exports. The existing derivation
  version rules still apply; a version bump is not proof that missing old beats were recovered.
  Do not add a blanket archive replay, force full-history rebuild or fabricate intervals.
- Leave app metadata `0.9.69+102` during source/coverage work. A future native release needs
  its own unused build number, complete backup/restore, payload and phone gates. Native/IPA
  builds remain held until coverage completion; main replacement remains B5 STOP.

More valid beat input can change later HRV/readiness when the existing night-quality gates
are met. Accepting the same valid eight-slot format in both paths is an input repair; it
does not approve new HRV, recovery, calorie or treadmill formulas. No UI layout change is
proposed. Any separately proposed UI change still needs complete-page preview review.

Before declaring this fixed, check authored counts 0/1/4/5/8/9, value boundaries and truncated
slots against realtime; retain revision-12/24/compact four-slot controls; run the unchanged
original negative; verify eight intervals reach real SQLite through engine ingestion before
the exact trim ACK; check refused commit/cursor/ACK retry, device-scoped deduplication and
reopen. Run full app/package analysis/tests on Linux Actions after the privacy gate. Numerical
outputs retain their existing minimum-input/uncertainty gates; synthetic checks do not certify
radio delivery or historical phone measurements.

The original source/log remain local as `cov47-r10-eight-beat-reproducer_test.dart` and
`cov47-r10-eight-repro-targeted.log`. `bugs.md` owns the open defect. Akshat approved this
exact count contract and protocol 1.0.1/algorithm 100 treatment.

Twenty-six authored codec controls pass across every count 0–8, invalid counts, signed value
boundaries, truncated slots, shared live DTO parity and retained four-slot formats. Ten new
engine/SQLite controls pass: six count cases check durable beat/token state inside the exact
ACK callback and after reopen; refused RR/cursor commits roll back without ACK and retry;
failed ACK delivery retains beats for deduplicated replay; a restored foreign-device row
survives primary replay. Two retained decoder controls and two independent public reanalysis
recovery controls also pass in the corrected 14-check app cohort. The unchanged original
eight-beat reproduction now passes its named case. Targeted analysis is clean.
The original ACK-case fixture waited for an abort-failure log although abort succeeded;
its source/log remain local. The corrected test observes actual durable `ack_failed` state
and completed offload, retaining all beat, token and retry assertions. No production timeout,
new skip or weakened durability assertion was needed. Combined proof and physical acceptance
remain separate gates.

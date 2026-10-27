# Public fixture boundary

**Status:** Akshat approved all nine listed substitutions; they and copied call sites are
implemented and pass targeted checks. Original evidence is hash-preserved locally. Current
outgoing-history review and full Linux run 40585719502 pass for parentless `7ad4687f`, including
app analysis/tests, both packages and synthetic pages. Main is unchanged;
IPA/native builds remain held until coverage completes.

## Prepared and verified

The 2,934-case protocol oracle and 550-case header oracle have verified exact local copies in
ignored `build/ownership-checkpoint/private-protocol-corpus/`, with a SHA-256 manifest. The
original test files remain in the private reference archive and Git bundles. Optional local
replay uses `WHOOP_PROTOCOL_CAPTURE_DIR`, falling back to that ignored directory; no download
or upload occurs. Their former public paths are ignored to prevent accidental re-addition.

`tool/generate_protocol_fixture.py` constructs 31 deterministic synthetic cases without
reading any capture or calling production decoders. Authored expected values cover historical
versions/headers, absent unsupported fields, live HR, RR bounds, motion absence versus zero and
IMU axes. `--check` reproduces every public fixture byte. This tests byte contracts, not hardware
validity or calibration. Three targeted protocol files pass 21 tests with the private corpus;
the public configuration passes 7 tests and explicitly skips 14 capture-dependent controls.
The candidate's full protocol suite passes 409 checks with 14 explicit private-corpus skips;
analytics passes 643 with six explicit skips. No native build is claimed.

## Implemented approved scope

The following source now uses authored inputs. Exact originals remain local and are never
published anew. The change affects public
test evidence, not app feature availability, metrics, schema or protocol implementation.

| File / section | What public CI would stop replaying | Proposed public replacement |
|---|---|---|
| `packages/protocol/test/reassembly_stress_test.dart` | Captured HELLO/name replies with an identifiable band serial and owner name | Independently constructed CRC-valid replies with fictional identity, retaining adversarial chunking and repeated-response assertions |
| `packages/protocol/test/v25_test.dart` | Three actual waveform bursts | Authored waveform bytes/timestamps proving routing, timestamp order, no invented HR/accel and exact raw-tail retention |
| `packages/protocol/test/gen5_historical_test.dart` | Actual v18/v26 sensor records and their empirical cross-checks | Independently packed semantic fields with hand-authored expectations; keep original empirical replay local |
| `packages/protocol/test/gen5_record_fields_test.dart` | Same captured v18/v26 records and measured field values | Independent flags/subsecond/optical/length boundary fixtures; retain exact original evidence locally |
| `packages/protocol/test/gen5_v22_test.dart` | Captured tag 1/2/3/5/6 records, even though their timestamps were already changed | Authored tag/poison-pattern examples; private originals retain observed tag/state relationships |
| `packages/protocol/test/gen5_test.dart`, live IMU section | Captured live record-21 sensor buffer | Authored independent arrays/header fixture with axis/order/scaling checks; retain other synthetic/control tests |
| `packages/protocol/test/oura_test.dart` | Real ring diagnostic bodies and capture-derived assertions | Authored byte-contract/absence cases; retain original ring evidence locally; no personal-app Oura feature is added or removed |
| `packages/protocol/test/oura_confirmation_test.dart`, captured batch-summary case | Captured ring batch response | Independently authored reply with the same field-boundary coverage, fictional counts; keep other synthetic cases |
| `packages/protocol/test/decode_guards_test.dart`, captured HELLO cases | Actual device response metadata | Fictional identity/battery/version fields with independent expected offsets and unchanged malformed-input checks |

All nine substitutions are approved and implemented; retain their separate verification boundaries. Capture-derived empirical claims must remain labelled as
private evidence and cannot be presented as newly proved by synthetic inputs. The original
local suites remain recoverable/runnable; report public skips and coverage changes explicitly.
The wider review also replaced copies in app mapping/persistence/archive/refusal tests, every
caller of the same identifiable HELLO example, a recorded nightly series, a recorded readiness
baseline and captured battery events. These are authored boundary cases, not anonymized exports.
Detailed private measurement commentary and the old version-by-version source commentary were
preserved in the archive before removal from the outgoing tree. No physiological output,
coefficient, algorithm version or schema changed in the fixture substitution. At candidate
`998d77af`, comment-stripped production source is identical apart from a fictional gallery label.
Later COV-40 makes separate storage-preservation corrections documented in `coverage-audit.md`;
do not extend the earlier equivalence claim to those executable changes.

Verification includes 227 checks across the ten primary protocol files (overlapping reruns are
not added twice), 30 app mapping/persistence checks, 28 app identity/refusal checks, 25 nightly/
battery checks and 26 analytics checks/one existing skip. Three preserved original suites also
pass 112 checks locally. Public/private results are separate; no full suite ran on this laptop.
The generator now owns 31 map-contract cases plus 26 named packet fixtures, independently
reproducible without any capture or production decoder. Exact original-file hashes and full
local logs remain under ignored `build/ownership-checkpoint/`.

The source review checks full contents, exact old-capture literals, names/serials, physical
profiles, secrets/contact patterns, binary images and the final outgoing ancestry. A scanner
is supporting evidence, not the sole privacy decision. Do not regenerate expectations using
the decoder under test; native/hardware/reference validation remains open.

## Publication remains separate

The current cleanup branch contains private preservation ancestors and must never be pushed.
The preceding reviewed tree is parentless `aaa7c5ce` on `ownership-ci-candidate-8`, with public
commit identity and no preservation ancestors: 830 tracked files, 13,817,233 bytes, 29 unchanged
reviewed binaries and no blocked findings. Manual review covered eleven changed text files
against candidate 7: fifteen authored host/live controls, the logger comment and owning docs.
Executable production source matches candidate 7; no metrics or runtime identities changed.
Captures, local probes/rasters and archives remain excluded. Combined Linux run
[40487773326](https://github.com/akshatksingh18/whoop/actions/runs/40487773326) passes. All existing remote heads/tags
were verified unchanged; only candidate 8 was added. Candidate 8 fully verifies the enabled Food regression and all 24 COV-43 controls;
candidate 10 below is the current fully verified checkpoint.
Candidate 6's full Linux run [40466294191](https://github.com/akshatksingh18/whoop/actions/runs/40466294191)
passes app/package/analysis and synthetic-page jobs (708 captures), including all nineteen
COV-42 controls. New COV-43 tests use authored 2021 dates, counts and sine waves with real
SQLite refusals; Food cases reuse authored entries. These pass full run 40483497760. No recording or personal measurements are
needed. Actual full-page review rasters remain local. Review all changed content and fresh
ancestry of the next candidate before push; these repairs are not covered by an earlier
production-equivalence claim. Earlier candidate refs remain until their exact B5 decisions.

The verified host/live controls use authored SQLite entries, retained motion arrays and an invented
equatorial route, with no captured GPS or sensor input. Their outgoing source/ancestry review
passes for candidate 8; combined verification passes; local failed harness probes remain private evidence.
Native/IPA builds remain held while coverage completes. Main replacement and every remote
branch/tag deletion remain at B5 STOP with their own exact-ref approval.

COV-44 adds authored coverage-only matrices and isolated SQLite/GATT/share/keychain controls.
Candidate 9 `c640c84e`, tree `9ec667747d581824959f83fe0df2203e56040c5f`, passed a fresh full-tree
and changed-text review: 851 files, 13,959,395 bytes, 29 unchanged reviewed binaries, 203 matching
normalized production hashes and no blocked findings. All 29 changed text files (21 new test/
helper files and eight owning technical documents) were reviewed; no original capture is an
input. Its one root commit uses the public noreply identity and has no preservation ancestors.
Only `ownership-ci-candidate-9` was added; all 24 earlier remote heads/tags are unchanged.
Full Linux run [40529212076](https://github.com/akshatksingh18/whoop/actions/runs/40529212076) passes
4,497 app checks, both packages, analysis and 708 synthetic captures. The inventory verifies
1,450 new handwritten line hits, no losses and no denominator change; candidate 9 is the
verified baseline for candidate 10 below. At that checkpoint, three explicit skipped regressions
retained two existing UI defects; COV-46 enables them after the authorized scoped repairs.
Local failed harness logs, captures, recovery caches and all private branch/archive refs stay local. Review any later tree afresh.

COV-45's verified candidate uses authored 2021 step windows, fictional band identifiers/names and
profile values, scripted transport/preference failures and isolated SQLite triggers. No private
capture is an input. Its source repair only checks background connection ownership; it changes
no calculation or persistent identity. Candidate 10 `7ad4687f`, tree
`9e629c7ce8d900d6045041454fa1f55772dba9b2`, passed full outgoing-tree and ancestry review:
853 files, 13,991,293 bytes, twelve changed text files, 29 unchanged reviewed binaries and no
blocked findings. All seven compatibility/licence exception files are byte-identical to
candidate 9. The single root commit uses the public noreply identity; only candidate 10 was
added and all 25 earlier remote refs remain unchanged. Linux run [40585719502](https://github.com/akshatksingh18/whoop/actions/runs/40585719502) passes all jobs: 4,549 app
checks, both packages, analysis and 708 synthetic captures. All 52 new controls pass; the local
three-file batch has 112 passing checks. The matching inventory has 44,285/50,371 lines executed
(87.92%), with 94 matching lines gaining execution, no lost hits and 17 new/modified repair
lines executed. AppState alone changes: denominator +14, net executed +111. The private
preservation branch, captures,
archives, probe logs and local tooling remain local. No native build or main replacement.

COV-46 adds authored sine-wave step snapshots, isolated SQLite/preference refusals and reset
races, synthetic keychain/dialog controls, and fictional notification rollups dated relative to
the test clock. Its three production repairs preserve calculations, metadata and active names.
Full-page Before/After evidence stays local. Candidate 11 is prepared for a fresh full outgoing-tree and parentless
ancestry review; no privacy or combined-CI success is inferred from the
previous candidate. No captures, private records, tooling, probe logs or archive ancestors may
be sent. Native/IPA and B5 gates remain.

# Public fixture boundary

**Status:** Akshat approved all nine listed substitutions; they and copied call sites are
implemented and pass targeted checks. Original evidence is hash-preserved locally. Current
outgoing-history review and full Linux run 40455040866 pass for parentless `22c733dd`, including
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
The latest reviewed tree is parentless `22c733dd` on `ownership-ci-candidate-4`, with public
commit identity and no private preservation ancestors. Full Linux run
[40455040866](https://github.com/akshatksingh18/whoop/actions/runs/40455040866) passes all app,
package, analysis and synthetic-page jobs (708 captures). Review every subsequent candidate
tree and ancestry before push. Earlier candidate refs remain until their exact B5 decisions.
Native/IPA builds remain held while coverage completes. Main replacement and every remote
branch/tag deletion remain at B5 STOP with their own exact-ref approval.

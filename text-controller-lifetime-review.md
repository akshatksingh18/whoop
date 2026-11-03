# Journal weight and meal sub-heading closure review

**Status:** Akshat approved both lifetime repairs. They are implemented with12 passing
production regressions and23 actual captures matching the reviewed proposal. Full85/41534829703 verifies the repair; independent coverage continues. No calculation, version, schema, stored
identifier or layout change is proposed.

The existing Journal weight dialog and Food meal sub-heading sheet dispose their text
controllers as soon as the navigation result completes. Flutter still uses the fields during
the closing animation. Actual Cancel/Save gestures reproduce a disposed-controller exception.
Original inputs and failure logs remain in the private checkpoint; no failing public case was
skipped or counted as a passing regression.

[Complete Before/Proposed pages and return states](build/ownership-checkpoint/cov54-controller-review/review.html)
contain36 authored PNGs at1x,2x and3.1x text. All13 corresponding open/page pairs are byte
identical. The manifest records every image hash and dimensions, complete scroll captures
and the two existing Journal3.1x layout failures. These diagnostic captures do **not** certify
that layout passes: the parent Journal page overflows by123px in both versions. That existing
layout problem and the historical entry dialog's "Weight today" wording remain separate.
Neither is silently fixed or represented as fixed by this proposal.

The approved repair follows the app's existing state-owned controller pattern. A small shared
widget owns the controller until its dialog/sheet subtree unmounts. The original showDialog
and bottom-sheet helpers, keyboard, fields, units, messages, styling and navigation remain.
There is no extra delay, second save or change to the returned values.

| Scope | Proposed result | Preserved behavior |
|---|---|---|
| Journal weight | Closing Save, Cancel or Clear no longer leaves an animated field with a disposed controller | Cancel retains stored/draft values; Clear is a deliberate pending deletion; editor Save remains required. Metric/imperial conversion, viewed historical date, notes, tags, explicit zero/time provenance and trend remain. |
| Saved-meal sub-heading | Choosing an existing/new/empty heading releases the controller only after the sheet unmounts | A new name is trimmed and must be nonblank; existing headings, No sub-heading, Back and meal items/units/history remain. |

Twelve private functional checks pass on the prototype: the six actual closure negatives
plus six retained trend/editor controls. The original prototype result remains separate from the later production checks. The same assertions now pass on the production repair: eight Journal and four Food
checks, including all six original closure failures. AST comparison proves every other token
unchanged in both source files and exact reviewed-helper/form equivalence. Full85/41534829703 verifies the repair and unchanged retained assertions. Retain original failures and full pages. Phone/keyboard/
VoiceOver acceptance, native/IPA hold and B5 remain separate.

Evidence: private `cov54-controller-private-proof-targeted.log`, lifetime-only prototypes,
`cov54-controller-review/complete-manifest.json` and its diagnostic exception record. The
additional scrollable-dialog experiment is not the proposed repair and is not production.

Implementation evidence: private cov54-controller-actual-targeted.log, cov54-approved-controller-ast-proof.json and cov54-controller-review/actual-manifest.json. All23 actual images match their reviewed proposed files byte for byte. The one recorded123px Journal3.1x overflow is unchanged; diagnostic captures are not layout acceptance.

The original overflow/title observations above describe the retained Before/lifetime-only
review. Akshat subsequently approved the separate journal-layout-review.md proposal; those
two UI repairs are now implemented with six regressions and30 matching phone captures.
Full83 passes all47 new controls but fails two owner-export/gallery-classification assertions;
those integration omissions are corrected locally. Keep the original failed run and previews;
fully green85 verifies the final repair and both unchanged integration assertions.

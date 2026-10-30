# Band-name guidance and error layout

**Status:** Akshat approved B. The dialog change, ten new checks, six retained validation/
lifetime checks and eight actual forms/four complete hosts pass locally. All twenty-two
actual frames match approved B. Combined Linux and native/phone acceptance remain open.

## Problem and choices

The name field truncates its character guidance and invalid-name error with an ellipsis.
The authored Before cases reproduce this at ordinary text as well as 2x/3.1x. A user can
therefore miss part of the allowed character list while trying to correct a name.

- **A:** allow all guidance/error text to wrap within the existing dialog width. Make the
  title/field area scroll when needed; keep Cancel and Save available.
- **B — approved:** the same complete wrapping/scroll support, with a wider dialog above
  the app's existing 1.3x large-text threshold. This gives enlarged copy more space; ordinary
  width stays the same as A.
- **Keep current:** retain the existing ellipsis and leave this accessibility defect open.

Both preserve the exact messages, colours, type sizes, 20-character counter, ASCII name
validation, draft, Cancel/Save, rename result and failure handling. No feature becomes
unreachable. The existing form-owned controller and dialog-lifetime repair stay intact.
The accepted change is limited to this name dialog; no actual band name, persisted key,
Bluetooth identity, calculation, schema, metadata or firmware behavior changes.

## Complete pages and forms

Each numbered link is a complete viewport. Read each sequence in order; its overlapping
views reach the bottom. The shared host pages retain the full device context, including
uncertainty/support labels and all actions. The dialog views show the complete form.
The keyboard case simulates a 300px inset; it does not paint or certify a native keyboard.

| Host width / text / keyboard inset | Complete unchanged device page |
|---|---|
| 390 / 1.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/host_390_1.0x_k0_0.png) [2](build/ownership-checkpoint/name-copy-preview/host_390_1.0x_k0_1.png) |
| 320 / 2.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/host_320_2.0x_k0_0.png) [2](build/ownership-checkpoint/name-copy-preview/host_320_2.0x_k0_1.png) [3](build/ownership-checkpoint/name-copy-preview/host_320_2.0x_k0_2.png) [4](build/ownership-checkpoint/name-copy-preview/host_320_2.0x_k0_3.png) |
| 430 / 3.1x / 0px | [1](build/ownership-checkpoint/name-copy-preview/host_430_3.1x_k0_0.png) [2](build/ownership-checkpoint/name-copy-preview/host_430_3.1x_k0_1.png) [3](build/ownership-checkpoint/name-copy-preview/host_430_3.1x_k0_2.png) [4](build/ownership-checkpoint/name-copy-preview/host_430_3.1x_k0_3.png) [5](build/ownership-checkpoint/name-copy-preview/host_430_3.1x_k0_4.png) |
| 390 / 2.0x / 300px | [1](build/ownership-checkpoint/name-copy-preview/host_390_2.0x_k300_0.png) [2](build/ownership-checkpoint/name-copy-preview/host_390_2.0x_k300_1.png) [3](build/ownership-checkpoint/name-copy-preview/host_390_2.0x_k300_2.png) |

| Form / width / text / keyboard inset | Before | A | B |
|---|---|---|---|
| helper / 390 / 1.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_helper_390_1.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_helper_390_1.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_helper_390_1.0x_k0_0.png) |
| error / 390 / 1.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_error_390_1.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_error_390_1.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_error_390_1.0x_k0_0.png) |
| helper / 320 / 2.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_helper_320_2.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_helper_320_2.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_helper_320_2.0x_k0_0.png) |
| error / 320 / 2.0x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_error_320_2.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_error_320_2.0x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_error_320_2.0x_k0_0.png) |
| helper / 430 / 3.1x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_helper_430_3.1x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_helper_430_3.1x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_helper_430_3.1x_k0_0.png) |
| error / 430 / 3.1x / 0px | [1](build/ownership-checkpoint/name-copy-preview/before_error_430_3.1x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_error_430_3.1x_k0_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_error_430_3.1x_k0_0.png) |
| helper / 390 / 2.0x / 300px | [1](build/ownership-checkpoint/name-copy-preview/before_helper_390_2.0x_k300_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_helper_390_2.0x_k300_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_helper_390_2.0x_k300_0.png) |
| error / 390 / 2.0x / 300px | [1](build/ownership-checkpoint/name-copy-preview/before_error_390_2.0x_k300_0.png) | [1](build/ownership-checkpoint/name-copy-preview/a_error_390_2.0x_k300_0.png) | [1](build/ownership-checkpoint/name-copy-preview/b_error_390_2.0x_k300_0.png) |

## Evidence and implementation gate

Twenty-six bounded cases pass, producing forty frames: four complete device hosts, all
twenty-four Before/A/B form states and two unchanged-prototype controls. The two baseline
prototype frames match the real production dialog pixel for pixel at 1x and 3.1x. Every
proposal's rendered guidance/error fits without ellipsis; complete scroll checks retain
all content and both actions. Invalid-name Save never reaches the mock rename command.
No proposed validation or callback change is being accepted through these static previews.

The prototype copies the current dialog source with only wrapping, scrollability and B's
large-text inset substituted. It uses the displayed current name, matching the real dialog.
The initial draft missed the SetRow import; the next harness wrongly required a scrollable
inside the old non-scrolling dialog. An early source-label mismatch used the fixture's
constructor name rather than the displayed name. All originals, failed logs and raster sets
are retained privately. The corrected controls pass; none is claimed as an app bug.

Exact hashes and comparisons are in `name-copy-preview/verified-manifest.json`; the private
source/log is `cov48_name_copy_preview_test.dart` / `cov48-name-copy-preview-d-targeted.log`.
One visual inspection and one confirmation are complete. These are authored Flutter test
pages with a test banner and substitute fonts, not a phone connection or native acceptance.

## Implemented B and remaining gates

The actual dialog now wraps guidance/errors through the existing field decoration, keeps
the title/field area scrollable and allows more width beyond 1.3x. Text can still size itself
intrinsically; it need not fill every available pixel immediately at 1.31x. Messages, styles,
the twenty-character ASCII rule, form-owned controller and mounted messenger checks stay.

Two actual 3.1x guidance/error regressions fail before repair and their readability assertions
pass unchanged afterward. Ten new checks cover ordinary/narrow/3.1x/keyboard-inset layouts,
invalid and empty input, trimmed corrected saves, cancellation/reopening, responsive width
and command-refusal retry. Six retained checks also pass: original save/refusal validation,
cancel/barrier reset, retry without stale error, and both deferred completions after host
disposal. Both new-test and changed-file analysis have zero errors/warnings; only two existing
production infos remain. Initial helper-declaration, intrinsic-width and queued-Snackbar test
assumptions are preserved as fixture corrections; no production behavior was changed for them.

All eight actual form states and four complete hosts match every one of the twenty-two
accepted B frames. Exact hashes/links are in `name-copy-implemented/verified-manifest.json`;
source, original negatives, targeted logs and the scoped LCOV comparison are in
`cov48-name-guidance-followthrough-review.json`. No previously missed candidate-48 line gains
are claimed: this repair strengthens an already executed UI path. Combined Linux verification
is still required. Native/IPA, phone, persisted-name migration N and exact-ref B5 gates remain.

# Body milestone date layout

**Status:** Akshat approved A. The shared reflow, nine regression checks and four actual
complete-page captures pass locally. All four actual pages match approved A pixel for pixel.
Full Linux [41048093355](https://github.com/akshatksingh18/whoop/actions/runs/41048093355)
passes on parentless `a32c446f`/candidate 49; native/phone acceptance remains open.
The earlier Body average A is retained.

## Problem and choices

Each milestone reserves a fixed 64px date column. At enlarged text, dates such as Oct 30
wrap inside the month word. The date, measurement and explanatory history remain present,
but the broken words are difficult to read. Ordinary text currently fits.

- **A — approved:** keep the ordinary row. Above the existing 1.3x large-text threshold,
  place the complete date above its measurement and explanation, using the same type sizes.
- **B:** stack date, measurement and explanation at every text size.
- **Keep current:** leave the existing composition and its enlarged-text defect open.

Both proposals preserve every date string, title, measurement, explanation, semantic label,
summary, chart, reading, photo area and navigation action. Neither changes calculations,
selected-range means, saved data, colours or type sizes. No feature becomes unreachable.
The proposed implementation changes only the shared Body milestone-row composition.

## Complete pages

Each link opens the whole page, including its header, chart, history, photos and milestones.
All values are authored fixtures. Files stay in local-only recovery; no real captures are used.

| Range / width / text | Before | A | B |
|---|---|---|---|
| All / 390 / 1x | [Before](build/ownership-checkpoint/body-milestone-preview/all_before_390_1.0x.png) | [A](build/ownership-checkpoint/body-milestone-preview/all_a_390_1.0x.png) | [B](build/ownership-checkpoint/body-milestone-preview/all_b_390_1.0x.png) |
| All / 320 / 2x | [Before](build/ownership-checkpoint/body-milestone-preview/all_before_320_2.0x.png) | [A](build/ownership-checkpoint/body-milestone-preview/all_a_320_2.0x.png) | [B](build/ownership-checkpoint/body-milestone-preview/all_b_320_2.0x.png) |
| All / 430 / 3.1x | [Before](build/ownership-checkpoint/body-milestone-preview/all_before_430_3.1x.png) | [A](build/ownership-checkpoint/body-milestone-preview/all_a_430_3.1x.png) | [B](build/ownership-checkpoint/body-milestone-preview/all_b_430_3.1x.png) |
| Since start / 390 / 1x | [Before](build/ownership-checkpoint/body-milestone-preview/sinceStart_before_390_1.0x.png) | [A](build/ownership-checkpoint/body-milestone-preview/sinceStart_a_390_1.0x.png) | [B](build/ownership-checkpoint/body-milestone-preview/sinceStart_b_390_1.0x.png) |

## Evidence and gate

Twelve bounded static preview cases pass. They mount the actual approved Body average A
page and substitute only milestone-row layout, retaining the original widget instances for
the date/title/explanation and original semantics. Complete scroll-extent checks retain all
sections and main actions. Proposed enlarged dates each fit on one line without shrinking.

All four Before pages are pixel-identical to the retained actual Body A pages. A is also
pixel-identical to Before at ordinary text, for both All and Since start. At enlarged sizes,
its pixel differences begin inside the milestone section. All twelve image hashes and
comparison bounds are in `body-milestone-preview/verified-manifest.json`; the private probe
source and log are retained beside it. One visual inspection and one confirmation are done.

These previews use Manrope in place of native SF. They do not certify an iPhone build,
VoiceOver, native safe areas, gestures or execution of callbacks after implementation.
The shared Body row now uses the approved reflow. Nine focused checks cover All/Since start,
ordinary/enlarged widths, the 1.3x boundary and 1.31x activation. Real paragraph bounds keep
complete enlarged dates on one line, above their unchanged measurement/explanation. All
original semantic labels, navigation actions and stored evidence remain. The two original
3.1x failures show a date split across three boxes; the same date assertions now pass. The
first test draft lacked an import; a later action check needed to scroll back to Body settings.
Those fixture failures and exact sources remain preserved, without weakened assertions.

Four actual production pages, without widget substitution, match accepted A. Their hashes
are in `body-milestone-implemented/verified-manifest.json`; complete source/log/local-delta
proof is in `cov48-milestone-food-followthrough-review.json`. Both new test files have clean
analysis; the changed production part retains two existing infos. Combined Linux verification
passes candidate 49; all 730 baseline gallery names remain, with a separately reviewed
extra trailing Body viewport that preserves the complete milestones and actions. Keep native/IPA, migration N/phone and exact-ref B5 gates intact.

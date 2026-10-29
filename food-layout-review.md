# Food day-page layout review

**Status:** Akshat approved A. The shared production fix and enabled 3.1x regression pass
targeted checks and full Linux run 40483497760. Native/phone acceptance remains open. This approval does not cover
the separate Log food default-meal fix, calorie changes, native builds or GitHub replacement.

## Choice

Approved **A: stack meal totals at large text**, using the existing shared `bigText` threshold
(above 1.3x). Keep today's compact meal heading at ordinary text. **B: stack meal totals at all
text sizes** makes the same information consistently vertical, with more space at ordinary text.
Both choices keep the locked A+B palette, fonts, panels, icons and all copy.

Both proposals also give the date picker its own full-width row at large text, keeping Previous,
Next and Today underneath, and allow the full `Calories unknown` label to wrap at word boundaries.
The first full-page inspection exposed these adjacent date/uncertainty issues; correcting only
the meal heading would leave a clipped uncertainty label. Numeric energy stays intact.

Nothing becomes unreachable: the day total and its minimum/unknown qualifiers, all four meal
headings/totals, groups, food labels/portions/macros/energy, Back, calendar, Previous, Next, Today,
meal-opening and item-opening actions remain. No metric, feature, navigation or calculation is
removed. The implemented change affects composition only, not default meals or historical dates.

## Complete before/after pages

These links are local-only evidence under the indexed recovery checkpoint, not GitHub assets.
Every image contains the entire page, including Snacks and bottom padding. A and B are identical
at the two large-text settings; A is pixel-identical to Before at 390 px/1x.

| Width / text scale | Existing page | A (approved) | B |
|---|---|---|---|
| 390 px / 1x | [Before](build/ownership-checkpoint/food-heading-preview/before_390_1.0x.png) | [A](build/ownership-checkpoint/food-heading-preview/a_390_1.0x.png) | [B](build/ownership-checkpoint/food-heading-preview/b_390_1.0x.png) |
| 320 px / 2x | [Before](build/ownership-checkpoint/food-heading-preview/before_320_2.0x.png) | [A](build/ownership-checkpoint/food-heading-preview/a_320_2.0x.png) | [B](build/ownership-checkpoint/food-heading-preview/b_320_2.0x.png) |
| 430 px / 3.1x | [Before](build/ownership-checkpoint/food-heading-preview/before_430_3.1x.png) | [A](build/ownership-checkpoint/food-heading-preview/a_430_3.1x.png) | [B](build/ownership-checkpoint/food-heading-preview/b_430_3.1x.png) |

### Existing full page, 430 px / 3.1x

![Existing full Food day page](build/ownership-checkpoint/food-heading-preview/before_430_3.1x.png)

### Proposed full page, 430 px / 3.1x (A and B)

![Proposed full Food day page](build/ownership-checkpoint/food-heading-preview/a_430_3.1x.png)

## Evidence and implementation gate

The ignored `food_heading_preview_test.dart` mounts the real `DayFoodPage` with authored SQLite
entries: a known breakfast, unknown lunch, explicit-zero dinner and empty Snacks on a historical
day. Proposals reuse actual page children, existing styles, strings and callbacks, replacing only
the three compositions described above. The viewport grows until the whole scroll extent is
visible; these are direct Flutter rasters, not stitched pages or HTML reconstructions.

Nine targeted preview cases pass after one batched visual inspection and one confirmation.
Before deliberately retains its existing right overflows (85 px at 320/2x, 150 px at 430/3.1x).
Both proposals have no Flutter overflow in these settings, and the complete unknown-energy label
fits. The manifest records dimensions, text scale and expected Before errors. The full pages were
visually checked for content, spacing and retained actions; production colors/type remain locked.

These are static Flutter test previews on Windows with Manrope standing in for native SF. They
do not certify callback execution after composition changes, native font/keyboard/VoiceOver,
safe-area behavior on an actual phone, or the unbuilt app. No iOS simulator/IPA was built.

All callers of shared `DayHeader` (day sheet, day page and meal page) and `_EntryRow` (meal
card, day page and meal page) were traced. The shared fix preserves callbacks, labels and styles.
Five historical deep-link cases pass at 390/1x, 430/1.3x, 430/1.31x, 320/2x and 430/3.1x;
the original 3.1x regression is enabled. Unknown-energy glyph bounds fit. Previous/Next/Today
navigation is checked at ordinary and 3.1x text without leaking historical entries or changing
logging dates. Combined Linux verification passes in run 40483497760.

The ignored `food_heading_implemented_test.dart` captures actual production widgets without
prototype substitution. Its three complete-page cases pass and one batched visual inspection
confirms retained content/actions. All three are pixel-identical to the approved A previews:

| Width / text scale | Actual implemented page |
|---|---|
| 390 px / 1x | [Implemented](build/ownership-checkpoint/food-heading-implemented/implemented_390_1.0x.png) |
| 320 px / 2x | [Implemented](build/ownership-checkpoint/food-heading-implemented/implemented_320_2.0x.png) |
| 430 px / 3.1x | [Implemented](build/ownership-checkpoint/food-heading-implemented/implemented_430_3.1x.png) |

The combined Linux run [40483497760](https://github.com/akshatksingh18/whoop/actions/runs/40483497760)
passes on privacy-reviewed parentless `3fd1686b`. Native/IPA hold and
B5 STOP remain. Targeted Flutter checks and synthetic pages do not certify native font,
VoiceOver, safe areas or phone acceptance. Original Before/A/B evidence stays locally preserved.

# Food day-page layout proposal

**Status:** Full-page synthetic previews are ready for Akshat's decision. Production UI is
unchanged; the known 3.1x regression remains explicitly skipped. Approval here does not approve
the separate Log food default-meal fix, calorie changes, native builds or GitHub replacement.

## Choice

Recommend **A: stack meal totals at large text**, using the existing shared `bigText` threshold
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
removed. The proposed change affects composition only, not default meals or historical dates.

## Complete before/after pages

These links are local-only evidence under the indexed recovery checkpoint, not GitHub assets.
Every image contains the entire page, including Snacks and bottom padding. A and B are identical
at the two large-text settings; A is pixel-identical to Before at 390 px/1x.

| Width / text scale | Existing page | A (recommended) | B |
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

After Akshat approves A or B, trace every caller of shared `DayHeader` and `_EntryRow`, implement
the smallest shared fix, enable the retained regression, and add boundary/narrow/large-text checks
for full text, controls, explicit historical date and navigation. Re-run targeted checks locally
and the combined suite on a new privacy-reviewed parentless Linux candidate. Keep the native/IPA
hold and B5 STOP. The repository's `CLAUDE.md` requires preview choices before UI implementation;
`product.md` explicitly requires approval. A green preview is not that approval.

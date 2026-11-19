# Food Undo:preserve the deleted entry

**Approved repair is implemented. All28 new and12 retained targeted controls pass.
All9 actual complete pages/41 viewports match the approved proposal pixel-for-pixel.
Strict full149 verifies the repair and all34 new controls;physical acceptance remains open.**

The original authored reproduction reordered a historical breakfast to target,last,first;
Delete/Undo then displayed last,first,target. The saved position became null instead of0
and creation/update timestamps changed. Eaten time,logged_at,nutrition and siblings stayed
exact. The exact regression now passes with full-row equality and correct visible order.
No actual phone-data loss is claimed.

The old shared path reconstructed a FoodEntry after deletion,losing columns absent from
that editable model. The repair captures the actual stored row at deletion and restores
that row;the screen's sorting and ordinary NutritionDb.put contract remain unchanged.

## Approved implemented repair and version decision

Snapshot capture and deletion share one SQLite transaction. An immutable store-created
DeletedFoodEntry token stays in the existing Undo callback. Restore writes all original
stored fields and refreshes counting atomically,including order and creation metadata. Preserve
nulls,measured zero,unit/conversion snapshots,group,source,confirmation,note,date,eaten time
and logged_at. An already identical row is idempotent;never overwrite a different row that
now owns the same ID. A refused delete/restore keeps the available evidence and uses the
existing failure feedback. No new dialog,action or visual layout is introduced.

This shared path serves Food cards,meal-page swipe/menu deletion,zero-portion Remove and
Quick add's existing deletion. The separate Undo of a newly added Log again entry deletes
that new row;it does not need a historical-row restore. An already missing row supplies no
Undo token and cannot resurrect an obsolete screen model.

Akshat approves keeping algorithm103/protocol1.0.1/schema50/app0.9.69+102:the repair restores entry
metadata and ordering,without changing calorie/nutrient formulas,headline Budget,meal-time
selection,wire/schema/backup formats or persisted-name migration. Repository CLAUDE.md requires
this output/version and complete-page review before implementation. Native/IPA remains held.

No metric,uncertainty label,history,date navigation,meal action,food editor,Undo,Back or other
entry point is removed. Every earlier public test/case/assertion remains unchanged. The original
negative stays local;its promoted regression adds exact raw-row and visible-order assertions.

## Verification and remaining acceptance

The original regression,12 exact-row/SQLite controls and15 actual entry-point/ownership
controls pass. All six deletion routes pass at1x/3.1x. Count refresh,unknown/measured-zero,
null/order/unit/conversion/group/source/confirmation/note/date/eaten/logged fields,stale
models,missing rows,idempotence and conflicting replacements are checked. Actual SQLite
delete/insert/count-update refusals roll back rows/counts and publish no false revision;
removing the refusal lets the same operation retry. Unrelated rows/definitions/counts stay.
Six retained Food card and six retained portion-removal controls also pass. Six additional
historical Log food handoff controls pass without changing meal defaults or calculations.

All9 actual Today/historical-day/Meal pages perform real Delete/Undo before capture at
1x/2x/3.1x. Every stored row,text/action set,order and outer-scroll end matches the approved
proposal;all41 actual viewport images are pixel-identical. Current-only coverage/full
source-role/test-case verification passes strict149. One old hit-only projection allocation
counter folds into its compile-time constant;all retained operation hits and every739 old
test file/case/assertion survive. Phone acceptance remains separate;Undo is the existing short-lived action,not a durable backup feature.

## Complete Before/Proposed pages

The previews use the current production components with authored faulty and preserved data
states. They illustrate the intended ordering;they do not claim a storage prototype passes.
Food Today,historical Food day and historical Meal pages are required at1x,2x and3.1x text.
Every outer scroll must reach its end. All18 renders reach the outer scroll end and preserve stored rows;paired text/action sets
match exactly. Food Today includes the real five-tab shell. Visual inspection covers all82
viewports in23 paired sheets:headers,unknown/measured-zero wording,ordered rows,meal actions,
copy/progress,maintenance context and bottom navigation remain available. At3.1x the existing
horizontally scrollable Food tabs show a scroll affordance;this proposal does not change them.
These original data-state previews were reviewed before implementation. The actual repaired
pages now match their Proposed viewports exactly;private raw contracts/hashes retain that proof.


### Today, 1.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_1.0x_proposed_2.png>) |

### Today, 2.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_2.png>) |
| ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_3.png>) | ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_3.png>) |
| ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_4.png>) | ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_4.png>) |
| ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_before_5.png>) | ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_2.0x_proposed_5.png>) |

### Today, 3.1x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_2.png>) |
| ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_3.png>) | ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_3.png>) |
| ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_4.png>) | ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_4.png>) |
| ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_5.png>) | ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_5.png>) |
| ![Viewport 7](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_6.png>) | ![Viewport 7](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_6.png>) |
| ![Viewport 8](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_7.png>) | ![Viewport 8](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_7.png>) |
| ![Viewport 9](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_before_8.png>) | ![Viewport 9](<build/ownership-checkpoint/cov88-food-undo-pages/undo_today_3.1x_proposed_8.png>) |

### History, 1.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_1.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_1.0x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_1.0x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_1.0x_proposed_1.png>) |

### History, 2.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_proposed_2.png>) |
| ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_before_3.png>) | ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_proposed_3.png>) |
| ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_before_4.png>) | ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_2.0x_proposed_4.png>) |

### History, 3.1x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_2.png>) |
| ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_3.png>) | ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_3.png>) |
| ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_4.png>) | ![Viewport 5](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_4.png>) |
| ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_5.png>) | ![Viewport 6](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_5.png>) |
| ![Viewport 7](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_6.png>) | ![Viewport 7](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_6.png>) |
| ![Viewport 8](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_before_7.png>) | ![Viewport 8](<build/ownership-checkpoint/cov88-food-undo-pages/undo_history_3.1x_proposed_7.png>) |

### Meal, 1.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_1.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_1.0x_proposed_0.png>) |

### Meal, 2.0x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_2.0x_proposed_2.png>) |

### Meal, 3.1x text

| Before:observed faulty order | Proposed:preserved order |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_before_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_proposed_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_before_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_proposed_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_before_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_proposed_2.png>) |
| ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_before_3.png>) | ![Viewport 4](<build/ownership-checkpoint/cov88-food-undo-pages/undo_meal_3.1x_proposed_3.png>) |

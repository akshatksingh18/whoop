# Food Undo:preserve the deleted entry

**Confirmed with authored SQLite/page inputs. Repair is proposed,not implemented. All18 complete
data-state page contracts pass. Visual inspection and approval request remain open.**

After reordering a historical breakfast to target,last,first,deleting target and pressing
Undo displays last,first,target. The restored row's saved position becomes null instead of0.
Its created_at and updated_at also become new values. Eaten time,logged_at,nutrition and the
other two rows remain exact in this reproduction. No actual phone-data loss is claimed.

The shared deleteDiaryEntry captures a FoodEntry,then Undo calls NutritionDb.put. That model
does not carry the original position or creation/update columns. put preserves those fields
only while the old row still exists;deletion has already removed it. This is a shared restore
boundary,not a reason to patch the Food card's sort order.

## Proposed preservation repair and version decision

Capture the actual row being removed and delete it in one SQLite transaction. Keep the
snapshot through the existing Undo callback. Restore its full stored fields,including the
original order and creation metadata,atomically with the existing counting refresh. Preserve
nulls,measured zero,unit/conversion snapshots,group,source,confirmation,note,date,eaten time
and logged_at. An already identical row is idempotent;never overwrite a different row that
now owns the same ID. A refused delete/restore keeps the available evidence and uses the
existing failure feedback. No new dialog,action or visual layout is proposed.

Use this shared path for Food cards,meal-page swipe/menu deletion,zero-portion Remove and
Quick add's existing deletion. The separate Undo of a newly added Log again entry deletes
that new row;it does not need a historical-row restore. Trace every caller when implementing.

Propose keeping algorithm103/protocol1.0.1/schema50/app0.9.69+102:the repair restores entry
metadata and ordering,without changing calorie/nutrient formulas,headline Budget,meal-time
selection,wire/schema/backup formats or persisted-name migration. Repository CLAUDE.md requires
this output/version and complete-page review before implementation. Native/IPA remains held.

No metric,uncertainty label,history,date navigation,meal action,food editor,Undo,Back or other
entry point is removed. The public test suite remains unchanged until an approved repair is
ready;the original negative is local evidence,not a new skip or accepted coverage.

## Required verification

Promote the exact original failure after approval. Cover Food cards and meal pages,all shared
deletion entry points,normal and large text,cancel,refused delete/Undo and retry,exact raw-row
restoration,count refresh,historical date/provenance,measured zero and unknown nutrients.
Include real concurrent replacement/refusal controls and preserve unrelated entries,
definitions,counts and days. Keep every existing assertion and source role/hit. Then compare
actual complete implementation pages with the reviewed proposal and run one consolidated
privacy-reviewed Linux candidate. Phone acceptance remains separate.

## Complete Before/Proposed pages

The previews use the current production components with authored faulty and preserved data
states. They illustrate the intended ordering;they do not claim a storage prototype passes.
Food Today,historical Food day and historical Meal pages are required at1x,2x and3.1x text.
Every outer scroll must reach its end. All18 renders reach the outer scroll end and preserve stored rows;paired text/action sets
match exactly. Food Today includes the real five-tab shell. These captures still need visual
inspection before the approval question;do not treat them as an implemented or approved repair.


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

# WHOOP App Design System

**Status:** locked by Akshat on 2026-10-12 after reviewing the full screen set: Today, Trends
(7 days, 30 days, 3 months), Food, Train, Progress, Sleep, Recovery and Live run. Implemented in
Build 88 source (`lib/ui2/theme.dart` tokens, panels, tab bar, `RangeChart`/`DayTiles`/
`MetricLine`/`HeroStat`): Today, Trends, Food, Train, Progress, Sleep, Recovery and the live
run follow their mocks. Sleep stages use navy deep, steel blue light, plum REM and clay awake,
each 4.5:1+ on paper. Secondary inks are darkened to `#3A2F27`/`#40352C`
(6.1:1 and 5.6:1 on the kraft) at Akshat's request; text on the ground otherwise uses
`onGround`.
Reference sketches with synthetic data are in `.impeccable/mocks/screens/` (local and
gitignored); regenerate them with `gen.py` there. This file is the visual contract that
Impeccable reads. Product truth stays in `CLAUDE.md` and `metrics-map.md`.

Build 96 retains the calm A framework Akshat selected with B's whole calorie-ring/compact-macro
card on Food. Progress has one closed-week goal check with the real first-check date, Next and
expandable method; Body outcomes and inputs use rolling periods against equal earlier periods.
The Body summary separates the latest individual reading, the 7-day average and the selected
period average. Recovery explains its measured inputs without changing its score. The kraft/cream
palette and metric-family colours stay locked. Titles clamp to Apple's Large Title scaling;
supporting labels and actions respect Dynamic Type. `todo.md` retains phone acceptance gates.

The approved COV-20 correction preserves this Recovery layout: a pinned morning score uses
its original driver points, comparison ranges and dated HRV context, captioned as the saved
morning score. Older pins without original evidence keep their score/history and show
"Morning breakdown unavailable". Do not reconstruct their explanation from a later sync.

The approved Build 95 repairs keep this composition: Body comparisons stack labels and intact
values when text or width requires it, Notifications gives Mark all read its own full-width row,
and enlarged notifications place time/unread context above the message. Save failures retain the
draft and name the retry; a stopped workout cannot appear to be recording. Selected settings
choices expose the same state to VoiceOver as to sighted users. See `build-95-repairs.md` for
implementation and verification status; this is not a new visual direction.
Build 97 keeps the same composition. For one recorded weight day, the latest reading and a
short comparison explanation replace repeated average/endpoints; the chart, entries, measures
and photos remain. Notification rows add one provenance label, with a short explanation below
the history; a due schedule is never presented as confirmed delivery.
The approved follow-up keeps targets under Today values in a consistent `of <goal>` format.
Trends places pins in its header and keeps units/coverage intact; the second energy method gets
full-width context. Food puts calories in every meal heading without repeating a singleton's
energy, and groups Copy a day/Progress inside the meals panel. Progress inputs have three labelled
groups with coverage, Add body entry is a filled action, and Body comparisons use the card width.
Body summaries use one decimal unless a milestone needs the second decimal or actual difference
to avoid a misleading tie; full readings/editing keep their precision. Sleep correction stays inside
one collapsible card. HR chart selection ends at the latest actual reading at or before now, in
all three Today ranges and day detail; unrecorded/future tails cannot acquire a cursor.

## Direction

Earth Pigment Studio on a deep kraft ground. Each metric family owns one flat earth/jewel
colour. All of a screen's data sits on cream panels above the kraft. Two behaviours are borrowed
from the other shortlisted directions:
- **Honest gaps** (from Training Logbook): every missing day is a hatched blank.
- **Freshness** (from Departure Board): an amber "NEW" marker stays on until the value has been
  seen, and unavailable values show in amber with "—".

Light appearance; this replaces the dark-only app.

## Colour Tokens

| Token | Hex | Use |
|---|---|---|
| ground | `#C9AE84` | screen background (deep kraft) |
| paper | `#F4EBDA` | data panels, tab bar |
| ink | `#2A211B` | primary text and numbers |
| ink2 | `#3A2F27` (darkened from `#6E6155` for legibility on the kraft) | labels and secondary text |
| onGround | `#3B2F23` | text placed directly on the kraft |
| rule | `#E2D2B8` | 1 px dividers inside panels |
| recovery | `#2E7D63` | recovery, HRV, resting HR, active tab |
| sleep | `#34478F` | sleep, deep stage, breathing |
| strain | `#C24E25` | strain, runs, live workout |
| food | `#A8730A` (was `#D9961A`, too faint on paper) | calories and macros |
| body | `#7A4F30` | steps, weight, body |
| alert | `#C8551B` | NEW marker, unavailable and stale values only |
| hatch | `#CDBBA2` | missing-day hatching |

Each family colour is used only for its own data. Alert colour never decorates.

## Type And Size

- **Typeface:** the system face (SF Pro), with Dynamic Type respected.
- **Food card (Build 90, clarified selection):** B's whole calorie/macro component inside A:
  a ring with calories left (or explicit overage), eaten and the fixed goal beside it, then four
  slim macro value/target rows with protein larger. The arc is the known remaining fraction;
  absent or partial balances do not imply an exact arc. Amount bounds remain explicit. The
  plate/utensil decoration and linear calorie bar are replaced. Unknown macro tracks are hatched
  and say not logged, not zero. All macros stay visible; large text stacks the ring and summary.
  Add food follows; full meal, counting, calendar and maintenance flows remain.
- **Hero number:** one primary number per card, 64 pt or 48 pt for long values in the shared
  HeroStat. Display-number scaling is bounded to keep a stable headline; supporting body,
  labels, units and actions retain full Dynamic Type. Long values scroll horizontally intact.
- **Row values:** 24 pt semibold in MetricLine, with units and qualified context below;
  tabular figures. Normal rows share a right edge independent of a chart or chevron.
- **Labels:** metric labels use sentence case and body size. Small section markers retain
  the existing uppercase style. Supporting text uses the existing medium-weight floor.
- **Large text:** rows reflow to full-width labels and intact values; comparison groups stack.
  Detail titles use their own full-width line. No metric ellipsis, digit wrapping or FittedBox
  shrinking in the shared metric/comparison primitives; vertical scrolling is expected.

## Shape And Layout

- **Panels:** 26 pt continuous corners, 12 pt side margin and a soft shadow.
- **Rows:** flexible label, optional real-history mini chart, right-anchored value, and a
  stable action gutter. Units sit under the value. Charts have no empty placeholder slot.
- **Composition:** Today leads with Recovery and early daily actions, with unique totals shown
  once. Trends groups recovery/sleep, heart/breathing and activity/wear, retaining pins and
  input gates. Train leads with Start/Resume and history before long chart material. Progress
  keeps one fixed-week goal judgment; exploration periods cannot change it. Reasoning and
  all detailed evidence remain reachable.
- **Illustration:** subtle authored leaf and moon artwork adds visual relief without
  implying data. It is excluded from accessibility semantics and may hide at large text.
  Charts, missing-data hatching and real photos retain their actual meaning.
- **Charts:**
  - Today and details use 7-day tiles.
  - Trends at 7 days uses bar charts.
  - Trends at 30 days uses a thin daily line plus a bold 7-day average line.
  - Trends at 3 months uses weekly-average points with a soft low-high band.
  - Missing data breaks the line and shows a hatched gap; a line never bridges a gap.
  - Target bars require a real target. Recomposition has no invented percentage or endpoint.
- **Navigation:** the system tab bar (Today, Trends, Food, Train, Progress); standard
  back navigation; segmented controls for ranges.
- **Estimates and absence:** estimates are labelled ("estimate"). Absent values are "—" with
  a one-line reason.

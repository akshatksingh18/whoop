# WHOOP App Design System (Build 88)

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
- **Hero number:** light weight, about 116 pt; 84-96 pt for long values such as 1,920, 80.4 or
  4.21.
- **Row values:** 30 pt semibold; 22 pt on dense screens. Tabular figures throughout.
- **Labels:** 11.5 pt uppercase with 0.12 em tracking. Body text is 13-15 pt.

## Shape And Layout

- **Panels:** 26 pt continuous corners, 12 pt side margin and a soft shadow.
- **Rows:** label, 7-day mini chart, then the value.
- **Charts:**
  - Today and details use 7-day tiles.
  - Trends at 7 days uses bar charts.
  - Trends at 30 days uses a thin daily line plus a bold 7-day average line.
  - Trends at 3 months uses weekly-average points with a soft low-high band.
  - Missing data breaks the line and shows a hatched gap; a line never bridges a gap.
  - Single values use a progress bar.
- **Navigation:** the system tab bar (Today, Trends, Food, Train, Progress); standard
  back navigation; segmented controls for ranges.
- **Estimates and absence:** estimates are labelled ("estimate"). Absent values are "—" with
  a one-line reason.

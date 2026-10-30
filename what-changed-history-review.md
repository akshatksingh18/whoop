# Historical What changed comparison review

**Status:** Akshat approved the proposed read-side date-boundary repair and unchanged
algorithm 99/schema 50 treatment. The minimal shared-reader fix is implemented; six new
and five retained controls pass locally, with clean changed-file analysis. Four new controls
failed against the original source and now pass unchanged. Combined verification is pending.
Six complete authored Before/Proposed pages are accepted. Their local
capture manifest and confirmation check verify all six scroll ends and six pixel-identical
confirmation frames. All complete pages were inspected; synthetic pages do not certify
native behavior or interactions. Independent coverage can continue while this decision waits.

The current reader can forget valid history for an earlier day when a later algorithm break
exists. In the authored example, April 6 has a resting heart rate of 100 bpm and twenty
earlier readings of 50/52 bpm. An April 7 algorithm break currently reduces the April 6
comparison to zero earlier readings, so the page says “Still learning your usual.” No saved
measurement is lost: the transient comparison selects the wrong cutoff.

The proposed page retains those twenty eligible earlier readings and shows the existing
finding: “resting heart rate 100 bpm — above your usual range (usually 50 bpm–52 bpm)”.
The later April 7 value of 200 bpm does not enter that comparison. These are invented test
inputs, not measurements or a health claim about Akshat.

The proposed rule is to use the latest algorithm break **on or before the shown calendar
day**, with the same recorded/local-day helper used by the existing series reader. Ignore
only breaks assigned to a later day. Keep the exact epoch cutoff for eligible breaks and
continue excluding observations before it. A break within the shown day still applies;
comparing its timestamp with midnight alone would incorrectly discard that break. Choose
the latest eligible break even if the input list is unsorted.

Apply the rule once in `collectSweepSeries`, whose current tracked production caller is
`WhatChangedData.load`. Keep global `getChart` metadata, month-grid data, thresholds (including
the fourteen-day minimum), ranking, units and finding wording. Reuse existing functions and
persist no replacement results. Notification/report history, headline calculations and stored
analytics remain outside this repair. The proposed version decision is to keep algorithm 99
and schema 50 for this read-side historical selection correction; that decision is part of
this explicit approval; stored analytics and package algorithms do not change.

Complete pages:

| Context | Existing reader | Proposed comparison |
| --- | --- | --- |
| 390 px, 1× text | [Before](build/ownership-checkpoint/future-break-preview/before_390_1.0x.png) | [Proposed](build/ownership-checkpoint/future-break-preview/proposed_390_1.0x.png) |
| 320 px, 2× text | [Before](build/ownership-checkpoint/future-break-preview/before_320_2.0x.png) | [Proposed](build/ownership-checkpoint/future-break-preview/proposed_320_2.0x.png) |
| 430 px, 3.1× text | [Before](build/ownership-checkpoint/future-break-preview/before_430_3.1x.png) | [Proposed](build/ownership-checkpoint/future-break-preview/proposed_430_3.1x.png) |

The preview uses the real existing screen and reader. For Proposed only, a local wrapper
filters the chart-break inputs by the proposed rule, then retains the original available
days and month grid. No production source is patched for a preview. All content is expanded
to the scroll end, retaining Back, day arrows, date picker, Latest, the day-timeline door,
the three month domains and all uncertainty/methodology text. Enlarged date ellipsis is an
existing retained behavior visible in both versions; this proposal does not redesign it.
Fonts are test substitutes; the view has synthetic safe-area padding.

After approval, regression checks must cover the original future-break failure; no breaks;
preceding, same-day and multiple unsorted breaks; observation values on either side of the
eligible cutoff; no future value leakage; recorded/travel-day assignment; missing/short
history and unchanged chart metadata/month grid. Preserve the original negative, compare
actual implemented full pages with the accepted proposal, and run combined Linux checks
after the privacy gate. Native/IPA, migration/phone acceptance and B5 holds remain.

Decision: Akshat approved this exact rule, complete previews and read-side version treatment.
Three actual complete pages, using the repaired production reader directly with no input
wrapper, pixel-match all three accepted Proposed pages. Their manifest is
`build/ownership-checkpoint/future-break-implemented/verified-manifest.json`.
The original failure source/log and initial broad formatter output are preserved locally;
the production diff is limited to the cutoff guard and its comment. Native/IPA and phone
acceptance remain separate.

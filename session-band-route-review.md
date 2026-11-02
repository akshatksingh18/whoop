# Session connection-help route review

**Status:** Akshat approved both destination repairs. Only their two callbacks and the
existing Devices import changed. Six real stored-session/gesture regressions pass at1×/2×/
3.1×, including Back to the same State/tab/date and unchanged session/measurement rows.
The exact same public six regressions fail on the original source for missing MyDevices;
the repaired source is restored byte for byte afterward.50 targeted summary checks pass,
including44 retained rating/edit/thermal/short-trace controls. Combined cloud proof is pending.

The19 complete Before/Proposed viewports and12 implemented viewports below are synthetic
Flutter previews at430×932, with shipped fonts/localization and1×/2×/3.1× text. They are not
native/phone acceptance. Existing large-text findings stay open; no layout repair is claimed.

## Actual behavior and proposed change

A real saved-session row goes through SessionDestination → LocalRepositoryImpl → ActivitySummary.
Before repair, on both Overview's no-heart-rate card and Graphs's no-series card,
“Check band connection” called openProfile, which opened EditProfile. Three real gesture negatives at1×/2×/3.1× confirm
the wrong page; they remain private failing checks, not public passing coverage or new skips.

Approved and implemented: change only those two connection-help destinations to existing MyDevices (“My sources”).
Keep the label, missing-data explanation, tab/date/session state, elapsed/active time, rating,
calorie uncertainty, Edit/Delete, and Back behavior. Body profile editing remains reachable
through Settings → Edit profile; the misleading connection-help shortcut to that editor is
the only entry point replaced. No feature, metric, stored row, history, calculation, schema,
protocol/algorithm/app version, or other openProfile caller changes.

Implementation: import the existing Devices page and route only these two callbacks to it.
Regressions must tap both real cards, assert MyDevices rather than EditProfile, return to the
same saved session/tab/date, preserve the stored session/measurements, and retain thermal/
one-minute exceptions. Reuse the three negative scales and broader saved-session controls.
Then include the repair in a privacy-reviewed consolidated Linux candidate. Native/IPA stays held.

## Existing layout findings remain separate

The complete current pages also show existing3.1× connection-help ellipsis, vertical Save
wrapping on Edit profile, and awkward connection-status word wrapping on My sources. This
route-only proposal does not repair or remove those controls. Keep them open for their own
complete layout previews/approval; a green navigation test must not be called a layout fix.
The synthetic historical session intentionally has no recorded calculation profile, so its
calorie-absence message remains; current body inputs are not borrowed to price that old bout.

## Complete Before and Proposed pages

Summary and Graphs pixels/copy stay identical in this proposal. Their Before pages below are
also the proposed source pages; only where the help action lands changes. Each group includes
all vertical-scroll positions, with overlap and fixed headers. No viewport was selected to
hide missing content. The first/raw capture accidentally selected an editable field's
horizontal scroller; those15 images are retained but are not the complete review set below.

### 1.0× text

**Overview — unchanged in proposal**

![Overview — unchanged in proposal, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_1.0_0.png)

**Graphs — unchanged in proposal**

![Graphs — unchanged in proposal, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/graphs_before_1.0_0.png)

**Before — actual wrong destination**

![Before — actual wrong destination, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_1.0_0.png)

**Proposed — existing My sources destination**

![Proposed — existing My sources destination, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/proposed_sources_1.0_0.png)

### 2.0× text

**Overview — unchanged in proposal**

![Overview — unchanged in proposal, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_2.0_0.png)

![Overview — unchanged in proposal, 2.0×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_2.0_1.png)

**Graphs — unchanged in proposal**

![Graphs — unchanged in proposal, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/graphs_before_2.0_0.png)

**Before — actual wrong destination**

![Before — actual wrong destination, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_2.0_0.png)

![Before — actual wrong destination, 2.0×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_2.0_1.png)

**Proposed — existing My sources destination**

![Proposed — existing My sources destination, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/proposed_sources_2.0_0.png)

### 3.1× text

**Overview — unchanged in proposal**

![Overview — unchanged in proposal, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_3.1_0.png)

![Overview — unchanged in proposal, 3.1×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_3.1_1.png)

![Overview — unchanged in proposal, 3.1×, viewport 3](build/ownership-checkpoint/cov53-session-band-review/pages-complete/summary_before_3.1_2.png)

**Graphs — unchanged in proposal**

![Graphs — unchanged in proposal, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/graphs_before_3.1_0.png)

**Before — actual wrong destination**

![Before — actual wrong destination, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_3.1_0.png)

![Before — actual wrong destination, 3.1×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_3.1_1.png)

![Before — actual wrong destination, 3.1×, viewport 3](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_3.1_2.png)

![Before — actual wrong destination, 3.1×, viewport 4](build/ownership-checkpoint/cov53-session-band-review/pages-complete/actual_wrong_profile_3.1_3.png)

**Proposed — existing My sources destination**

![Proposed — existing My sources destination, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/pages-complete/proposed_sources_3.1_0.png)


## Implemented complete pages

The original Before-capture diagnostic also asserted the wrong EditProfile page so it could
record that page. It is retained unchanged; it is not called passing after the repair. The
public regression instead checks the promised MyDevices destination and Back/data preservation,
and its six-case old-source failure is independently recorded.

### Implemented 1.0×

![Implemented Overview, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_1.0_0.png)

![Implemented Graphs, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_graphs_1.0_0.png)

![Implemented My sources, 1.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_sources_1.0_0.png)

### Implemented 2.0×

![Implemented Overview, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_2.0_0.png)

![Implemented Overview, 2.0×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_2.0_1.png)

![Implemented Graphs, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_graphs_2.0_0.png)

![Implemented My sources, 2.0×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_sources_2.0_0.png)

### Implemented 3.1×

![Implemented Overview, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_3.1_0.png)

![Implemented Overview, 3.1×, viewport 2](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_3.1_1.png)

![Implemented Overview, 3.1×, viewport 3](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_overview_3.1_2.png)

![Implemented Graphs, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_graphs_3.1_0.png)

![Implemented My sources, 3.1×, viewport 1](build/ownership-checkpoint/cov53-session-band-review/actual-pages/coverage102_session_band_help_sources_3.1_0.png)


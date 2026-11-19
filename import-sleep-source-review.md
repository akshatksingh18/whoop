# Imported sleep-source repair

**Status:** The approved handoff repair and algorithm103 pass strict full130,including both
complete import regressions;physical acceptance remains open. Production is algorithm103/protocol1.0.1/schema50,
app0.9.69+102;IPA remains held.

## Confirmed boundary

The complete cloud import checks expose incorrect saved provenance. `deriveImportedDays`
uses `_deriveDay`,which previously created `PreparedDerivationDay` without `sleepSource`.
Its default was `auto`,so the shared writer lost the calendar-day detector's actual source.
The repaired handoff now passes it,matching the ordinary prepared-worker serialization.
The absent-night negative in full128 directly reproduces the loss. All original errors,
source hashes and raw failed shard evidence are preserved locally;none enters a verified score.

The first positive fixture had no valid gravity anywhere. The existing observed-window
gate correctly refused its night;that fixture did not establish a qualifying HR-led result.
The corrected positive retains measured gravity during the night,with the longer search
window still below the accel-detection floor. It must still pass the existing HR dip,
observation and staging gates. It qualifies through those gates in strict full130;the long-gap case abstains. No gate is weakened.

## Approved implemented change and version

- Pass `sleepSource: day.sleepSource` at this one import handoff. Keep the constructor's
  backward-compatible default and existing serialization. Preserve all other prepared fields.
- Use algorithm103 with a narrow changelog/contract update,because saved output provenance
  changes. Protocol1.0.1,schema50 and app metadata remain unchanged during the IPA hold.
- Preserve numerical methods,HR/RR/gravity admission,staging,confidence,uncertainty and
  correction scheduling. The numeric pipeline distinguishes manual/confirmed sources for
  settling time;auto/fallback/none remain outside that branch. Source and flags must agree.
- Keep every existing saved version,row,pin,original input and correction. Do not infer a
  legacy label from an ambiguous auto string or bulk-rewrite finalized history. Reprocessing
  is limited to retained input admitted through the existing workflow;repair of older labels
  without sufficient evidence remains a separate investigation.

## Existing interface before and after

The full Sleep page retains its metrics,unknown values,hypnogram,Stages,Overnight signals,
Naps,day navigation and breathing-report link. Its existing **Fix sleep times** card stays
folded initially. For a genuine HR-led fallback,opening it changes:

| Before | Proposed |
|---|---|
| “This window was staged from the signals” | “This window was inferred from heart rate” |
| Fallback explanation and confirmation absent | Existing best-guess explanation and “These times are right” restored |
| Set the times myself and Not sleep | Both retained |

An absent night remains absent;no new window,score or correction control is invented.
Home and Recovery retain their existing output. No layout/style redesign is proposed.

## Complete page previews

[Open the complete Before/Proposed gallery](build/ownership-checkpoint/import-sleep-source-review-v3/index.html).
It includes42 complete page states in21 comparison pairs:Sleep,Home and Recovery at1x,2x
and3.1x for an absent night and a representative qualifying fallback,plus expanded correction
cards. All18 initial-page pairs are byte-identical;the expanded card changes only the
explanation and existing confirmation action described above. All other text is retained.

Thirty-six bounded render checks pass. Inputs are representative authored UI records,not
personal captures or proof of the amended overnight calculation. Private
`cov82-import-source-page-review.json` owns exact capture hashes and text/initial-page parity.
The first preview assertions incorrectly checked the folded card and then omitted “the”
from an existing action label;those fixture negatives remain private. The final checks use
the actual expanded card and exact existing labels. Production now implements the approved handoff;UI code is unchanged.
Eighteen bounded actual-version103 render checks pass:all21 complete page states and their
text match the approved proposal byte-for-byte. This is representative UI proof;the full
overnight calculations also pass strict full130. Neither substitutes for phone acceptance.

## Validation and STOP

Keep both full import regressions and every earlier assertion. Strict full130 verifies the implemented plan with all24 new active-workflow/import controls,
the corrected positive fixture,absent-night source,numerical/preservation contracts,all retained
old hits/cases/skips,source hashes and current-only coverage. Prototype,
failed and older counters remain excluded. Synthetic checks close no phone/migration gate.

The repair/version and complete-page approval gate is satisfied. Do not ask again.
Main replacement and each remote branch/tag deletion remain separate B5 stops.

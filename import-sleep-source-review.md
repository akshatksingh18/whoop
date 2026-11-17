# Imported sleep-source repair proposal

**Status:** Complete pages ready for review;production is unchanged at algorithm102/protocol1.0.1/schema50,
app0.9.69+102. The repair and proposed algorithm103 require explicit approval. IPA remains held.

## Confirmed boundary

The complete cloud import checks expose incorrect saved provenance. `deriveImportedDays`
uses `_deriveDay`,which creates `PreparedDerivationDay` without `sleepSource`. Its default
is `auto`,so the shared writer receives auto regardless of the calendar-day detector's
actual source. The ordinary prepared-worker path already serializes the source correctly.
The absent-night negative in full128 directly reproduces the loss. All original errors,
source hashes and raw failed shard evidence are preserved locally;none enters a verified score.

The first positive fixture had no valid gravity anywhere. The existing observed-window
gate correctly refused its night;that fixture did not establish a qualifying HR-led result.
The corrected positive retains measured gravity during the night,with the longer search
window still below the accel-detection floor. It must still pass the existing HR dip,
observation and staging gates. Its full verification remains pending;no gate is weakened.

## Exact proposed change and version

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
the actual expanded card and exact existing labels. Production is unchanged.

## Validation and STOP

Keep both full import regressions and every earlier assertion. After approval,run one
combined privacy-reviewed parentless Linux verification with the banked active-workflow
controls. Check the corrected positive fixture,absent-night source,numerical/preservation
contracts,all old hits/cases/skips,source hashes and full current-only coverage. Prototype,
failed and older counters remain excluded. Synthetic checks close no phone/migration gate.

STOP: approve the exact repair/version plan and reviewed complete pages before production
implementation. Main replacement and each remote branch/tag deletion remain separate B5 stops.

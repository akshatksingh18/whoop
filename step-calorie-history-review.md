# Step-calorie history: approved repair and verification

**Status:** Akshat approved both the read-side repair/version plan and the complete-page UI.
The reviewed changes are implemented locally. The original reader negative and twelve retained
reader controls pass;42 page/locale/cache/range/route controls pass. All58 actual implementation
viewports match the approved proposal byte-for-byte. Full Linux109 verifies the implemented repair;
physical acceptance remains. This is a read-side missing-evidence repair.
The reviewed source basis is verified97 and production-identical candidate98. The latter's
38 new public controls and full Linux verification are owned by coverage-audit.md.

## Confirmed problem and callers

A permanent Steps chart point can survive after its measured step windows are absent.
getChart('steps') retains that total; getMeasuredDaySteps correctly returns unknown. The
shared stepCalorieModels reader takes zero from the conservative maintenance floor and
publishes it as a measured Budget step-calorie point. A real SQLite/reader negative reproduces
this with an authored1000-step point and a complete synthetic profile. Its original source/logs
stay private,uncounted and unskipped; twelve independent measured/profile/date controls pass.

The helper serves both HealthData.load on Trends and MetricData.load on Step calories.
The detail caches by repository,input revision,window and local day. Its selected-day route
opens the existing DayStepsDetail; that reader already withholds walking energy when
walkingEnergy has no measured steps. This proposal changes neither that reader nor the
conservative full-day maintenance estimate. Permanent metric_series data is not rewritten.
The no-span day reader can still say no steps counted when only a chart scalar survives;
that older reconstruction/explanation discrepancy is separate and remains under investigation.

## Output and version decision

Approved and implemented: withhold the Budget comparison point when DayUpkeep.steps is unknown. Keep the
existing dated profile,run-overlap accounting,measured-zero handling and formulas exactly.
Do not infer measured movement from the surviving chart scalar. The alternate distance
estimate stays under its current rules; _walkingDistance already refuses unknown walked steps.

With the authored mixed fixture,1000 measured steps,a separate retained2000-step total without
windows,and a measured zero produce these display changes:

| Display | Current | Proposed |
|---|---|---|
| Budget step-calorie average | 8 kcal,3 of7 days | 11 kcal,2 of7 days |
| Movement comparison | Unavailable because its count differs | 9 kcal over the existing two eligible days |
| Unknown selected day | Budget0 kcal | Budget unavailable |
| Measured zero | 0 kcal | 0 kcal |
| Steps average/count and saved totals | Existing values | Identical |
| Headline maintenance/Budget,resting energy,food,run calculations | Existing methods | Identical |

Akshat approved retaining algorithm101,protocol1.0.1 and schema50 for this separately approved
read-side admission correction. No analytical formula,stored derived bundle,package output,
backfill or baseline changes. The shared reader's displayed average/count and gaps DO change;
Akshat gave the separate output/version approval before implementation.

## UI decision and retained actions

The bare guard was rejected during private review: an entirely unknown range would otherwise
fall into generic no-history copy,suggest overnight band wear and hide Browse days. The final
proposal shows Step calories unavailable with this explanation: “Measured step coverage and
body weight are needed for a calorie estimate. Missing inputs stay unknown. Browse days to
review recorded activity.” This describes missing prerequisites without inventing a reason.

Keep the selected-day Previous/Next arrows,day opening,Browse days,Back and every range.
An entirely unknown range replaces its unsupported zero chart/scrubber with the honest absence
card and the retained day controls. That conditional zero-chart interaction is the only old
visual interaction that becomes unavailable; no valid measured chart or day route is removed.
On Today,retain the original method explanation even when the comparison is unavailable,and
retain the embedded day reader. That reader's existing no-span wording stays visible in the
complete pages; this review does not silently reconstruct old totals or change its policies.

Above the existing1.3x text threshold,stack the complete selected date above the existing
Budget and movement readouts; retain both outside arrows and the day-opening chevron.
Ordinary rows keep their current composition,including their current date ellipsis. Other
metrics,Trends layout,uncertainty labels,units and destinations stay. The existing horizontally
scrollable movement subtitle on Trends is retained,including its large-text initial clipping.

The two absence strings are added to all six existing localization resources;prior values are
preserved. English complete pages own the review;six-locale1x/3.1x overflow controls pass.
No parked calorie,treadmill or meal-default proposal is implemented through this repair.

## Complete Before/Proposed pages

All values are authored test fixtures,not Akshat's measurements. Each430x932 phone page was
captured through its actual scroll end at1x,2x and3.1x. Proposed pages use isolated copies of
the shipped renderers/readers; no production file was temporarily patched. The catalog below
contains36 complete states and all of their uncropped viewports. The valid Today pages use
the explicit Today range and actual loading/embedded reader; initial wrong-range prototype
sources/logs/captures remain private and are excluded from this catalog.

Captures and prototype code remain local recovery evidence,never published. These private
checks/LCOV are not part of the public38-check batch or the coverage percentage.

### Step calories — seven-day range

| Fixture / text | Before,top to actual end | Proposed,top to actual end |
|---|---|---|
| Measured + unknown + zero / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_1.0x_0.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_1.0x_0.png) |
| Measured + unknown + zero / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_2.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_2.0x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_2.0x_2.png) |
| Measured + unknown + zero / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_before_3.1x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_mixed_proposed_3.1x_3.png) |
| Only unknown history / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_1.0x_0.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_1.0x_0.png) |
| Only unknown history / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_2.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_2.0x_1.png) |
| Only unknown history / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_before_3.1x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_range_empty_proposed_3.1x_2.png) |

### Step calories — Today

| Fixture / text | Before,top to actual end | Proposed,top to actual end |
|---|---|---|
| Measured + unknown + zero / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_1.0x_0.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_1.0x_0.png) |
| Measured + unknown + zero / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_2.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_2.0x_1.png) |
| Measured + unknown + zero / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_mixed_before_3.1x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_mixed_proposed_3.1x_4.png) |
| Only unknown history / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_1.0x_0.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_1.0x_0.png) |
| Only unknown history / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_2.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_2.0x_1.png) |
| Only unknown history / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_corrected_empty_before_3.1x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_detail_today_final_empty_proposed_3.1x_4.png) |

### Trends — complete page

| Fixture / text | Before,top to actual end | Proposed,top to actual end |
|---|---|---|
| Measured + unknown + zero / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_1.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_1.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_1.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_1.0x_1.png) |
| Measured + unknown + zero / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_2.0x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_2.0x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_2.0x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_2.0x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_2.0x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_2.0x_3.png) |
| Measured + unknown + zero / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_4.png) · [Viewport 6](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_5.png) · [Viewport 7](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_6.png) · [Viewport 8](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_before_3.1x_7.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_4.png) · [Viewport 6](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_5.png) · [Viewport 7](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_6.png) · [Viewport 8](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_mixed_proposed_3.1x_7.png) |
| Only unknown history / 1.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_1.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_1.0x_1.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_1.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_1.0x_1.png) |
| Only unknown history / 2.0x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_2.0x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_2.0x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_2.0x_3.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_2.0x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_2.0x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_2.0x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_2.0x_3.png) |
| Only unknown history / 3.1x | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_4.png) · [Viewport 6](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_5.png) · [Viewport 7](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_6.png) · [Viewport 8](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_before_3.1x_7.png) | [Viewport 1](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_0.png) · [Viewport 2](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_1.png) · [Viewport 3](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_2.png) · [Viewport 4](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_3.png) · [Viewport 5](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_4.png) · [Viewport 6](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_5.png) · [Viewport 7](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_6.png) · [Viewport 8](build/ownership-checkpoint/cov61-step-calorie-review-pages/step_calorie_complete_trends_empty_proposed_3.1x_7.png) |

## Accepted implementation and remaining verification

1. Implemented: only the reviewed unknown-point guard and the approved absence/navigation/large-text
   composition. Keep every maintenance/helper formula and stored record unchanged. Preserve
   original negatives and exact source reversal; do not turn the private preview code into an
   app dependency or copy its authored values into production.
2. Implemented and targeted-green: promote the desired real-reader negative without changing its assertion. Cover measured0,
   missing age/height/weight,dated weights and run overlap,retained-only history,range edges,
   future exclusion and no writes. Exercise both actual loader entry points and verify every
   unaffected metric and both energy series against their prior outputs.
3. Targeted-green: Today/7/30/90-day ranges,revision and local-day cache invalidation,reopening,
   unknown-day arrows/opening/Browse days/Back,all-unknown and genuinely empty ranges,
   measured zero and input repair. Keep all actions/notes at1x/2x/3.1x and around1.3x. Compare
   actual complete implementation pages with the approved proposal; retain all six locales.
4. Verified in full100 with the combined72-control tree. Retain the rule:run only quick
   targeted local probes; privacy-review a parentless candidate and run the full Linux suite,
   analysis,source/caller/strict-LCOV checks and complete page evidence once the batch is ready.
   Never count an original failure as a passing check or add an exclusion to reach100%.
5. Synchronize todo,bugs,coverage and current setup/owning status. Preserve all refs and new
   local-only evidence in a verified bundle/vault. Native/IPA,migrationN/phone/N+1 and exact-ref
   B5 gates remain separate and unchanged.

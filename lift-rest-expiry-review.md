# Paused Lift rest timer:approved redraw repair

**Approved and implemented. Ten targeted controls and six complete-page contracts pass;full cloud verification and physical acceptance remain open.**

When rest expires while a Lift workout is paused,the deadline becomes expired and the
haptic fires,but the last countdown can remain on screen. The local rest tick clears
its cached deadline without requesting a rebuild. Running sessions normally redraw from
the host clock;the paused clock has no later tick to refresh the body.

The actual shipped host reproduces the paused case at1x/3.1x. Its two running controls
pass. A stronger isolated diagnostic also confirms the expired deadline and one haptic
before the display assertion fails. Original failures remain private and uncounted.

## Approved repair and version decision

The existing tick now calls `setState(() => _restUntil = null)` at expiry. The expired
countdown,+30s and Skip row then disappears,matching the existing running-session result.
Rest still follows its existing wall-clock deadline during a workout pause. No new timer,
rest policy,calculation,formula,wire/schema/storage format or notification timing is proposed.
Keep app0.9.69+102,algorithm103,protocol1.0.1 and schema50. Native/IPA stays held.

The exercise list,sets,split identity,rest settings,search,Add exercise,workout duration,
calorie estimate/uncertainty,band explanation,Resume/Pause,Finish and minimise stay.
No screen or functional entry point retires. Existing large-text word wrapping is outside
this narrow proposal. Physical iPhone/OS acceptance remains separate.

The isolated prototype changes only the expiry redraw in the actual Lift component.
All12 current/proposed running/paused contracts pass at1x/2x/3.1x. Every full outer scroll
reaches its end;session rows and saved sets remain exact. These are synthetic pages,
not accepted coverage or a phone test. Runtime clock labels can differ between captures.
Repository CLAUDE.md requires complete-page approval before this UI implementation.

## Complete pages

Each column contains all successive overlapping viewports,top to bottom,at430x932.
Open an image for full size. The paused pages are the affected state;running controls
are included to check that the same metrics,explanations and actions remain.

### Paused, 1.0x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_1.0x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_1.0x_0.png>) |

### Paused, 2.0x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_2.0x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_2.0x_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_2.0x_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_2.0x_1.png>) |

### Paused, 3.1x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_3.1x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_3.1x_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_3.1x_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_3.1x_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_paused_3.1x_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_paused_3.1x_2.png>) |

### Running, 1.0x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_1.0x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_1.0x_0.png>) |

### Running, 2.0x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_2.0x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_2.0x_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_2.0x_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_2.0x_1.png>) |

### Running, 3.1x text

| Before | Proposed |
| --- | --- |
| ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_3.1x_0.png>) | ![Viewport 1](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_3.1x_0.png>) |
| ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_3.1x_1.png>) | ![Viewport 2](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_3.1x_1.png>) |
| ![Viewport 3](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_before_running_3.1x_2.png>) | ![Viewport 3](<build/ownership-checkpoint/cov87-lift-rest-prototype/build/ownership-checkpoint/cov87-lift-rest-pages-v3/rest_proposed_running_3.1x_2.png>) |

## Verification after implementation

The single shared redraw is implemented and the original host/isolated regressions are promoted.
Retain all old cases and emitted roles/hits,and verify one combined Linux candidate.
Do not credit private prototype/failed LCOV. Keep phone acceptance and all migration/B5 gates.

All ten promoted/extended regressions and15 retained timer/controller checks pass. New-test
analysis is clean;seven pre-existing Lift-source informational lints remain. Six actual
complete-page contracts match the approved proposal exactly. The source-role map preserves
all3,479 emitted roles across Lift and a separate three-line BLE comment-only correction;
no old role retires. Full current-source/hit/case verification remains open.

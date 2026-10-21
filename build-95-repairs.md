# Build 95 audit repairs

**Status:** All 29 confirmed findings are implemented in Build 96 preparation on `build-96`, based on Build 95 app source `f5b270f3` and integrated documentation `b0c2c8d6`. 73 distinct focused synthetic checks pass locally, including 9 render/scroll checks; Akshat approved the visual checks and authorized Codex to integrate and deliver the IPA. Full cloud checks and the new IPA are pending; physical iPhone acceptance remains open. The existing Build 95 IPA does not contain these repairs.

Keep the approved kraft/cream interface, existing activities and recorded data. Reuse approved energy/goal methods; repair fabricated inputs, persistence and consumers rather than tuning scientific coefficients. Algorithm 97 and schema 50 are unchanged. Build 96 uses version `0.9.63+96`; dependencies and BLE ACK ordering are unchanged.

## Implemented repairs

- [x] B95-01: commit privacy with the initial session; atomic metadata preservation and durable start.
- [x] B95-02: hydrate unread notification history on launch/resume.
- [x] B95-03: persist notification retention pruning without reload loops.
- [x] B95-04: dated historical Food notification destination.
- [x] B95-05: first-check checklist uses its own evidence weeks.
- [x] B95-06: latest individual weigh-in separate from daily-first means.
- [x] B95-07: intact Body values and full labels at enlarged text.
- [x] B95-08: readable notification action and enlarged messages.
- [x] B95-09: quiesce writers and backup publication before reset.
- [x] B95-10: stage restore media; cancellation/failure leaves no orphan photos.
- [x] B95-11: historical Sleep/Nap clock choices use stored IANA zones.
- [x] B95-12: Body retries pending stages without stale profile or duplicate readings.
- [x] B95-13: deleted-food editing preserves portion/conversion and unknown nutrients.
- [x] B95-14: deterministic same-day tape selection across consumers.
- [x] B95-15: preserve editable nutrition target precision.
- [x] B95-16: interval rounds/phase persist and use the shared active clock.
- [x] B95-17: activity-appropriate inputs; no unlogged poses or pool-derived rowing.
- [x] B95-18: picker/setup share approved active calorie estimate.
- [x] B95-19: failed final save has a truthful stopped/retry lifecycle.
- [x] B95-20: private sessions excluded from promised summary aggregates.
- [x] B95-21: reviewed last-set end bounds all retained workout evidence.
- [x] B95-22: preserve unknown-finish flag and withhold fabricated duration/energy.
- [x] B95-23: unknown activity keeps identity/reachable detail without invented MET.
- [x] B95-24: split editor shows save failure and preserves retry state.
- [x] B95-25: Body history refreshes immediate changes on return.
- [x] B95-26: dismissing away-from-Home choice does not start reminders.
- [x] B95-27: Home permission/armed status reloads on foreground.
- [x] B95-28: selected settings choices expose accessibility state.
- [x] B95-29: workout relative dates use calendar-day arithmetic across DST.

## Verification

Six new focused files contain 58 runnable regression/render cases:
- `test/build95_repair_store_test.dart`: 4 — stable unread hydration, old repeating plans, tape ties and stored-zone DST arithmetic.
- `test/build95_repair_flows_test.dart`: 19 — existing audit closures plus durable private start, failed start/reset, dated Food routes, retention, first-check weeks and latest individual weight.
- `test/build95_repair_lifecycle_test.dart`: 9 — historic sleep instants, cancelled/accepted media restore, backup/reset race, final-save retry, tape selection, private totals, older invalid traces and last-set cutoffs (including a tick that already clamped elapsed time).
- `test/build95_repair_ui_test.dart`: 8 — target precision, dirty forms, deleted-food portions, partial Body retry, active picker energy, activity-specific fields, interval reopening and Body history refresh.
- `test/build95_repair_interactions_test.dart`: 9 — DST labels, unknown activity/finish, stopped-session retry UI, split persistence failure/retry, cancelled away choice, Home permission/radius refresh and selected semantics.
- `test/build95_repair_render_test.dart`: 9 — Notifications normal/2x/3.1x and empty states; Body normal, 2x and 3.1x including 320-point width. Full vertical scroll is checked and captured; weight digits stay on one line.

15 existing checks also pass: all 7 `notification_log_test.dart` cases, both
`workout_stop_durability_test.dart` cases, and 6 selected existing automatic-backup queue,
encryption and format-2 media round-trip cases. This is targeted local verification, not a full
suite run. Focused Dart analysis of routing, lifecycle, repository, summary, Food, Body and the
interaction harness has zero errors/warnings; 12 informational lints remain.

The legacy trace repair preserves complete pre-end minute observations and clears unbounded
aggregates, re-scoring from actual bounded raw records if still present. It does not keep a
post-finish peak/strain merely because that older value was larger. New final saves and their
immediate summary read the same bounded stats. Algorithm 97 and schema 50 remain unchanged;
no scientific coefficient, dependency or ACK ordering changed. Release metadata advances to Build 96.

Local-only evidence is under this checkout's ignored `build/`: `repair-confirmation.log`,
`repair-lifecycle-final.log`, `repair-interactions-final.log`, `repair-store.log`,
`repair-existing-backup.log`, `repair-stopped-ui.log`, `repair-branch-confirmation.log`,
`repair-render-confirmation.log`, and `repair-final-analysis.log`.
`build/ui_capture/repair-review.html` contains before/after and complete scroll capture sequences.
All fixtures and captures are synthetic. The Windows render uses Manrope as a stand-in for SF;
actual iPhone typography, VoiceOver, permission delivery, BLE/GPS and suspend/kill behavior are
not proven by these renders or platform mocks.

## Integration and device gate

The backend commit is `c52cedbd`; the UI/lifecycle and regression follow-up is `88209956`.
Akshat approved the complete-page checks and assigned Codex the full integration, privacy review,
GitHub checks and IPA delivery. Release preparation is on `build-96`; existing main and Claude
checkouts are preserved. Do not treat the earlier source's passing CI or IPA as verification of
these edits. `setup.md` owns the new artifact/source evidence as each release gate completes.

The phone pass should include cold-launch unread/history and dated Food taps; a private workout
from start through history; minimise/pause/reopen intervals; stopped-save retry and corrected finish
times; Body multi-reading/profile/history behavior; saved-food fallback editing; Home Settings
return, cancellation, radius and VoiceOver choices; historical Sleep/Nap times after travel; and
backup/restore/reset on a disposable test copy. BLE/GPS background continuity and native permission
behavior remain the existing physical-device gates. Release and phone acceptance are not claimed.

## Documentation impact

`CLAUDE.md`, `todo.md`, `bugs.md`, `metrics-map.md`, `background-sync-plan.md`, `setup.md`
and the iOS guides track Build 96 preparation separately from the last reported installation.
`DESIGN.md` retains the approved layout and `README.md` retains the existing build/install
contract. Ancestor routing, dependencies, workflows, signing identity and capabilities are
unchanged. Keep the existing IPA and new repair source distinct until delivery.

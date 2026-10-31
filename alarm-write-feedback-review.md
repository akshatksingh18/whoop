# Alarm write refusal and feedback

**Status:** Two real command failures are reproduced with an authored GATT peripheral.
Akshat approved both repairs. The boolean/state repair is implemented; both unchanged
original negatives and fourteen targeted public checks pass. Cloud combined proof is pending.

## What fails

The actual AppState/FBP connection completes normally, then the scripted peripheral refuses
the requested write. No connected flag is fabricated and no real radio or alarm is used.

- Test buzz logs a failed opcode `0x44` write, but `testAlarmBuzz()` completes normally.
  The existing screen treats normal completion as success and says “Buzzing the band”.
- Cancel first has an actually saved, synthetically confirmed alarm. After a refused opcode
  `0x45` write, its local armed epoch becomes null. The screen can say “Alarm cancelled”
  although this app never delivered that cancellation.

The original two failing checks, source and complete logs are retained locally as
`cov49-alarm-write-refusal-negative_test.dart` / `cov49-alarm-negative-c-targeted.log`.
An earlier two-test harness replaced a cached FBP stream between cases; its connection failure
is preserved separately and is not app-bug evidence. The corrected harness reuses the platform
stream just as the existing GATT tests do. Physical delivery remains a phone acceptance task.

## Approved shared repair

Preserve `_send`'s existing boolean result through `BleEngine.runAlarm` and `disableAlarm`.
Their two AppState callers should refuse a false result. A refused cancel must retain the
existing local epoch, preference, confirmation/uncertainty state and grace owner. Use the
screen's existing exception feedback; do not clear the local alarm on an undelivered cancel.

Approved failure copy:

- Test buzz: **Test buzz not sent. Reconnect and retry.**
- Cancel: **Cancel not sent. Reconnect and retry.**

An accepted write keeps the existing flow. This is not proof of physical buzzing or an alarm
event. Existing pending/confirmed/unknown labels retain their meanings. Find-band's separate
best-effort boolean path remains; no pulse bytes, slot IDs, timing, automatic resend policy,
confirmation events, setting flow, persisted identity, calculation, schema or metadata changes.
Algorithm 100/protocol 1.0.1 stay. All real callers and test doubles need the matching return type.

## Complete Before/Proposed pages

The complete pages below use the unchanged production `AlarmScreenView` and its existing
feedback path. Before models the observed normal completion/false local clear; Proposed
supplies the intended exception and retains the existing armed card. No production widget,
controller or command is replaced by these static previews. Data is authored and fonts are
substituted. Expanded pages expose all content; the separate 844px views show the actual
transient overlay. At enlarged text that overlay can briefly cover lower controls, then
disappears under the existing timing; the retained controls are checked again after dismissal.

| Action / width / text | Before full page | Proposed full page | Proposed 844px viewport |
| --- | --- | --- | --- |
| Test / 390 / 1.0× | [Before](build/ownership-checkpoint/alarm-feedback-review/pulse_before_390_1.0x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_390_1.0x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_390_1.0x_viewport.png) |
| Test / 320 / 2.0× | [Before](build/ownership-checkpoint/alarm-feedback-review/pulse_before_320_2.0x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_320_2.0x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_320_2.0x_viewport.png) |
| Test / 430 / 3.1× | [Before](build/ownership-checkpoint/alarm-feedback-review/pulse_before_430_3.1x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_430_3.1x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/pulse_proposed_430_3.1x_viewport.png) |
| Cancel / 390 / 1.0× | [Before](build/ownership-checkpoint/alarm-feedback-review/cancel_before_390_1.0x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_390_1.0x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_390_1.0x_viewport.png) |
| Cancel / 320 / 2.0× | [Before](build/ownership-checkpoint/alarm-feedback-review/cancel_before_320_2.0x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_320_2.0x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_320_2.0x_viewport.png) |
| Cancel / 430 / 3.1× | [Before](build/ownership-checkpoint/alarm-feedback-review/cancel_before_430_3.1x.png) | [Proposed](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_430_3.1x.png) | [Viewport](build/ownership-checkpoint/alarm-feedback-review/cancel_proposed_430_3.1x_viewport.png) |

All twelve preview checks pass, with twelve complete pages and twelve 844px views.
`alarm-feedback-review/verified-manifest.json` owns exact hashes; earlier harness/wording
sets remain preserved locally. Source/manifests/hashes stay in ignored local recovery.
No feature, metric or navigation action becomes unreachable. No native/IPA build is authorized.
Both original behavioral negatives now pass unchanged. Fourteen targeted public checks
pass across the real AppState failure paths, both generations' wire contracts and retained
alarm retry/ownership controls. The saved preference is also asserted unchanged on refusal.
The existing AppState test double now returns the real boolean contract. Further retry/state
coverage, actual implementation captures and cloud validation remain open. The bounded alarm
workflow runs whole-candidate analysis and five retained test files on Linux Actions. Main replacement and each deletion remain at B5.

The original and prototype capture sets stay preserved. The production view/layout is unchanged;
its existing error path now receives the exact approved messages. Actual implementation
captures/whole-candidate validation and physical acceptance remain separate open gates.

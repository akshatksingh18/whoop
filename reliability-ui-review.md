# Reliability repair review

**Status:** Akshat authorized these three repairs using agent judgment. Complete synthetic
Before/After prototypes were inspected before applying the two UI fixes. The targeted UI checks pass, including
the three enabled regressions; full Linux and native acceptance are separate; native/IPA builds remain held.

## Scope

- Backup: preserve the existing keychain failure caption when a canceled/refused nested prompt
  returns no new message. All actions, copy, layout and encryption rules remain.
- Band name: let the existing form field own its controller through the dialog transition;
  preserve validation, actions and copy. Do not use a disposed messenger after command completion.
- Step tail: serialized immutable snapshots, the existing acknowledged checkpoint and idempotent
  SQLite replacement protect retry and reconnect. This has no visual change.

## Complete-page evidence

Authored test state only; Manrope substitutes for native SF. Each series reaches the bottom
with overlapping viewports at 390×844/1× and 430×932/2×. Device host/dialog before and prototype
after are pixel-identical across all ten matched frames. Backup after includes the full existing
failure caption; its extra height changes subsequent viewport positions. No metric or action is removed.
All 44 frames were inspected together; full-resolution originals follow.

The existing name character-helper line is truncated at 2× in both before and after. It is a
separate open accessibility issue, outside the dialog-lifetime fix. No physical keyboard, native
font, screen reader, keychain or BLE behavior is certified by these synthetic pages.

## Before

- [cov46_before_backup_refusal_1.0x_0](build/ui_capture/cov46_before_backup_refusal_1.0x_0.png)
- [cov46_before_backup_refusal_1.0x_1](build/ui_capture/cov46_before_backup_refusal_1.0x_1.png)
- [cov46_before_backup_refusal_1.0x_2](build/ui_capture/cov46_before_backup_refusal_1.0x_2.png)
- [cov46_before_backup_refusal_2.0x_0](build/ui_capture/cov46_before_backup_refusal_2.0x_0.png)
- [cov46_before_backup_refusal_2.0x_1](build/ui_capture/cov46_before_backup_refusal_2.0x_1.png)
- [cov46_before_backup_refusal_2.0x_2](build/ui_capture/cov46_before_backup_refusal_2.0x_2.png)
- [cov46_before_backup_refusal_2.0x_3](build/ui_capture/cov46_before_backup_refusal_2.0x_3.png)
- [cov46_before_backup_refusal_2.0x_4](build/ui_capture/cov46_before_backup_refusal_2.0x_4.png)
- [cov46_before_backup_refusal_2.0x_5](build/ui_capture/cov46_before_backup_refusal_2.0x_5.png)
- [cov46_before_backup_refusal_2.0x_6](build/ui_capture/cov46_before_backup_refusal_2.0x_6.png)
- [cov46_before_backup_refusal_2.0x_7](build/ui_capture/cov46_before_backup_refusal_2.0x_7.png)
- [cov46_before_device_host_1.0x_0](build/ui_capture/cov46_before_device_host_1.0x_0.png)
- [cov46_before_device_host_1.0x_1](build/ui_capture/cov46_before_device_host_1.0x_1.png)
- [cov46_before_device_host_2.0x_0](build/ui_capture/cov46_before_device_host_2.0x_0.png)
- [cov46_before_device_host_2.0x_1](build/ui_capture/cov46_before_device_host_2.0x_1.png)
- [cov46_before_device_host_2.0x_2](build/ui_capture/cov46_before_device_host_2.0x_2.png)
- [cov46_before_name_dialog_1.0x_0](build/ui_capture/cov46_before_name_dialog_1.0x_0.png)
- [cov46_before_name_dialog_1.0x_1](build/ui_capture/cov46_before_name_dialog_1.0x_1.png)
- [cov46_before_name_dialog_2.0x_0](build/ui_capture/cov46_before_name_dialog_2.0x_0.png)
- [cov46_before_name_dialog_2.0x_1](build/ui_capture/cov46_before_name_dialog_2.0x_1.png)
- [cov46_before_name_dialog_2.0x_2](build/ui_capture/cov46_before_name_dialog_2.0x_2.png)

## After

- [cov46_after_backup_refusal_1.0x_0](build/ui_capture/cov46_after_backup_refusal_1.0x_0.png)
- [cov46_after_backup_refusal_1.0x_1](build/ui_capture/cov46_after_backup_refusal_1.0x_1.png)
- [cov46_after_backup_refusal_1.0x_2](build/ui_capture/cov46_after_backup_refusal_1.0x_2.png)
- [cov46_after_backup_refusal_1.0x_3](build/ui_capture/cov46_after_backup_refusal_1.0x_3.png)
- [cov46_after_backup_refusal_2.0x_0](build/ui_capture/cov46_after_backup_refusal_2.0x_0.png)
- [cov46_after_backup_refusal_2.0x_1](build/ui_capture/cov46_after_backup_refusal_2.0x_1.png)
- [cov46_after_backup_refusal_2.0x_2](build/ui_capture/cov46_after_backup_refusal_2.0x_2.png)
- [cov46_after_backup_refusal_2.0x_3](build/ui_capture/cov46_after_backup_refusal_2.0x_3.png)
- [cov46_after_backup_refusal_2.0x_4](build/ui_capture/cov46_after_backup_refusal_2.0x_4.png)
- [cov46_after_backup_refusal_2.0x_5](build/ui_capture/cov46_after_backup_refusal_2.0x_5.png)
- [cov46_after_backup_refusal_2.0x_6](build/ui_capture/cov46_after_backup_refusal_2.0x_6.png)
- [cov46_after_backup_refusal_2.0x_7](build/ui_capture/cov46_after_backup_refusal_2.0x_7.png)
- [cov46_after_backup_refusal_2.0x_8](build/ui_capture/cov46_after_backup_refusal_2.0x_8.png)
- [cov46_after_device_host_1.0x_0](build/ui_capture/cov46_after_device_host_1.0x_0.png)
- [cov46_after_device_host_1.0x_1](build/ui_capture/cov46_after_device_host_1.0x_1.png)
- [cov46_after_device_host_2.0x_0](build/ui_capture/cov46_after_device_host_2.0x_0.png)
- [cov46_after_device_host_2.0x_1](build/ui_capture/cov46_after_device_host_2.0x_1.png)
- [cov46_after_device_host_2.0x_2](build/ui_capture/cov46_after_device_host_2.0x_2.png)
- [cov46_after_name_dialog_1.0x_0](build/ui_capture/cov46_after_name_dialog_1.0x_0.png)
- [cov46_after_name_dialog_1.0x_1](build/ui_capture/cov46_after_name_dialog_1.0x_1.png)
- [cov46_after_name_dialog_2.0x_0](build/ui_capture/cov46_after_name_dialog_2.0x_0.png)
- [cov46_after_name_dialog_2.0x_1](build/ui_capture/cov46_after_name_dialog_2.0x_1.png)
- [cov46_after_name_dialog_2.0x_2](build/ui_capture/cov46_after_name_dialog_2.0x_2.png)

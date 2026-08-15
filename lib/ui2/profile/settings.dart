// Settings, and editing the profile.
//
// Two deliberate departures from the reference design:
//
//   · "Log out" is "Reset all data". Logging out of an app with no server is
//     theatre — it clears a session that does not exist while leaving every
//     byte on disk. The destructive action here is the honest one, and it says
//     what it destroys.
//   · Email, username, bio, location and date of birth are gone from the edit
//     form. None of them feed a metric, and a field that changes nothing is a
//     field that implies an account.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../../state/units_controller.dart';
import '../../theme/theme_controller.dart';
import '../ui2.dart';
import 'profile.dart';

// ══════════════════ MORE SETTINGS ══════════════════

class MoreSettings extends StatelessWidget {
  const MoreSettings({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final units = c.watch<UnitsController>();
    final theme = c.watch<ThemeController>();
    return MoreSettingsView(
      units: units.system.label,
      appearance: theme.choice.label,
      phoneSteps: app.phoneStepsEnabled,
      telemetry: app.telemetryConsent,
      onEditProfile: () => goto(c, const EditProfile()),
      onCycleUnits: () => units.setSystem(units.isImperial
          ? UnitSystem.metric
          : UnitSystem.imperial),
      onCycleAppearance: () => theme.setChoice(AppThemeChoice.values[
          (theme.choice.index + 1) % AppThemeChoice.values.length]),
      onTogglePhoneSteps: () => app.phoneStepsEnabled
          ? app.disablePhoneSteps()
          : app.requestPhoneSteps(),
      onToggleTelemetry: () => app.setTelemetryConsent(!app.telemetryConsent),
      onReset: () => _confirmReset(c, app),
    );
  }
}

Future<void> _confirmReset(BuildContext c, AppState app) async {
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: const Text('Reset all data?'),
      content: const Text(
        'Every measured day, session and profile field on this phone is '
        'deleted, and the band is unpaired. There is no copy anywhere else — '
        'export first if you want one.',
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Keep my data')),
        TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Delete everything')),
      ],
    ),
  );
  if (ok != true) return;
  final repo = app.repo;
  if (repo != null) {
    final days = await repo.availableDays();
    if (days.isNotEmpty) await app.deleteDays(days.toSet());
  }
  await app.signOut();
}

class MoreSettingsView extends StatelessWidget {
  final String units, appearance;
  final bool phoneSteps, telemetry;
  final VoidCallback? onEditProfile,
      onCycleUnits,
      onCycleAppearance,
      onTogglePhoneSteps,
      onToggleTelemetry,
      onReset;

  const MoreSettingsView({
    super.key,
    this.units = 'Metric',
    this.appearance = 'System',
    this.phoneSteps = false,
    this.telemetry = false,
    this.onEditProfile,
    this.onCycleUnits,
    this.onCycleAppearance,
    this.onTogglePhoneSteps,
    this.onToggleTelemetry,
    this.onReset,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Settings'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                settingsGroup(c, 'You', [
                  SetRow(LucideIcons.userPen, C.purple, 'Edit profile',
                      sub: 'Sex, age, height, weight', onTap: onEditProfile),
                ]),
                settingsGroup(c, 'Preferences', [
                  SetRow(LucideIcons.ruler, C.blue, 'Units',
                      value: units, onTap: onCycleUnits),
                  SetRow(LucideIcons.sun, C.yellow, 'Appearance',
                      value: appearance, onTap: onCycleAppearance),
                  SetRow(LucideIcons.footprints, C.teal, 'Phone steps',
                      sub: 'The band cannot count steps at 1 Hz',
                      value: phoneSteps ? 'On' : 'Off',
                      onTap: onTogglePhoneSteps),
                ]),
                settingsGroup(c, 'Privacy', [
                  SetRow(LucideIcons.bug, C.orange, 'Crash reports',
                      sub: 'Off by default. Nothing is sent until you say so',
                      value: telemetry ? 'On' : 'Off',
                      onTap: onToggleTelemetry),
                ]),
                const SizedBox(height: S.x6),
                Surface(
                  pad: const EdgeInsets.symmetric(horizontal: S.x4),
                  child: SetRow(LucideIcons.trash2, C.red, 'Reset all data',
                      danger: true, chevron: false, onTap: onReset),
                ),
                const SizedBox(height: S.x3),
                Center(
                  child: Text('No account to sign out of.',
                      style: F.over.copyWith(color: p.ink3)),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

// ══════════════════ EDIT PROFILE ══════════════════

class EditProfile extends StatelessWidget {
  const EditProfile({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.read<AppState>();
    return EditProfileView(
      initial: app.user ?? const {},
      onSave: (fields) async {
        // A field the user CLEARED must be removed, not merged over — the
        // profile map is a merge, so writing only what is present would keep
        // a stale value alive and score the day against a body that is no
        // longer described.
        await app.updateProfile({
          for (final k in const ['name', 'sex', 'age', 'height_cm', 'weight_kg'])
            k: fields[k],
        });
        if (c.mounted) Navigator.of(c).maybePop();
      },
    );
  }
}

class EditProfileView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  const EditProfileView(
      {super.key, required this.onSave, this.initial = const {}});

  @override
  State<EditProfileView> createState() => _EditProfileViewState();
}

class _EditProfileViewState extends State<EditProfileView> {
  late final _name =
      TextEditingController(text: '${widget.initial['name'] ?? ''}');
  late final _age =
      TextEditingController(text: _s(widget.initial['age']));
  late final _height =
      TextEditingController(text: _s(widget.initial['height_cm']));
  late final _weight =
      TextEditingController(text: _s(widget.initial['weight_kg']));
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();

  static String _s(Object? v) => v == null ? '' : '$v';

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Edit profile',
                trailing: Pressable(
                  semanticLabel: 'Save',
                  onTap: () => widget.onSave({
                    'name': _name.text.trim().isEmpty ? null : _name.text.trim(),
                    'sex': _sex,
                    'age': num.tryParse(_age.text.trim())?.round(),
                    'height_cm': num.tryParse(_height.text.trim())?.toDouble(),
                    'weight_kg': num.tryParse(_weight.text.trim())?.toDouble(),
                  }),
                  child: Text('Save',
                      style: F.body.copyWith(
                          color: p.on(C.green), fontWeight: FontWeight.w600)),
                )),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                _text(c, _name, 'NAME', TextInputType.name),
                const SizedBox(height: S.x4),
                Text('SEX', style: F.over.copyWith(color: p.ink3)),
                const SizedBox(height: S.x2),
                Wrap(spacing: S.x2, runSpacing: S.x2, children: [
                  for (final (key, label) in const [
                    ('m', 'Male'),
                    ('f', 'Female'),
                    ('other', 'Prefer not to say'),
                  ])
                    Pressable(
                      onTap: () => setState(() => _sex = key),
                      semanticLabel: label,
                      child: Container(
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(
                            horizontal: S.x4, vertical: S.x2),
                        decoration: BoxDecoration(
                          color: _sex == key ? p.wash(C.green) : p.card,
                          borderRadius: R.rPill,
                          border: Border.all(
                              color: _sex == key ? p.on(C.green) : p.line),
                        ),
                        child: Text(label,
                            style: F.cap.copyWith(
                                color: _sex == key ? p.on(C.green) : p.ink2)),
                      ),
                    ),
                ]),
                const SizedBox(height: S.x4),
                _text(c, _age, 'AGE (YEARS)', TextInputType.number),
                const SizedBox(height: S.x4),
                _text(c, _height, 'HEIGHT (CM)', TextInputType.number),
                const SizedBox(height: S.x4),
                _text(c, _weight, 'WEIGHT (KG)', TextInputType.number),
                const SizedBox(height: S.x6),
                const StatusCard(
                  'These four change your numbers',
                  'They feed heart-rate zones, calorie estimates and training '
                      'load. Clear one and only the metrics that need it stay '
                      'unavailable — nothing is guessed in its place.',
                  icon: LucideIcons.info,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _text(BuildContext c, TextEditingController ctl, String label,
      TextInputType kind) {
    final p = P.of(c);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: F.over.copyWith(color: p.ink3)),
      TextField(
        controller: ctl,
        keyboardType: kind,
        style: F.head.copyWith(color: p.ink),
        decoration: InputDecoration(
          hintText: 'Not set',
          hintStyle: F.head.copyWith(color: p.ink3),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: S.x3),
          enabledBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: p.line)),
          focusedBorder:
              UnderlineInputBorder(borderSide: BorderSide(color: p.on(C.green))),
        ),
      ),
    ]);
  }
}

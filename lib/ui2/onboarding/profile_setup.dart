// Profile setup.
//
// The audit found this screen promising one thing and enforcing another: the
// copy said "leave a field blank and only that metric stays unknown — never
// guessed", and the validator then refused to continue until all four were
// filled. A promise the form contradicts is worse than no promise, because it
// teaches the user that the honesty copy elsewhere is decoration too.
//
// So: every field is optional except sex, which is the one input with no
// honest default — the analytics coefficient tables key on it and the
// midpoint of two sexes is a third person. Everything else that is blank
// simply withholds the metrics that need it.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../ui2.dart';

class ProfileSetupScreen extends StatefulWidget {
  /// Called after the profile has been written. The router uses it to let a
  /// deliberately-partial profile through the gate.
  final VoidCallback? onDone;

  const ProfileSetupScreen({super.key, this.onDone});

  @override
  State<ProfileSetupScreen> createState() => _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends State<ProfileSetupScreen> {
  @override
  Widget build(BuildContext c) {
    final app = context.read<AppState>();
    return ProfileSetupView(
      initial: app.user ?? const {},
      onSave: (fields) async {
        await app.updateProfile(fields);
        widget.onDone?.call();
      },
    );
  }
}

/// The three sexes the analytics coefficient tables define. 'other' maps to
/// the non-binary block — the published mean of the two sex constants — which
/// is a stated choice, not a guess at one of them.
const _sexes = <(String, String)>[
  ('m', 'Male'),
  ('f', 'Female'),
  ('other', 'Prefer not to say'),
];

class ProfileSetupView extends StatefulWidget {
  final Map<String, dynamic> initial;
  final Future<void> Function(Map<String, dynamic> fields) onSave;

  const ProfileSetupView(
      {super.key, required this.onSave, this.initial = const {}});

  @override
  State<ProfileSetupView> createState() => _ProfileSetupViewState();
}

class _ProfileSetupViewState extends State<ProfileSetupView> {
  late String? _sex = (widget.initial['sex'] as String?)?.toLowerCase();
  late final _age = TextEditingController(text: _str(widget.initial['age']));
  late final _height =
      TextEditingController(text: _str(widget.initial['height_cm']));
  late final _weight =
      TextEditingController(text: _str(widget.initial['weight_kg']));

  static String _str(Object? v) => v == null ? '' : '$v';

  @override
  void dispose() {
    _age.dispose();
    _height.dispose();
    _weight.dispose();
    super.dispose();
  }

  /// Only what was actually entered. A blank field writes nothing, so the
  /// dependent metric abstains rather than scoring somebody else's body.
  Map<String, dynamic> _fields() => {
        if (_sex != null) 'sex': _sex,
        if (num.tryParse(_age.text.trim()) != null)
          'age': num.parse(_age.text.trim()).round(),
        if (num.tryParse(_height.text.trim()) != null)
          'height_cm': num.parse(_height.text.trim()).toDouble(),
        if (num.tryParse(_weight.text.trim()) != null)
          'weight_kg': num.parse(_weight.text.trim()).toDouble(),
      };

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x6, S.x4, S.x8),
          children: [
            Text('About you', style: F.t1.copyWith(color: p.ink)),
            const SizedBox(height: S.x3),
            Text(
              'Four numbers change how your data is scored. Leave any of them '
              'blank and only the metrics that need it stay unavailable.',
              style: F.body.copyWith(color: p.ink2),
            ),
            const SizedBox(height: S.x6),
            Text('SEX', style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Row(children: [
              for (final (key, label) in _sexes) ...[
                Expanded(
                  child: _Choice(
                    label: label,
                    on: _sex == key,
                    onTap: () => setState(() => _sex = key),
                  ),
                ),
                if (key != _sexes.last.$1) const SizedBox(width: S.x2),
              ],
            ]),
            const SizedBox(height: S.x5),
            _Field(_age, 'AGE', 'years',
                'Without it: heart-rate zones, calories, fitness age.'),
            _Field(_height, 'HEIGHT', 'cm',
                'Without it: stride length, and distance from steps.'),
            _Field(_weight, 'WEIGHT', 'kg',
                'Without it: calories and training load.'),
            const SizedBox(height: S.x5),
            BigButton('Continue',
                color: C.green,
                onTap: _sex == null
                    ? null
                    : () async {
                        await widget.onSave(_fields());
                      }),
            if (_sex == null) ...[
              const SizedBox(height: S.x2),
              Text('Pick one option above to continue.',
                  style: F.cap.copyWith(color: p.ink3)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  const _Choice({required this.label, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: label,
      child: Container(
        constraints: const BoxConstraints(minHeight: S.tap),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x2),
        decoration: BoxDecoration(
          color: on ? p.wash(C.green) : p.card,
          borderRadius: R.rMd,
          border: Border.all(color: on ? p.on(C.green) : p.line),
        ),
        child: Text(label,
            textAlign: TextAlign.center,
            style: F.cap.copyWith(
                color: on ? p.on(C.green) : p.ink2,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label, unit, consequence;
  const _Field(this.controller, this.label, this.unit, this.consequence);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(bottom: S.x4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(label, style: F.over.copyWith(color: p.ink3))),
          Text('OPTIONAL', style: F.over.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x1),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: F.head.copyWith(color: p.ink),
          decoration: InputDecoration(
            hintText: unit,
            hintStyle: F.head.copyWith(color: p.ink3),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(vertical: S.x3),
            enabledBorder:
                UnderlineInputBorder(borderSide: BorderSide(color: p.line)),
            focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: p.on(C.green))),
          ),
        ),
        const SizedBox(height: S.x1),
        Text(consequence, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

// ══════════════════ THE DAY-0 CONTRACT ══════════════════

/// What day zero is allowed to show.
///
/// A recovery score on the first morning is a fabrication — there is no
/// baseline to be recovered relative to. So the headline metric is shown
/// LOCKED, with the exact date it opens and the exact count of nights banked,
/// next to the one number that is honest and instant: live heart rate off the
/// band right now.
///
/// [have] and [need] come from the analytics `need_baseline:have=H,need=N`
/// note that already rides on the abstaining metric — nothing new is computed
/// to draw this.
class UnlockContract extends StatelessWidget {
  final String metric;
  final int have;
  final int need;

  /// Live heart rate from the band, or null when nothing is streaming.
  final int? liveHr;

  /// Injectable so the golden is not a function of the calendar.
  final DateTime? now;

  const UnlockContract({
    super.key,
    required this.metric,
    required this.have,
    required this.need,
    this.liveHr,
    this.now,
  });

  /// The date the metric opens: one night per remaining night, from today.
  static DateTime unlockDate(DateTime from, int have, int need) =>
      DateTime(from.year, from.month, from.day + (need - have).clamp(0, 3650));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final today = now ?? DateTime.now();
    final open = unlockDate(today, have, need);
    final hr = liveHr;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(LucideIcons.lock, size: 16, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(metric,
                style: F.body
                    .copyWith(color: p.ink2, fontWeight: FontWeight.w600)),
          ),
        ]),
        const SizedBox(height: S.x2),
        Text('Opens ${formatDay(open)}', style: F.n24.copyWith(color: p.ink)),
        const SizedBox(height: S.x1),
        Text('$have of $need nights banked',
            style: F.cap.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        ClipRRect(
          borderRadius: R.rPill,
          child: LinearProgressIndicator(
            value: need == 0 ? 0 : (have / need).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: p.track,
            valueColor: AlwaysStoppedAnimation<Color>(p.on(C.green)),
          ),
        ),
        const SizedBox(height: S.x4),
        Divider(color: p.line, height: 1),
        const SizedBox(height: S.x4),
        Row(children: [
          Icon(LucideIcons.heartPulse, size: 18, color: p.on(C.red)),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text('Heart rate, right now',
                style: F.cap.copyWith(color: p.ink2)),
          ),
          if (hr != null && hr > 0) ...[
            Text('$hr', style: F.n24.copyWith(color: p.ink)),
            const SizedBox(width: S.x1),
            Text('bpm', style: F.cap.copyWith(color: p.ink3)),
          ] else
            Text('Band not streaming', style: F.cap.copyWith(color: p.ink3)),
        ]),
      ]),
    );
  }
}

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Thu 4 Sep" — a date a person can hold, not an ISO string. Local by
/// construction; the app's day labels are local everywhere.
String formatDay(DateTime d) =>
    '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}';

// Journal — the one place a day's self-report is written.
//
// Mood, water, caffeine and alcohol are NOT new concepts here: they are
// existing `journal_metric` fields (`lib/data/journal_fields.dart`), and this
// screen is their editor. A parallel "wellness log" model would have split the
// correlation engine's inputs in half for no gain.
//
// Ratings are 1–5 and doses are stepped, both straight off the field spec —
// the ceiling exists so one mis-tap cannot enter forty coffees and dominate
// every correlation that field appears in for months.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../ai/journal_ai.dart' show kJournalPresetTags;
import '../../data/day_label.dart';
import '../../data/journal_fields.dart';
import '../../state/app_state.dart';
import '../ui2.dart';

class JournalCompose extends StatefulWidget {
  const JournalCompose({super.key, this.date});

  /// The day being written. Defaults to today's LOCAL label — never a UTC one.
  final String? date;

  @override
  State<JournalCompose> createState() => _JournalComposeState();
}

class _JournalComposeState extends State<JournalCompose> {
  late final String _date = widget.date ?? todayLabel();
  final _note = TextEditingController();

  List<JournalFieldSpec> _specs = const [];
  Map<String, JournalMetricValue> _values = {};
  Set<String> _tags = {};
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final specs = await repo.getJournalFields();
    final values = await repo.getJournalMetrics(_date);
    final entries = await repo.getJournal(range: '30d');
    Map<String, dynamic>? today;
    for (final e in entries) {
      if (e['date'] == _date) today = e;
    }
    if (!mounted) return;
    setState(() {
      _specs = specs;
      _values = {...values};
      _tags = {...?(today?['tags'] as List?)?.map((t) => t.toString())};
      _note.text = (today?['note'] as String?) ?? '';
      _loading = false;
    });
  }

  void _set(String key, double? v) {
    setState(() {
      if (v == null) {
        _values.remove(key);
      } else {
        _values[key] = JournalMetricValue(
          v,
          atMinuteOfDay: _values[key]?.atMinuteOfDay,
        );
      }
    });
  }

  Future<void> _save() async {
    final repo = context.read<AppState>().repo;
    if (repo == null) return;
    setState(() => _saving = true);
    await repo.postJournalMetrics(_date, _values);
    await repo.postJournal(_date, _tags.toList(), _note.text.trim());
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            NavBar(
              'Journal',
              sub: _date,
              onBack: () => Navigator.of(c).pop(),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x8),
                      children: [
                        MoodPicker(
                          value: _values['mood']?.value.round(),
                          onChanged: (v) => _set('mood', v.toDouble()),
                        ),
                        Section(
                          'Today',
                          Surface(
                            pad: const EdgeInsets.symmetric(horizontal: S.x4),
                            child: Column(
                              children: [
                                for (final s in _specs.where(
                                  (s) => s.key != 'mood',
                                ))
                                  FieldStepper(
                                    spec: s,
                                    value: _values[s.key]?.value,
                                    onChanged: (v) => _set(s.key, v),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        Section(
                          'What happened',
                          Wrap(
                            spacing: S.x2,
                            runSpacing: S.x2,
                            children: [
                              for (final t in kJournalPresetTags)
                                Pressable(
                                  onTap: () => setState(
                                    () => _tags.contains(t)
                                        ? _tags.remove(t)
                                        : _tags.add(t),
                                  ),
                                  child: Pill(
                                    t,
                                    _tags.contains(t) ? C.domMind : C.n400,
                                    icon: _tags.contains(t)
                                        ? LucideIcons.check
                                        : null,
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: S.x5),
                        OsTextField(
                          controller: _note,
                          label: 'Anything else',
                          hint: 'A line about the day.',
                          lines: 4,
                        ),
                        const SizedBox(height: S.x6),
                        BigButton(
                          _saving ? 'Saving' : 'Save',
                          icon: LucideIcons.check,
                          color: C.domMind,
                          onTap: _saving ? null : _save,
                        ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The 1–5 self-report. Five faces, not ten: a ten-point self-report is not
/// ten distinguishable states, and the extra resolution is noise a rank
/// correlation then has to see through.
class MoodPicker extends StatelessWidget {
  const MoodPicker({super.key, this.value, required this.onChanged});

  final int? value;
  final ValueChanged<int> onChanged;

  static const _faces = [
    LucideIcons.frown,
    LucideIcons.annoyed,
    LucideIcons.meh,
    LucideIcons.smile,
    LucideIcons.laugh,
  ];
  static const _tints = [C.red, C.orange, C.yellow, C.green, C.green];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'How are you feeling?',
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: S.x1),
          Text(
            value == null
                ? 'Not answered yet'
                : 'Mood $value of 5',
            style: F.cap.copyWith(color: p.ink3),
          ),
          const SizedBox(height: S.x4),
          Row(
            children: [
              for (var i = 0; i < 5; i++) ...[
                Expanded(
                  child: Pressable(
                    semanticLabel: 'Mood ${i + 1} of 5',
                    onTap: () => onChanged(i + 1),
                    child: AnimatedContainer(
                      duration: motion(c, Motion.base),
                      height: S.tap,
                      decoration: BoxDecoration(
                        borderRadius: R.rMd,
                        color: value == i + 1
                            ? p.fill(_tints[i])
                            : p.wash(_tints[i]),
                      ),
                      child: Icon(
                        _faces[i],
                        size: 22,
                        color: value == i + 1 ? p.inkOnFill : p.on(_tints[i]),
                      ),
                    ),
                  ),
                ),
                if (i < 4) const SizedBox(width: S.x2),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// One journal field as a stepper. Handles ratings and doses from the same
/// spec — the difference is only the step size and the ceiling.
class FieldStepper extends StatelessWidget {
  const FieldStepper({
    super.key,
    required this.spec,
    required this.value,
    required this.onChanged,
  });

  final JournalFieldSpec spec;

  /// Null means the field was left blank, which is NOT zero: "no caffeine
  /// today" is a logged zero, "did not say" is an absence.
  final double? value;
  final ValueChanged<double?> onChanged;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.label, style: F.body.copyWith(color: p.ink)),
                Text(
                  v == null ? 'Not logged' : spec.formatWithUnit(v),
                  style: F.over.copyWith(color: p.ink3),
                ),
              ],
            ),
          ),
          _Step(
            icon: LucideIcons.minus,
            enabled: v != null && v > 0,
            onTap: () {
              final next = (v ?? 0) - spec.step;
              onChanged(next <= 0 ? (v == 0 ? null : 0) : next);
            },
          ),
          const SizedBox(width: S.x2),
          _Step(
            icon: LucideIcons.plus,
            enabled: v == null || v < spec.max,
            onTap: () =>
                onChanged(((v ?? 0) + spec.step).clamp(0, spec.max).toDouble()),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.icon, required this.enabled, required this.onTap});
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: icon == LucideIcons.plus ? 'Increase' : 'Decrease',
      onTap: enabled ? onTap : null,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
        child: Icon(icon, size: 16, color: enabled ? p.ink2 : p.ink3),
      ),
    );
  }
}

/// The app's one text input. Lives here rather than in `grammar.dart` because
/// exactly two screens type into anything — a journal note and a medication
/// name.
class OsTextField extends StatelessWidget {
  const OsTextField({
    super.key,
    required this.controller,
    required this.label,
    this.hint = '',
    this.lines = 1,
    this.keyboard,
  });

  final TextEditingController controller;
  final String label;
  final String hint;
  final int lines;
  final TextInputType? keyboard;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: S.x3,
            vertical: S.x2,
          ),
          decoration: BoxDecoration(
            color: p.card,
            borderRadius: R.rMd,
            border: Border.all(color: p.line),
          ),
          // The label is drawn as a sibling `Text`, which a screen reader reads
          // on the way past and then forgets. Focused, the field itself
          // announced only its HINT — and the hint disappears the moment the
          // user types, leaving "text field" with no way to ask what it is for.
          child: Semantics(
            label: label,
            textField: true,
            child: TextField(
              controller: controller,
              maxLines: lines,
              minLines: 1,
              keyboardType: keyboard,
              style: F.body.copyWith(color: p.ink),
              cursorColor: p.on(C.domMind),
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: F.body.copyWith(color: p.ink3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

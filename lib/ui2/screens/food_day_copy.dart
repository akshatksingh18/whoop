import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'food_diary.dart' show askText, dayTitle;
import 'food_picker.dart' show mealName;
import 'home_screen.dart' show thousands;
import 'metric_detail.dart' show detailScaffold;

/// A full review with one explicit write action; cancel never calls [onLog].
Future<bool?> reviewFoodDayCopy(
  BuildContext c, {
  required String from,
  required String to,
  required List<FoodEntry> entries,
  required Future<void> Function(List<FoodEntry>) onLog,
}) => Navigator.of(c).push<bool>(
  MaterialPageRoute(
    builder: (_) =>
        _FoodDayCopyReview(from: from, to: to, entries: entries, onLog: onLog),
  ),
);

class _FoodDayCopyReview extends StatefulWidget {
  const _FoodDayCopyReview({
    required this.from,
    required this.to,
    required this.entries,
    required this.onLog,
  });
  final String from, to;
  final List<FoodEntry> entries;
  final Future<void> Function(List<FoodEntry>) onLog;
  @override
  State<_FoodDayCopyReview> createState() => _FoodDayCopyReviewState();
}

class _FoodDayCopyReviewState extends State<_FoodDayCopyReview> {
  late final _selected = List.filled(widget.entries.length, true);
  late final _factors = List.filled(widget.entries.length, 1.0);
  bool _saving = false;
  String? _error;
  Future<void> _portion(int i) async {
    final text = await askText(
      context,
      'Portion of ${widget.entries[i].label}',
      'Portion (1 = as logged, 0.5 = half)',
      editableNumber(_factors[i]),
      keyboard: const TextInputType.numberWithOptions(decimal: true),
      validate: (v) {
        final n = double.tryParse(v);
        return n == null || !n.isFinite || n <= 0
            ? 'Enter a portion above zero.'
            : null;
      },
    );
    if (text == null || !mounted) return;
    try {
      final n = double.parse(text);
      widget.entries[i].scaledPortion(n);
      setState(() {
        _factors[i] = n;
        _error = null;
      });
    } catch (_) {
      setState(
        () => _error = 'That portion is too large. Enter a smaller amount.',
      );
    }
  }

  Future<void> _log() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final reviewed = [
        for (var i = 0; i < widget.entries.length; i++)
          if (_selected[i]) widget.entries[i].scaledPortion(_factors[i]),
      ];
      if (reviewed.isEmpty) {
        setState(() => _saving = false);
        return;
      }
      await widget.onLog(reviewed);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted)
        setState(() {
          _saving = false;
          _error =
              'Food was not copied. Your review is here; try logging again.';
        });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c), any = _selected.any((x) => x);
    final picked = [
      for (var i = 0; i < widget.entries.length; i++)
        if (_selected[i]) widget.entries[i].scaledPortion(_factors[i]),
    ];
    final known = [for (final e in picked) ?e.kcal];
    final total = known.fold<double>(0, (a, v) => a + v);
    String factor(double f) => '${editableNumber(f)}×';
    return detailScaffold(c, 'Copy a day', [
      Text(
        'From ${dayTitle(widget.from)} into ${dayTitle(widget.to)}',
        style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: S.x1),
      Text(
        'Untick anything you do not want, or change a portion.',
        style: F.cap.copyWith(color: p.ink2),
      ),
      const SizedBox(height: S.x3),
      if (widget.entries.isEmpty)
        const StatusCard(
          'Nothing to copy',
          'No food is logged on that day.',
          icon: LucideIcons.utensils,
        )
      else
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (var i = 0; i < widget.entries.length; i++) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                _row(c, p, i, factor),
              ],
            ],
          ),
        ),
      if (_error != null) ...[
        const SizedBox(height: S.x3),
        Text(_error!, style: F.cap.copyWith(color: p.on(C.alert))),
      ],
      const SizedBox(height: S.x5),
      BigButton(
        _saving
            ? 'Copying…'
            : picked.isEmpty
            ? 'Nothing selected'
            : 'Copy ${picked.length} item${picked.length == 1 ? '' : 's'}'
                  '${known.isEmpty ? '' : ' · ${known.length < picked.length ? '≥ ' : ''}${thousands(total)} kcal'}',
        icon: LucideIcons.copy,
        color: C.domFood,
        onTap: _saving || !any ? null : _log,
      ),
    ]);
  }

  Widget _row(BuildContext c, P p, int i, String Function(double) factor) {
    final e = widget.entries[i];
    final on = _selected[i];
    final kcal = e.scaledPortion(_factors[i]).kcal;
    return Row(
      children: [
        Expanded(
          child: Pressable(
            semanticLabel: '${e.label}, ${on ? 'selected' : 'not selected'}',
            onTap: _saving ? null : () => setState(() => _selected[i] = !on),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.x3),
              child: Row(
                children: [
                  Icon(
                    on ? LucideIcons.squareCheck : LucideIcons.square,
                    size: 20,
                    color: on ? p.on(C.domFood) : p.ink3,
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.label, style: F.body.copyWith(color: p.ink)),
                        Text(
                          '${mealName(e.meal)} · '
                          '${kcal == null ? 'calories unknown' : '${kcal.round()} kcal'}',
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Pressable(
          semanticLabel: 'Portion of ${e.label}, ${factor(_factors[i])}',
          onTap: _saving || !on ? null : () => _portion(i),
          child: Pill(factor(_factors[i]), on ? C.domFood : C.n400),
        ),
      ],
    );
  }
}

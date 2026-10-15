import 'package:flutter/material.dart';
import '../../data/nutrition_store.dart';
import '../theme.dart';
import 'food_diary.dart' show askText;
import 'food_picker.dart' show mealName;

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
      'Multiplier (1 = original, 0.5 = half)',
      _factors[i].toString(),
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
    return Scaffold(
      appBar: AppBar(title: const Text('Copy a food day')),
      body: ListView(
        padding: const EdgeInsets.all(S.x4),
        children: [
          Text(
            'From ${widget.from} · Into ${widget.to}',
            style: F.body.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Text(
            'Review every item. Adjust portions or untick anything you do not want.',
            style: F.cap.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x3),
          if (widget.entries.isEmpty)
            Text(
              'No food logged on that date.',
              style: F.body.copyWith(color: p.ink),
            ),
          for (var i = 0; i < widget.entries.length; i++) ...[
            CheckboxListTile(
              value: _selected[i],
              onChanged: _saving
                  ? null
                  : (v) => setState(() => _selected[i] = v ?? false),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: Text(widget.entries[i].label),
              subtitle: Text(
                '${mealName(widget.entries[i].meal)} · ${_factors[i]}× portion · '
                '${widget.entries[i].scaledPortion(_factors[i]).kcal?.round() ?? 'unknown'} kcal',
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: _saving ? null : () => _portion(i),
                child: Text('Adjust portion: ${widget.entries[i].label}'),
              ),
            ),
            Divider(color: p.line),
          ],
          if (_error != null)
            Text(_error!, style: F.body.copyWith(color: p.on(C.alert))),
          const SizedBox(height: S.x3),
          FilledButton(
            onPressed: _saving || !any ? null : _log,
            child: Text(_saving ? 'Logging…' : 'Log into ${widget.to}'),
          ),
          TextButton(
            onPressed: _saving ? null : () => Navigator.of(c).pop(false),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

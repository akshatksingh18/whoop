import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../data/db.dart';
import '../../data/nutrition_store.dart';
import '../ui2.dart';
import 'food_diary.dart' show askText;
import 'food_picker.dart' show PickRow;

/// Optional destination selected before any food write.
class MealGroupPicker extends StatefulWidget {
  const MealGroupPicker({
    super.key,
    required this.date,
    required this.meal,
    required this.group,
    required this.onChanged,
  });
  final String date, meal, group;
  final ValueChanged<String> onChanged;
  @override
  State<MealGroupPicker> createState() => _MealGroupPickerState();
}

class _MealGroupPickerState extends State<MealGroupPicker> {
  bool _busy = false;
  Future<void> _pick() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final entries = await NutritionDb.entriesForDay(
        await LocalDb.instance,
        widget.date,
      );
      final groups = {
        if (widget.group.isNotEmpty) widget.group,
        for (final e in entries)
          if (e.meal == widget.meal && e.group.isNotEmpty) e.group,
      }.toList()..sort();
      if (!mounted) return;
      final selected = await showModalBottomSheet<String>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        backgroundColor: P.of(context).card,
        builder: (s) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(S.x5),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Meal heading',
                  style: F.head.copyWith(color: P.of(s).ink),
                ),
                const SizedBox(height: S.x3),
                PickRow(
                  'No heading',
                  'Keep it in the main meal list',
                  onTap: () => Navigator.of(s).pop(''),
                ),
                for (final g in groups)
                  PickRow(
                    g,
                    g == widget.group ? 'Selected' : 'Add here',
                    onTap: () => Navigator.of(s).pop(g),
                  ),
                const SizedBox(height: S.x3),
                BigButton(
                  'Create a heading',
                  color: C.domFood,
                  icon: LucideIcons.plus,
                  onTap: () async {
                    final text = await askText(
                      s,
                      'New meal heading',
                      'Name',
                      '',
                    );
                    if (text != null && text.trim().isNotEmpty && s.mounted) {
                      Navigator.of(s).pop(text.trim());
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      );
      if (selected != null && mounted) widget.onChanged(selected);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Meal headings could not load. Please retry.'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PickRow(
    'Meal heading',
    _busy
        ? 'Loading…'
        : widget.group.isEmpty
        ? 'Optional · choose or create'
        : widget.group,
    trailing: LucideIcons.layers,
    onTap: _busy ? null : _pick,
  );
}

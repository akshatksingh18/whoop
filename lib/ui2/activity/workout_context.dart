import 'package:flutter/material.dart';
import '../../gps/workout_context.dart';
import '../grammar.dart';
import '../theme.dart';

class WorkoutContextSelector extends StatelessWidget {
  const WorkoutContextSelector({
    super.key,
    required this.tags,
    required this.onChanged,
  });
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  @override
  Widget build(BuildContext context) {
    final p = P.of(context);
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Session context · optional',
            style: F.head.copyWith(color: p.ink),
          ),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x2,
            runSpacing: S.x2,
            children: [
              for (final e in workoutContextLabels.entries)
                Pressable(
                  semanticLabel:
                      '${e.value}, ${tags.contains(e.key) ? "selected" : "not selected"}',
                  onTap: () => onChanged(toggleWorkoutContext(tags, e.key)),
                  child: Pill(
                    '${tags.contains(e.key) ? "✓ " : ""}${e.value}',
                    tags.contains(e.key) ? C.green : C.n500,
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          Text(
            'Your notes help compare similar sessions. Unset means unknown. '
            'These tags do not adjust calories or infer weather.',
            style: F.cap.copyWith(color: p.ink3),
          ),
        ],
      ),
    );
  }
}

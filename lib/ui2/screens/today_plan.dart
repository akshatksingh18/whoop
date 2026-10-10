// Today's plan (build 86 redesign): what the day still asks of you, in one
// card, each row with its progress and the one action that moves it. Steps
// against the goal, food against the calorie goal, today's weigh-in (and
// the tape on measurement day), Pushups, and the workout: Resume while one
// runs, otherwise a way to Train. Plain words, measured numbers only.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../grammar.dart';
import '../theme.dart';
import 'home_screen.dart' show thousands;
import 'metric_detail.dart' show MetricDetail;
import 'progress_screen.dart' show TodayBodyRow;
import 'pushups_screen.dart' show TodayPushupRow;
import 'workout_screen.dart' show SessionDestination;

/// One row: icon well, what it is, how far along, and its action.
class PlanRow extends StatelessWidget {
  const PlanRow({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    this.frac,
    this.action,
    this.onAction,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title, sub;

  /// Progress 0…1 under the words; null draws no bar.
  final double? frac;
  final String? action;
  final VoidCallback? onAction, onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: p.wash(color),
                borderRadius: R.rMd,
              ),
              child: Icon(icon, size: 18, color: p.on(color)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(sub, style: F.cap.copyWith(color: p.ink3)),
                  if (frac != null) ...[
                    const SizedBox(height: S.x2),
                    ClipRRect(
                      borderRadius: R.rPill,
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          children: [
                            Positioned.fill(child: ColoredBox(color: p.track)),
                            FractionallySizedBox(
                              widthFactor: frac!.clamp(0.0, 1.0),
                              child: ColoredBox(
                                color: p.on(color),
                                child: const SizedBox.expand(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (action != null) ...[
              const SizedBox(width: S.x2),
              Pressable(
                semanticLabel: action!,
                onTap: onAction,
                // A full 44 pt target round the smaller pill.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: S.tap,
                    minWidth: S.tap,
                  ),
                  child: Center(child: Pill(action!, color)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TodayPlanCard extends StatelessWidget {
  const TodayPlanCard({
    super.key,
    required this.steps,
    required this.stepGoal,
    this.eaten,
    this.budget,
    this.full = true,
  });

  final int? steps;
  final int stepGoal;
  final double? eaten, budget;

  /// The rows that read their own stores (Body, Pushups, workout). Off in
  /// goldens, which have no database.
  final bool full;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final app = () {
      try {
        return c.watch<AppState?>();
      } catch (_) {
        return null;
      }
    }();
    final goal = (app?.user?['kcal_target'] as num?)?.toDouble();
    final live = app?.activeWorkout;
    final s = steps;
    final food = eaten ?? 0;
    final rows = <Widget>[
      PlanRow(
        icon: LucideIcons.footprints,
        color: C.green,
        title: s == null ? 'Steps' : '${thousands(s)} steps',
        sub: s == null
            ? 'Not recorded yet'
            : stepGoal > 0
            ? s >= stepGoal
                  ? 'Goal of ${thousands(stepGoal)} reached'
                  : '${thousands(stepGoal - s)} to your ${thousands(stepGoal)} goal'
            : 'No step goal set',
        frac: s == null || stepGoal <= 0 ? null : s / stepGoal,
        onTap: () => Navigator.of(c).push(
          MaterialPageRoute<void>(builder: (_) => const MetricDetail('steps')),
        ),
      ),
      PlanRow(
        icon: LucideIcons.utensils,
        color: C.domFood,
        title: food <= 0 ? 'Food' : '${thousands(food)} kcal eaten',
        sub: goal != null && goal > 0
            ? food <= goal
                  ? '${thousands(goal - food)} left of ${thousands(goal)}'
                  : '${thousands(food - goal)} over your ${thousands(goal)} goal'
            : budget != null
            ? 'Budget ${thousands(budget!)} so far'
            : 'Nothing logged yet',
        frac: goal != null && goal > 0 ? food / goal : null,
        action: 'Log',
        onAction: app == null ? null : () => app.navRequest.value = 6,
        onTap: app == null ? null : () => app.navRequest.value = 6,
      ),
      if (full) ...[
        const TodayBodyRow(embedded: true),
        const TodayPushupRow(embedded: true),
        if (live != null)
          PlanRow(
            icon: LucideIcons.dumbbell,
            color: C.purple,
            title: 'Workout running',
            sub:
                'Started ${live.startTime.hour.toString().padLeft(2, '0')}:'
                '${live.startTime.minute.toString().padLeft(2, '0')}',
            action: 'Resume',
            onAction: () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => const SessionDestination(null),
              ),
            ),
          )
        else
          PlanRow(
            icon: LucideIcons.dumbbell,
            color: C.purple,
            title: 'Train',
            sub: 'Run, walk, lift or anything else',
            action: 'Start',
            onAction: app == null ? null : () => app.navRequest.value = 4,
            onTap: app == null ? null : () => app.navRequest.value = 4,
          ),
      ],
    ];
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: S.x3),
            child: Text('TODAY', style: F.section.copyWith(color: p.ink3)),
          ),
          for (var i = 0; i < rows.length; i++) rows[i],
        ],
      ),
    );
  }
}

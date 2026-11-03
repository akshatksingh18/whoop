// Current Home actions and embedded Body/Pushups rows. Home owns its totals;
// PlanRow is also used independently by Body, Pushups and the developer gallery.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../grammar.dart';
import '../theme.dart';
import 'home_screen.dart' show weightUnitNow;
import 'progress_screen.dart' show TodayBodyRow, BodyEntryScreen;
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
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(
          children: [
            Icon(icon, size: 20, color: p.on(color)),
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
                // A full 44 pt target round the smaller pill. A real pill,
                // not bare text, so the action reads as a button (Build 89).
                child: Pill(action!, color),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class TodayPlanCard extends StatelessWidget {
  const TodayPlanCard({super.key, this.full = true});

  /// Store-reading Body/Pushups rows and the weigh-in action. Off in captures
  /// that provide already-authored Home data without a live database.
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
    final live = app?.activeWorkout;
    final rows = <Widget>[
      if (full) ...[
        const TodayBodyRow(embedded: true),
        const TodayPushupRow(embedded: true),
      ],
    ];
    Widget action(IconData icon, String title, VoidCallback? onTap) =>
        Pressable(
          onTap: onTap,
          semanticLabel: title,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 72),
            padding: const EdgeInsets.all(S.x3),
            decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 21, color: p.on(C.recovery)),
                const SizedBox(height: S.x1),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: F.cap.copyWith(color: p.ink),
                ),
              ],
            ),
          ),
        );
    final actions = [
      action(
        LucideIcons.scale,
        'Weigh in',
        !full
            ? null
            : () async {
                final unit = weightUnitNow(c);
                await Navigator.of(c).push(
                  MaterialPageRoute<void>(
                    builder: (_) => BodyEntryScreen(unit: unit),
                  ),
                );
              },
      ),
      action(
        LucideIcons.utensils,
        'Log food',
        app == null ? null : () => app.navRequest.value = 6,
      ),
      action(
        LucideIcons.dumbbell,
        live == null ? 'Train' : 'Resume',
        app == null
            ? null
            : () {
                if (live == null) {
                  app.navRequest.value = 4;
                } else {
                  Navigator.of(c).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SessionDestination(null),
                    ),
                  );
                }
              },
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bigText(c))
          for (final a in actions)
            Padding(
              padding: const EdgeInsets.only(bottom: S.x2),
              child: a,
            )
        else
          Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) const SizedBox(width: S.x2),
                Expanded(child: actions[i]),
              ],
            ],
          ),
        if (rows.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Surface(child: Column(children: rows)),
        ],
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../compute/profile.dart';
import '../../compute/training_review.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import '../../gps/workout_context.dart';
import 'home_screen.dart' show repoOf, prettyDay, go;
import 'metric_detail.dart' show detailScaffold, detailLinkRow;
import 'workout_screen.dart' show SessionDestination;
import 'package:lucide_icons_flutter/lucide_icons.dart';

class TrainingReviewScreen extends StatefulWidget {
  const TrainingReviewScreen({super.key, this.day});
  final String? day;
  @override
  State<TrainingReviewScreen> createState() => _TrainingReviewScreenState();
}

class _TrainingReviewScreenState extends State<TrainingReviewScreen>
    with RevisionReload {
  TrainingReviewData? _data;
  bool _failed = false, _loading = true;
  @override
  bool get revisionReloads => widget.day == null;
  @override
  void reload() => _load();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final token = beginRead(#review), repo = repoOf(context);
    if (repo == null) {
      setState(() {
        _loading = false;
        _failed = true;
      });
      return;
    }
    try {
      final data = widget.day == null
          ? await TrainingReviewData.load(
              repo,
              Profile.fromMap(context.read<AppState>().user),
            )
          : await TrainingReviewData.retained(widget.day!);
      if (stillNewest(#review, token))
        setState(() {
          _data = data;
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (stillNewest(#review, token))
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  Widget _consistency(TrainingReviewData d, P p) {
    final usable = d.observations.where((s) => s.usable).toList();
    String period(bool recent) {
      final rows = usable
          .where((s) => (s.day.compareTo(d.split) >= 0) == recent)
          .toList();
      final days = rows.map((s) => s.day).toSet().length;
      final minutes = rows.fold<double>(0, (n, s) => n + s.seconds) / 60;
      return '${rows.length} sessions · $days active days · ${minutes.round()} active minutes';
    }

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Recorded consistency', style: F.head.copyWith(color: p.ink)),
          Text(
            'Earlier fortnight: ${period(false)}.\nRecent fortnight: ${period(true)}.',
            style: F.cap.copyWith(color: p.ink2),
          ),
          Text(
            'Only reviewed sessions with usable route and HR data. Unrecorded movement and incomplete sessions are not inferred.',
            style: F.cap.copyWith(color: p.ink3),
          ),
          for (final distance in ['1K', '5K', '10K', 'Half marathon']) ...[
            if (usable.any((s) => s.bestEfforts.containsKey(distance))) ...[
              const SizedBox(height: S.x2),
              Text(
                '$distance best recorded effort',
                style: F.cap.copyWith(color: p.ink),
              ),
              for (final recent in [false, true]) ...[
                Builder(
                  builder: (_) {
                    final rows =
                        usable
                            .where(
                              (s) =>
                                  (s.day.compareTo(d.split) >= 0) == recent &&
                                  s.bestEfforts[distance] != null,
                            )
                            .toList()
                          ..sort(
                            (a, b) => a.bestEfforts[distance]!.compareTo(
                              b.bestEfforts[distance]!,
                            ),
                          );
                    if (rows.isEmpty)
                      return Text(
                        '${recent ? "Recent" : "Earlier"}: not recorded',
                        style: F.cap.copyWith(color: p.ink3),
                      );
                    final best = rows.first,
                        sec = best.bestEfforts[distance]!.round();
                    return detailLinkRow(
                      context,
                      LucideIcons.timer,
                      '${recent ? "Recent" : "Earlier"}: ${sec ~/ 60}:${(sec % 60).toString().padLeft(2, "0")}',
                      '${prettyDay(best.day)} · recorded route, conditions may differ',
                      () => go(context, SessionDestination(best.id)),
                    );
                  },
                ),
              ],
            ],
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final d = _data, p = P.of(c);
    return detailScaffold(c, 'Training review', [
      if (_loading)
        const Center(child: CircularProgressIndicator())
      else if (_failed)
        StatusCard(
          'Review could not load',
          'Your sessions are intact.',
          fix: 'Retry',
          onFix: _load,
        )
      else if (d == null)
        const StatusCard(
          'Review unavailable',
          'This notification’s evidence is no longer available.',
        )
      else ...[
        Text(
          '${prettyDay(d.start)} – ${prettyDay(d.end)} · completed days',
          style: F.cap.copyWith(color: p.ink3),
        ),
        Surface(
          child: Text(
            '${d.examined} sessions checked · ${d.observations.where((s) => s.usable).length} with usable route and HR data. '
            'Each comparison needs three separate sessions per fortnight, at similar pace or heart rate. '
            'Recorded context tags must match. Missing tags mean unknown conditions. Weather, terrain and fatigue are not controlled; this describes recordings, not proven fitness change.',
            style: F.cap.copyWith(color: p.ink2, height: 1.5),
          ),
        ),
        const SizedBox(height: S.x3),
        _consistency(d, p),
        if (d.comparisons.isEmpty)
          const StatusCard(
            'Not enough comparable sessions',
            'Keep recording runs and walks. Missing data stays out of the comparison.',
          ),
        for (final result in d.comparisons)
          Section(
            '${result.type} · ${result.recent.length} matched pairs',
            Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    result.atSimilarPace
                        ? '${result.hrChange >= 0 ? '+' : ''}${result.hrChange.toStringAsFixed(1)} bpm at similar pace'
                        : '${result.paceChange >= 0 ? '+' : ''}${result.paceChange.toStringAsFixed(1)}% pace at similar HR',
                    style: F.head.copyWith(color: p.ink),
                  ),
                  Text(
                    'Earlier: ${prettyDay(d.start)} to ${prettyDay(d.split)}. Recent: ${prettyDay(d.split)} to ${prettyDay(d.end)}.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                  if (result.cadenceChange != null)
                    Text(
                      '${result.cadenceChange! >= 0 ? '+' : ''}${result.cadenceChange!.toStringAsFixed(1)} steps/min cadence change in matched sessions. Phone recordings only.',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  for (final s in [...result.older, ...result.recent])
                    detailLinkRow(
                      c,
                      LucideIcons.activity,
                      '${prettyDay(s.day)} · ${(s.meters / 1000).toStringAsFixed(2)} km',
                      '${s.hr.round()} bpm · ${(s.coverage * 100).round()}% HR coverage · ${s.context.isEmpty ? "Context unknown" : s.context.map((v) => workoutContextLabels[v] ?? v).join(", ")}',
                      () => go(c, SessionDestination(s.id)),
                    ),
                ],
              ),
            ),
          ),
      ],
    ]);
  }
}

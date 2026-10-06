// Breathing pattern in sleep — the across-nights heart-rate-cycling screen.
//
// Individual nights now have dated measured readouts; missing/irregular nights
// retain their quality labels. The across-night finding remains separate, not
// a breathing measurement or diagnostic reassurance.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../../l10n/app_localizations.dart';
import '../ui2.dart';
import 'home_screen.dart' show envValue, pointsOf, repoOf, prettyDay;
import 'metric_detail.dart' show detailScaffold;

class SleepBreathingScreen extends StatefulWidget {
  const SleepBreathingScreen({super.key, this.data});

  /// Injected by tests; null loads from the repository.
  final ana.Metric<ana.CvhrDistribution>? data;

  /// Assemble the stored nights and hand them to the analytics screen. A night
  /// the screen abstained on is not a zero and never enters the denominator.
  ///
  /// ponytail: one bundle read per night over the window, paid once on open.
  /// If it ever feels slow, add a repo read of `cvhr_per_hour` and
  /// `analyzed_hours` without the payload rather than shrinking the window.
  static Future<ana.Metric<ana.CvhrDistribution>> load(
    LocalRepository repo,
  ) async => ana.cvhrPersonalDistribution(await nights(repo));

  /// The stored nights the screen reads, newest first.
  static Future<List<ana.CvhrNight>> nights(LocalRepository repo) async {
    final days = [...await repo.availableDays()]
      ..sort((a, b) => b.compareTo(a));
    final stop = DateTime.parse(dayLabelOf(DateTime.now()));
    final cutoff = dayLabelOf(
      DateTime(
        stop.year,
        stop.month,
        stop.day - ana.cvhrDistributionWindowNights + 1,
      ),
    );
    final flags = <String, double>{
      for (final p in pointsOf(await repo.getChart('irregular_rhythm_flag')))
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)): p.v,
    };
    final nights = <ana.CvhrNight>[];
    for (final day
        in days
            .where(
              (d) =>
                  d.compareTo(cutoff) >= 0 &&
                  d.compareTo(dayLabelOf(stop)) <= 0,
            )
            .take(ana.cvhrDistributionWindowNights)) {
      final v = envValue((await repo.getDayLungs(day))['cvhr']);
      final rate = v?['cvhr_per_hour'] as num?;
      final hours = v?['analyzed_hours'] as num?;
      if (rate == null || hours == null) continue;
      nights.add(
        ana.CvhrNight(
          dayKey: day,
          cvhrPerHour: rate.toDouble(),
          analyzedHours: hours.toDouble(),
          irregularRhythm: (flags[day] ?? 0) >= 1,
        ),
      );
    }
    return nights;
  }

  @override
  State<SleepBreathingScreen> createState() => _SleepBreathingScreenState();
}

class _SleepBreathingScreenState extends State<SleepBreathingScreen>
    with RevisionReload {
  ana.Metric<ana.CvhrDistribution>? _m;
  List<ana.CvhrNight> _nights = const [];
  bool _loading = true;
  bool _more = false;
  bool _failed = false;
  int? _pick;
  Map<String, String> _notes = const {};

  @override
  void initState() {
    super.initState();
    if (widget.data != null) {
      _m = widget.data;
      _loading = false;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  bool get revisionReloads => widget.data == null;
  @override
  void reload() => _load();
  Future<void> _load() async {
    final repo = repoOf(context);
    if (repo == null) {
      setState(() => _loading = false);
      return;
    }
    final token = beginRead(#breathing);
    try {
      final ns = await SleepBreathingScreen.nights(repo);
      final notes = <String, String>{};
      final valid = ns.map((n) => n.dayKey).toSet();
      final now = DateTime.now(), last = dayLabelOf(now);
      final first = dayLabelOf(DateTime(now.year, now.month, now.day - 29));
      final days =
          (await repo.availableDays())
              .where((d) => d.compareTo(first) >= 0 && d.compareTo(last) <= 0)
              .toList()
            ..sort();
      for (final day in days) {
        if (valid.contains(day)) continue;
        final raw = (await repo.getDayLungs(day))['cvhr'];
        if (raw is Map) notes[day] = raw['note']?.toString() ?? 'not measured';
      }
      if (stillNewest(#breathing, token))
        setState(() {
          _nights = ns;
          _notes = notes;
          _m = ana.cvhrPersonalDistribution(ns);
          _loading = false;
          _failed = false;
        });
    } catch (_) {
      if (stillNewest(#breathing, token))
        setState(() {
          _loading = false;
          _failed = true;
        });
    }
  }

  Widget _history(BuildContext c) {
    final p = P.of(c);
    return Surface(
      child: Builder(
        builder: (c) {
          final byDate = {for (final n in _nights) n.dayKey: n};

          final last = DateTime.parse(dayLabelOf(DateTime.now()));
          final first = DateTime(last.year, last.month, last.day - 29);
          final calendar = <String>[];
          for (
            var day = first;
            !day.isAfter(last);
            day = DateTime(day.year, day.month, day.day + 1)
          ) {
            calendar.add(dayLabelOf(day));
          }
          final series = [for (final day in calendar) byDate[day]?.cvhrPerHour];
          final axis = AxisSpec.of(
            series.whereType<double>(),
            floor: 0,
            ticks: 2,
          );
          final pick = _pick?.clamp(0, series.length - 1);
          String says(int i) {
            final n = byDate[calendar[i]];
            return '${prettyDay(calendar[i])} · ${n == null ? (_notes[calendar[i]] ?? "not recorded") : "${n.cvhrPerHour.toStringAsFixed(1)} cycles per observed hour · ${n.analyzedHours.toStringAsFixed(1)} h analysed${n.irregularRhythm ? " · irregular-rhythm flag" : ""}"}';
          }

          return ChartFrame(
            title: 'Each night',
            unit: 'cycles per observed hour',
            height: 110,
            yAxis: axis,
            series: series,
            readout: pick == null ? null : says(pick),
            xLabels: [prettyDay(calendar.first), prettyDay(calendar.last)],
            child: Scrubber(
              value: pick == null ? null : pick / (series.length - 1),
              step: 1 / (series.length - 1),
              label: 'Sleep heart-rate cycling by night',
              describe: (f) => says((f * (series.length - 1)).round()),
              onChanged: (f) =>
                  setState(() => _pick = (f * (series.length - 1)).round()),
              child: CustomPaint(
                size: Size.infinite,
                painter: LineChart(
                  series,
                  p.on(C.sleep),
                  dots: series.length <= 40,
                  dotInk: p.card,
                  cursor: pick,
                  cursorInk: p.ink,
                  axis: axis,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext c) {
    final l = AppLocalizations.of(c);
    final p = P.of(c);
    final m = _m;
    final v = m?.value;
    return detailScaffold(c, 'Breathing pattern in sleep', [
      if (_loading) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else if (_failed)
        StatusCard(
          'Breathing history could not load',
          'Your saved nights are intact.',
          fix: 'Retry',
          onFix: _load,
        )
      else if (v == null)
        StatusCard(
          l?.investigateNotEnoughNightsAcross ??
              'Not enough nights for the across-nights view',
          l?.investigateNeedsSeveralNights ??
              'This needs several nights with a few observed hours each.',
          icon: LucideIcons.wind,
        )
      else ...[
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Icon(
                    v.aboveOwnUsual
                        ? LucideIcons.trendingUp
                        : LucideIcons.check,
                    size: 20,
                    color: p.on(v.aboveOwnUsual ? C.yellow : C.green),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Text(
                      v.aboveOwnUsual
                          ? 'Higher than your usual'
                          : 'Within your usual range',
                      style: F.head.copyWith(color: p.ink),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: S.x1),
              Text(
                'Heart-rate cycling while asleep · ${v.nightsUsed} nights',
                style: F.cap.copyWith(color: p.ink3),
              ),
              const SizedBox(height: S.x3),
              Text(
                'A pattern in your pulse, not a breathing test.',
                style: F.cap.copyWith(color: p.ink2),
              ),
            ],
          ),
        ),
        const SizedBox(height: S.x4),
        Pressable(
          onTap: () => setState(() => _more = !_more),
          semanticLabel: 'What this means',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'What this means',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ),
              Icon(
                _more ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 16,
                color: p.ink3,
              ),
            ],
          ),
        ),
        if (_more) ...[
          const SizedBox(height: S.x2),
          Surface(
            elevation: 0,
            color: p.card2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in const [
                  'It counts how often your heart rate swings up and down while '
                      'you sleep. Breathing pauses cause that, but so do an '
                      'irregular rhythm, altitude and a broken-up night.',
                  'It cannot rule anything in or out, and one night means little '
                      'on its own.',
                  'If you snore, wake unrefreshed, or someone has seen you stop '
                      'breathing in your sleep, a clinician can test that properly.',
                ]) ...[
                  Text(line, style: F.cap.copyWith(color: p.ink2, height: 1.5)),
                  const SizedBox(height: S.x2),
                ],
              ],
            ),
          ),
        ],
      ],
      if (!_loading &&
          !_failed &&
          (_nights.isNotEmpty || _notes.isNotEmpty)) ...[
        const SizedBox(height: S.x3),
        _history(c),
      ],
    ]);
  }
}

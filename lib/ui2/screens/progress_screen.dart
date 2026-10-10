// Progress (build 86): the one recomposition page — leaner while getting
// stronger — with Body inside it. Body progress first (weight and tape with
// a measurement and a range menu, dated Start / Latest / Change, entries and
// two-panel photo comparison), then strength, food, activity and recovery,
// and one weekly / monthly review drawn from recorded evidence only.
//
// Nothing here is a score. Every number shows its dates and counts, a family
// with no data says so, and nothing claims muscle gained or a cause.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../compute/profile.dart' show isLiftType;
import '../../data/body_log.dart';
import '../../data/calculation_store.dart';
import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/lift_log.dart';
import '../../data/nutrition_store.dart';
import '../../data/photo_encode.dart';
import '../../data/progress_review.dart';
import '../../gps/run_history.dart' show isRunType, isWalkType;
import '../../notify/notification_event.dart' show NotifCategory;
import '../../notify/notification_service.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show pad, pointsOf, pullToRefresh, repoOf, thousands;
import 'journal_compose.dart' show OsTextField;

const _camera = MethodChannel('openstrap/camera');

String _md(String day) {
  const m = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final d = DateTime.parse(day);
  final now = DateTime.now();
  return '${m[d.month - 1]} ${d.day}${d.year == now.year ? '' : ', ${d.year}'}';
}

String _num(double v, [int places = 1]) {
  final s = v.toStringAsFixed(places);
  return s.contains('.') ? s.replaceFirst(RegExp(r'\.?0+$'), '') : s;
}

/// Everything the page shows, read once per revision.
class ProgressData {
  ProgressData({
    required this.weights,
    required this.measures,
    required this.photos,
    required this.lifts,
    required this.food,
    required this.steps,
    required this.sleepMin,
    required this.recovery,
    required this.sessions,
    required this.baseline,
    required this.heightCm,
  });

  final List<BodyWeightRow> weights;
  final List<BodyMeasure> measures;
  final List<BodyPhoto> photos;
  final List<LiftWorkout> lifts;
  final List<
    ({
      String date,
      double? kcal,
      bool counts,
      double? protein,
      bool proteinComplete,
    })
  >
  food;
  final List<DatedValue> steps, sleepMin, recovery;
  final List<({String date, String type})> sessions;
  final String? baseline;
  final double? heightCm;

  String? get earliest {
    final ds = [
      if (weights.isNotEmpty) weights.first.date,
      if (measures.isNotEmpty) measures.last.date,
      if (photos.isNotEmpty) photos.first.date,
    ]..sort();
    return ds.isEmpty ? null : ds.first;
  }

  static const baselineKey = progressBaselineKey;

  static Future<ProgressData> load(BuildContext c) async {
    final repo = repoOf(c);
    final user = c.read<AppState>().user ?? const {};
    final db = await LocalDb.instance;
    List<DatedValue> chart(Map<String, dynamic>? m) => [
      for (final p in pointsOf(m))
        (
          date: dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)),
          value: p.v,
        ),
    ];
    Future<Map<String, dynamic>?> get(String k) async {
      try {
        return await repo?.getChart(k);
      } catch (_) {
        return null;
      }
    }

    final win = await NutritionDb.window(db, days: 400);
    final now = DateTime.now();
    final sessions = await LocalDb.sessionsInRange(
      DateTime(now.year - 1, now.month, now.day).millisecondsSinceEpoch ~/ 1000,
      now.millisecondsSinceEpoch ~/ 1000,
    );
    return ProgressData(
      weights: await BodyLogDb.weights(),
      measures: await BodyLogDb.measures(),
      photos: await BodyLogDb.photos(),
      lifts: await LiftLogDb.finished(),
      food: [
        for (final d in win.days)
          (
            date: d.date,
            kcal: d.kcal.value,
            counts: d.countsTowardAverages,
            protein: d.protein.value,
            proteinComplete: d.protein.complete,
          ),
      ],
      steps: chart(await get('steps')),
      sleepMin: chart(await get('sleep')),
      recovery: chart(await get('recovery')),
      sessions: [
        for (final r in sessions)
          if (r['status'] != 'live' && r['start_ts'] is num)
            (
              date: dayLabelOf(
                DateTime.fromMillisecondsSinceEpoch(
                  (r['start_ts'] as num).toInt() * 1000,
                ),
              ),
              type: (r['type'] as String?) ?? '',
            ),
      ],
      baseline: await CalculationStore.read(baselineKey),
      heightCm: (user['height_cm'] as num?)?.toDouble(),
    );
  }
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> with RevisionReload {
  ProgressData? _d;
  bool _failed = false;
  ProgressRange _range = ProgressRange.threeMonths;
  String _metricKey = 'weight';
  String _unit = 'kg';
  bool _trend = false;

  @override
  void initState() {
    super.initState();
    _prefs();
  }

  Future<void> _prefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      setState(() {
        _unit = p.getString('body.unit') ?? 'kg';
        _range =
            ProgressRange.values
                .where((r) => r.name == p.getString('progress.range'))
                .firstOrNull ??
            _range;
        _metricKey = p.getString('progress.metric') ?? _metricKey;
      });
    } catch (_) {}
  }

  Future<void> _save(String k, String v) async {
    try {
      await (await SharedPreferences.getInstance()).setString(k, v);
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_d == null && !_failed) reload();
  }

  @override
  void reload() async {
    final t = beginRead(#progress);
    try {
      final d = await ProgressData.load(context);
      if (stillNewest(#progress, t)) setState(() => (_d = d, _failed = false));
    } catch (_) {
      if (stillNewest(#progress, t)) setState(() => _failed = true);
    }
  }

  ProgressMetric get _metric => switch (_metricKey) {
    'steps' => const StepsMetric(),
    'weight' => WeightMetric(_unit),
    _ => SiteMetric(BodySite.parse(_metricKey) ?? BodySite.waistNavel),
  };

  @override
  Widget build(BuildContext c) {
    final d = _d;
    return RefreshIndicator(
      onRefresh: () => pullToRefresh(c, () async => reload()),
      child: ListView(
        padding: pad,
        children: [
          const ScreenTitle('Progress'),
          if (_failed)
            StatusCard(
              'Progress could not load',
              'Your saved records are intact.',
              fix: 'Retry',
              onFix: reload,
            )
          else if (d == null)
            const Center(child: CircularProgressIndicator())
          else
            ..._page(c, d),
        ],
      ),
    );
  }

  List<Widget> _page(BuildContext c, ProgressData d) {
    final p = P.of(c);
    final today = todayLabel();
    final from = _range.from(today, baseline: d.baseline, earliest: d.earliest);
    return [
      Text(
        'Recomposition: leaner while getting stronger'
        '${d.baseline == null ? '' : ' · since ${_md(d.baseline!)}'}',
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x3),
      Row(
        children: [
          Expanded(
            child: BigButton(
              'Add entry',
              icon: LucideIcons.plus,
              color: C.teal,
              onTap: () => _addEntry(c, d),
            ),
          ),
          const SizedBox(width: S.x2),
          Pressable(
            semanticLabel: 'Body settings',
            onTap: () => _settings(c, d),
            child: Padding(
              padding: const EdgeInsets.all(S.x3),
              child: Icon(LucideIcons.settings2, size: 20, color: p.ink2),
            ),
          ),
        ],
      ),
      const SizedBox(height: S.x4),
      _menus(c, p),
      const SizedBox(height: S.x3),
      ..._bodySection(c, p, d, from, today),
      const SizedBox(height: S.x5),
      _photoCard(c, p, d),
      const SizedBox(height: S.x5),
      ..._reviewSection(c, p, d, today),
      const SizedBox(height: S.x5),
      ..._strengthSection(c, p, d, from, today),
      const SizedBox(height: S.x5),
      ..._foodSection(c, p, d, from, today),
      const SizedBox(height: S.x5),
      ..._activitySection(c, p, d, from, today),
    ];
  }

  Widget _menus(BuildContext c, P p) {
    Widget chip(String label, bool on, VoidCallback tap) => Padding(
      padding: const EdgeInsets.only(right: S.x2, bottom: S.x2),
      child: Pressable(
        semanticLabel: on ? '$label, selected' : label,
        onTap: tap,
        child: Pill(label, on ? C.teal : C.n400),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              chip(
                'Weight',
                _metricKey == 'weight',
                () => _setMetric('weight'),
              ),
              chip('Steps', _metricKey == 'steps', () => _setMetric('steps')),
              for (final s in BodySite.values)
                chip(s.title, _metricKey == s.name, () => _setMetric(s.name)),
            ],
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final r in ProgressRange.values)
                chip(r.label, _range == r, () {
                  setState(() => _range = r);
                  _save('progress.range', r.name);
                }),
            ],
          ),
        ),
      ],
    );
  }

  void _setMetric(String k) {
    setState(() => _metricKey = k);
    _save('progress.metric', k);
  }

  // ── body ──

  List<Widget> _bodySection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final m = _metric;
    final List<DatedValue> series = switch (m) {
      WeightMetric() => weightSeries(d.weights, unit: _unit),
      StepsMetric() => d.steps,
      SiteMetric(:final site) => siteSeries(d.measures, site),
    };
    final r = inRange(series, from, today);
    final summary = m is StepsMetric ? null : bodySummary(r);
    final steps = m is StepsMetric ? stepsSummary(r) : null;
    final points = m is WeightMetric && _trend
        ? [
            for (final day in daysBetween(from, today))
              if (BodyLogDb.sevenDayMean(d.weights, day) case final mean?)
                _unit == 'lb' ? mean.kg * kLbPerKg : mean.kg,
          ]
        : [for (final x in r) x.value];
    return [
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    m.label,
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (m is WeightMetric) ...[
                  Pressable(
                    semanticLabel: _trend
                        ? 'Show readings'
                        : 'Show 7-day trend',
                    onTap: () => setState(() => _trend = !_trend),
                    child: Text(
                      _trend ? '7-day trend' : 'Readings',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  ),
                  const SizedBox(width: S.x3),
                  Pressable(
                    semanticLabel:
                        'Switch to ${_unit == 'kg' ? 'pounds' : 'kilograms'}',
                    onTap: () {
                      final u = _unit == 'kg' ? 'lb' : 'kg';
                      setState(() => _unit = u);
                      _save('body.unit', u);
                    },
                    child: Text(_unit, style: F.cap.copyWith(color: p.ink2)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: S.x3),
            if (r.isEmpty)
              Text(
                'Nothing recorded in ${_range.label.toLowerCase()}.',
                style: F.cap.copyWith(color: p.ink3),
              )
            else ...[
              if (points.length >= 2)
                SizedBox(
                  height: 140,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: LineChart(
                      points,
                      p.on(C.teal),
                      fill: false,
                      dots: true,
                    ),
                  ),
                ),
              const SizedBox(height: S.x2),
              if (summary != null)
                Row(
                  children: [
                    _stat(
                      p,
                      'Start',
                      '${_num(summary.start.value)} ${m.unit}',
                      _md(summary.start.date),
                    ),
                    _stat(
                      p,
                      'Latest',
                      '${_num(summary.latest.value)} ${m.unit}',
                      _md(summary.latest.date),
                    ),
                    _stat(
                      p,
                      'Change',
                      summary.count < 2
                          ? '—'
                          : '${summary.change >= 0 ? '+' : '−'}${_num(summary.change.abs())} ${m.unit}',
                      '${summary.count} ${summary.count == 1 ? 'reading' : 'readings'}',
                    ),
                  ],
                ),
              if (steps != null)
                Row(
                  children: [
                    _stat(
                      p,
                      'Total',
                      thousands(steps.total),
                      '${steps.days} days measured',
                    ),
                    _stat(
                      p,
                      'Average',
                      steps.average == null ? '—' : thousands(steps.average!),
                      'per measured day',
                    ),
                  ],
                ),
              if (m is WeightMetric && d.weights.isNotEmpty)
                if (BodyLogDb.sevenDayMean(d.weights, today) case final mean?)
                  Padding(
                    padding: const EdgeInsets.only(top: S.x2),
                    child: Text(
                      '7-day average ${_num(_unit == 'lb' ? mean.kg * kLbPerKg : mean.kg)} $_unit '
                      'from ${mean.count} ${mean.count == 1 ? 'reading' : 'readings'}',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ),
              if (m is SiteMetric && m.site == BodySite.waistNavel)
                ..._estimates(p, d),
            ],
          ],
        ),
      ),
      const SizedBox(height: S.x3),
      ..._entries(c, p, d, m, from, today),
    ];
  }

  List<Widget> _estimates(P p, ProgressData d) {
    final latest = d.measures
        .where((x) => x.value(BodySite.waistNavel) != null)
        .firstOrNull;
    final h = d.heightCm == null ? null : d.heightCm! / 2.54;
    if (latest == null || h == null) return const [];
    final waist = latest.value(BodySite.waistNavel)!;
    final neck = d.measures
        .where((x) => x.value(BodySite.neck) != null)
        .firstOrNull
        ?.value(BodySite.neck);
    final bf = BodyLogDb.navyBodyFat(waist, neck, h);
    return [
      Padding(
        padding: const EdgeInsets.only(top: S.x2),
        child: Text(
          'Estimates from ${_md(latest.date)}: waist-to-height ${(waist / h).toStringAsFixed(2)}'
          '${bf == null ? '' : ' · US Navy body fat about ${bf.toStringAsFixed(0)}%'}. '
          'The trend matters, not the exact number.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ),
    ];
  }

  Widget _stat(P p, String k, String v, String sub) => Expanded(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(k.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
        Text(v, style: F.n17.copyWith(color: p.ink)),
        Text(sub, style: F.over.copyWith(color: p.ink3)),
      ],
    ),
  );

  List<Widget> _entries(
    BuildContext c,
    P p,
    ProgressData d,
    ProgressMetric m,
    String from,
    String today,
  ) {
    if (m is StepsMetric) return const [];
    final rows = <Widget>[];
    if (m is WeightMetric) {
      final ws = [
        for (final w in d.weights.reversed)
          if (w.date.compareTo(from) >= 0) w,
      ];
      for (final w in ws.take(5)) {
        rows.add(
          _entryRow(
            c,
            p,
            w.date,
            bodyWeightText(w, unit: _unit),
            w.historyOnly
                ? (w.source == 'whoop' ? 'Added later' : 'Imported')
                : '',
            () => _editWeight(c, w),
          ),
        );
      }
    } else if (m is SiteMetric) {
      final ms = [
        for (final x in d.measures)
          if (x.date.compareTo(from) >= 0 && x.value(m.site) != null) x,
      ];
      for (final x in ms.take(5)) {
        final ch = BodyLogDb.changeSince(d.measures, x, m.site);
        rows.add(
          _entryRow(
            c,
            p,
            x.date,
            '${_num(x.value(m.site)!, 2)} in',
            ch == null
                ? ''
                : '${ch >= 0 ? '+' : '−'}${_num(ch.abs(), 2)} in since the last',
            () => _editMeasure(c, x),
          ),
        );
      }
    }
    return [
      Section(
        'Entries',
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x4),
                  child: Text(
                    'No entries in this range.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                )
              : Column(children: rows),
        ),
        action: 'All history',
        onAction: () async {
          await Navigator.of(c).push(
            MaterialPageRoute<void>(builder: (_) => BodyHistoryScreen(data: d)),
          );
          reload();
        },
      ),
    ];
  }

  Widget _entryRow(
    BuildContext c,
    P p,
    String date,
    String value,
    String sub,
    VoidCallback onTap,
  ) {
    final photosThatDay = (_d?.photos ?? const [])
        .where((x) => x.date == date)
        .length;
    return Pressable(
      semanticLabel: '${_md(date)}, $value',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_md(date), style: F.body.copyWith(color: p.ink)),
                  if (sub.isNotEmpty)
                    Text(sub, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
            if (photosThatDay > 0) ...[
              Icon(LucideIcons.image, size: 15, color: p.ink3),
              const SizedBox(width: S.x2),
            ],
            Text(value, style: F.n17.copyWith(color: p.ink)),
          ],
        ),
      ),
    );
  }

  // ── photos ──

  Widget _photoCard(BuildContext c, P p, ProgressData d) => Surface(
    onTap: d.photos.isEmpty
        ? null
        : () => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoCompareScreen(photos: d.photos),
            ),
          ),
    semanticLabel: 'Compare photos',
    child: Row(
      children: [
        Icon(LucideIcons.images, size: 20, color: p.ink2),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photos',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                d.photos.isEmpty
                    ? 'Add front and side photos from Add entry.'
                    : '${d.photos.length} photos · latest ${_md(d.photos.last.date)}. Compare any two.',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
        if (d.photos.isNotEmpty)
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ],
    ),
  );

  // ── review ──

  List<Widget> _reviewSection(
    BuildContext c,
    P p,
    ProgressData d,
    String today,
  ) {
    final ws = weightSeries(d.weights, unit: _unit);
    Widget card(String title, DayWindow before, DayWindow after) {
      final wb = weightWindow(ws, before), wa = weightWindow(ws, after);
      final waist = siteSeries(d.measures, BodySite.waistNavel);
      final wBefore = inRange(waist, '0000-00-00', before.to).lastOrNull;
      final wAfter = inRange(waist, after.from, after.to).lastOrNull;
      final rv = review(
        weightBefore: wb,
        weightAfter: wa,
        waistChange: wBefore == null || wAfter == null
            ? null
            : wAfter.value - wBefore.value,
        food: foodWindow(d.food, after),
        lifts: liftComparisons(d.lifts, before, after),
        sessionsAfter: d.sessions
            .where(
              (s) =>
                  s.date.compareTo(after.from) >= 0 &&
                  s.date.compareTo(after.to) <= 0,
            )
            .length,
      );
      return Padding(
        padding: const EdgeInsets.only(bottom: S.x3),
        child: Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
              Text(
                '${_md(after.from)} – ${_md(after.to)} vs ${_md(before.from)} – ${_md(before.to)}',
                style: F.over.copyWith(color: p.ink3),
              ),
              const SizedBox(height: S.x2),
              Text(
                rv.headline,
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              for (final b in rv.because)
                Text(b, style: F.cap.copyWith(color: p.ink2)),
              if (rv.next != null) ...[
                const SizedBox(height: S.x2),
                Text(rv.next!, style: F.cap.copyWith(color: p.ink)),
              ],
            ],
          ),
        ),
      );
    }

    final (lastWeek, weekBefore) = closedWeeks(today);
    final (lastMonth, monthBefore) = closedMonths(today);
    return [
      Section(
        'Review',
        Column(
          children: [
            card('Last week', weekBefore, lastWeek),
            card('Last month', monthBefore, lastMonth),
            Text(
              'Observations from what was recorded, not a diagnosis. Change your goals yourself; '
              'this never changes them.',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
    ];
  }

  // ── strength ──

  List<Widget> _strengthSection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final lifts = [
      for (final w in d.lifts)
        if (dayLabelOf(w.startedAt).compareTo(from) >= 0) w,
    ];
    final mid = DateTime.parse(
      from,
    ).add(DateTime.parse(today).difference(DateTime.parse(from)) ~/ 2);
    final first = (from: from, to: dayLabelOf(mid), days: 0, partial: false);
    final second = (
      from: dayLabelOf(DateTime(mid.year, mid.month, mid.day + 1)),
      to: today,
      days: 0,
      partial: false,
    );
    final cmp = liftComparisons(d.lifts, first, second);
    final sets = lifts.fold<int>(0, (n, w) => n + w.setCount);
    String setText(LiftComparison x, LiftSet s) =>
        '${liftWeightText(s.load)} ${x.mode.shortUnit} × ${s.reps}';
    return [
      Section(
        'Strength',
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${lifts.length} logged workouts · $sets logged sets',
                style: F.cap.copyWith(color: p.ink3),
              ),
              if (cmp.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: S.x2),
                  child: Text(
                    lifts.isEmpty
                        ? 'No sets logged in this range.'
                        : 'Comparisons appear once the same lift, load meaning and equipment is logged in both halves of the range.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ),
              for (final x in cmp) ...[
                const SizedBox(height: S.x3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        x.exercise,
                        style: F.body.copyWith(color: p.ink),
                      ),
                    ),
                    Icon(
                      x.direction > 0
                          ? LucideIcons.trendingUp
                          : x.direction < 0
                          ? LucideIcons.trendingDown
                          : LucideIcons.minus,
                      size: 16,
                      color: p.ink2,
                    ),
                  ],
                ),
                Text(
                  'Best ${setText(x, x.before)} → ${setText(x, x.after)}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  // ── food ──

  List<Widget> _foodSection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final w = (
      from: from,
      to: today,
      days: daysBetween(from, today).length,
      partial: true,
    );
    final f = foodWindow(d.food, w);
    return [
      Section(
        'Food',
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _stat(
                    p,
                    'Calories',
                    f.kcal == null ? '—' : thousands(f.kcal!),
                    '${f.kcalDays} of ${f.windowDays} days',
                  ),
                  _stat(
                    p,
                    'Protein',
                    f.protein == null ? '—' : '${f.protein!.round()} g',
                    '${f.proteinDays} complete days',
                  ),
                ],
              ),
              const SizedBox(height: S.x2),
              Text(
                'Averages over days that count; a day without food logged is unknown, not zero.',
                style: F.over.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── activity and recovery ──

  List<Widget> _activitySection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final ss = [
      for (final s in d.sessions)
        if (s.date.compareTo(from) >= 0) s,
    ];
    final lifts = ss.where((s) => isLiftType(s.type)).length;
    final runs = ss.where((s) => isRunType(s.type)).length;
    final walks = ss.where((s) => isWalkType(s.type)).length;
    final st = stepsSummary(inRange(d.steps, from, today));
    double? mean(List<DatedValue> v) =>
        v.isEmpty ? null : v.fold<double>(0, (a, x) => a + x.value) / v.length;
    final sleep = inRange(d.sleepMin, from, today);
    final rec = inRange(d.recovery, from, today);
    final sm = mean(sleep), rm = mean(rec);
    return [
      Section(
        'Activity and recovery',
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _stat(
                    p,
                    'Workouts',
                    '${ss.length}',
                    '$lifts lift · $runs run · $walks walk',
                  ),
                  _stat(
                    p,
                    'Steps',
                    st.average == null ? '—' : thousands(st.average!),
                    '${st.days} days measured',
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  _stat(
                    p,
                    'Sleep',
                    sm == null ? '—' : '${sm ~/ 60}h ${(sm % 60).round()}m',
                    '${sleep.length} nights',
                  ),
                  _stat(
                    p,
                    'Recovery',
                    rm == null ? '—' : '${rm.round()}%',
                    '${rec.length} days',
                  ),
                ],
              ),
              const SizedBox(height: S.x2),
              Text(
                'Side by side for context; it does not show what caused what.',
                style: F.over.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── entry and settings sheets ──

  Future<void> _addEntry(BuildContext c, ProgressData d) async {
    final changed = await Navigator.of(c).push<bool>(
      MaterialPageRoute(builder: (_) => BodyEntryScreen(unit: _unit)),
    );
    if (changed == true) reload();
  }

  Future<void> _editWeight(BuildContext c, BodyWeightRow w) async {
    final changed = await Navigator.of(c).push<bool>(
      MaterialPageRoute(
        builder: (_) => BodyEntryScreen(unit: _unit, date: w.date),
      ),
    );
    if (changed == true) reload();
  }

  Future<void> _editMeasure(BuildContext c, BodyMeasure m) async {
    final changed = await Navigator.of(c).push<bool>(
      MaterialPageRoute(
        builder: (_) => BodyEntryScreen(unit: _unit, date: m.date, measure: m),
      ),
    );
    if (changed == true) reload();
  }

  Future<void> _settings(BuildContext c, ProgressData d) async {
    await Navigator.of(c).push(
      MaterialPageRoute<void>(builder: (_) => BodySettingsScreen(data: d)),
    );
    reload();
  }
}

// ── Today's Body row ────────────────────────────────────────────────────────

/// Today: the 7-day weight with its reading count, a one-tap weigh-in, and
/// the way into Progress. Not a second dashboard.
class TodayBodyRow extends StatefulWidget {
  const TodayBodyRow({super.key});
  @override
  State<TodayBodyRow> createState() => _TodayBodyRowState();
}

class _TodayBodyRowState extends State<TodayBodyRow> with RevisionReload {
  ({double kg, int count})? _mean;
  bool _today = false;
  String _unit = 'kg';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    reload();
  }

  @override
  void reload() async {
    final t = beginRead(#todayBody);
    try {
      final ws = await BodyLogDb.weights();
      final u = (await SharedPreferences.getInstance()).getString('body.unit') ?? 'kg';
      final today = todayLabel();
      if (!stillNewest(#todayBody, t)) return;
      setState(() {
        _mean = BodyLogDb.sevenDayMean(ws, today);
        _today = ws.any((w) => w.date == today);
        _unit = u;
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final m = _mean;
    return Surface(
      onTap: () => c.read<AppState>().navRequest.value = 5,
      semanticLabel: 'Body. Opens Progress',
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Body', style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text(
              m == null
                  ? 'No weigh-ins this week'
                  : '7-day ${_num(_unit == 'lb' ? m.kg * kLbPerKg : m.kg)} $_unit · '
                        '${m.count} ${m.count == 1 ? 'reading' : 'readings'}',
              style: F.cap.copyWith(color: p.ink3),
            ),
          ]),
        ),
        if (!_today)
          Pressable(
            semanticLabel: 'Log weigh-in',
            onTap: () async {
              final changed = await Navigator.of(c).push<bool>(
                MaterialPageRoute(builder: (_) => BodyEntryScreen(unit: _unit)),
              );
              if (changed == true) reload();
            },
            child: Pill('Weigh in', C.teal, icon: LucideIcons.plus),
          ),
        const SizedBox(width: S.x2),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    );
  }
}

// ── Add / edit an entry ─────────────────────────────────────────────────────

/// One dated body entry: weight, any tape sites and photos, for today or a
/// chosen past day. A past or imported weight is history only.
class BodyEntryScreen extends StatefulWidget {
  const BodyEntryScreen({
    super.key,
    required this.unit,
    this.date,
    this.measure,
  });
  final String unit;
  final String? date;
  final BodyMeasure? measure;
  @override
  State<BodyEntryScreen> createState() => _BodyEntryScreenState();
}

class _BodyEntryScreenState extends State<BodyEntryScreen> {
  late String _date = widget.date ?? todayLabel();
  late String _unit = widget.unit;
  final _weight = TextEditingController();
  final _sites = {for (final s in BodySite.values) s: TextEditingController()};
  BodyWeightRow? _existing;
  List<BodyPhoto> _photos = const [];
  bool _busy = false;
  String? _error;
  bool _changed = false;

  @override
  void initState() {
    super.initState();
    final m = widget.measure;
    if (m != null) {
      for (final s in BodySite.values) {
        final v = m.value(s);
        if (v != null) _sites[s]!.text = _num(v, 2);
      }
    }
    _loadDay();
  }

  Future<void> _loadDay() async {
    final w = await BodyLogDb.weightOn(_date);
    final ph = [
      for (final x in await BodyLogDb.photos())
        if (x.date == _date) x,
    ];
    if (!mounted) return;
    setState(() {
      _existing = w;
      _photos = ph;
      if (w != null && _weight.text.isEmpty) {
        _weight.text = w.entered != null && w.unit == _unit
            ? _num(w.entered!)
            : _num(_unit == 'lb' ? w.kg * kLbPerKg : w.kg);
      }
    });
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.parse(_date),
      firstDate: DateTime(2000),
      lastDate: now,
    );
    if (picked == null) return;
    setState(() {
      _date = dayLabelOf(picked);
      _weight.clear();
    });
    _loadDay();
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => (_busy = true, _error = null));
    try {
      final app = context.read<AppState>();
      final wText = _weight.text.trim().replaceAll(',', '.');
      if (wText.isNotEmpty) {
        final v = double.tryParse(wText);
        if (v == null)
          throw const BodyLogError('Enter the weight as a number.');
        final kg = _unit == 'lb' ? v / kLbPerKg : v;
        if (_existing != null &&
            (_existing!.kg - kg).abs() >= 0.05 &&
            mounted) {
          final ok = await confirmRemove(
            context,
            title: 'Replace ${_md(_date)}\'s weight?',
            body:
                'It is ${bodyWeightText(_existing!, unit: _unit)}. One weight per day: the new one replaces it.',
            remove: 'Replace',
            keep: 'Keep it',
          );
          if (!ok) throw const BodyLogError('Weight kept as it was.');
        }
        await BodyLogDb.putWeight(_date, v, _unit);
        // Today's weigh-in is the current profile weight, as Food's always
        // was; a past day's never re-prices anything.
        if (_date == todayLabel()) {
          await app.updateProfile({'weight_kg': kg});
        }
      }
      // Sites a newer build wrote that this one does not know are carried.
      final inches = <String, double>{
        for (final e
            in (widget.measure?.inches ?? const <String, double>{}).entries)
          if (BodySite.parse(e.key) == null) e.key: e.value,
      };
      for (final s in BodySite.values) {
        final t = _sites[s]!.text.trim().replaceAll(',', '.');
        if (t.isEmpty) continue;
        final v = double.tryParse(t);
        if (v == null) throw BodyLogError('${s.title} must be a number.');
        inches[s.name] = v;
      }
      if (inches.isNotEmpty) {
        await BodyLogDb.putMeasure(
          BodyMeasure(
            id: widget.measure?.id,
            date: _date,
            recordedAt: widget.measure?.recordedAt ?? DateTime.now(),
            inches: inches,
          ),
        );
      }
      app.bumpInsights();
      if (mounted) Navigator.of(context).pop(true);
    } on BodyLogError catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Not saved. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addPhoto(String pose, {required bool camera}) async {
    try {
      Uint8List? raw;
      if (camera) {
        raw = await _camera.invokeMethod<Uint8List>('capture');
      } else {
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.image,
        );
        final path = picked?.files.single.path;
        if (path != null) raw = await File(path).readAsBytes();
      }
      if (raw == null) return;
      final jpeg = await encodeProgressPhoto(raw);
      await BodyLogDb.addPhoto(jpeg, date: _date, pose: pose);
      _changed = true;
      await _loadDay();
    } on PlatformException catch (e) {
      setState(() => _error = e.message ?? 'The camera is not available.');
    } catch (_) {
      setState(() => _error = 'That photo could not be added.');
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar(
                widget.date == null ? 'Add entry' : 'Edit ${_md(_date)}',
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  Surface(
                    onTap: _pickDate,
                    semanticLabel: 'Day ${_md(_date)}. Change',
                    child: Row(
                      children: [
                        Icon(LucideIcons.calendar, size: 18, color: p.ink2),
                        const SizedBox(width: S.x3),
                        Expanded(
                          child: Text(
                            _date == todayLabel() ? 'Today' : _md(_date),
                            style: F.body.copyWith(color: p.ink),
                          ),
                        ),
                        Text('Change', style: F.cap.copyWith(color: p.ink2)),
                      ],
                    ),
                  ),
                  if (_date != todayLabel())
                    Padding(
                      padding: const EdgeInsets.only(top: S.x2),
                      child: Text(
                        'A past day is kept as history: it does not change that day\'s calories or your current weight.',
                        style: F.over.copyWith(color: p.ink3),
                      ),
                    ),
                  const SizedBox(height: S.x4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: OsTextField(
                          controller: _weight,
                          label: 'Weight ($_unit)',
                          keyboard: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: S.x2),
                      Pressable(
                        semanticLabel:
                            'Use ${_unit == 'kg' ? 'pounds' : 'kilograms'}',
                        onTap: () => setState(() {
                          final v = double.tryParse(_weight.text.trim());
                          _unit = _unit == 'kg' ? 'lb' : 'kg';
                          if (v != null)
                            _weight.text = _num(
                              _unit == 'lb' ? v * kLbPerKg : v / kLbPerKg,
                            );
                        }),
                        child: Padding(
                          padding: const EdgeInsets.all(S.x3),
                          child: Pill(_unit, C.teal),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: S.x5),
                  Text(
                    'TAPE (INCHES, OPTIONAL)',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x2),
                  for (final s in BodySite.values) ...[
                    OsTextField(
                      controller: _sites[s]!,
                      label: s.title,
                      hint: s.guidance,
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                    ),
                    const SizedBox(height: S.x3),
                  ],
                  const SizedBox(height: S.x2),
                  Text('PHOTOS', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x2),
                  if (_photos.isNotEmpty)
                    SizedBox(
                      height: 96,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          for (final ph in _photos)
                            _Thumb(ph, size: 96, label: ph.pose),
                        ],
                      ),
                    ),
                  const SizedBox(height: S.x2),
                  Wrap(
                    spacing: S.x2,
                    runSpacing: S.x2,
                    children: [
                      for (final pose in const ['front', 'side']) ...[
                        Pressable(
                          semanticLabel: 'Take a $pose photo',
                          onTap: () => _addPhoto(pose, camera: true),
                          child: Pill(
                            'Camera · ${pose == 'front' ? 'Front' : 'Side'}',
                            C.teal,
                            icon: LucideIcons.camera,
                          ),
                        ),
                        Pressable(
                          semanticLabel: 'Choose a $pose photo',
                          onTap: () => _addPhoto(pose, camera: false),
                          child: Pill(
                            'Photos · ${pose == 'front' ? 'Front' : 'Side'}',
                            C.n400,
                            icon: LucideIcons.image,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: S.x4),
                    Text(_error!, style: F.cap.copyWith(color: p.on(C.red))),
                  ],
                  const SizedBox(height: S.x5),
                  BigButton(
                    _busy ? 'Saving' : 'Save',
                    color: C.teal,
                    onTap: _busy ? null : _save,
                  ),
                  if (_changed) ...[
                    const SizedBox(height: S.x2),
                    Text(
                      'Photos are saved as soon as they are added.',
                      style: F.over.copyWith(color: p.ink3),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Thumb extends StatelessWidget {
  const _Thumb(
    this.photo, {
    this.size = 72,
    this.label,
    this.selected = false,
    this.onTap,
  });
  final BodyPhoto photo;
  final double size;
  final String? label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.only(right: S.x2),
      child: Pressable(
        semanticLabel: '${photo.pose} photo, ${_md(photo.date)}',
        onTap: onTap,
        child: Column(
          children: [
            Container(
              width: size * .75,
              height: size * .75 * 4 / 3 > size ? size : size * .75 * 4 / 3,
              decoration: BoxDecoration(
                borderRadius: R.rMd,
                border: Border.all(
                  color: selected ? p.on(C.teal) : p.line,
                  width: selected ? 2 : 1,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: FutureBuilder<File>(
                future: BodyLogDb.photoFile(photo),
                builder: (_, s) => s.data == null
                    ? const SizedBox.shrink()
                    : Image.file(
                        s.data!,
                        fit: BoxFit.cover,
                        cacheWidth: 200,
                        errorBuilder: (_, _, _) =>
                            Icon(LucideIcons.imageOff, color: p.ink3),
                      ),
              ),
            ),
            if (label != null)
              Text(label!, style: F.over.copyWith(color: p.ink3)),
          ],
        ),
      ),
    );
  }
}

// ── photo comparison ────────────────────────────────────────────────────────

/// Two independent panels. Tap a panel to make it active, then pick its
/// photo from the dated strip; the other panel stays. Any photo against any
/// other; same-pose filtering is a convenience. No overlay, no verdict.
class PhotoCompareScreen extends StatefulWidget {
  const PhotoCompareScreen({super.key, required this.photos});
  final List<BodyPhoto> photos;
  @override
  State<PhotoCompareScreen> createState() => _PhotoCompareScreenState();
}

class _PhotoCompareScreenState extends State<PhotoCompareScreen> {
  late BodyPhoto _left = widget.photos.first;
  late BodyPhoto _right = widget.photos.last;
  int _active = 1;
  String? _pose;

  List<BodyPhoto> get _strip => [
    for (final x in widget.photos)
      if (_pose == null || x.pose == _pose) x,
  ];

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget panel(int side, BodyPhoto ph) => Expanded(
      child: Pressable(
        semanticLabel:
            '${side == 0 ? 'Left' : 'Right'} panel, ${ph.pose} ${_md(ph.date)}${_active == side ? ', active' : ''}',
        onTap: () => setState(() => _active = side),
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 3 / 4,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: R.rLg,
                  border: Border.all(
                    color: _active == side ? p.on(C.teal) : p.line,
                    width: _active == side ? 2 : 1,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: FutureBuilder<File>(
                  future: BodyLogDb.photoFile(ph),
                  builder: (_, s) => s.data == null
                      ? const SizedBox.shrink()
                      : InteractiveViewer(
                          child: Image.file(
                            s.data!,
                            fit: BoxFit.contain,
                            errorBuilder: (_, _, _) => Center(
                              child: Text(
                                'File missing',
                                style: F.cap.copyWith(color: p.ink3),
                              ),
                            ),
                          ),
                        ),
                ),
              ),
            ),
            const SizedBox(height: S.x1),
            Text(
              '${_md(ph.date)} · ${ph.pose}',
              style: F.cap.copyWith(color: p.ink2),
            ),
          ],
        ),
      ),
    );
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Compare photos'),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Row(
                children: [
                  panel(0, _left),
                  Pressable(
                    semanticLabel: 'Swap sides',
                    onTap: () => setState(() {
                      final t = _left;
                      _left = _right;
                      _right = t;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.all(S.x2),
                      child: Icon(
                        LucideIcons.arrowLeftRight,
                        size: 18,
                        color: p.ink2,
                      ),
                    ),
                  ),
                  panel(1, _right),
                ],
              ),
            ),
            const SizedBox(height: S.x3),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Row(
                children: [
                  for (final (k, label) in const [
                    (null, 'All'),
                    ('front', 'Front'),
                    ('side', 'Side'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(right: S.x2),
                      child: Pressable(
                        semanticLabel: 'Show $label',
                        onTap: () => setState(() => _pose = k),
                        child: Pill(label, _pose == k ? C.teal : C.n400),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    'Picking for the ${_active == 0 ? 'left' : 'right'}',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x2),
            SizedBox(
              height: 112,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: S.x4),
                scrollDirection: Axis.horizontal,
                children: [
                  for (final ph in _strip)
                    _Thumb(
                      ph,
                      size: 96,
                      label: _md(ph.date),
                      selected: (_active == 0 ? _left : _right).id == ph.id,
                      onTap: () => setState(
                        () => _active == 0 ? _left = ph : _right = ph,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: S.x2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Text(
                'Light, pose and distance change how a photo looks. These are for your own eye; the app makes no judgement from them.',
                style: F.over.copyWith(color: p.ink3),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── history ─────────────────────────────────────────────────────────────────

class BodyHistoryScreen extends StatefulWidget {
  const BodyHistoryScreen({super.key, required this.data});
  final ProgressData data;
  @override
  State<BodyHistoryScreen> createState() => _BodyHistoryScreenState();
}

class _BodyHistoryScreenState extends State<BodyHistoryScreen> {
  late ProgressData d = widget.data;
  String _unit = 'kg';

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => _unit = p.getString('body.unit') ?? 'kg');
    });
  }

  Future<void> _refresh() async {
    final n = await ProgressData.load(context);
    if (mounted) setState(() => d = n);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final days = <String>{
      for (final w in d.weights) w.date,
      for (final m in d.measures) m.date,
      for (final ph in d.photos) ph.date,
    }.toList()..sort((a, b) => b.compareTo(a));
    String? month;
    final rows = <Widget>[];
    for (final day in days) {
      final mo = day.substring(0, 7);
      if (mo != month) {
        month = mo;
        rows.add(
          Padding(
            padding: const EdgeInsets.only(top: S.x4, bottom: S.x2),
            child: Text(
              '${_md('$mo-01').split(' ').first.toUpperCase()} ${mo.substring(0, 4)}',
              style: F.over.copyWith(color: p.ink3),
            ),
          ),
        );
      }
      final w = d.weights.where((x) => x.date == day).firstOrNull;
      final ms = d.measures.where((x) => x.date == day).toList();
      final ph = d.photos.where((x) => x.date == day).toList();
      rows.add(
        Surface(
          pad: const EdgeInsets.all(S.x3),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(_md(day), style: F.body.copyWith(color: p.ink)),
                  ),
                  if (w != null)
                    Text(
                      bodyWeightText(w, unit: _unit),
                      style: F.n17.copyWith(color: p.ink),
                    ),
                ],
              ),
              for (final m in ms)
                Text(
                  [
                    for (final s in BodySite.values)
                      if (m.value(s) != null)
                        '${s.title} ${_num(m.value(s)!, 2)}',
                  ].join(' · '),
                  style: F.cap.copyWith(color: p.ink3),
                ),
              if (ph.isNotEmpty)
                SizedBox(
                  height: 80,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final x in ph)
                        _Thumb(
                          x,
                          size: 72,
                          onTap: () async {
                            if (await confirmRemove(
                              c,
                              title: 'Delete this photo?',
                              body:
                                  '${x.pose} photo from ${_md(x.date)}. That day\'s weight and measurements stay.',
                              remove: 'Delete',
                            )) {
                              await BodyLogDb.deletePhoto(x);
                              await _refresh();
                            }
                          },
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  Pressable(
                    semanticLabel: 'Edit ${_md(day)}',
                    onTap: () async {
                      final changed = await Navigator.of(c).push<bool>(
                        MaterialPageRoute(
                          builder: (_) => BodyEntryScreen(
                            unit: _unit,
                            date: day,
                            measure: ms.firstOrNull,
                          ),
                        ),
                      );
                      if (changed == true) await _refresh();
                    },
                    child: Padding(
                      padding: const EdgeInsets.only(top: S.x2, right: S.x4),
                      child: Text('Edit', style: F.cap.copyWith(color: p.ink2)),
                    ),
                  ),
                  if (w != null)
                    Pressable(
                      semanticLabel: 'Delete weight on ${_md(day)}',
                      onTap: () async {
                        if (await confirmRemove(
                          c,
                          title: 'Delete ${_md(day)}\'s weight?',
                          body: 'Photos and measurements from that day stay.',
                          remove: 'Delete',
                        )) {
                          await BodyLogDb.deleteWeight(day);
                          await _refresh();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: S.x2, right: S.x4),
                        child: Text(
                          'Delete weight',
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ),
                    ),
                  for (final m in ms)
                    Pressable(
                      semanticLabel: 'Delete measurements on ${_md(day)}',
                      onTap: () async {
                        if (await confirmRemove(
                          c,
                          title: 'Delete these measurements?',
                          body: 'From ${_md(day)}. Its weight and photos stay.',
                          remove: 'Delete',
                        )) {
                          await BodyLogDb.deleteMeasure(m.id);
                          await _refresh();
                        }
                      },
                      child: Padding(
                        padding: const EdgeInsets.only(top: S.x2),
                        child: Text(
                          'Delete tape',
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
      rows.add(const SizedBox(height: S.x2));
    }
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Body history'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: rows.isEmpty
                    ? [
                        Text(
                          'Nothing recorded yet.',
                          style: F.cap.copyWith(color: p.ink3),
                        ),
                      ]
                    : rows,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── settings ────────────────────────────────────────────────────────────────

class BodySettingsScreen extends StatefulWidget {
  const BodySettingsScreen({super.key, required this.data});
  final ProgressData data;
  @override
  State<BodySettingsScreen> createState() => _BodySettingsScreenState();
}

class _BodySettingsScreenState extends State<BodySettingsScreen> {
  int _weekday = DateTime.saturday;
  bool _reminder = false;
  String? _baseline;

  static const _names = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final wd = await BodyLogDb.measureWeekday();
    final p = await SharedPreferences.getInstance();
    final b = await CalculationStore.read(ProgressData.baselineKey);
    if (!mounted) return;
    setState(() {
      _weekday = wd;
      _reminder = p.getBool('body.reminder') ?? false;
      _baseline = b;
    });
  }

  Future<void> _setReminder(bool on) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('body.reminder', on);
    if (on) {
      await NotificationService.instance.scheduleWeekly(
        id: NotificationService.idBodyReminder,
        category: NotifCategory.reminders,
        title: 'Measurement day',
        body: 'Weigh in and take your tape measurements in Progress.',
        weekday: _weekday,
        hour: 8,
        minute: 0,
      );
    } else {
      await NotificationService.instance.cancel(
        NotificationService.idBodyReminder,
      );
    }
    setState(() => _reminder = on);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final d = widget.data;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Body settings'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  Section(
                    'Measurement day',
                    Surface(
                      pad: const EdgeInsets.symmetric(horizontal: S.x4),
                      child: Column(
                        children: [
                          for (var i = 1; i <= 7; i++)
                            Pressable(
                              semanticLabel: _names[i - 1],
                              onTap: () async {
                                await BodyLogDb.setMeasureWeekday(i);
                                setState(() => _weekday = i);
                                if (_reminder) await _setReminder(true);
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: S.x3,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      _weekday == i
                                          ? LucideIcons.circleDot
                                          : LucideIcons.circle,
                                      size: 18,
                                      color: p.ink2,
                                    ),
                                    const SizedBox(width: S.x3),
                                    Text(
                                      _names[i - 1],
                                      style: F.body.copyWith(color: p.ink),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  Surface(
                    onTap: () => _setReminder(!_reminder),
                    semanticLabel:
                        'Weekly reminder ${_reminder ? 'on' : 'off'}',
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Weekly reminder',
                                style: F.body.copyWith(color: p.ink),
                              ),
                              Text(
                                '8:00 on ${_names[_weekday - 1]}',
                                style: F.over.copyWith(color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        Pill(
                          _reminder ? 'On' : 'Off',
                          _reminder ? C.teal : C.n400,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  Surface(
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: c,
                        initialDate: DateTime.parse(
                          _baseline ?? d.earliest ?? todayLabel(),
                        ),
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                      );
                      if (picked == null) return;
                      final v = dayLabelOf(picked);
                      await CalculationStore.write(ProgressData.baselineKey, v);
                      setState(() => _baseline = v);
                    },
                    semanticLabel: 'Journey start',
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Journey start',
                                style: F.body.copyWith(color: p.ink),
                              ),
                              Text(
                                'What "Since start" compares against. Earlier records stay in All.',
                                style: F.over.copyWith(color: p.ink3),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          _baseline == null
                              ? (d.earliest == null ? '—' : _md(d.earliest!))
                              : _md(_baseline!),
                          style: F.cap.copyWith(color: p.ink2),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: S.x4),
                  Text(
                    d.heightCm == null
                        ? 'Add your height in Settings → Profile for the waist-to-height and body-fat estimates.'
                        : 'Estimates use your profile height, ${d.heightCm!.round()} cm.',
                    style: F.cap.copyWith(color: p.ink3),
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

// Progress (build 87): the one recomposition page — leaner while getting
// stronger — with Body inside it. Body progress first (weight and tape with
// a measurement and a range menu, dated Start / Latest / Change, entries and
// two-panel photo comparison), with dated strength, food, activity and recovery,
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

import '../../compute/profile.dart' show isLiftType, Profile, bmrMifflin;
import '../../data/body_log.dart';
import '../../data/calculation_store.dart';
import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/goal_plan.dart';
import '../../data/goal_review.dart';
import '../../data/lift_log.dart';
import '../../data/lift_progress.dart' show SetVerdict;
import '../../data/nutrition_store.dart';
import '../../data/photo_encode.dart';
import '../../data/progress_milestones.dart';
import '../../data/progress_review.dart';
import '../../gps/run_history.dart' show isRunType, isWalkType;
import '../../notify/notification_event.dart' show NotifCategory;
import '../../notify/notification_service.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show pad, pointsOf, pullToRefresh, repoOf, thousands;
import 'journal_compose.dart' show OsTextField;
import 'metric_detail.dart' show detailScaffold;
import 'progress_routes.dart';
import 'today_plan.dart' show PlanRow;

part 'progress_details.dart';

const _camera = MethodChannel('openstrap/camera');

/// B88-12 (C6): one tape reading, or two of the same site averaged. Two
/// readings more than half an inch apart are refused: one of them is off.
@visibleForTesting
double tapeReading(String site, String text) {
  final parts = text
      .replaceAll(',', '.')
      .split(RegExp(r'[\s/]+'))
      .where((x) => x.isNotEmpty)
      .toList();
  final vs = [for (final x in parts) double.tryParse(x)];
  if (vs.isEmpty || vs.length > 2 || vs.any((v) => v == null || v <= 0)) {
    throw BodyLogError('$site must be one number, or two from measuring twice.');
  }
  if (vs.length == 2 && (vs[0]! - vs[1]!).abs() > 0.5) {
    throw BodyLogError(
      'The two $site readings are more than half an inch apart. Measure again.',
    );
  }
  return vs.length == 1 ? vs[0]! : (vs[0]! + vs[1]!) / 2;
}

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
    this.measureWeekday = DateTime.saturday,
    this.goal = const GoalPlan(phase: GoalPhase.recomp),
    this.goalChosen = false,
    this.user = const {},
    this.readErrors = const [],
  });

  /// The goal you chose (recomposition until you choose), and the profile
  /// the advice reads its calorie goal and resting energy from.
  final GoalPlan goal;
  final bool goalChosen;
  final Map<String, dynamic> user;
  final List<String> readErrors;

  /// Body's measurement weekday: weekly weight blocks start on it.
  final int measureWeekday;

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
      ...weights.map((x) => x.date),
      ...measures.map((x) => x.date),
      ...photos.map((x) => x.date),
      ...food.map((x) => x.date),
      ...sessions.map((x) => x.date),
      ...lifts.map((x) => dayLabelOf(x.startedAt)),
      ...steps.map((x) => x.date),
      ...sleepMin.map((x) => x.date),
      ...recovery.map((x) => x.date),
    ]..sort();
    return ds.isEmpty ? null : ds.first;
  }

  static const baselineKey = progressBaselineKey;

  /// Build 90: the overview's one review, over the goal's closed weeks.
  GoalReview review(String today) => goalReview(
    plan: goal,
    today: today,
    weights: weights,
    measures: measures,
    lifts: lifts,
    food: food,
    steps: steps,
    sleepMin: sleepMin,
    recovery: recovery,
    sessions: sessions,
    currentGoal: (user['kcal_target'] as num?)?.toDouble(),
    restingKcal: bmrMifflin(Profile.fromMap(user)),
    female: (user['sex'] as String?)?.toLowerCase().startsWith('f') ?? false,
  );

  static Future<ProgressData> load(
    BuildContext c, {
    ProgressData? previous,
  }) async {
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
    final errors = <String>[];
    Future<T> read<T>(String label, Future<T> future, T fallback) async {
      try {
        return await future;
      } catch (_) {
        errors.add(label);
        return fallback;
      }
    }

    Future<Map<String, dynamic>?> get(String k) => read(
      k,
      repo?.getChart(k) ?? Future.error(StateError('No repository')),
      null,
    );
    // ponytail: retained history is materialized here; multi-year diaries need
    // SQL day aggregates and paged details before memory becomes a constraint.
    final byDay = await read(
      'Food',
      NutritionDb.entriesSince(db, '0000-00-00'),
      <String, List<FoodEntry>>{},
    );
    final marks = await read(
      'Food',
      NutritionDb.dayMarks(db, '0000-00-00', strict: true),
      <String, String>{},
    );
    final win = NutritionWindow([
      for (final date in byDay.keys.toList()..sort())
        rollupDay(date, byDay[date]!, today: todayLabel(), mark: marks[date]),
    ]);
    final now = DateTime.now();
    Future<List<DatedValue>> dated(String key, List<DatedValue>? saved) async {
      final value = await get(key);
      return errors.contains(key) ? saved ?? const [] : chart(value);
    }

    final sessions = await read(
      'Workouts',
      LocalDb.sessionsInRange(0, now.millisecondsSinceEpoch ~/ 1000),
      <Map<String, dynamic>>[],
    );
    return ProgressData(
      weights: await read(
        'Weight',
        BodyLogDb.weights(),
        previous?.weights ?? <BodyWeightRow>[],
      ),
      measures: await read(
        'Measurements',
        BodyLogDb.measures(),
        previous?.measures ?? <BodyMeasure>[],
      ),
      photos: await read(
        'Photos',
        BodyLogDb.photos(),
        previous?.photos ?? <BodyPhoto>[],
      ),
      lifts: await read(
        'Lifts',
        LiftLogDb.finished(),
        previous?.lifts ?? <LiftWorkout>[],
      ),
      food: errors.contains('Food') && previous != null
          ? previous.food
          : [
              for (final d in win.days)
                (
                  date: d.date,
                  kcal: d.kcal.value,
                  counts: d.countsTowardAverages,
                  protein: d.protein.value,
                  proteinComplete: d.protein.complete,
                ),
            ],
      steps: await dated('steps', previous?.steps),
      sleepMin: await dated('sleep', previous?.sleepMin),
      recovery: await dated('recovery', previous?.recovery),
      sessions: errors.contains('Workouts') && previous != null
          ? previous.sessions
          : [
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
      baseline: await read<String?>(
        'Baseline',
        CalculationStore.read(baselineKey),
        previous?.baseline,
      ),
      heightCm: (user['height_cm'] as num?)?.toDouble(),
      measureWeekday: await read(
        'Measurement day',
        BodyLogDb.measureWeekday(),
        previous?.measureWeekday ?? DateTime.saturday,
      ),
      goal: await read(
        'Goal',
        GoalPlan.read(strict: true),
        previous?.goal ?? const GoalPlan(phase: GoalPhase.recomp),
      ),
      goalChosen: await read(
        'Goal selection',
        GoalPlan.isChosen(),
        previous?.goalChosen ?? false,
      ),
      readErrors: errors.toSet().toList(),
      user: user,
    );
  }
}

class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key, this.data});
  final ProgressData? data;
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen>
    with RevisionReload, _ProgressCommon {
  @override
  ProgressData? get _fixed => widget.data;

  @override
  void initState() {
    super.initState();
    _d = widget.data;
    _prefs();
  }

  @override
  Widget build(BuildContext c) {
    final d = _d;
    return RefreshIndicator(
      onRefresh: () => pullToRefresh(c, reload),
      child: ListView(
        padding: pad,
        children: [
          // The goal card names the goal; no kicker repeats it.
          const ScreenTitle('Progress'),
          if (_failed)
            StatusCard(
              'Progress could not load',
              'Your saved records are intact.',
              fix: 'Retry',
              onFix: reload,
            ),
          if (d == null && !_failed)
            const Center(child: CircularProgressIndicator()),
          if (d != null) ...[
            if (d.readErrors.isNotEmpty) _readErrors(c, d),
            ..._overview(c, d),
          ],
        ],
      ),
    );
  }

  /// Build 90: the overview judges the goal and shows the evidence for it,
  /// all from the goal's own closed weeks (`goalReview`). Charts, histories,
  /// methods and every other period live on the detail pages.
  List<Widget> _overview(BuildContext c, ProgressData d) {
    final p = P.of(c);
    final r = d.review(todayLabel());
    return [
      Row(
        children: [
          Expanded(
            child: BigButton(
              'Add body entry',
              icon: LucideIcons.plus,
              color: C.teal,
              soft: true,
              onTap: () => _addEntry(c, d),
            ),
          ),
          const SizedBox(width: S.x2),
          IconButton(
            tooltip: 'Body settings',
            onPressed: () => _settings(c, d),
            icon: Icon(LucideIcons.settings2, color: p.onGround),
          ),
        ],
      ),
      const SizedBox(height: S.x3),
      _goalCard(c, p, d, r),
      const SizedBox(height: S.x4),
      Section('Results', _outcomes(c, p, d, r)),
      const SizedBox(height: S.x4),
      _inputs(c, p, r),
      const SizedBox(height: S.x4),
      _photoStrip(c, p, d),
    ];
  }

  // ── the goal ──

  /// The record families the goal review reads. A failed steps, sleep or
  /// recovery read leaves the verdict standing (it uses none of them).
  static const _reviewFamilies = {
    'Weight',
    'Food',
    'Lifts',
    'Measurements',
    'Goal',
    'Goal selection',
  };

  Widget _goalCard(BuildContext c, P p, ProgressData d, GoalReview r) {
    final a = r.advice;
    final unavailable = d.readErrors.any(_reviewFamilies.contains);
    final (word, color) = unavailable
        ? ('Unavailable', C.n400)
        : switch (a.verdict) {
            GoalVerdict.onTrack => ('On track', C.green),
            GoalVerdict.adjust => ('Adjust', C.orange),
            GoalVerdict.reviewRecovery => ('Review', C.yellow),
            GoalVerdict.needMore => ('Not yet', C.n400),
          };
    final days = r.daysOnGoal;
    final lines = unavailable
        ? const ['Review unavailable until the records refresh.']
        : a.verdict == GoalVerdict.needMore
        ? [
            ...a.because.take(3),
            if (a.because.length > 3)
              'and ${a.because.length - 3} more · Details',
          ]
        : a.because.take(1).toList();
    return Surface(
      onTap: () => _goalDetails(c, d, r),
      semanticLabel:
          'Goal ${r.plan.phase.title}. $word. ${unavailable ? '' : a.headline}. Details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Wraps rather than squeezing: at large text the verdict word drops
          // under the goal line instead of overflowing it.
          Wrap(
            spacing: S.x3,
            runSpacing: S.x1,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                [
                  'Goal · ${r.plan.phase.title}',
                  if (days != null) 'day ${days + 1}',
                ].join(' · '),
                style: F.cap.copyWith(
                  color: p.ink2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                word,
                style: F.label.copyWith(
                  color: p.on(color),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x1),
          Text(
            '${reviewWeekLabel(r.after.from, r.after.to)} vs '
            '${reviewWeekLabel(r.before.from, r.before.to)}',
            style: F.cap.copyWith(color: p.ink2),
          ),
          const SizedBox(height: S.x2),
          Row(
            children: [
              Expanded(
                child: Text(
                  unavailable ? 'Not available' : a.headline,
                  style: F.t2.copyWith(color: p.ink),
                ),
              ),
              Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
            ],
          ),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(top: S.x1),
              child: Text(line, style: F.body.copyWith(color: p.ink2)),
            ),
          if (a.next != null && !unavailable) ...[
            const SizedBox(height: S.x2),
            Text(
              'Next: ${a.next!}',
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _goalDetails(BuildContext c, ProgressData d, GoalReview r) async {
    final g = r.plan;
    final band = g.band;
    String pct(double v) =>
        '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';
    final change = await showDialog<bool>(
      context: c,
      builder: (dc) => AlertDialog(
        title: Text(g.phase.title),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in [
                'Compares ${reviewWeekLabel(r.after.from, r.after.to)} with '
                    '${reviewWeekLabel(r.before.from, r.before.to)}: the last '
                    '${g.windowWeeks == 1 ? 'closed week with the one' : '${g.windowWeeks} closed weeks with the ${g.windowWeeks}'} before.',
                'Aim ${pct(band.low)} to ${pct(band.high)} a week · protein '
                    '${band.proteinLow}–${band.proteinHigh} g/kg',
                if (g.since != null) 'Since ${_md(g.since!)}',
                if (d.readErrors.any(_reviewFamilies.contains))
                  'Review unavailable until the records refresh.'
                else ...[
                  r.advice.headline,
                  ...r.advice.because,
                  ?r.advice.next,
                ],
                'Suggestions only. Your goals are never changed automatically. '
                    'Changing the History range on the detail pages never '
                    'changes this review.',
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: S.x3),
                  child: Text(line, style: F.body.copyWith(color: P.of(dc).ink2)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dc).pop(true),
            child: const Text('Change goal'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dc).pop(false),
            child: const Text('Close'),
          ),
        ],
      ),
    );
    if (change != true || !c.mounted) return;
    final kg = BodyLogDb.sevenDayMean(d.weights, todayLabel())?.kg;
    final changed = await Navigator.of(c).push<bool>(
      MaterialPageRoute(builder: (_) => GoalScreen(plan: g, kg: kg)),
    );
    if (changed == true) reload();
  }

  // ── the three results ──

  Widget _outcomes(BuildContext c, P p, ProgressData d, GoalReview r) {
    double u(double kg) => _unit == 'lb' ? kg * kLbPerKg : kg;
    String signed(double v, String unit, [int places = 1]) =>
        '${v >= 0 ? '+' : '−'}${_num(v.abs(), places)} $unit';
    final before = reviewWeekLabel(r.before.from, r.before.to);
    final after = reviewWeekLabel(r.after.from, r.after.to);
    final wa = r.weightAfter, wb = r.weightBefore;
    final weight = (
      value: wa.mean == null ? '—' : '${_num(u(wa.mean!))} $_unit',
      sub: wa.mean == null
          ? 'No weigh-in in $after'
          : r.weightChangeKg == null
          ? 'Average of ${wa.count} weigh-ins · none in $before to compare'
          : '${signed(u(r.weightChangeKg!), _unit)} vs $before · '
                '${wa.count} and ${wb.count} weigh-ins',
    );
    final latest = r.waistLatest;
    final waist = (
      value: latest == null ? '—' : '${_num(latest.value, 2)} in',
      sub: latest == null
          ? 'No waist reading yet'
          : r.waistFrom != null && r.waistTo != null
          ? '${signed(r.waistTo!.value - r.waistFrom!.value, 'in', 2)} · '
                '${_md(r.waistFrom!.date)} → ${_md(r.waistTo!.date)}'
          : 'Latest ${_md(latest.date)} · no reading near '
                '${_md(r.before.from)} to compare',
    );
    final comparable = [
      for (final x in r.lifts)
        if (x.change != SetVerdict.incomparable) x,
    ];
    final up = comparable.where((x) => x.change == SetVerdict.better).length;
    final down = comparable.where((x) => x.change == SetVerdict.worse).length;
    final apart = r.lifts.length - comparable.length;
    final strength = (
      value: comparable.isEmpty ? '—' : '$up of ${comparable.length}',
      sub: r.lifts.isEmpty
          ? 'No lift on the same setup in both halves'
          : comparable.isEmpty
          ? '${r.lifts.length} ${r.lifts.length == 1 ? 'lift' : 'lifts'}, none comparable'
          : [
              'improved',
              if (comparable.length - up - down > 0)
                '${comparable.length - up - down} same',
              if (down > 0) '$down down',
              if (apart > 0) '$apart not comparable',
            ].join(' · '),
    );
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
      child: Column(
        children: [
          _outcomeRow(c, p, 'Weight', weight.value, weight.sub, ProgressDest.weight),
          Divider(color: p.line, height: 1),
          _outcomeRow(c, p, 'Waist', waist.value, waist.sub, ProgressDest.waist),
          Divider(color: p.line, height: 1),
          _outcomeRow(
            c,
            p,
            'Strength',
            strength.value,
            strength.sub,
            ProgressDest.strength,
          ),
        ],
      ),
    );
  }

  Widget _outcomeRow(
    BuildContext c,
    P p,
    String label,
    String value,
    String sub,
    ProgressDest dest,
  ) => Pressable(
    semanticLabel: '$label: $value. $sub. Details',
    onTap: () => openProgress(c, dest, _d),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(sub, style: F.cap.copyWith(color: p.ink2)),
              ],
            ),
          ),
          const SizedBox(width: S.x3),
          Text(value, style: F.n17.copyWith(color: p.ink)),
          const SizedBox(width: S.x1),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ),
    ),
  );

  // ── what went in ──

  Widget _inputs(BuildContext c, P p, GoalReview r) {
    final f = r.food;
    final parts = <String>[
      f.kcal == null
          ? 'Food: no counted day'
          : '${thousands(f.kcal!)} kcal (${f.kcalDays} ${f.kcalDays == 1 ? 'day' : 'days'})',
      if (f.protein != null)
        '${f.protein!.round()} g protein (${f.proteinDays} ${f.proteinDays == 1 ? 'day' : 'days'})',
      '${r.workouts.total} ${r.workouts.total == 1 ? 'workout' : 'workouts'}',
      if (r.steps.average != null)
        '${thousands(r.steps.average!)} steps a day (${r.steps.days} days)',
      if (r.sleep.minutes case final m?)
        'sleep ${m ~/ 60}h ${(m % 60).round()}m (${r.sleep.nights} nights)',
      if (r.recovery.pct case final v?)
        'recovery ${v.round()}% (${r.recovery.days} days)',
    ];
    return Surface(
      onTap: () => openProgress(c, ProgressDest.food, _d),
      semanticLabel: 'What went in: ${parts.join(', ')}. Details',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'What went in · ${reviewWeekLabel(r.after.from, r.after.to)}',
                  style: F.cap.copyWith(
                    color: p.ink2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: S.x1),
                Text(parts.join(' · '), style: F.body.copyWith(color: p.ink)),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ),
    );
  }

  // ── photos ──

  Widget _photoStrip(BuildContext c, P p, ProgressData d) {
    final recent = d.photos.reversed.take(4).toList();
    return Surface(
      onTap: d.photos.isEmpty
          ? () => _addEntry(c, d)
          : () => Navigator.of(c).push(
              MaterialPageRoute<void>(
                builder: (_) => PhotoCompareScreen(photos: d.photos),
              ),
            ),
      semanticLabel: d.photos.isEmpty ? 'Add a photo' : 'Compare photos',
      child: Row(
        children: [
          if (recent.isEmpty)
            Icon(LucideIcons.images, size: 20, color: p.ink2)
          else
            for (final ph in recent.reversed)
              Padding(
                padding: const EdgeInsets.only(right: S.x2),
                child: _Thumb(ph, size: 52, label: _md(ph.date)),
              ),
          const SizedBox(width: S.x2),
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
                      ? 'No photos yet · Add'
                      : '${d.photos.length} · latest ${_md(d.photos.last.date)} · Compare',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ),
    );
  }
}

/// What the overview and the detail pages share: the loaded data, the unit,
/// the shared sheets and the small figure block.
mixin _ProgressCommon<T extends StatefulWidget> on RevisionReload<T> {
  ProgressData? _d;
  bool _failed = false;
  String _unit = 'kg';

  /// Data handed in by a test or the gallery: shown as is, never reloaded.
  ProgressData? get _fixed;

  Future<void> _prefs() async {
    try {
      final p = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _unit = p.getString('body.unit') == 'lb' ? 'lb' : 'kg');
      _prefsLoaded(p);
    } catch (_) {}
  }

  /// A detail page reads its own saved choices here.
  void _prefsLoaded(SharedPreferences p) {}

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
  Future<void> reload() async {
    if (_fixed != null) return;
    final t = beginRead(#progress);
    try {
      final d = await ProgressData.load(context, previous: _d);
      if (stillNewest(#progress, t)) setState(() => (_d = d, _failed = false));
    } catch (_) {
      if (stillNewest(#progress, t)) setState(() => _failed = true);
    }
  }

  Widget _readErrors(BuildContext c, ProgressData d) => Row(
    children: [
      Expanded(
        child: Text(
          '${d.readErrors.join(', ')} could not refresh. Saved view retained where available.',
          style: F.cap.copyWith(color: P.of(c).on(C.orange)),
        ),
      ),
      TextButton(onPressed: reload, child: const Text('Retry')),
    ],
  );

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
  /// Drawn as one row of Today's plan card rather than its own card.
  const TodayBodyRow({super.key, this.embedded = false});
  final bool embedded;
  @override
  State<TodayBodyRow> createState() => _TodayBodyRowState();
}

class _TodayBodyRowState extends State<TodayBodyRow> with RevisionReload {
  ({double kg, int count})? _mean;
  bool _today = false;
  String _unit = 'kg';

  /// Today is the measurement weekday and no tape is logged yet.
  bool _tapeDue = false;

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
      final u =
          (await SharedPreferences.getInstance()).getString('body.unit') ??
          'kg';
      final today = todayLabel();
      final wd = await BodyLogDb.measureWeekday();
      final measured = (await BodyLogDb.measures()).any((m) => m.date == today);
      if (!stillNewest(#todayBody, t)) return;
      setState(() {
        _mean = BodyLogDb.sevenDayMean(ws, today);
        _today = ws.any((w) => w.date == today);
        _unit = u;
        _tapeDue = DateTime.now().weekday == wd && !measured;
      });
    } catch (_) {}
  }

  Future<void> _entry(BuildContext c) async {
    final changed = await Navigator.of(c).push<bool>(
      MaterialPageRoute(builder: (_) => BodyEntryScreen(unit: _unit)),
    );
    if (changed == true) reload();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final m = _mean;
    if (widget.embedded) {
      final mean = m == null
          ? null
          : '${_num(_unit == 'lb' ? m.kg * kLbPerKg : m.kg)} $_unit';
      return PlanRow(
        icon: LucideIcons.scale,
        color: C.teal,
        title: _tapeDue
            ? 'Measurement day'
            : _today
            ? 'Weighed in'
            : 'Weigh in',
        sub: _tapeDue
            ? 'Take your tape today${mean == null ? '' : ' · 7-day $mean'}'
            : mean == null
            ? 'No weigh-ins this week'
            : '7-day $mean · ${m!.count} ${m.count == 1 ? 'reading' : 'readings'}',
        action: !_today
            ? 'Weigh in'
            : _tapeDue
            ? 'Measure'
            : null,
        onAction: () => _entry(c),
        onTap: () => openProgress(c, ProgressDest.weight),
      );
    }
    return Surface(
      onTap: () => openProgress(c, ProgressDest.weight),
      semanticLabel: 'Body. Opens Progress',
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Body',
                  style: F.body.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  m == null
                      ? 'No weigh-ins this week'
                      : '7-day ${_num(_unit == 'lb' ? m.kg * kLbPerKg : m.kg)} $_unit · '
                            '${m.count} ${m.count == 1 ? 'reading' : 'readings'}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
                if (_tapeDue)
                  Text(
                    'Measurement day: take your tape today',
                    style: F.cap.copyWith(color: p.on(C.teal)),
                  ),
              ],
            ),
          ),
          if (_tapeDue && _today)
            Pressable(
              semanticLabel: 'Take measurements',
              onTap: () async {
                final changed = await Navigator.of(c).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BodyEntryScreen(unit: _unit),
                  ),
                );
                if (changed == true) reload();
              },
              child: Pill('Measure', C.teal, icon: LucideIcons.ruler),
            ),
          if (!_today)
            Pressable(
              semanticLabel: 'Log weigh-in',
              onTap: () async {
                final changed = await Navigator.of(c).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => BodyEntryScreen(unit: _unit),
                  ),
                );
                if (changed == true) reload();
              },
              child: Pill('Weigh in', C.teal, icon: LucideIcons.plus),
            ),
          const SizedBox(width: S.x2),
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ],
      ),
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
        final t = _sites[s]!.text.trim();
        if (t.isEmpty) continue;
        inches[s.name] = tapeReading(s.title, t);
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
                  const SizedBox(height: S.x1),
                  // B88-12 (C6): what makes two tape readings comparable.
                  Text(
                    'Same spot and same time of day each time, relaxed, tape '
                    'snug but not pressing. Measured twice? Enter both, like '
                    '34.5 34.75, and the average is kept.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                  const SizedBox(height: S.x2),
                  for (final s in BodySite.values) ...[
                    OsTextField(
                      controller: _sites[s]!,
                      label: s.title,
                      hint: s.guidance,
                      // Signed numbers open iOS's numbers-and-punctuation
                      // keyboard, which has the space a second reading needs.
                      keyboard: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: true,
                      ),
                    ),
                    const SizedBox(height: S.x3),
                  ],
                  const SizedBox(height: S.x2),
                  Text('PHOTOS', style: F.over.copyWith(color: p.ink3)),
                  const SizedBox(height: S.x2),
                  if (_photos.isNotEmpty)
                    SizedBox(
                      height:
                          96 +
                          MediaQuery.textScalerOf(c).scale(F.over.fontSize!) *
                              2,
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
    if (widget.photos.isEmpty) {
      return Scaffold(
        backgroundColor: p.bg,
        body: SafeArea(
          child: ListView(
            children: [
              const NavBar('Compare photos'),
              Text('No photos yet', style: F.cap.copyWith(color: p.ink3)),
            ],
          ),
        ),
      );
    }
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
        child: ListView(
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
              child: Wrap(
                spacing: S.x2,
                runSpacing: S.x2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (k, label) in const [
                    (null, 'All'),
                    ('front', 'Front'),
                    ('side', 'Side'),
                  ])
                    Pressable(
                      semanticLabel: 'Show $label',
                      onTap: () => setState(() => _pose = k),
                      child: Pill(label, _pose == k ? C.teal : C.n400),
                    ),
                  Text(
                    'Picking for the ${_active == 0 ? 'left' : 'right'}',
                    style: F.over.copyWith(color: p.ink3),
                  ),
                ],
              ),
            ),
            const SizedBox(height: S.x2),
            SizedBox(
              height:
                  96 + MediaQuery.textScalerOf(c).scale(F.over.fontSize!) * 2,
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
    final blocks = BodyLogDb.weekBlocks(d.weights, DateTime.monday);
    double u(double kg) => _unit == 'lb' ? kg * kLbPerKg : kg;
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
        // Weekly weight blocks, by the month they start in (Body parity).
        final inMonth = [
          for (final b in blocks)
            if (b.from.startsWith(mo)) b,
        ];
        if (inMonth.isNotEmpty) {
          rows.add(
            Surface(
              pad: const EdgeInsets.all(S.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('Weekly averages', style: F.cap.copyWith(color: p.ink2)),
                  for (final b in inMonth)
                    Padding(
                      padding: const EdgeInsets.only(top: S.x1),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '${_md(b.from)} – ${_md(b.to)} · '
                              '${b.count} ${b.count == 1 ? 'reading' : 'readings'}',
                              style: F.cap.copyWith(color: p.ink3),
                            ),
                          ),
                          Text(
                            [
                              '${_num(u(b.kg))} $_unit',
                              if (b.change case final ch?)
                                '${ch >= 0 ? '+' : '−'}${_num(u(ch.abs()))}',
                            ].join('  '),
                            style: F.cap.copyWith(color: p.ink),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          );
          rows.add(const SizedBox(height: S.x2));
        }
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
  int _hour = 8;
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
      _hour = p.getInt('body.reminder.hour') ?? 8;
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
        hour: _hour,
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
                                '$_hour:00 on ${_names[_weekday - 1]}',
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
                  if (_reminder) ...[
                    const SizedBox(height: S.x2),
                    Wrap(
                      spacing: S.x2,
                      runSpacing: S.x2,
                      children: [
                        for (final h in const [6, 7, 8, 9, 10])
                          Pressable(
                            semanticLabel: 'Remind at $h:00',
                            onTap: () async {
                              final pr = await SharedPreferences.getInstance();
                              await pr.setInt('body.reminder.hour', h);
                              setState(() => _hour = h);
                              await _setReminder(true);
                            },
                            child: Pill('$h:00', _hour == h ? C.teal : C.n400),
                          ),
                      ],
                    ),
                  ],
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

/// Choose and change your goal (build 86): the phase, its pace or your
/// training age where that changes the aim, with what each one means.
class GoalScreen extends StatefulWidget {
  const GoalScreen({super.key, required this.plan, this.kg});
  final GoalPlan plan;
  final double? kg;
  @override
  State<GoalScreen> createState() => _GoalScreenState();
}

class _GoalScreenState extends State<GoalScreen> {
  late GoalPhase _phase = widget.plan.phase;
  late GoalPace _pace = widget.plan.pace;
  late TrainingAge _age = widget.plan.trainingAge;
  bool _saving = false;

  GoalPlan get _draft =>
      GoalPlan(phase: _phase, pace: _pace, trainingAge: _age);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final band = _draft.band;
    String pct(double v) =>
        '${v >= 0 ? '+' : '−'}${v.abs().toStringAsFixed(2)}%';
    String kgWeek(double v) => widget.kg == null
        ? ''
        : ' (${v >= 0 ? '+' : '−'}${(widget.kg! * v.abs() / 100).toStringAsFixed(2)} kg)';
    Widget option(String title, String sub, bool on, VoidCallback tap) =>
        Pressable(
          semanticLabel: title,
          onTap: tap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  on ? LucideIcons.circleDot : LucideIcons.circle,
                  size: 18,
                  color: on ? p.on(C.teal) : p.ink3,
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: F.body.copyWith(color: p.ink)),
                      if (sub.isNotEmpty)
                        Text(sub, style: F.cap.copyWith(color: p.ink3)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return detailScaffold(c, 'Your goal', [
      Surface(
        pad: const EdgeInsets.symmetric(horizontal: S.x4),
        child: Column(
          children: [
            for (final ph in GoalPhase.values)
              option(
                ph.title,
                ph.plain,
                _phase == ph,
                () => setState(() => _phase = ph),
              ),
          ],
        ),
      ),
      if (_phase == GoalPhase.fatLoss) ...[
        const SizedBox(height: S.x4),
        Text('PACE', style: F.section.copyWith(color: p.ink3)),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (final pc in GoalPace.values)
                option(
                  pc.title,
                  () {
                    final b = GoalPlan(phase: GoalPhase.fatLoss, pace: pc).band;
                    return '${pct(b.high)} to ${pct(b.low)} a week${kgWeek(b.low)}'
                        '${pc == GoalPace.faster ? '. Harder to keep strength.' : ''}';
                  }(),
                  _pace == pc,
                  () => setState(() => _pace = pc),
                ),
            ],
          ),
        ),
      ],
      if (_phase == GoalPhase.leanGain) ...[
        const SizedBox(height: S.x4),
        Text('TRAINING AGE', style: F.section.copyWith(color: p.ink3)),
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4),
          child: Column(
            children: [
              for (final a in TrainingAge.values)
                option(
                  a.title,
                  () {
                    final b = GoalPlan(
                      phase: GoalPhase.leanGain,
                      trainingAge: a,
                    ).band;
                    return '${pct(b.low)} to ${pct(b.high)} a week${kgWeek(b.high)}';
                  }(),
                  _age == a,
                  () => setState(() => _age = a),
                ),
            ],
          ),
        ),
      ],
      const SizedBox(height: S.x4),
      Surface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'What the review will aim for',
              style: F.cap.copyWith(color: p.ink3),
            ),
            const SizedBox(height: S.x1),
            Text(
              'Weight ${pct(band.low)} to ${pct(band.high)} a week on the 7-day '
              'average, protein ${band.proteinLow}–${band.proteinHigh} g per kg, '
              'and comparable lifts holding or better.',
              style: F.cap.copyWith(color: p.ink),
            ),
            const SizedBox(height: S.x2),
            Text(
              'It waits two weeks after a goal change, then needs five weigh-ins '
              'and five full food days in each week it looks at (one week '
              'against the one before for losing fat or building muscle, four '
              'weeks for the others). It suggests changes of 100 to 250 kcal, '
              'raises protein before cutting calories, and never suggests '
              'going below your resting energy or 1,500 kcal (1,200 for '
              'women). Water, salt and glycogen move the scale day to day; the '
              'trend is what counts. With a medical condition or a history of '
              'disordered eating, set goals with a clinician instead.',
              style: F.over.copyWith(color: p.ink3),
            ),
          ],
        ),
      ),
      const SizedBox(height: S.x4),
      BigButton(
        _saving ? 'Saving…' : 'Use this goal from today',
        color: C.teal,
        onTap: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                await GoalPlan.save(
                  GoalPlan(
                    phase: _phase,
                    pace: _pace,
                    trainingAge: _age,
                    since: todayLabel(),
                    holdKg: _phase == GoalPhase.maintain ? widget.kg : null,
                  ),
                );
                if (c.mounted) Navigator.of(c).pop(true);
              },
      ),
    ]);
  }
}

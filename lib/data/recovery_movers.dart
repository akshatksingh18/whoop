// What moves your recovery (build 81): patterns between what you already log
// and how you wake. Replaces the journal tags, which the personal build no
// longer collects, as the source of a metric screen's "What moves it".
//
// Each morning is tagged from the day before it (meals, workouts, strain,
// steps) and from the night itself (bedtime). A tag is compared only on
// mornings where it can be known — a day with no food logged says nothing
// about late meals — and is shown only with enough mornings on both sides.
// Association with counts, never a cause.

import 'db.dart';
import 'day_label.dart';
import 'nutrition_store.dart';

/// Mornings needed on EACH side before a pattern is shown.
const int kMoverMinEach = 5;

/// The metric-series key, unit and direction for each outcome a metric screen
/// can show patterns for.
const kMoverOutcomes = <String, ({String unit, bool higherBetter})>{
  'readiness': (unit: '', higherBetter: true),
  'rmssd': (unit: 'ms', higherBetter: true),
  'rhr': (unit: 'bpm', higherBetter: false),
  'tst_min': (unit: 'min', higherBetter: true),
};

/// Mean outcome on mornings WITH each tag minus mornings WITHOUT it.
///
/// [outcome] is date → value. [tags] is date → (tag → known value); a tag
/// absent from a date's map is unknown that morning and counts on neither
/// side. Rows come back largest difference first, in the shape the metric
/// screen's "What moves it" renders.
List<Map<String, dynamic>> moversFrom({
  required String outcomeKey,
  required Map<String, double> outcome,
  required Map<String, Map<String, bool>> tags,
  int minEach = kMoverMinEach,
}) {
  final spec = kMoverOutcomes[outcomeKey];
  if (spec == null) return const [];
  final withV = <String, List<double>>{};
  final withoutV = <String, List<double>>{};
  for (final MapEntry(key: date, value: v) in outcome.entries) {
    final t = tags[date];
    if (t == null) continue;
    for (final MapEntry(key: tag, value: on) in t.entries) {
      (on ? withV : withoutV).putIfAbsent(tag, () => []).add(v);
    }
  }
  double mean(List<double> xs) => xs.reduce((a, b) => a + b) / xs.length;
  final rows = <Map<String, dynamic>>[];
  for (final tag in {...withV.keys, ...withoutV.keys}) {
    final a = withV[tag] ?? const <double>[];
    final b = withoutV[tag] ?? const <double>[];
    if (a.length < minEach || b.length < minEach) continue;
    final delta = mean(a) - mean(b);
    rows.add({
      'tag': tag,
      'outcome': outcomeKey,
      'delta': delta,
      'unit': spec.unit,
      'helped': delta == 0 ? false : (delta > 0) == spec.higherBetter,
      'n_with': a.length,
      'n_without': b.length,
    });
  }
  rows.sort(
    (x, y) =>
        (y['delta'] as double).abs().compareTo((x['delta'] as double).abs()),
  );
  return rows;
}

String _prev(String date) {
  final d = DateTime.parse(date);
  return dayLabelOf(DateTime(d.year, d.month, d.day - 1));
}

int _localHour(int epochSec) =>
    DateTime.fromMillisecondsSinceEpoch(epochSec * 1000).hour;

/// Tags for each morning in [dates], from logs the app already keeps.
///
/// [onsetSec] is the stored `sleep_onset_sec`: signed seconds either side of
/// 04:00 local for the night that ended that morning.
Map<String, Map<String, bool>> moverTags({
  required Iterable<String> dates,
  required Map<String, List<FoodEntry>> food,
  required List<Map<String, dynamic>> sessions,
  required Map<String, double> strain,
  required Map<String, double> steps,
  required Map<String, double> onsetSec,
  double? kcalTarget,
  double? proteinTarget,
}) {
  final eveningWorkout = <String>{};
  for (final s in sessions) {
    final ts = (s['start_ts'] as num?)?.toInt();
    if (ts == null) continue;
    if (_localHour(ts) >= 19) {
      eveningWorkout.add(
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(ts * 1000)),
      );
    }
  }
  final out = <String, Map<String, bool>>{};
  for (final date in dates) {
    final prev = _prev(date);
    final t = <String, bool>{};
    final meals = food[prev];
    if (meals != null && meals.isNotEmpty) {
      t['Ate after 22:00'] = meals.any(
        (e) => e.atTs != null && _localHour(e.atTs!) >= 22,
      );
      final kcal = meals.fold<double>(0, (a, e) => a + (e.kcal ?? 0));
      if (kcalTarget != null && kcalTarget > 0) {
        t['Ate over your calorie goal'] = kcal > kcalTarget;
      }
      final protein = meals.fold<double>(0, (a, e) => a + (e.proteinG ?? 0));
      if (proteinTarget != null && proteinTarget > 0) {
        t['Hit your protein goal'] = protein >= proteinTarget;
      }
    }
    t['Workout after 19:00'] = eveningWorkout.contains(prev);
    if (strain[prev] case final s?) t['Strain 14 or more'] = s >= 14;
    if (steps[prev] case final n?) t['10,000+ steps'] = n >= 10000;
    if (onsetSec[date] case final o?) {
      // After 01:00 = later than three hours before 04:00.
      t['Asleep after 01:00'] = o > -3 * 3600;
    }
    out[date] = t;
  }
  return out;
}

Map<String, double> _byDate(List<Map<String, dynamic>> rows, String from) => {
  for (final r in rows)
    if (r['date'] is String &&
        (r['date'] as String).compareTo(from) >= 0 &&
        r['value'] is num)
      r['date'] as String: (r['value'] as num).toDouble(),
};

/// The last [days] mornings of patterns for [outcomeKey] (a
/// [kMoverOutcomes] key). Empty until a pattern has enough mornings.
Future<List<Map<String, dynamic>>> loadRecoveryMovers(
  String outcomeKey, {
  Map<String, dynamic> profile = const {},
  int days = 120,
}) async {
  if (!kMoverOutcomes.containsKey(outcomeKey)) return const [];
  final now = DateTime.now();
  final fromDay = DateTime(now.year, now.month, now.day - days);
  final from = dayLabelOf(fromDay);
  final outcome = _byDate(
    await LocalDb.metricSeries(outcomeKey, measuredOnly: true),
    from,
  );
  if (outcome.length < 2 * kMoverMinEach) return const [];
  final db = await LocalDb.instance;
  final food = await NutritionDb.entriesSince(db, _prev(from));
  final sessions = await LocalDb.sessionsInRange(
    fromDay.subtract(const Duration(days: 1)).millisecondsSinceEpoch ~/ 1000,
    now.millisecondsSinceEpoch ~/ 1000,
  );
  double? target(String k) => (profile[k] as num?)?.toDouble();
  final tags = moverTags(
    dates: outcome.keys,
    food: food,
    sessions: sessions,
    strain: _byDate(await LocalDb.metricSeries('strain'), _prev(from)),
    steps: _byDate(await LocalDb.metricSeries('steps'), _prev(from)),
    onsetSec: _byDate(await LocalDb.metricSeries('sleep_onset_sec'), from),
    kcalTarget: target('kcal_target'),
    proteinTarget: target('protein_target'),
  );
  return moversFrom(outcomeKey: outcomeKey, outcome: outcome, tags: tags);
}

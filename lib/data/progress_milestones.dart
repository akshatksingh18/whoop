// Build 90 (D5): dated milestones on Progress's Body and Strength pages.
//
// A milestone is a FACT from recorded readings, with its date and what it is
// compared with — never a score, a badge or a claim about muscle or fat, and
// never a notification. Strength compares only the same exercise, load
// meaning and setup (the live workout's comparator, `compareSet`).

import 'body_log.dart';
import 'day_label.dart';
import 'lift_log.dart';
import 'lift_progress.dart';
import 'progress_review.dart';
import 'journal_fields.dart' show formatShortDate;

String _md(String day) => formatShortDate(DateTime.parse(day));

/// Summary precision only; stored readings and exact detail values stay intact.
int bodyComparisonPlaces(double before, double after) =>
    before != after && before.toStringAsFixed(1) == after.toStringAsFixed(1)
    ? 2
    : 1;

String _in(double v, [int places = 1]) {
  final s = v.toStringAsFixed(places);
  return s.replaceFirst(RegExp(r'\.?0+$'), '');
}

/// One body milestone: the day it happened, what changed, and what it was
/// compared with.
typedef BodyMilestone = ({String date, String title, String sub});

/// Waist readings inside [from]…[to] that were the lowest so far, newest
/// first (at most [limit]). Compared with every earlier reading, not only
/// those in range.
List<BodyMilestone> bodyMilestones(
  List<BodyMeasure> measures,
  String from,
  String to, {
  int limit = 5,
}) {
  final s = siteSeries(measures, BodySite.waistNavel);
  final site = BodySite.waistNavel.title;
  final out = <BodyMilestone>[];
  DatedValue? low;
  DatedValue? first;
  var count = 0;
  for (final r in s) {
    count++;
    first ??= r;
    if (low != null &&
        r.value < low.value &&
        r.date.compareTo(from) >= 0 &&
        r.date.compareTo(to) <= 0) {
      final places = bodyComparisonPlaces(low.value, r.value);
      // Two decimals can still tie; then the difference itself is stated.
      final indistinguishable =
          low.value.toStringAsFixed(places) == r.value.toStringAsFixed(places);
      final since = 'Lowest of $count since ${_md(first.date)}';
      out.add((
        date: r.date,
        title: indistinguishable
            ? '$site ${_in(r.value, places)} in'
            : '$site ${_in(low.value, places)} → ${_in(r.value, places)} in',
        sub: indistinguishable
            ? '$since · ${(low.value - r.value).toStringAsPrecision(2)} in '
                  'lower than the previous lowest on ${_md(low.date)}'
            : '$since · was ${_in(low.value, places)} on ${_md(low.date)}',
      ));
    }
    if (low == null || r.value < low.value) low = r;
  }
  return out.reversed.take(limit).toList();
}

/// Sessions inside [from]…[to] whose best set beat every earlier comparable
/// best on the same setup, newest first (at most [limit]).
List<String> liftMilestones(
  List<LiftWorkout> finished,
  String from,
  String to, {
  int limit = 8,
}) {
  final sessions = [
    for (final w in finished)
      if (!w.isActive) w,
  ]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final best = <String, ({LiftSet set, String date})>{};
  final out = <String>[];
  for (final w in sessions) {
    final date = dayLabelAt(w.startedAt);
    for (final e in w.exercises) {
      if (e.sets.isEmpty) continue;
      final k =
          '${liftNameKey(e.name)}|${e.loadMode.name}|${liftNameKey(e.equipmentNote)}';
      final now = bestSet(e.sets);
      final prev = best[k];
      if (prev == null) {
        best[k] = (set: now, date: date);
        continue;
      }
      if (compareSet(now, prev.set) != SetVerdict.better) continue;
      if (date.compareTo(from) >= 0 && date.compareTo(to) <= 0) {
        final name = e.equipmentNote.isEmpty
            ? e.name
            : '${e.name} · ${e.equipmentNote}';
        out.add(
          '$name ${e.setText(now)} on ${_md(date)}: your best on this setup '
          '(previous ${e.setText(prev.set)}, ${_md(prev.date)}).',
        );
      }
      best[k] = (set: now, date: date);
    }
  }
  return out.reversed.take(limit).toList();
}

// Session timing/profile shared by sensors, UI and historical calculations.
import 'dart:convert';
import 'dart:async';
import '../data/calculation_store.dart';
import '../compute/profile.dart';
import '../state/prefs.dart';

typedef ActiveWindow = ({DateTime start, DateTime end});

class WorkoutClock {
  final String id;
  final DateTime start;
  final Profile? profile;
  final List<ActiveWindow> pauses;
  DateTime? pausedAt, end;
  int spokenKm;
  Map<String, dynamic> results;
  void Function(bool)? onPauseChanged;
  static WorkoutClock? current;
  WorkoutClock(
    this.id,
    this.start, {
    this.profile,
    List<ActiveWindow>? pauses,
    this.pausedAt,
    this.end,
    this.spokenKm = 0,
    Map<String, dynamic>? results,
  }) : pauses = pauses ?? [],
       results = results ?? {};
  static WorkoutClock begin(String id, DateTime start, Profile profile) {
    final c = WorkoutClock(id, start, profile: profile);
    current = c;
    c.save();
    return c;
  }

  static WorkoutClock read(String id, DateTime start, {DateTime? end}) {
    final live = current;
    if (live != null &&
        live.id == id &&
        live.start.millisecondsSinceEpoch ~/ 1000 ==
            start.millisecondsSinceEpoch ~/ 1000) {
      return WorkoutClock(
        id,
        live.start,
        profile: live.profile,
        pauses: [...live.pauses],
        pausedAt: live.pausedAt,
        end: end ?? live.end,
        spokenKm: live.spokenKm,
        results: {...live.results},
      );
    }
    try {
      final m = jsonDecode(Prefs.getString('workout.clock.$id', ''));
      if (m is Map &&
          m['start'] is num &&
          (m['start'] as num).toInt() ~/ 1000 ==
              start.millisecondsSinceEpoch ~/ 1000) {
        DateTime at(num ms) => DateTime.fromMillisecondsSinceEpoch(ms.toInt());
        return WorkoutClock(
          id,
          at(m['start']),
          profile: m['profile'] is Map
              ? Profile.fromMap(Map<String, dynamic>.from(m['profile']))
              : null,
          pauses: [
            for (final p in m['pauses'] as List? ?? [])
              if (p is List && p.length == 2 && p[0] is num && p[1] is num)
                (start: at(p[0]), end: at(p[1])),
          ],
          pausedAt: m['paused'] is num ? at(m['paused']) : null,
          end: end ?? (m['end'] is num ? at(m['end']) : null),
          spokenKm: (m['spoken'] as num?)?.toInt() ?? 0,
          results: Map<String, dynamic>.from(m['results'] as Map? ?? {}),
        );
      }
    } catch (_) {
      /* Legacy sessions have no metadata. */
    }
    return WorkoutClock(id, start, end: end);
  }

  void setPaused(bool on, [DateTime? at]) {
    final now = at ?? DateTime.now();
    if (on) {
      pausedAt ??= now;
    } else if (pausedAt != null) {
      if (now.isAfter(pausedAt!)) pauses.add((start: pausedAt!, end: now));
      pausedAt = null;
    }
    save();
    onPauseChanged?.call(on);
  }

  List<ActiveWindow> windows([DateTime? until]) {
    final stop = end ?? until ?? DateTime.now();
    var cursor = start;
    final out = <ActiveWindow>[];
    for (final p in ([
      ...pauses,
      if (pausedAt != null) (start: pausedAt!, end: stop),
    ]..sort((a, b) => a.start.compareTo(b.start)))) {
      if (p.start.isAfter(cursor)) {
        out.add((start: cursor, end: p.start.isAfter(stop) ? stop : p.start));
      }
      if (p.end.isAfter(cursor)) cursor = p.end;
      if (!cursor.isBefore(stop)) break;
    }
    if (cursor.isBefore(stop)) out.add((start: cursor, end: stop));
    return out.where((w) => w.end.isAfter(w.start)).toList();
  }

  Duration activeDuration([DateTime? until]) =>
      Duration(seconds: activeSeconds(until));

  int activeSeconds([DateTime? until]) =>
      windows(until).fold<int>(
        0,
        (sum, w) => sum + w.end.difference(w.start).inMilliseconds,
      ) ~/
      1000;
  List<ActiveWindow> onDay(String day, [DateTime? until]) {
    final lo = DateTime.parse(day);
    final endDay = DateTime(lo.year, lo.month, lo.day + 1);
    return [
      for (final w in windows(until))
        if (w.start.isBefore(endDay) && w.end.isAfter(lo))
          (
            start: w.start.isBefore(lo) ? lo : w.start,
            end: w.end.isAfter(endDay) ? endDay : w.end,
          ),
    ];
  }

  /// Active elapsed time at a sample; paused gaps never stretch HR integration.
  double secondsAt(DateTime at) => windows(at)
      .where((w) => w.start.isBefore(at))
      .fold<double>(
        0,
        (sum, w) =>
            sum +
            (w.end.isAfter(at) ? at : w.end)
                    .difference(w.start)
                    .inMilliseconds /
                1000,
      );

  bool includes(DateTime at) => windows(
    end ?? DateTime.now().add(const Duration(seconds: 1)),
  ).any((w) => !at.isBefore(w.start) && at.isBefore(w.end));
  void finish(DateTime at) {
    if (pausedAt != null) {
      if (at.isAfter(pausedAt!)) pauses.add((start: pausedAt!, end: at));
      pausedAt = null;
    }
    end = at;
    save();
  }

  static final _writes = <String, Future<void>>{};
  Map<String, dynamic> toJson() => {
    'start': start.millisecondsSinceEpoch,
    'end': end?.millisecondsSinceEpoch,
    'profile': profile?.toMap(),
    'paused': pausedAt?.millisecondsSinceEpoch,
    'pauses': [
      for (final p in pauses)
        [p.start.millisecondsSinceEpoch, p.end.millisecondsSinceEpoch],
    ],
    'spoken': spokenKm,
    'results': results,
  };
  static Future<void> flushWrites() => Future.wait(_writes.values).then((_) {});
  Future<void> persist() {
    final value = jsonEncode(toJson());
    final prior = _writes[id] ?? Future<void>.value();
    final next = prior.catchError((Object _) {}).then((_) async {
      await CalculationStore.write('workout.clock.$id', value);
    });
    _writes[id] = next;
    return next.whenComplete(() {
      if (identical(_writes[id], next)) _writes.remove(id);
    });
  }

  void save() => unawaited(persist().catchError((Object _) {}));
}

import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'dart:isolate';

bool _loaded = false;
Map<String, tz.Location> _locations = {};
void initializeDayZones() {
  if (_loaded) return;
  final previousLocal = tz.timeZoneDatabase.isInitialized ? tz.local : null;
  tzdata.initializeTimeZones();
  _locations = Map.of(tz.timeZoneDatabase.locations);
  // Notifications owns tz.local. Preserve it, and keep this complete IANA
  // snapshot independent of another consumer loading a smaller database.
  if (previousLocal != null) tz.setLocalLocation(previousLocal);
  _loaded = true;
}

tz.Location dayZoneLocation(String id) {
  initializeDayZones();
  final zone = _locations[id];
  if (zone == null) throw ArgumentError.value(id, 'zone', 'Unknown IANA zone');
  return zone;
}

int? dayZoneCalendarStart(String date, String zoneId) {
  final d = DateTime.tryParse(date);
  if (d == null) return null;
  return tz.TZDateTime(
        dayZoneLocation(zoneId),
        d.year,
        d.month,
        d.day,
      ).millisecondsSinceEpoch ~/
      1000;
}

Future<List<DayZone>> buildDayZonesOffThread(
  int start,
  int finish,
  List<ZoneChange> changes,
) => Isolate.run(
  () => buildDayZones(fromSec: start, throughSec: finish, changes: changes),
);

String _date(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

class ZoneChange {
  final int atSec;
  final String zoneId;
  const ZoneChange(this.atSec, this.zoneId);
  Map<String, Object> toRow() => {'at_ts': atSec, 'zone_id': zoneId};
  factory ZoneChange.fromRow(Map row) =>
      ZoneChange((row['at_ts'] as num).toInt(), row['zone_id'] as String);
}

class DayZone {
  final String date, zoneId;
  final int startSec, endSec, startOffsetSec, endOffsetSec;
  const DayZone({
    required this.date,
    required this.zoneId,
    required this.startSec,
    required this.endSec,
    required this.startOffsetSec,
    required this.endOffsetSec,
  });
  Map<String, Object> toRow() => {
    'date': date,
    'zone_id': zoneId,
    'start_ts': startSec,
    'end_ts': endSec,
    'start_offset_sec': startOffsetSec,
    'end_offset_sec': endOffsetSec,
  };
  factory DayZone.fromRow(Map row) => DayZone(
    date: row['date'] as String,
    zoneId: row['zone_id'] as String,
    startSec: (row['start_ts'] as num).toInt(),
    endSec: (row['end_ts'] as num).toInt(),
    startOffsetSec: (row['start_offset_sec'] as num).toInt(),
    endOffsetSec: (row['end_offset_sec'] as num).toInt(),
  );
}

/// Pure chronology. A forward date jump opens a new day at the change instant;
/// this is the only possible seam that neither assigns pre-arrival instants to
/// the destination nor overlaps the day already lived. A westward change holds
/// the label until a destination midnight advances it.
List<DayZone> buildDayZones({
  required int fromSec,
  required int throughSec,
  required List<ZoneChange> changes,
  String? startingLabel,
}) {
  if (changes.isEmpty || throughSec < fromSec) return [];
  initializeDayZones();
  final ordered = List<ZoneChange>.of(changes)
    ..sort((a, b) => a.atSec.compareTo(b.atSec));
  var zone = ordered.first.zoneId;
  var index = 0;
  while (index < ordered.length && ordered[index].atSec <= fromSec) {
    zone = ordered[index++].zoneId;
  }
  tz.TZDateTime local(int t, String z) =>
      tz.TZDateTime.fromMillisecondsSinceEpoch(dayZoneLocation(z), t * 1000);
  final initial = local(fromSec, zone);
  var cursor = startingLabel == null
      ? tz.TZDateTime(
              dayZoneLocation(zone),
              initial.year,
              initial.month,
              initial.day,
            ).millisecondsSinceEpoch ~/
            1000
      : fromSec;
  var label = startingLabel ?? _date(initial);
  int nextMidnight(int at, String z, String heldLabel) {
    final loc = dayZoneLocation(z);
    final d = local(at, z);
    var next = tz.TZDateTime(loc, d.year, d.month, d.day + 1);
    while (_date(next).compareTo(heldLabel) <= 0) {
      next = tz.TZDateTime(loc, next.year, next.month, next.day + 1);
    }
    return next.millisecondsSinceEpoch ~/ 1000;
  }

  final result = <DayZone>[];
  while (cursor <= throughSec) {
    final startZone = zone;
    var end = nextMidnight(cursor, zone, label);
    String? jumpedLabel;
    while (index < ordered.length && ordered[index].atSec < end) {
      final change = ordered[index++];
      if (change.atSec <= cursor) {
        zone = change.zoneId;
        continue;
      }
      final newLabel = _date(local(change.atSec, change.zoneId));
      if (newLabel.compareTo(label) > 0) {
        end = change.atSec;
        jumpedLabel = newLabel;
        // The next day starts in the destination zone; this day's trailing
        // offset is the one immediately before that seam.
        index--;
        break;
      }
      zone = change.zoneId;
      end = nextMidnight(change.atSec, zone, label);
    }
    result.add(
      DayZone(
        date: label,
        zoneId: zone,
        startSec: cursor,
        endSec: end,
        startOffsetSec: local(cursor, startZone).timeZoneOffset.inSeconds,
        endOffsetSec: local(end - 1, zone).timeZoneOffset.inSeconds,
      ),
    );
    cursor = end;
    while (index < ordered.length && ordered[index].atSec <= cursor) {
      zone = ordered[index++].zoneId;
    }
    label = jumpedLabel ?? _date(local(cursor, zone));
  }
  return result;
}

/// Read-only process/isolate context, hydrated from SQLite or a worker payload.
/// Calendar-only DateTime construction remains separate from instant lookup.
class DayClock {
  static List<DayZone> _days = [];
  static List<ZoneChange> _changes = [];
  static final Map<String, DayZone> _byDate = {};
  static List<DayZone> get days => List.unmodifiable(_days);
  static List<ZoneChange> get changes => List.unmodifiable(_changes);
  static void install(List<DayZone> days, List<ZoneChange> changes) {
    if (days.isNotEmpty || changes.isNotEmpty) initializeDayZones();
    _days = List.of(days)..sort((a, b) => a.startSec.compareTo(b.startSec));
    _changes = List.of(changes)..sort((a, b) => a.atSec.compareTo(b.atSec));
    _byDate
      ..clear()
      ..addEntries(_days.map((d) => MapEntry(d.date, d)));
  }

  static Map<String, dynamic> snapshot() => {
    'days': [for (final d in _days) d.toRow()],
    'changes': [for (final c in _changes) c.toRow()],
  };
  static void restore(Map snapshot) => install(
    [
      for (final d in snapshot['days'] as List? ?? [])
        DayZone.fromRow(d as Map),
    ],
    [
      for (final c in snapshot['changes'] as List? ?? [])
        ZoneChange.fromRow(c as Map),
    ],
  );
  static DayZone? forDate(String date) => _byDate[date];
  static int? chartAnchor(String date) {
    final day = forDate(date);
    if (day == null) return null;
    final d = DateTime.tryParse(date);
    if (d == null) return null;
    final noon =
        tz.TZDateTime(
          dayZoneLocation(day.zoneId),
          d.year,
          d.month,
          d.day,
          12,
        ).millisecondsSinceEpoch ~/
        1000;
    return noon >= day.startSec && noon < day.endSec
        ? noon
        : day.startSec + (day.endSec - day.startSec) ~/ 2;
  }

  static DayZone? at(int second) {
    var lo = 0, hi = _days.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_days[mid].startSec <= second) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0 || second >= _days[lo - 1].endSec) return null;
    return _days[lo - 1];
  }

  static String? zoneAt(int second) {
    var lo = 0, hi = _changes.length;
    while (lo < hi) {
      final mid = (lo + hi) ~/ 2;
      if (_changes[mid].atSec <= second) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo > 0
        ? _changes[lo - 1].zoneId
        : _changes.isNotEmpty
        ? _changes.first.zoneId
        : at(second)?.zoneId;
  }

  static DateTime localAt(int second) {
    final zone = zoneAt(second);
    return zone == null
        ? DateTime.fromMillisecondsSinceEpoch(second * 1000)
        : tz.TZDateTime.fromMillisecondsSinceEpoch(
            dayZoneLocation(zone),
            second * 1000,
          );
  }

  static int offsetAt(int second) => localAt(second).timeZoneOffset.inSeconds;
  static bool spansZoneChange(int start, int end) => _changes.any(
    (c) => c.atSec > start && c.atSec < end && zoneAt(c.atSec - 1) != c.zoneId,
  );
  static String? abbreviation(String date, {required int nowSec}) {
    final day = forDate(date);
    if (day == null || day.zoneId == zoneAt(nowSec)) return null;
    return tz.TZDateTime.fromMillisecondsSinceEpoch(
      dayZoneLocation(day.zoneId),
      (day.endSec - 1) * 1000,
    ).timeZoneName;
  }
}

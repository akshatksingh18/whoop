import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:sqflite/sqflite.dart';
import 'day_zone_rules.dart';
import 'db.dart';
import '../sync/file_log.dart';

/// Internal SQL expressions only; every timestamp reader shares the same seam.
String storedDayLabelSql(String timestamp) =>
    "COALESCE((SELECT z.date FROM day_zone z WHERE z.start_ts <= $timestamp "
    "AND z.end_ts > $timestamp ORDER BY z.start_ts DESC LIMIT 1), "
    "strftime('%Y-%m-%d', $timestamp, 'unixepoch', 'localtime'))";

/// SQLite owns the timeline; native notifications are a durable inbox until
/// this transaction commits. Foreground/sync checks recover missed callbacks.
class DayZoneStore {
  static const _channel = MethodChannel('openstrap/day_zone');
  static Future<void> _tail = Future.value();
  static bool _listening = false;

  static Future<void> hydrate(DatabaseExecutor db) async {
    DayClock.install(
      [
        for (final r in await db.query('day_zone', orderBy: 'start_ts'))
          DayZone.fromRow(r),
      ],
      [
        for (final r in await db.query('zone_change', orderBy: 'at_ts'))
          ZoneChange.fromRow(r),
      ],
    );
  }

  static Future<void> check(String reason) async {
    if (Platform.isIOS && !_listening) {
      _listening = true;
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'changed') await check('native');
      });
    }
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final inbox = Platform.isIOS
          ? (await _channel.invokeListMethod<dynamic>('events') ?? [])
          : const [];
      final events = <ZoneChange>[
        for (final r in inbox.whereType<Map>()) ZoneChange.fromRow(r),
      ];
      await observe([...events, ZoneChange(now, zone)], throughSec: now);
      if (Platform.isIOS && events.isNotEmpty) {
        await _channel.invokeMethod<void>(
          'ack',
          events.map((c) => c.atSec).reduce(math.max),
        );
      }
    } catch (e) {
      unawaited(FileLog.write('[zone] $reason check deferred: $e'));
    }
  }

  /// Persist only observed zone identifiers. Pre-observation legacy instants
  /// have no known travel history; the first observed zone seeds their context
  /// on first derivation rather than pretending to reconstruct earlier trips.
  static Future<void> observe(
    List<ZoneChange> observations, {
    required int throughSec,
    int? fromSec,
  }) {
    final next = _tail.then((_) async {
      initializeDayZones();
      for (final c in observations) {
        dayZoneLocation(c.zoneId);
      }
      final db = await LocalDb.instance;
      await db.transaction((tx) async {
        final changes = [
          for (final r in await tx.query('zone_change', orderBy: 'at_ts'))
            ZoneChange.fromRow(r),
        ];
        final incoming = List<ZoneChange>.of(observations)
          ..sort((a, b) => a.atSec.compareTo(b.atSec));
        var changed = false;
        for (final c in incoming) {
          final prior = changes.where((x) => x.atSec <= c.atSec).toList();
          if (prior.isNotEmpty && prior.last.zoneId == c.zoneId) continue;
          changed = true;
          await tx.insert(
            'zone_change',
            c.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          changes.removeWhere((x) => x.atSec == c.atSec);
          changes.add(c);
          changes.sort((a, b) => a.atSec.compareTo(b.atSec));
        }
        if (changes.isEmpty) return;
        final old = [
          for (final r in await tx.query('day_zone', orderBy: 'start_ts'))
            DayZone.fromRow(r),
        ];
        int? legacyStart;
        if (old.isEmpty) {
          final labels = await tx.rawQuery(
            'SELECT MIN(day_id) AS date FROM day_result '
            'UNION SELECT MIN(date) FROM metric_series '
            'UNION SELECT MIN(date) FROM food_entry '
            'UNION SELECT MIN(date) FROM body_weight',
          );
          for (final row in labels) {
            final date = row['date'];
            if (date is! String) continue;
            final at = dayZoneCalendarStart(date, changes.first.zoneId);
            if (at != null) legacyStart = math.min(legacyStart ?? at, at);
          }
          final instants = await tx.rawQuery(
            'SELECT MIN(start_ts) AS at FROM sessions '
            'UNION SELECT MIN(rec_ts) FROM decoded_onehz WHERE rec_ts > 0',
          );
          for (final row in instants) {
            final at = (row['at'] as num?)?.toInt();
            if (at != null) legacyStart = math.min(legacyStart ?? at, at);
          }
        }
        final start = old.isEmpty
            ? (fromSec ?? throughSec)
            : math.min(fromSec ?? old.first.startSec, old.first.startSec);
        final finish = old.isEmpty
            ? throughSec
            : math.max(throughSec, old.last.startSec);
        if (!changed &&
            old.isNotEmpty &&
            start >= old.first.startSec &&
            finish < old.last.endSec)
          return;
        final generated = await buildDayZonesOffThread(
          math.min(start, legacyStart ?? start),
          finish,
          changes,
        );
        final oldByDate = {for (final d in old) d.date: d};
        for (final d in generated) {
          final previous = oldByDate[d.date];
          if (previous != null &&
              previous.toRow().toString() == d.toRow().toString())
            continue;
          await tx.insert(
            'day_zone',
            d.toRow(),
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
        }
      });
      await hydrate(db);
    });
    _tail = next.catchError((Object _) {});
    return next;
  }

  static Future<void> ensureRange(int start, int end) async {
    final db = await LocalDb.instance;
    if (DayClock.changes.isEmpty) await hydrate(db);
    if (DayClock.changes.isEmpty) return; // No invented IANA identifier.
    if (DayClock.at(start) != null && DayClock.at(end) != null) return;
    await observe([], fromSec: start, throughSec: end);
  }
}

// journal_metric round-trip: the numeric half of a journal entry.
//
// The behaviour worth pinning is the destructive one. A field the user
// cleared is deleted rather than left behind. A stale "3 coffees" surviving
// an edit becomes a reading nobody made, and it lands in a correlation as if
// it were real.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../support/root_path_provider.dart';

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('whoop_journal_metric_');
    PathProviderPlatform.instance = RootPathProvider(tmp.path);
    LocalDb.dbName = 'whoop_journal_metric_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  // The app's writer: [changes] patch the day against what was read ([base]).
  Future<void> save(
    String date,
    Map<String, JournalMetricValue?> changes, {
    Map<String, JournalMetricValue> base = const {},
  }) async {
    expect(
      await JournalStore.saveEdit(date, changes: changes, base: base),
      isEmpty,
    );
  }

  setUp(() async {
    final db = await LocalDb.instance;
    await db.delete('journal_metric');
    await db.delete('journal_field_def');
  });

  test('a day round-trips, time included', () async {
    await save('2026-06-01', {
      'mood': const JournalMetricValue(4),
      'caffeine_mg': const JournalMetricValue(200, atMinuteOfDay: 855),
    });

    final back = await JournalStore.metricsForDay('2026-06-01');
    expect(back['mood'], const JournalMetricValue(4));
    expect(back['caffeine_mg']!.value, 200);
    expect(back['caffeine_mg']!.atMinuteOfDay, 855);
  });

  test('a zero is stored as a real reading', () async {
    // "No caffeine today" is an answer. It has to survive a round trip as 0
    // and not come back as absent.
    await save('2026-06-01', {'caffeine_mg': const JournalMetricValue(0)});
    final back = await JournalStore.metricsForDay('2026-06-01');
    expect(back.containsKey('caffeine_mg'), isTrue);
    expect(back['caffeine_mg']!.value, 0);
  });

  test('a cleared field is deleted, not left behind', () async {
    await save('2026-06-01', {
      'mood': const JournalMetricValue(4),
      'water_ml': const JournalMetricValue(2000),
    });
    // The user cleared water and re-saved.
    await save(
      '2026-06-01',
      {'water_ml': null},
      base: {'water_ml': const JournalMetricValue(2000)},
    );

    final back = await JournalStore.metricsForDay('2026-06-01');
    expect(back.keys, ['mood']);
    expect(
      back.containsKey('water_ml'),
      isFalse,
      reason: 'a cleared field must not survive as a reading nobody made',
    );
  });

  test('saving one day never touches another', () async {
    await save('2026-06-01', {'mood': const JournalMetricValue(2)});
    await save('2026-06-02', {'mood': const JournalMetricValue(5)});

    expect((await JournalStore.metricsForDay('2026-06-01'))['mood']!.value, 2);
    expect((await JournalStore.metricsForDay('2026-06-02'))['mood']!.value, 5);
  });

  test('clearing every field clears the day', () async {
    await save('2026-06-01', {'mood': const JournalMetricValue(3)});
    await save(
      '2026-06-01',
      {'mood': null},
      base: {'mood': const JournalMetricValue(3)},
    );
    expect(await JournalStore.metricsForDay('2026-06-01'), isEmpty);
  });

  test('a day never recorded reads as empty, not as an error', () async {
    expect(await JournalStore.metricsForDay('1999-01-01'), isEmpty);
  });

  test('the correlation read groups by day, oldest first', () async {
    await save('2026-06-03', {'mood': const JournalMetricValue(1)});
    await save('2026-06-01', {
      'mood': const JournalMetricValue(3),
      'water_ml': const JournalMetricValue(1500),
    });
    await save('2026-06-02', {'mood': const JournalMetricValue(2)});

    final all = await JournalStore.metricsByDay();
    expect(all.keys.toList(), ['2026-06-01', '2026-06-02', '2026-06-03']);
    expect(all['2026-06-01']!.keys.toSet(), {'mood', 'water_ml'});

    final since = await JournalStore.metricsByDay(sinceDaysEpoch: '2026-06-02');
    expect(since.keys.toList(), ['2026-06-02', '2026-06-03']);
  });

  test(
    'a day export carries the custom definitions, not just the numbers',
    () async {
      // The definitions are not day-scoped, so without an explicit copy an
      // exported day holds values under `custom_magnesium` with no label, no
      // unit and no scale — the numbers survive and their meaning does not.
      await JournalStore.putFieldDef(
        const JournalFieldSpec(
          key: 'custom_magnesium',
          label: 'Magnesium',
          kind: JournalFieldKind.dose,
          unit: 'mg',
          max: 1000,
          step: 50,
          custom: true,
        ),
      );
      await save('2026-06-01', {
        'custom_magnesium': const JournalMetricValue(400),
      });

      final path = await LocalDb.exportDaysDb({'2026-06-01'});
      final exported = await databaseFactory.openDatabase(path);
      try {
        final metrics = await exported.query('journal_metric');
        expect(metrics.single['field'], 'custom_magnesium');
        final defs = await exported.query('journal_field_def');
        expect(defs.single['label'], 'Magnesium');
        expect(defs.single['unit'], 'mg');
      } finally {
        await exported.close();
      }
    },
  );

  group('custom field definitions', () {
    const spec = JournalFieldSpec(
      key: 'custom_magnesium',
      label: 'Magnesium',
      kind: JournalFieldKind.dose,
      unit: 'mg',
      max: 1000,
      step: 50,
      hasTime: true,
      custom: true,
    );

    test('round-trip preserves every part of the definition', () async {
      await JournalStore.putFieldDef(spec);
      final back = (await JournalStore.fieldDefs()).single;
      expect(back.key, spec.key);
      expect(back.label, spec.label);
      expect(back.kind, JournalFieldKind.dose);
      expect(back.unit, 'mg');
      expect(back.max, 1000);
      expect(back.step, 50);
      expect(back.hasTime, isTrue);
      expect(back.custom, isTrue, reason: 'a stored def is always a custom');
    });

    test(
      'an unknown kind from a newer build degrades instead of throwing',
      () async {
        final db = await LocalDb.instance;
        await db.insert('journal_field_def', {
          'key': 'custom_future',
          'label': 'From the future',
          'kind': 'something_new',
          'unit': 'x',
          'max_value': 10.0,
          'step': 1.0,
          'has_time': 0,
          'created_at': 0,
        });
        // One unreadable row must not take the whole journal screen down.
        final back = await JournalStore.fieldDefs();
        expect(back.single.kind, JournalFieldKind.dose);
      },
    );
  });
}

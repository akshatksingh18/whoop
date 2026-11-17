// Authored findings use the real retained-report store and the shipped reader.
// A newer recomputation must not replace the wording of the notification tapped.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/notify/notification_report.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart' show DayNav;
import 'package:whoop_companion/ui2/screens/what_changed.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'coverage_what_changed_reader_boundaries_test.dart' show ChartRepo;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('retained-finding-actions');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  testWidgets('retained wording survives steering onto another derived day', (
    t,
  ) async {
    final id = await t.runAsync(
      () => NotificationReport.save(
        'Authored evening finding',
        'Original authored evidence, not a fresh recomputation.',
        '2021-04-06',
      ),
    );
    final app = AppState.forTesting()..repo = ChartRepo();
    addTearDown(app.dispose);
    await localizedPage(
      t,
      WhatChangedScreen(day: '2021-04-06', reportId: id),
      app: app,
    );
    await flush(t);
    var text = (await readPage(t)).join(' ');
    expect(text, contains('Original authored evidence'));
    expect(text, contains('Authored evening finding'));
    expect(text, contains('100'));
    t.widget<DayNav>(find.byType(DayNav)).onDay('2021-04-05');
    await flush(t);
    expect(t.widget<DayNav>(find.byType(DayNav)).day, '2021-04-05');
    text = (await readPage(t)).join(' ');
    expect(text, contains('Original authored evidence'));
    expect(text, contains('Nothing stood out'));
    expect(text, isNot(contains('no longer retained')));
    expect(
      (await t.runAsync(() => NotificationReport.read(id!)))!['day'],
      '2021-04-06',
    );
  });

  testWidgets(
    'an expired report is disclosed while current findings still load',
    (t) async {
      final app = AppState.forTesting()..repo = ChartRepo();
      addTearDown(app.dispose);
      await localizedPage(
        t,
        const WhatChangedScreen(
          day: '2021-04-06',
          reportId: 'authored-expired',
        ),
        app: app,
      );
      await flush(t);
      final text = (await readPage(t)).join(' ');
      expect(
        text,
        contains('original notification finding is no longer retained'),
      );
      expect(text, contains('100'));
      expect(text, contains('Nothing here is a cause'));
      expect(text, isNot(contains('Findings could not load')));
    },
  );

  testWidgets(
    'a refused report decode can retry without replacing its identity',
    (t) async {
      const id = 'authored-report-retry';
      await t.runAsync(
        () => CalculationStore.write('${NotificationReport.prefix}$id', '{'),
      );
      final app = AppState.forTesting()..repo = ChartRepo();
      addTearDown(app.dispose);
      await localizedPage(
        t,
        const WhatChangedScreen(day: '2021-04-06', reportId: id),
        app: app,
      );
      await flush(t);
      expect(find.text('Findings could not load'), findsOneWidget);
      await t.runAsync(
        () => CalculationStore.write(
          '${NotificationReport.prefix}$id',
          jsonEncode({
            'title': 'Retained authored finding',
            'body': 'Authored report recovered at the same key.',
            'day': '2021-04-06',
          }),
        ),
      );
      await reveal(t, find.text('Retry'));
      await t.tap(find.text('Retry'));
      await flush(t);
      final text = (await readPage(t)).join(' ');
      expect(text, contains('Authored report recovered at the same key'));
      expect(text, isNot(contains('Findings could not load')));
      expect(text, contains('100'));
      expect(
        t.widget<WhatChangedScreen>(find.byType(WhatChangedScreen)).reportId,
        id,
      );
    },
  );

  test(
    'report retention removes only the oldest report keys and their mirrors',
    () async {
      await CalculationStore.write('authored-unrelated-anchor', 'keep');
      final ids = <String>[];
      for (var i = 1; i <= 34; i++) {
        final date = DateTime(2021, 3, i).toIso8601String().substring(0, 10);
        ids.add(
          await NotificationReport.save(
            'Authored finding',
            'Authored record $i',
            date,
          ),
        );
      }
      expect(await NotificationReport.read(ids[0]), isNull);
      expect(await NotificationReport.read(ids[1]), isNull);
      for (var i = 2; i < ids.length; i++) {
        expect(
          (await NotificationReport.read(ids[i]))!['title'],
          'Authored finding',
        );
      }
      await CalculationStore.clearCache();
      expect(await NotificationReport.read(ids[0]), isNull);
      expect(await NotificationReport.read(ids.last), isNotNull);
      expect(await CalculationStore.read('authored-unrelated-anchor'), 'keep');
      final rows = await (await LocalDb.instance).query(
        'baselines',
        where: 'key LIKE ?',
        whereArgs: ['${CalculationStore.prefix}${NotificationReport.prefix}%'],
      );
      expect(rows, hasLength(32));
    },
  );

  test(
    'repeating identical wording on the same day retains one report',
    () async {
      final first = await NotificationReport.save(
        'Authored',
        'Same evidence',
        '2021-04-06',
      );
      final second = await NotificationReport.save(
        'Authored',
        'Same evidence',
        '2021-04-06',
      );
      expect(second, first);
      final rows = await (await LocalDb.instance).query(
        'baselines',
        where: 'key LIKE ?',
        whereArgs: ['${CalculationStore.prefix}${NotificationReport.prefix}%'],
      );
      expect(rows, hasLength(1));
      expect((await NotificationReport.read(first))!['body'], 'Same evidence');
    },
  );
}

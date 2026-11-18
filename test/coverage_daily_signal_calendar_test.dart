// The active daily chart uses its real reader/rendering, with only time pinned.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';
import 'support/test_local_repository.dart';

class WearCalendarReader extends TestLocalRepository {
  final dates = <String>[];
  final inputs = <Map<String, dynamic>>[];
  bool refuse = false, empty = false;
  @override
  Future<Map<String, dynamic>> getDayWear(String date) async {
    dates.add(date);
    if (refuse) throw StateError('authored wear read refusal');
    final midnight = localDayStartSec(date)!;
    final data = <String, dynamic>{
      'date': date,
      'segments': [
        if (!empty) ...[
          {
            'start': midnight + 8 * 3600,
            'end': midnight + 9 * 3600,
            'on': true,
          },
          {
            'start': midnight + 9 * 3600,
            'end': midnight + 9 * 3600 + 1800,
            'on': false,
          },
        ],
      ],
    };
    inputs.add(data);
    return data;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WearCalendarReader reader;
  late AppState app;
  late DateTime now;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('daily-signal-calendar');
  });
  setUp(() async {
    await resetCoverageStore();
    reader = WearCalendarReader();
    app = AppState.forTesting()..repo = reader;
    now = DateTime(2021, 4, 6, 12, 30);
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t) => localizedPage(
    t,
    Scaffold(body: TodaySignalDetail('wear', clock: () => now)),
    app: app,
  );
  ChartFrame chart(WidgetTester t) =>
      t.widget<ChartFrame>(find.byType(ChartFrame));
  Scrubber scrubber(WidgetTester t) =>
      t.widget<Scrubber>(find.byType(Scrubber));

  Future<void> noWrites(WidgetTester t) async {
    expect(
      await t.runAsync(
        () async => (await LocalDb.instance).query('day_result'),
      ),
      isEmpty,
    );
    expect(t.takeException(), isNull);
  }

  testWidgets(
    'midday keeps recorded zero distinct from gaps and caps inspection at the current hour',
    (t) async {
      await open(t);
      expect(reader.dates, ['2021-04-06']);
      final before = jsonEncode(reader.inputs);
      final series = chart(t).series;
      expect(series, hasLength(24));
      expect(series[8], 60);
      expect(series[9], 0);
      expect(series[10], isNull);
      expect(series.skip(13), everyElement(isNull));
      expect(scrubber(t).maxValue, 12 / 23);
      scrubber(t).onChanged(1);
      await t.pumpAndSettle();
      expect(chart(t).readout, contains('12:00 PM · not recorded'));
      expect(jsonEncode(reader.inputs), before);
      await noWrites(t);
    },
  );

  testWidgets(
    'the last hour retains all recorded slots and the complete inspection range',
    (t) async {
      now = DateTime(2021, 4, 6, 23, 59);
      await open(t);
      expect(scrubber(t).maxValue, 1);
      expect(chart(t).series[8], 60);
      expect(chart(t).series[9], 0);
      scrubber(t).onChanged(1);
      await t.pumpAndSettle();
      expect(chart(t).readout, contains('11:00 PM · not recorded'));
      await noWrites(t);
    },
  );

  testWidgets(
    'midnight with no evidence remains unknown rather than a measured zero day',
    (t) async {
      now = DateTime(2021, 4, 6, 0, 1);
      reader.empty = true;
      await open(t);
      expect(chart(t).series, everyElement(isNull));
      expect(scrubber(t).maxValue, 0);
      scrubber(t).onChanged(0);
      await t.pumpAndSettle();
      expect(chart(t).readout, contains('12:00 AM · not recorded'));
      await noWrites(t);
    },
  );

  testWidgets(
    'a new-day revision re-reads the new label and clears the prior chart',
    (t) async {
      now = DateTime(2021, 4, 6, 23, 59);
      await open(t);
      expect(chart(t).series[8], 60);
      now = DateTime(2021, 4, 7, 0, 1);
      reader.empty = true;
      app.bumpInsights();
      await t.pumpAndSettle();
      expect(reader.dates, ['2021-04-06', '2021-04-07']);
      expect(chart(t).series, everyElement(isNull));
      expect(scrubber(t).maxValue, 0);
      await noWrites(t);
    },
  );

  testWidgets(
    'a refused read retries the same pinned day without inventing saved evidence',
    (t) async {
      reader.refuse = true;
      await open(t);
      expect(find.text('Daily chart could not load'), findsOneWidget);
      expect(find.byType(ChartFrame), findsNothing);
      reader.refuse = false;
      await invokeControl(
        t,
        t.widget<StatusCard>(find.byType(StatusCard)).onFix,
      );
      expect(reader.dates, ['2021-04-06', '2021-04-06']);
      expect(chart(t).series[8], 60);
      expect(chart(t).series[10], isNull);
      await noWrites(t);
    },
  );
}

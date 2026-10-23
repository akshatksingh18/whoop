// Synthetic secondary-screen and stored-zone fixtures only.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/sync/high_freq_wake_window.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/screens/month_grid.dart';
import 'package:openstrap_edge/ui2/screens/what_changed.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

class _Repo extends LocalRepository {
  bool failing = true;
  @override
  Future<List<String>> availableDays() async => [];
  @override
  Future<Map<String, dynamic>> getToday() async => {};
  @override
  Future<Map<String, dynamic>> getChart(String key, {int? from, int? to}) async {
    if (failing) throw StateError('Synthetic metric read failure');
    return {'points': []};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadAuditFonts);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    DayClock.install([], []);
  });
  tearDown(() => DayClock.install([], []));

  test('wake-window target keeps local wall time over spring DST', () {
    final zone = dayZoneLocation('America/New_York');
    final start =
        tz.TZDateTime(zone, 2026, 3, 1).millisecondsSinceEpoch ~/ 1000;
    final now = tz.TZDateTime(zone, 2026, 3, 7, 9);
    final changes = [ZoneChange(start, zone.name)];
    DayClock.install(
      buildDayZones(
        fromSec: start,
        throughSec: start + 10 * 86400,
        changes: changes,
      ),
      changes,
    );
    final rows = [
      for (var d = 4; d <= 6; d++)
        {
          'window_json': {
            'value': {
              'offset_ms': tz.TZDateTime(
                zone,
                2026,
                3,
                d,
                7,
                30,
              ).millisecondsSinceEpoch,
            },
          },
        },
    ];
    final plan = HighFreqWakeWindow.planFromRows(rows, now);
    expect(plan.targetWake?.toUtc(), DateTime.utc(2026, 3, 8, 11, 30));
    expect(plan.shouldEnable, isFalse);
  });

  test(
    'month-grid failures propagate instead of silently dropping a metric',
    () async {
      await expectLater(loadGridRows(_Repo()), throwsStateError);
    },
  );

  testWidgets('What changed exposes a failed grid read and supports Retry', (
    t,
  ) async {
    final repo = _Repo();
    final app = AppState.forTesting()..repo = repo;
    addTearDown(app.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          home: const WhatChangedScreen(),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('Findings could not load'), findsOneWidget);
    repo.failing = false;
    await t.tap(find.text('Retry'));
    await t.pumpAndSettle();
    expect(find.text('Findings could not load'), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  for (final scale in [1.0, 3.1]) {
    testWidgets('month grid retains complete labels at ${scale}x', (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final rows = [
        for (final key in kGridMetrics)
          GridRow(
            spec: specOf(key),
            cells: List<double?>.filled(30, .5),
            have: 28,
            historyDays: 30,
          ),
      ];
      await t.pumpWidget(
        RepaintBoundary(
          key: auditCaptureKey,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: buildTheme(Brightness.light),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: MonthGrid(rows),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      for (final row in rows) {
        final text = find.text(row.spec.title).first;
        await t.ensureVisible(text);
        expect(
          t.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
      }
      expect(t.takeException(), isNull);
      await captureAuditScroll(t, 'month_grid_${scale}x');
      await t.pumpWidget(const SizedBox());
    });
  }
}

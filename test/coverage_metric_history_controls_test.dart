// Dated ranks, sparse period selection and live profile changes on real pages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart' show prettyDay;
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_session_destination_boundaries_test.dart' show io;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class GoalReader extends LocalRepositoryImpl {
  GoalReader(Map<String, dynamic> profile)
    : super(getProfileMap: () => profile);
  @override
  Future<Map<String, dynamic>> getChart(
    String metric, {
    int? from,
    int? to,
  }) async => {'points': <Object>[]};
}

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('metric-history-controls');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  String ago(int n) {
    final now = DateTime.parse(todayLabel());
    return dayLabelOf(DateTime(now.year, now.month, now.day - n));
  }

  int noon(String day) =>
      DateTime.parse(
        day,
      ).add(const Duration(hours: 12)).millisecondsSinceEpoch ~/
      1000;
  Future<void> open(WidgetTester t, Widget page, bool localized) async {
    if (localized) {
      await localizedPage(t, page);
    } else {
      t.view.physicalSize = const Size(430, 1800);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(
        MaterialApp(theme: buildTheme(Brightness.light), home: page),
      );
      await t.pumpAndSettle();
      addTearDown(() => t.pumpWidget(const SizedBox()));
    }
  }

  for (final localized in [false, true]) {
    for (final historical in [false, true]) {
      for (final band in [null, 'within your usual']) {
        testWidgets(
          'rank dates its input historical=$historical band=$band localized=$localized',
          (t) async {
            final offset = historical ? 4 : 0;
            await open(
              t,
              MetricDetail(
                'steps',
                range: 2,
                data: MetricData(
                  daysAvailable: 30,
                  series: [
                    for (var i = 8; i >= 0; i--)
                      (t: noon(ago(i + offset)), v: 5000.0 + i * 100),
                  ],
                  percentile: {'percentile_of_you': 23, 'label': ?band},
                ),
              ),
              localized,
            );
            final all = (await readPage(t)).join(' ');
            expect(all, contains('23rd percentile of your own history'));
            expect(
              all,
              contains(historical ? 'Your reading from' : 'Today sits'),
            );
            if (historical) expect(all, isNot(contains('Today sits')));
            if (band != null) expect(all, contains(band));
            expect(all, contains('Lowest'));
            expect(all, contains('Highest'));
          },
        );
      }
    }
    testWidgets(
      'a short history names its own sample size localized=$localized',
      (t) async {
        await open(
          t,
          MetricDetail(
            'steps',
            range: 2,
            data: MetricData(
              daysAvailable: 7,
              series: [
                for (var i = 6; i >= 0; i--)
                  (t: noon(ago(i)), v: 5000.0 + i * 100),
              ],
            ),
          ),
          localized,
        );
        expect(
          (await readPage(t)).join(' '),
          contains('From 7 of your own days.'),
        );
      },
    );
    testWidgets(
      'an old dated link discloses the range limit localized=$localized',
      (t) async {
        final requested = ago(120);
        await open(
          t,
          MetricDetail(
            'steps',
            day: requested,
            range: 1,
            data: MetricData(
              daysAvailable: 30,
              series: [(t: noon(ago(1)), v: 5200)],
            ),
          ),
          localized,
        );
        final all = (await readPage(t)).join(' ');
        expect(all, contains(prettyDay(requested)));
        expect(all, contains('older than this chart reaches'));
        final previous = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Previous day',
        );
        await reveal(t, previous);
        await t.tap(previous);
        await t.pumpAndSettle();
        expect(
          (await readPage(t)).join(' '),
          isNot(contains('older than this chart reaches')),
        );
      },
    );
    testWidgets(
      'a month row selects its newest measured day across gaps localized=$localized',
      (t) async {
        final old = ago(65), newest = ago(1);
        await open(
          t,
          MetricDetail(
            'steps',
            range: 3,
            data: MetricData(
              daysAvailable: 90,
              series: [(t: noon(old), v: 2100), (t: noon(newest), v: 6200)],
            ),
          ),
          localized,
        );
        final row = find.byWidgetPredicate(
          (w) =>
              w is Pressable && w.semanticLabel?.contains('avg 2,100') == true,
        );
        await reveal(t, row);
        await t.tap(row);
        await t.pumpAndSettle();
        expect(
          find.byWidgetPredicate(
            (w) => w is Surface && w.semanticLabel == 'Open ${prettyDay(old)}',
          ),
          findsOneWidget,
        );
        expect((await readPage(t)).join(' '), contains('2 of 90'));
      },
    );
  }

  for (final editing in [false, true]) {
    testWidgets(
      'a profile revision ${editing ? 'preserves the open draft' : 'refreshes the closed goal editor'}',
      (t) async {
        final profile = <String, dynamic>{'step_goal': 8000};
        final reader = GoalReader(profile);
        final app = AppState.forTesting()..repo = reader;
        addTearDown(app.dispose);
        await localizedPage(
          t,
          const MetricDetail('steps'),
          app: app,
          settle: false,
        );
        await io(t);
        final edit = find.byWidgetPredicate(
          (w) => w is Pressable && w.semanticLabel == 'Edit daily step goal',
        );
        if (editing) {
          await reveal(t, edit);
          await t.tap(edit);
          await t.pumpAndSettle();
          await t.enterText(find.byType(TextField), '12345');
        }
        profile['step_goal'] = 9000;
        app.insightsRevision.value++;
        await io(t);
        if (!editing) {
          expect((await readPage(t)).join(' '), contains('9,000 steps'));
          await reveal(t, edit);
          await t.tap(edit);
          await t.pumpAndSettle();
        }
        expect(
          t.widget<TextField>(find.byType(TextField)).controller!.text,
          editing ? '12345' : '9000',
        );
        expect(profile['step_goal'], 9000);
      },
    );
  }
}

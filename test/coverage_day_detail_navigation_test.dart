// Actual SQLite readers and visible day controls; no substituted metric data.
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/activity/day_strain.dart';
import 'package:whoop_companion/ui2/screens/day_steps.dart';
import 'package:whoop_companion/ui2/screens/metric_detail.dart';
import 'package:whoop_companion/ui2/ui2.dart' show Pressable;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await coverageStore('day-detail-navigation', fresh: true);
    await loadAuditFonts();
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final metric in ['steps', 'step_kcal', 'strain']) {
    // The shipped embedded Strain preview deliberately has no day controls;
    // its navigation contract belongs to the complete Strain page.
    for (final embedded in metric == 'strain' ? [false] : [false, true]) {
      for (final scale in [1.0, 3.1]) {
        testWidgets(
          '$metric ${embedded ? 'embedded' : 'full'} ${scale}x arrows preserve date, values and stored evidence',
          (t) async {
            final app = AppState.forTesting()
              ..user = const Profile(
                ageYears: 30,
                sex: 'f',
                weightKg: 70,
                heightCm: 170,
              ).toMap();
            app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
            final units = UnitsController.seed(UnitSystem.metric);
            final theme = ThemeController.seed(
              AppThemeChoice.light,
              Brightness.light,
            );
            addTearDown(app.dispose);
            addTearDown(units.dispose);
            addTearDown(theme.dispose);
            final now = DateTime.now();
            final dates = [
              for (final ago in [3, 2, 1, 0])
                DateTime(now.year, now.month, now.day - ago),
            ];
            final labels = dates.map(dayLabelOf).toList();
            final snapshot = await t.runAsync(() async {
              for (var i = 0; i < dates.length; i++) {
                final noon =
                    DateTime(
                      dates[i].year,
                      dates[i].month,
                      dates[i].day,
                      12,
                    ).millisecondsSinceEpoch ~/
                    1000;
                final known = i < 3;
                final strain = known ? 4.2 + i : null;
                await LocalDb.putDayResult(
                  dayId: labels[i],
                  algoVersion: 102,
                  finalized: known,
                  windowJson: '{}',
                  payloadJson: jsonEncode({
                    'date': labels[i],
                    'device_family': 'gen4',
                    'scalars': {
                      'strain': strain,
                      'steps': known ? 1111 * (i + 1) : null,
                    },
                    'series': {
                      'strain_curve': [
                        if (known) {'t': noon, 'v': strain},
                      ],
                    },
                    'absent': {
                      if (!known) 'strain': 'Not enough observed activity',
                    },
                  }),
                  series: {
                    if (known) 'strain': strain,
                    if (known) 'steps': 1111.0 * (i + 1),
                  },
                );
                if (known) {
                  await LocalDb.replacePhoneCoverageForDay(
                    labels[i],
                    [
                      (
                        startTs: noon,
                        endTs: noon + 3600,
                        steps: 1111 * (i + 1),
                      ),
                    ],
                    distances: {'$noon-${noon + 3600}': 555.5 * (i + 1)},
                  );
                }
              }
              await LocalDb.setCursor('authored-navigation', 'retain');
              final db = await LocalDb.instance;
              return {
                for (final table in [
                  'day_result',
                  'metric_series',
                  'live_coverage',
                  'sync_cursor',
                ])
                  table: await db.query(table),
              };
            });
            final Widget page = embedded
                ? MetricDetail(metric, range: 0)
                : metric == 'strain'
                ? DayStrainDetail(day: labels.last)
                : DayStepsDetail(
                    day: labels.last,
                    calories: metric == 'step_kcal',
                  );
            await localizedPage(
              t,
              page,
              app: app,
              units: units,
              themeController: theme,
              scale: scale,
              push: true,
            );
            t.view.physicalSize = const Size(430, 932);

            DayNav nav() => t.widget<DayNav>(find.byType(DayNav).last);
            Finder button(String label) => find.byWidgetPredicate(
              (w) => w is Pressable && w.semanticLabel == label,
            );
            Future<void> settled(String day) async {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 80)),
              );
              await t.pump(const Duration(milliseconds: 400));
              await reveal(t, find.byType(DayNav));
              for (var i = 0; i < 40; i++) {
                await t.runAsync(
                  () => Future<void>.delayed(const Duration(milliseconds: 30)),
                );
                await t.pump();
                if (find.byType(DayNav).evaluate().isNotEmpty &&
                    nav().day == day &&
                    find.byType(CircularProgressIndicator).evaluate().isEmpty) {
                  break;
                }
              }
              await t.pumpAndSettle();
              expect(t.takeException(), isNull);
              expect(nav().day, day);
              expect(find.byType(CircularProgressIndicator), findsNothing);
            }

            Future<void> tap(String label, String day) async {
              await reveal(t, button(label));
              expect(t.widget<Pressable>(button(label)).onTap, isNotNull);
              await t.tap(button(label));
              await t.pump();
              await settled(day);
            }

            await settled(labels.last);
            await tap('Previous day', labels[2]);
            final firstSeen = await readPage(t);
            if (metric == 'strain') expect(firstSeen, contains('6.2'));
            if (metric == 'steps') expect(firstSeen, contains('3,333'));
            if (embedded && metric != 'strain') {
              final opened = t.widget<DayStepsDetail>(
                find.byType(DayStepsDetail).last,
              );
              expect(opened.embedded, false);
              expect(opened.calories, metric == 'step_kcal');
              expect(opened.day, labels[2]);
            }
            await tap('Previous day', labels[1]);
            final secondSeen = await readPage(t);
            if (metric == 'strain') {
              expect(secondSeen, contains('5.2'));
              expect(secondSeen, isNot(contains('6.2')));
            }
            if (metric == 'steps') {
              expect(secondSeen, contains('2,222'));
              expect(secondSeen, isNot(contains('3,333')));
            }
            await tap('Next day', labels[2]);
            await tap('Jump to today', labels.last);
            final unknown = await readPage(t);
            if (metric == 'steps') expect(unknown, isNot(contains('3,333')));
            if (metric == 'strain') expect(unknown, isNot(contains('6.2')));
            await reveal(t, button('Back'));
            await t.tap(button('Back'));
            await t.pumpAndSettle();
            if (embedded && metric != 'strain') {
              await settled(labels.last);
              expect(find.byType(MetricDetail), findsOneWidget);
            } else {
              expect(find.text('Closed test page'), findsOneWidget);
            }
            final after = await t.runAsync(() async {
              final db = await LocalDb.instance;
              return {
                for (final table in snapshot!.keys)
                  table: await db.query(table),
              };
            });
            expect(after, snapshot);
            expect(t.takeException(), isNull);
          },
        );
      }
    }
  }
}

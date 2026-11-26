// Existing overview producers open their retained destinations; cancel writes nothing.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'localized_progress_test.dart' show progress;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('progress-context-photo-handoff');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final target in ['food', 'photo']) {
      testWidgets('Progress $target route preserves range/data at ${scale}x', (
        t,
      ) async {
        final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
        await prefs.setString('progress.range', 'year');
        await prefs.setString('progress.metric', 'waistNavel');
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(getProfileMap: () => {});
        addTearDown(app.dispose);
        final db = await LocalDb.instance;
        await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
        final before = await db.query('metric_series');
        await localizedPage(
          t,
          Scaffold(body: ProgressScreen(data: progress(true))),
          app: app,
          scale: scale,
        );
        final control = find.byWidgetPredicate(
          (w) =>
              w is Surface &&
              (target == 'photo'
                  ? w.semanticLabel == 'Add a photo'
                  : (w.semanticLabel?.startsWith('What went in, ') ?? false)),
        );
        await reveal(t, control);
        expect(control, findsOneWidget);
        await t.tap(control);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        if (target == 'photo') {
          final entry = find.byType(BodyEntryScreen);
          expect(entry, findsOneWidget);
          Navigator.of(t.element(entry)).pop(false);
        } else {
          final heading = find.text('Food, training and recovery');
          expect(heading, findsOneWidget);
          final tabs = t.widget<SubTabs>(find.byType(SubTabs).first);
          expect(tabs.items, contains('7 days'));
          expect(tabs.index, 0);
          Navigator.of(t.element(heading)).pop();
        }
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(find.byType(ProgressScreen), findsOneWidget);
        expect(find.byType(BodyEntryScreen), findsNothing);
        expect(prefs.getString('progress.range'), 'year');
        expect(prefs.getString('progress.metric'), 'waistNavel');
        for (final table in [
          'body_weight_reading',
          'body_measure',
          'body_photo',
        ]) {
          expect(await t.runAsync(() => db.query(table)), isEmpty);
        }
        expect(await t.runAsync(() => db.query('metric_series')), before);
        expect(t.takeException(), isNull);
      });
    }
  }
}

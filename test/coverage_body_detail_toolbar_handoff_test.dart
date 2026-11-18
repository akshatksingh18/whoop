// Actual retained Body toolbar/remembered-site controls,with cancellation only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_localized_progress_test.dart' show progress;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-detail-toolbar');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final target in ['entry', 'settings', 'remembered-site']) {
      testWidgets(
        'Body $target keeps preferences and stored readings at ${scale}x',
        (t) async {
          final prefs = (await t.runAsync(SharedPreferences.getInstance))!;
          await prefs.setString('progress.metric', 'waistNavel');
          await prefs.setString('progress.range', 'year');
          final app = AppState.forTesting()
            ..repo = LocalRepositoryImpl(getProfileMap: () => {});
          addTearDown(app.dispose);
          final db = await LocalDb.instance;
          await LocalDb.putMetricSeriesValue('2021-04-06', 'steps', 1234);
          final before = await db.query('metric_series');
          final data = progress(true);
          final page = progressDetailPage(
            ProgressDest.overview,
            initial: data,
            range: ProgressRange.month,
          );
          await localizedPage(t, page, app: app, scale: scale);
          final selected = find.byWidgetPredicate(
            (w) =>
                w is Pressable &&
                w.semanticLabel == 'Chart Waist (navel), selected',
          );
          await reveal(t, selected);
          expect(selected, findsOneWidget);
          if (target != 'remembered-site') {
            final control = find.byTooltip(
              target == 'entry' ? 'Add body entry' : 'Body settings',
            );
            await reveal(t, control);
            await t.tap(control);
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
            expect(t.takeException(), isNull);
            final destination = target == 'entry'
                ? find.byType(BodyEntryScreen)
                : find.byType(BodySettingsScreen);
            expect(destination, findsOneWidget);
            Navigator.of(t.element(destination)).pop(false);
            await t.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 100)),
            );
            await t.pumpAndSettle();
            expect(find.byType(BodyEntryScreen), findsNothing);
            expect(find.byType(BodySettingsScreen), findsNothing);
          }
          expect(prefs.getString('progress.metric'), 'waistNavel');
          expect(prefs.getString('progress.range'), 'year');
          expect(
            await t.runAsync(() => db.query('body_weight_reading')),
            isEmpty,
          );
          expect(await t.runAsync(() => db.query('metric_series')), before);
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

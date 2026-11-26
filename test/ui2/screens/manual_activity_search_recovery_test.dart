// The historical manual-window picker remains editable after a failed search.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/profile.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'food_calendar_recovery_test.dart' show flush;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('manual-activity-search-recovery');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {}
      ..repo = LocalRepositoryImpl(getProfileMap: () => {});
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  for (final language in ['en', 'es', 'hi']) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'manual activity search reopens without stale query at $language ${scale}x',
        (t) async {
          final start = DateTime(2021, 4, 6, 8);
          await localizedPage(
            t,
            LogWorkout(
              start: start,
              end: start.add(const Duration(minutes: 20)),
              now: DateTime(2021, 4, 7),
            ),
            app: app,
            language: language,
            scale: scale,
          );
          await flush(t);
          final l = AppLocalizations.of(t.element(find.byType(LogWorkout)))!;
          Finder activity() => find.byWidgetPredicate(
            (w) => w is SetRow && w.title == l.logWorkoutActivityLabel,
          );
          final original = t.widget<SetRow>(activity()).value;
          final db = await LocalDb.instance;
          final before = await db.query('sessions');
          Future<void> open() async {
            await reveal(t, activity());
            await t.tap(activity());
            await flush(t);
          }

          await open();
          await t.enterText(
            find.byType(TextField),
            'authored-no-such-activity',
          );
          await t.pumpAndSettle();
          expect(find.text(l.logWorkoutNoActivityByName), findsOneWidget);
          // Dismissal commits neither a made-up activity nor a workout.
          Navigator.of(t.element(find.byType(TextField))).pop();
          await flush(t);
          expect(t.widget<SetRow>(activity()).value, original);
          expect(await db.query('sessions'), before);
          await open();
          expect(
            t.widget<TextField>(find.byType(TextField)).controller?.text ?? '',
            isEmpty,
          );
          expect(find.text(l.logWorkoutNoActivityByName), findsNothing);
          await t.enterText(find.byType(TextField), '  WaLkInG  ');
          await t.pumpAndSettle();
          final walking = find.byWidgetPredicate(
            (w) => w is SetRow && w.title == 'Walking',
          );
          expect(walking, findsOneWidget);
          await reveal(t, walking);
          await t.tap(walking);
          await flush(t);
          expect(t.widget<SetRow>(activity()).value, 'Walking');
          expect(await db.query('sessions'), before);
          final form = t.widget<LogWorkout>(find.byType(LogWorkout));
          expect(form.start, start);
          expect(form.end, start.add(const Duration(minutes: 20)));
          await open();
          await t.enterText(find.byType(TextField), 'again-no-such-activity');
          await t.pumpAndSettle();
          expect(find.text(l.logWorkoutNoActivityByName), findsOneWidget);
          Navigator.of(t.element(find.byType(TextField))).pop();
          await flush(t);
          expect(t.widget<SetRow>(activity()).value, 'Walking');
          expect(await db.query('sessions'), before);
        },
      );
    }
  }
}

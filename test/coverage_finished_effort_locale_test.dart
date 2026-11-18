// Freshly-finished effort is optional self-report,independent of measured scores.
// Actual localized summary/gestures and authored SQLite sessions;no sensor claim.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/activity/summary.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const id = 'authored-finished-effort';
  final start = DateTime(2021, 4, 6, 12);
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('finished-effort-locale');
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170, 'weight_kg': 70};
    app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
    await LocalDb.putSession({
      'id': id,
      'type': 'weight_training',
      'start_ts': start.millisecondsSinceEpoch ~/ 1000,
      'end_ts':
          start.add(const Duration(minutes: 20)).millisecondsSinceEpoch ~/ 1000,
      'status': 'done',
      'duration_min': 20,
      'source': 'manual',
      'private': 0,
      'calories_basis': 'active',
      'created_at': 1,
    });
    Prefs.setInt('workout.rpe_skips', 1);
  });
  tearDown(() => app.dispose());
  tearDownAll(LocalDb.close);
  Future<void> io(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 90)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  Future<void> open(WidgetTester t, String language) async {
    await localizedPage(
      t,
      ActivitySummary(
        ActivityResult(
          activityByName('Weight training')!,
          start: start,
          duration: const Duration(minutes: 20),
          sessionId: id,
        ),
        justFinished: true,
      ),
      app: app,
      language: language,
      push: true,
    );
    await io(t);
  }

  AppLocalizations strings(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(ActivitySummary)))!;
  Finder rate(AppLocalizations l, int n) => find.byWidgetPredicate(
    (w) => w is Pressable && w.semanticLabel == l.activitySummaryRateEffort(n),
  );
  Future<Map<String, Object?>> row(WidgetTester t) async =>
      (await t.runAsync(() => LocalDb.session(id)))!;
  for (final language in ['en', 'de', 'es', 'fr', 'hi', 'zh']) {
    for (final answer in [0, 1, 10]) {
      testWidgets(
        'COV-64 $language finished effort answer=$answer never defaults or changes measured session fields',
        (t) async {
          await open(t, language);
          final l = strings(t);
          await reveal(t, rate(l, 1));
          for (var n = 1; n <= 10; n++) {
            expect(rate(l, n), findsOneWidget);
          }
          final before = await row(t);
          expect(before['rpe'], isNull);
            final revision = app.insightsRevision.value;
          final pick = answer == 0
              ? find.text(l.activitySummaryNotNow)
              : rate(l, answer);
          await reveal(t, pick);
          await t.tap(pick);
          await io(t);
          final after = await row(t);
          expect(after, {...before, if (answer != 0) 'rpe': answer.toDouble()});
          expect(rate(l, 1), findsNothing);
          expect(Prefs.getInt('workout.rpe_skips', 0), answer == 0 ? 2 : 0);
          expect(
              app.insightsRevision.value,
            answer == 0 ? revision : greaterThan(revision),
          );
          expect(
            await t.runAsync(
              () => (LocalDb.instance).then((db) => db.query('day_result')),
            ),
            isEmpty,
          );
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final failure in ['SQLite refusal', 'missing row']) {
    testWidgets(
      'COV-64 finished effort $failure cannot report a saved rating and permits a real retry',
      (t) async {
        await open(t, 'en');
        final l = strings(t);
        final db = await t.runAsync(() => LocalDb.instance);
        final before = await row(t);
        final revision = app.insightsRevision.value;
        if (failure == 'SQLite refusal') {
          await t.runAsync(
            () => db!.execute(
              "CREATE TRIGGER authored_refuse_effort BEFORE UPDATE ON sessions WHEN OLD.id='$id' BEGIN SELECT RAISE(ABORT,'authored effort refusal'); END",
            ),
          );
        } else {
          await t.runAsync(
            () => db!.delete('sessions', where: 'id = ?', whereArgs: [id]),
          );
        }
        try {
          await reveal(t, rate(l, 10));
          await t.tap(rate(l, 10));
          await io(t);
          expect(rate(l, 10), findsOneWidget);
          expect(Prefs.getInt('workout.rpe_skips', 0), 1);
          expect(app.insightsRevision.value, revision);
          if (failure == 'SQLite refusal') {
            expect(await row(t), before);
            await t.runAsync(
              () => db!.execute('DROP TRIGGER authored_refuse_effort'),
            );
            await t.tap(rate(l, 10));
            await io(t);
            expect((await row(t))['rpe'], 10.0);
            expect(rate(l, 10), findsNothing);
          } else {
            expect(await t.runAsync(() => LocalDb.session(id)), isNull);
          }
        } finally {
          await t.runAsync(
            () => db!.execute('DROP TRIGGER IF EXISTS authored_refuse_effort'),
          );
        }
      },
    );
  }
}

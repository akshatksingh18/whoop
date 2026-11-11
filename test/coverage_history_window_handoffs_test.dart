// Actual retained-history compatibility, correction and delete/calendar controls.
// All SQLite rows are authored; no native or physiological validation is claimed.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/screens/workout_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

import 'coverage_session_destination_boundaries_test.dart' show io;
import 'coverage_workout_history_actions_test.dart' show action;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await (FontLoader(
      'Roboto',
    )..addFont(rootBundle.load('assets/fonts/Manrope/Manrope-400.ttf'))).load();
    await coverageStore('history-window-handoffs');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  late AppState app;
  late DateTime start;
  setUp(() {
    final now = DateTime.now();
    start = DateTime(now.year, now.month, now.day - 2, 8);
    app = AppState.forTesting()
      ..user = {'age': 30, 'sex': 'f', 'height_cm': 170, 'weight_kg': 70};
    app.repo = LocalRepositoryImpl(
      getProfileMap: () => app.user,
      onSessionChanged: app.publishSessionChange,
    );
  });
  tearDown(() async {
    await (await LocalDb.instance).execute(
      'DROP TRIGGER IF EXISTS authored_history_delete_refusal',
    );
    app.dispose();
  });

  Future<void> seed({String type = 'yoga', int? end, bool unknown = false}) =>
      LocalDb.putSession({
        'id': 'authored-history',
        'type': type,
        'start_ts': start.millisecondsSinceEpoch ~/ 1000,
        'end_ts': end,
        'end_ts_fabricated': unknown ? 1 : 0,
        'duration_min': 12,
        'status': 'done',
        'source': 'manual',
        'created_at': 1,
      });
  Future<void> open(WidgetTester t, {double scale = 1}) async {
    await localizedPage(
      t,
      const WorkoutHistoryScreen(weightKg: 70),
      app: app,
      scale: scale,
      settle: false,
    );
    await io(t);
  }

  Finder expandedRow() => find.byWidgetPredicate(
    (w) => w is Surface && w.semanticLabel?.endsWith('tap for details') == true,
  );
  Future<void> expand(WidgetTester t) async {
    final row = expandedRow().first;
    await reveal(t, row);
    // The nested activity title opens the summary; invoke the distinct
    // rendered expansion callback rather than tapping that child by accident.
    await invokeControl(t, t.widget<Surface>(row).onTap);
    await io(t);
  }

  for (final type in ['yoga', 'cycling']) {
    for (final end in <int?>[null, 0]) {
      testWidgets('legacy $type duration remains usable with end=$end', (
        t,
      ) async {
        await seed(type: type, end: end);
        final before = await LocalDb.session('authored-history');
        await open(t);
        expect((await readPage(t)).join(' '), contains('12 min'));
        await expand(t);
        final words = (await readPage(t)).join(' ');
        expect(words, contains('12:00'));
        expect(words, isNot(contains('NaN')));
        expect(
          await t.runAsync(() => LocalDb.session('authored-history')),
          before,
        );
      });
    }
  }
  for (final unknown in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      testWidgets(
        'history correction carries ${unknown ? 'unknown' : 'known'} end at ${scale}x',
        (t) async {
          final end = start.add(const Duration(minutes: 12));
          await seed(end: end.millisecondsSinceEpoch ~/ 1000, unknown: unknown);
          final before = await LocalDb.session('authored-history');
          await open(t, scale: scale);
          await expand(t);
          final fix = action('Fix the times on this session');
          await reveal(t, fix);
          await t.tap(fix);
          await io(t);
          final form = t.widget<LogWorkout>(find.byType(LogWorkout));
          expect(form.sessionId, 'authored-history');
          expect(form.start, start);
          expect(form.end, unknown ? start : end);
          expect(form.activity!.typeKey, 'yoga');
          Navigator.of(t.element(find.byType(LogWorkout))).pop();
          await io(t);
          expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
          expect(
            await t.runAsync(() => LocalDb.session('authored-history')),
            before,
          );
        },
      );
    }
  }
  for (final direction in [-1.0, 1.0]) {
    for (final outcome in ['keep', 'remove', 'refuse']) {
      testWidgets(
        'history swipe $direction/$outcome reflects the durable outcome',
        (t) async {
          await seed(
            end:
                start.add(const Duration(minutes: 12)).millisecondsSinceEpoch ~/
                1000,
          );
          final before = await LocalDb.session('authored-history');
          await open(t);
          final row = find.byType(Dismissible).first;
          await reveal(t, row);
          await t.drag(row, Offset(550 * direction, 0));
          await t.pumpAndSettle();
          expect(find.text('Delete this yoga?'), findsOneWidget);
          if (outcome == 'refuse') {
            await t.runAsync(
              () async => (await LocalDb.instance).execute(
                "CREATE TRIGGER authored_history_delete_refusal BEFORE DELETE ON sessions BEGIN SELECT RAISE(ABORT,'authored history delete refusal'); END",
              ),
            );
          }
          await t.tap(find.text(outcome == 'keep' ? 'Keep it' : 'Remove').last);
          await io(t);
          final after = await t.runAsync(
            () => LocalDb.session('authored-history'),
          );
          expect(after, outcome == 'remove' ? isNull : before);
          expect(
            action('Open Yoga session'),
            outcome == 'remove' ? findsNothing : findsOneWidget,
          );
          if (outcome == 'refuse') {
            expect(
              find.text('That workout was not deleted. Try again.'),
              findsOneWidget,
            );
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }
  for (final single in [true, false]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
        'accepted ${single ? 'single-day' : 'multi-day'} custom history range reopens at ${scale}x',
        (t) async {
          await seed(
            end:
                start.add(const Duration(minutes: 12)).millisecondsSinceEpoch ~/
                1000,
          );
          final before = await LocalDb.session('authored-history');
          await open(t, scale: scale);
          Future<void> picker() async {
            await t.tap(find.byTooltip('Select Dates'));
            await t.pumpAndSettle();
            await t.tap(find.text('Choose dates').last);
            await t.pumpAndSettle();
          }

          await picker();
          final from = DateUtils.dateOnly(start);
          final to = single ? from : DateUtils.dateOnly(DateTime.now());
          final local = MaterialLocalizations.of(
            t.element(find.byType(DateRangePickerDialog)),
          );
          await t.tap(find.byTooltip(local.inputDateModeButtonLabel));
          await t.pumpAndSettle();
          await t.enterText(
            find.byType(TextField).at(0),
            local.formatCompactDate(from),
          );
          await t.enterText(
            find.byType(TextField).at(1),
            local.formatCompactDate(to),
          );
          await t.tap(find.text(local.okButtonLabel).last);
          await io(t);
          expect(find.byType(DateRangePickerDialog), findsNothing);
          expect(action('Open Yoga session'), findsOneWidget);
          await picker();
          final reopened = t.widget<DateRangePickerDialog>(
            find.byType(DateRangePickerDialog),
          );
          expect(
            reopened.initialDateRange,
            DateTimeRange(start: from, end: to),
          );
          Navigator.of(t.element(find.byType(DateRangePickerDialog))).pop();
          await io(t);
          expect(action('Open Yoga session'), findsOneWidget);
          expect(
            await t.runAsync(() => LocalDb.session('authored-history')),
            before,
          );
        },
      );
    }
  }
}

// Manual corrections retain the recorded day's clock, including a DST seam.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';
import 'package:whoop_companion/ui2/ui2.dart';

class _Repo extends LocalRepository {
  int? start, end;
  @override
  Future<Map<String, dynamic>> setWorkoutWindow(
    String id, {
    required int startTs,
    required int endTs,
  }) async {
    start = startTs;
    end = endTs;
    return {'unscored': true};
  }
}

void main() {
  tearDown(() => DayClock.install([], []));
  Future<(GlobalKey<NavigatorState>, _Repo)> open(
    WidgetTester t,
    DateTime start,
    DateTime end,
    DateTime now,
  ) async {
    final first =
        start.subtract(const Duration(days: 3)).millisecondsSinceEpoch ~/ 1000;
    final changes = [ZoneChange(first, 'America/New_York')];
    DayClock.install(
      buildDayZones(
        fromSec: first,
        throughSec: now.millisecondsSinceEpoch ~/ 1000,
        changes: changes,
      ),
      changes,
    );
    t.view.physicalSize = const Size(1170, 3600);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final repo = _Repo();
    final app = AppState.forTesting()..repo = repo;
    addTearDown(app.dispose);
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: app,
        child: MaterialApp(
          navigatorKey: nav,
          theme: buildTheme(Brightness.light),
          home: LogWorkout(
            sessionId: 'synthetic',
            start: start,
            end: end,
            now: now,
            spans: const [],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    return (nav, repo);
  }

  Future<void> save(WidgetTester t) async {
    await t.ensureVisible(find.text('Save the new times'));
    await t.tap(find.text('Save the new times'));
    await t.pumpAndSettle();
  }

  testWidgets('historical form and time correction use the recorded zone', (
    t,
  ) async {
    final (nav, repo) = await open(
      t,
      DateTime.utc(2026, 10, 22, 13, 30),
      DateTime.utc(2026, 10, 22, 14, 30),
      DateTime.utc(2026, 10, 23, 18),
    );
    expect(find.text('9:30 AM'), findsOneWidget);
    await t.tap(find.text('Started'));
    await t.pumpAndSettle();
    nav.currentState!.pop(const TimeOfDay(hour: 9, minute: 45));
    await t.pumpAndSettle();
    await save(t);
    expect(
      repo.start,
      DateTime.utc(2026, 10, 22, 13, 45).millisecondsSinceEpoch ~/ 1000,
    );
    expect(
      repo.end,
      DateTime.utc(2026, 10, 22, 14, 45).millisecondsSinceEpoch ~/ 1000,
    );
  });

  testWidgets(
    'date correction keeps wall time in the destination recorded day',
    (t) async {
      final (nav, repo) = await open(
        t,
        DateTime.utc(2026, 10, 22, 13, 30),
        DateTime.utc(2026, 10, 22, 14, 30),
        DateTime.utc(2026, 10, 23, 18),
      );
      await t.tap(find.text('Date'));
      await t.pumpAndSettle();
      nav.currentState!.pop(DateTime(2026, 10, 21));
      await t.pumpAndSettle();
      await save(t);
      expect(
        repo.start,
        DateTime.utc(2026, 10, 21, 13, 30).millisecondsSinceEpoch ~/ 1000,
      );
    },
  );

  testWidgets('past-midnight end follows the recorded DST calendar', (t) async {
    final (nav, repo) = await open(
      t,
      DateTime.utc(2026, 3, 8, 4, 30),
      DateTime.utc(2026, 3, 8, 5, 30),
      DateTime.utc(2026, 3, 9, 18),
    );
    await t.tap(find.text('Ended'));
    await t.pumpAndSettle();
    nav.currentState!.pop(const TimeOfDay(hour: 3, minute: 20));
    await t.pumpAndSettle();
    await save(t);
    expect(
      repo.end,
      DateTime.utc(2026, 3, 8, 7, 20).millisecondsSinceEpoch ~/ 1000,
    );
    expect(repo.end! - repo.start!, 10200);
  });
}

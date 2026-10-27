import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/ui2/screens/day_timeline.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';

int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

Finder _scrubber(String label) =>
    find.byWidgetPredicate((w) => w is Scrubber && w.label == label);

void main() {
  test(
    'heart boundary uses actual records, not trailing gaps or invalid values',
    () {
      expect(latestRecordedHeartSlot([]), isNull);
      expect(
        latestRecordedHeartSlot([null, 0, double.nan, double.infinity]),
        isNull,
      );
      expect(latestRecordedHeartSlot([72, null, 78, null, 0]), 2);
      expect(latestRecordedHeartSlot([72]), 0);
    },
  );

  test('heart boundary rejects future minutes and future windows', () {
    final start = DateTime.utc(2026, 11, 1, 5);
    final now = start.add(const Duration(minutes: 2, seconds: 40));
    expect(
      latestRecordedHeartSlot(
        [70, null, 74, 999],
        startSec: _sec(start),
        now: now,
      ),
      2,
    );
    expect(
      latestRecordedHeartSlot([70], startSec: _sec(now) + 1, now: now),
      isNull,
    );
    expect(
      latestRecordedHeartSlot(
        [70, null, 74],
        startSec: _sec(start),
        now: start.subtract(const Duration(days: 1)),
      ),
      isNull,
    );
  });

  test(
    'heart boundary uses absolute instants through short and long DST days',
    () {
      final start = DateTime.utc(2026, 11, 1, 5);
      final now = start.add(const Duration(hours: 24, minutes: 20));
      final longDay = List<double?>.filled(1500, null)..[1450] = 77;
      expect(
        latestRecordedHeartSlot(longDay, startSec: _sec(start), now: now),
        1450,
      );
      final shortDay = List<double?>.filled(1380, null)..[1379] = 73;
      expect(
        latestRecordedHeartSlot(shortDay, startSec: _sec(start), now: now),
        1379,
      );
    },
  );

  for (final window in ['Day', '10 min', '1 hour']) {
    testWidgets('Today HR $window stops at the last recorded minute', (
      t,
    ) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final now = DateTime.now();
      final minute = _sec(now) ~/ 60 * 60;
      final start = minute - 120 * 60;
      final hr = List<double?>.filled(1440, null)
        ..[115] = 69
        ..[118] = 74
        ..[121] =
            999; // Future data must affect neither the cursor nor the range.
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: HomeScreen(
                data: HomeData(
                  readiness: const Metric(value: 74, confidence: .8),
                  graph: DayGraph(hr: hr, dayStartSec: start),
                  recentHr: [
                    {'t': minute - 5 * 60, 'v': 69},
                    {'t': minute - 2 * 60, 'v': 74},
                    {'t': minute + 60, 'v': 999},
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.scrollUntilVisible(
        find.text(window),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      final initial = t.widget<Scrubber>(_scrubber('Heart rate chart'));
      initial.onChanged(initial.maxValue);
      await t.pump();
      await Scrollable.ensureVisible(
        t.element(find.text(window)),
        alignment: .3,
      );
      await t.pumpAndSettle();
      expect(find.text(window).hitTestable(), findsOneWidget);
      await t.tap(find.text(window));
      await t.pumpAndSettle();
      final chart = _scrubber('Heart rate chart');
      await t.ensureVisible(chart);
      expect(
        t.widget<Scrubber>(chart).value,
        isNull,
        reason: 'Changing ranges clears the old selection.',
      );
      expect(t.widget<Scrubber>(chart).maxValue, lessThan(1));
      await t.tapAt(t.getTopRight(chart) + const Offset(-1, 40));
      await t.pump();
      final selected = t.widget<Scrubber>(chart);
      expect(selected.value, selected.maxValue);
      final lastTime = DateTime.fromMillisecondsSinceEpoch(
        (minute - 2 * 60) * 1000,
      );
      final time = formatClock(lastTime);
      expect(selected.describe(selected.value!), '$time · 74 bpm');
      final semantics = t.widget<Semantics>(
        find.descendant(
          of: chart,
          matching: find.byWidgetPredicate(
            (w) => w is Semantics && w.properties.slider == true,
          ),
        ),
      );
      semantics.properties.onIncrease!();
      await t.pump();
      expect(t.widget<Scrubber>(chart).value, selected.maxValue);
      final lines = find.descendant(
        of: chart,
        matching: find.byType(CustomPaint),
      );
      final line = t
          .widgetList<CustomPaint>(lines)
          .map((w) => w.painter)
          .whereType<LineChart>()
          .single;
      expect(
        line.d.length,
        window == 'Day'
            ? 1440
            : window == '10 min'
            ? 11
            : 61,
        reason: 'The requested range must actually have opened.',
      );
      expect(line.d.whereType<double>(), isNot(contains(999)));
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'day detail clamps a held cursor after the available data shrinks',
    (t) async {
      final now = _sec(DateTime.now()) ~/ 60 * 60;
      final start = now - 120 * 60;
      Future<void> show(int last) async {
        await t.pumpWidget(
          MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Scaffold(
              body: DayHeartCard(
                DayGraph(
                  hr: List<double?>.filled(1440, null)..[last] = 76,
                  dayStartSec: start,
                ),
              ),
            ),
          ),
        );
        await t.pumpAndSettle();
      }

      await show(118);
      final chart = _scrubber('Heart rate through the day');
      await t.tapAt(t.getTopRight(chart) + const Offset(-1, 40));
      await t.pump();
      await show(110);
      final selected = t.widget<Scrubber>(chart);
      expect(selected.value, selected.maxValue);
      expect(selected.maxValue, closeTo(110 / 1439, 1e-12));
      expect(selected.describe(selected.value!), contains('76 bpm'));
      expect(t.takeException(), isNull);
    },
  );
}

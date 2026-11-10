// Real screen loaders/revision ownership over authored repository responses.
// These do not claim sensor delivery or validate a breathing diagnosis.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/screens/sleep_breathing.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_history_read_boundaries_test.dart' show History;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/localized_coverage.dart';

class BreathingReader extends History {
  String? refusal;
  int starts = 0;
  Completer<List<String>>? firstDays;
  @override
  Future<List<String>> availableDays() async {
    starts++;
    if (starts == 1 && firstDays != null) return firstDays!.future;
    if (refusal == 'days') throw StateError('authored day-index refusal');
    return super.availableDays();
  }

  @override
  Future<Map<String, dynamic>> getChart(String metric, {int? from, int? to}) {
    if (refusal == 'flags') throw StateError('authored flag read refusal');
    return super.getChart(metric, from: from, to: to);
  }

  @override
  Future<Map<String, dynamic>> getDayLungs(String date) {
    if (refusal == 'night') throw StateError('authored stored-night refusal');
    return super.getDayLungs(date);
  }
}

void main() {
  setUpAll(loadAuditFonts);
  late BreathingReader reader;
  late AppState app;
  setUp(() {
    reader = BreathingReader();
    app = AppState.forTesting()..repo = reader;
  });
  tearDown(() => app.dispose());

  Future<void> open(WidgetTester t) => localizedPage(
    t,
    const Scaffold(body: SleepBreathingScreen()),
    app: app,
    settle: reader.firstDays == null,
  );

  void expectReady() {
    expect(find.textContaining('28 nights'), findsOneWidget);
    expect(
      find.text('A pattern in your pulse, not a breathing test.'),
      findsOneWidget,
    );
    expect(find.text('Breathing history could not load'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  }

  for (final above in [false, true]) {
    testWidgets(
      'across-night screen loads stored responses and reloads on revision above=$above',
      (t) async {
        reader.above = above;
        await open(t);
        expectReady();
        expect(
          find.text(
            above ? 'Higher than your usual' : 'Within your usual range',
          ),
          findsOneWidget,
        );
        final starts = reader.starts;
        reader.above = !above;
        app.bumpInsights();
        await t.pumpAndSettle();
        expect(reader.starts, greaterThan(starts));
        expectReady();
        expect(
          find.text(
            !above ? 'Higher than your usual' : 'Within your usual range',
          ),
          findsOneWidget,
        );
      },
    );
  }
  testWidgets(
    'no repository shows honest missing-night state without starting a read',
    (t) async {
      app.repo = null;
      await open(t);
      expect(find.textContaining('Not enough nights'), findsOneWidget);
      expect(reader.starts, 0);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    },
  );

  for (final stage in ['days', 'flags', 'night']) {
    testWidgets(
      '$stage read refusal retains Retry and recovers the across-night report',
      (t) async {
        reader.refusal = stage;
        await open(t);
        expect(find.text('Breathing history could not load'), findsOneWidget);
        expect(find.text('Your saved nights are intact.'), findsOneWidget);
        expect(find.textContaining('28 nights'), findsNothing);
        reader.refusal = null;
        await invokeControl(
          t,
          t.widget<StatusCard>(find.byType(StatusCard)).onFix,
        );
        expectReady();
      },
    );
  }

  for (final oldFails in [false, true]) {
    testWidgets(
      'a superseded ${oldFails ? 'failure' : 'success'} cannot replace the newer report state',
      (t) async {
        final first = Completer<List<String>>();
        reader.firstDays = first;
        await open(t);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        reader.refusal = oldFails ? null : 'days';
        app.bumpInsights();
        await t.pumpAndSettle();
        expect(reader.starts, 2);
        if (oldFails) {
          expectReady();
          first.completeError(StateError('authored late refusal'));
        } else {
          expect(find.text('Breathing history could not load'), findsOneWidget);
          first.complete([for (var i = 0; i < 30; i++) reader.day(i)]);
        }
        await t.pumpAndSettle();
        if (oldFails) {
          expectReady();
        } else {
          expect(find.text('Breathing history could not load'), findsOneWidget);
          expect(find.textContaining('28 nights'), findsNothing);
        }
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final refuses in [false, true]) {
    testWidgets(
      'closing during a night read ignores its late ${refuses ? 'failure' : 'result'}',
      (t) async {
        final first = Completer<List<String>>();
        reader.firstDays = first;
        await open(t);
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        if (refuses) {
          first.completeError(StateError('authored late refusal'));
        } else {
          first.complete([reader.day(0)]);
        }
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        final starts = reader.starts;
        app.bumpInsights();
        await t.pumpAndSettle();
        expect(reader.starts, starts);
      },
    );
  }
}

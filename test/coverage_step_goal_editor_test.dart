// Real metric-detail goal controls with only the profile-write boundary substituted.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;

class _App extends AppState {
  _App() : super.forTesting();
  final saved = <Map<String, dynamic>>[];
  bool refuse = false;
  Completer<void>? waiting;
  @override
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> patch) async {
    if (waiting != null) await waiting!.future;
    if (refuse) throw StateError('synthetic profile refusal');
    saved.add(Map.of(patch));
    return Map.of(patch);
  }
}

Finder action(String label) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == label);

void main() {
  setUpAll(loadAuditFonts);
  late _App app;
  setUp(() => app = _App());
  tearDown(() => app.dispose());
  Future<void> open(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!,
          ),
          home: const MetricDetail('steps', data: MetricData(stepGoal: 12000)),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.ensureVisible(action('Edit daily step goal'));
    await t.pumpAndSettle();
    await t.tap(action('Edit daily step goal'));
    await t.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(
      t.widget<TextField>(find.byType(TextField)).controller!.text,
      '12000',
    );
  }

  Future<void> save(WidgetTester t, String value) async {
    await t.enterText(find.byType(TextField), value);
    await t.ensureVisible(action('Save step goal'));
    await t.pumpAndSettle();
    await t.tap(action('Save step goal'));
    await t.pumpAndSettle();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  }

  for (final text in [
    '',
    'letters',
    'NaN',
    'Infinity',
    '1e309',
    '499',
    '100001',
    '-12',
  ]) {
    testWidgets('invalid goal "$text" retains the draft and never writes', (
      t,
    ) async {
      await open(t);
      await save(t, text);
      expect(app.saved, isEmpty);
      expect(find.byType(TextField), findsOneWidget);
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        text,
      );
      expect(find.byType(SnackBar), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
  for (final value in [500, 100000]) {
    testWidgets('the inclusive goal boundary $value reaches the write seam', (
      t,
    ) async {
      await open(t);
      await save(t, '$value');
      expect(app.saved, [
        {'step_goal': value},
      ]);
      expect(find.byType(TextField), findsNothing);
      expect(action('Edit daily step goal'), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
  testWidgets(
    'a failed goal write keeps its value and permits an explicit retry',
    (t) async {
      await open(t);
      app.refuse = true;
      await save(t, '17654');
      expect(app.saved, isEmpty);
      expect(
        find.text('The step goal could not save. Try again.'),
        findsOneWidget,
      );
      expect(
        t.widget<TextField>(find.byType(TextField)).controller!.text,
        '17654',
      );
      app.refuse = false;
      await save(t, '17654');
      expect(app.saved, [
        {'step_goal': 17654},
      ]);
      expect(find.byType(TextField), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'leaving during a successful write does not reload a disposed page',
    (t) async {
      await open(t);
      app.waiting = Completer<void>();
      await save(t, '15600');
      expect(app.saved, isEmpty);
      await close(t);
      app.waiting!.complete();
      await t.pumpAndSettle();
      expect(app.saved, [
        {'step_goal': 15600},
      ]);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'leaving during a refused write does not access a disposed context',
    (t) async {
      await open(t);
      app.waiting = Completer<void>();
      app.refuse = true;
      await save(t, '15600');
      await close(t);
      app.waiting!.complete();
      await t.pumpAndSettle();
      expect(app.saved, isEmpty);
      expect(t.takeException(), isNull);
    },
  );
  for (final scale in [2.0, 3.1]) {
    testWidgets(
      'goal edit and Save remain usable at ${scale}x without inventing steps',
      (t) async {
        await open(t, scale: scale);
        expect(find.text('0%'), findsNothing);
        await save(t, '14000');
        expect(app.saved, [
          {'step_goal': 14000},
        ]);
        expect(t.takeException(), isNull);
        await close(t);
      },
    );
  }
}

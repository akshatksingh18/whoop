// Build 95 layout regressions. All values and titles are synthetic.
import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/data/body_log.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/progress_review.dart';
import 'package:openstrap_edge/notify/notification_log.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/screens/notifications_screen.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/screens/progress_routes.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<void> capture(WidgetTester t, String name) async {
  final b = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await b.toImage(pixelRatio: 1.5);
    final bytes = (await image.toByteData(format: ui.ImageByteFormat.png))!;
    Directory('build/ui_capture').createSync(recursive: true);
    File(
      'build/ui_capture/$name.png',
    ).writeAsBytesSync(bytes.buffer.asUint8List());
    image.dispose();
  });
}

Widget frame(AppState app, Widget child, double scale, UnitsController units) =>
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: app),
        ChangeNotifierProvider<UnitsController>.value(value: units),
      ],
      child: RepaintBoundary(
        key: const ValueKey('capture'),
        child: MaterialApp(
          theme: buildTheme(Brightness.light),
          debugShowCheckedModeBanner: false,
          builder: (c, w) => MediaQuery(
            data: MediaQuery.of(
              c,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: w!,
          ),
          home: child,
        ),
      ),
    );
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 15)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    for (final family in ['Manrope', '.SF Pro Text']) {
      final loader = FontLoader(family);
      for (final file in Directory(
        'assets/fonts/Manrope',
      ).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
        loader.addFont(file.readAsBytes().then((b) => ByteData.sublistView(b)));
      }
      await loader.load();
    }
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide');
    icons.addFont(
      rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
    );
    await icons.load();
  });
  for (final scale in [1.0, 2.0, 3.1]) {
    testWidgets('notification history full scroll at ${scale}x', (t) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final u = UnitsController.withUnits();
      addTearDown(u.dispose);
      final now = DateTime.now();
      final entries = [
        LoggedNotification(
          key: '1',
          at: now,
          title: 'Your recovery is ready',
          body:
              'Your overnight score is available. Open it to see which inputs were measured.',
          category: 'recovery',
          origin: NotificationOrigin.submitted,
        ),
        LoggedNotification(
          key: '2',
          at: now.subtract(const Duration(hours: 2)),
          title: "Is today's food complete?",
          body:
              'Mark it complete, or leave it — a day with half your goal or more counts on its own.',
          category: 'reminders',
          origin: NotificationOrigin.scheduled,
        ),
        LoggedNotification(
          key: '3',
          at: now.subtract(const Duration(days: 1)),
          title: 'Your week in review',
          body: 'Compare recorded days and see what changed.',
          category: 'health',
          read: true,
        ),
      ];
      // Use the real singleton only in the first widget test: its queued
      // Future chain otherwise carries the preceding fake-async test zone.
      if (scale == 1.0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'notify.log',
          jsonEncode([for (final e in entries) e.toJson()]),
        );
      }
      await t.pumpWidget(
        frame(
          app,
          scale == 1.0
              ? const NotificationsScreen()
              : NotificationsScreen(entries: entries),
          scale,
          u,
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      await capture(t, 'b95_repaired_notifications_${scale}x');
      if (scale == 1.0) {
        expect(find.text('Mark all read'), findsOneWidget);
        await t.tap(find.text('Mark all read'));
        await settle(t);
        expect(
          (await NotificationLog.instance.entries()).every((e) => e.read),
          isTrue,
        );
        expect(find.text('Mark all read'), findsNothing);
      }
      final scroll = find.byType(Scrollable).first;
      final pos = t.state<ScrollableState>(scroll).position;
      for (var i = 0; i < 30 && pos.extentAfter > .5; i++) {
        await t.drag(scroll, const Offset(0, -500));
        await settle(t);
        expect(t.takeException(), isNull);
        await capture(t, 'b95_repaired_notifications_${scale}x_scroll_$i');
      }
      expect(pos.extentAfter, lessThanOrEqualTo(.5));
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
  }
  for (final scale in [1.0, 3.1]) {
    testWidgets('notification empty state at ${scale}x', (t) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final u = UnitsController.withUnits();
      addTearDown(u.dispose);
      await t.pumpWidget(
        frame(app, const NotificationsScreen(entries: []), scale, u),
      );
      await settle(t);
      expect(find.textContaining('Nothing yet.'), findsOneWidget);
      expect(find.text('Mark all read'), findsNothing);
      expect(t.takeException(), isNull);
      await capture(t, 'b95_repaired_notifications_empty_${scale}x');
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
  }
  for (final (width, scale) in [
    (390.0, 1.0),
    (390.0, 2.0),
    (320.0, 2.0),
    (390.0, 3.1),
  ]) {
    testWidgets('Body numeric line integrity ${width}w ${scale}x', (t) async {
      SharedPreferences.setMockInitialValues({'body.unit': 'lb'});
      await Prefs.ensureLoaded();
      t.view.physicalSize = Size(width, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final u = UnitsController.withUnits(weight: 'lb');
      addTearDown(u.dispose);
      final now = DateTime.now(), day = todayLabel();
      final d = ProgressData(
        latestWeightReading: (
          id: 'synthetic-render-reading',
          date: day,
          kg: 181.4 / kLbPerKg,
          atTs: now.millisecondsSinceEpoch ~/ 1000,
          unit: 'lb',
          entered: 181.4,
          source: 'whoop',
          historyOnly: false,
        ),
        weights: [
          (
            date: day,
            kg: 181.4 / kLbPerKg,
            atTs: now.millisecondsSinceEpoch ~/ 1000,
            unit: 'lb',
            entered: 181.4,
            source: 'whoop',
            originId: null,
            historyOnly: false,
          ),
        ],
        measures: [],
        photos: [],
        lifts: [],
        food: [],
        steps: [],
        sleepMin: [],
        recovery: [],
        sessions: [],
        baseline: null,
        heightCm: null,
      );
      await t.pumpWidget(
        frame(
          app,
          progressDetailPage(
            ProgressDest.weight,
            initial: d,
            range: ProgressRange.week,
          ),
          scale,
          u,
        ),
      );
      await settle(t);
      final value = find.text('181.4 lb').first;
      expect(value, findsOneWidget);
      expect(find.textContaining('One day of weight data.'), findsOneWidget);
      expect(find.text('FIRST READING'), findsNothing);
      await t.ensureVisible(value);
      await settle(t);
      await capture(t, 'b95_repaired_body_numeric_${width.toInt()}w_${scale}x');
      final paragraph = t.renderObject<RenderParagraph>(value);
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: 5),
      );
      final lines = boxes.map((b) => b.top).toSet();
      debugPrint(
        'Body numeric diagnostic width=$width scale=$scale digitLines=${lines.length} boxes=$boxes',
      );
      expect(
        lines,
        hasLength(1),
        reason: 'Digits of one weight must stay on one line',
      );
      expect(t.takeException(), isNull);
      final scroll = find
          .byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          )
          .first;
      final position = t.state<ScrollableState>(scroll).position;
      position.jumpTo(0);
      await settle(t);
      await capture(t, 'b95_repaired_body_${width.toInt()}w_${scale}x_top');
      for (var i = 0; i < 40 && position.extentAfter > .5; i++) {
        await t.drag(scroll, const Offset(0, -500));
        await settle(t);
        expect(t.takeException(), isNull);
        await capture(
          t,
          'b95_repaired_body_${width.toInt()}w_${scale}x_scroll_$i',
        );
      }
      expect(position.extentAfter, lessThanOrEqualTo(.5));
      await t.pumpWidget(const SizedBox.shrink());
      await settle(t);
    });
  }
}

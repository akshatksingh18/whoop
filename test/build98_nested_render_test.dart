// Fresh synthetic nested-view coverage; no personal records or production edits.
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:openstrap_edge/data/lift_log.dart';
import 'package:openstrap_edge/data/nutrition_store.dart';
import 'package:openstrap_edge/data/progress_review.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/state/units_controller.dart';
import 'package:openstrap_edge/ui2/screens/food_day_copy.dart';
import 'package:openstrap_edge/ui2/screens/progress_routes.dart';
import 'package:openstrap_edge/ui2/screens/progress_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';
import 'build95_repair_render_test.dart' show frame, settle;

Future<void> shot(WidgetTester t, String name) async {
  final boundary = t.renderObject<RenderRepaintBoundary>(
    find.byKey(const ValueKey('capture')),
  );
  await t.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final dir = Directory('build/ui_capture');
    await dir.create(recursive: true);
    await File(
      '${dir.path}/build98_$name.png',
    ).writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> scrollAll(WidgetTester t, String name) async {
  final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
  await shot(t, '${name}_top');
  var n = 0;
  while (pos.extentAfter > .5 && n < 40) {
    pos.jumpTo(
      (pos.pixels + 500).clamp(pos.minScrollExtent, pos.maxScrollExtent),
    );
    await settle(t);
    expect(t.takeException(), isNull);
    await shot(t, '${name}_scroll_${n++}');
  }
  expect(pos.extentAfter, lessThanOrEqualTo(.5));
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
  for (final scale in [1.0, 3.1]) {
    testWidgets('populated Strength full scroll at ${scale}x', (t) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      final units = UnitsController.withUnits();
      addTearDown(app.dispose);
      addTearDown(units.dispose);
      final now = DateTime.now();
      final lifts = [
        for (final days in [10, 3])
          LiftWorkout(
            startedAt: now.subtract(Duration(days: days)),
            endedAt: now
                .subtract(Duration(days: days))
                .add(const Duration(minutes: 20)),
            exercises: [
              for (final name in [
                'Synthetic dumbbell press',
                'Synthetic backpack row',
                'Synthetic split squat',
              ])
                LiftExercise(
                  name: name,
                  loadMode: LiftLoadMode.total,
                  equipmentNote: 'Same synthetic setup',
                  sets: [
                    LiftSet(
                      reps: 8,
                      load: days == 10 ? 50 : 55,
                      completedAt: now.subtract(Duration(days: days)),
                    ),
                  ],
                ),
            ],
          ),
      ];
      final data = ProgressData(
        weights: [],
        measures: [],
        photos: [],
        lifts: lifts,
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
            ProgressDest.strength,
            initial: data,
            range: ProgressRange.week,
          ),
          scale,
          units,
        ),
      );
      await settle(t);
      expect(t.takeException(), isNull);
      await scrollAll(t, 'strength_${scale}x');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('Copy a day review and explicit commit at ${scale}x', (
      t,
    ) async {
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final app = AppState.forTesting();
      final units = UnitsController.withUnits();
      addTearDown(app.dispose);
      addTearDown(units.dispose);
      final entries = [
        for (var i = 0; i < 4; i++)
          FoodEntry(
            id: 'synthetic-$i',
            date: '2026-09-01',
            meal: i < 2 ? 'breakfast' : 'lunch',
            label: 'Synthetic item ${i + 1}',
            kcal: i == 3 ? null : 100,
          ),
      ];
      List<FoodEntry>? written;
      await t.pumpWidget(
        frame(
          app,
          Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => reviewFoodDayCopy(
                  c,
                  from: '2026-09-01',
                  to: '2026-09-02',
                  entries: entries,
                  onLog: (items) async {
                    written = items;
                  },
                ),
                child: const Text('Review'),
              ),
            ),
          ),
          scale,
          units,
        ),
      );
      await t.tap(find.text('Review'));
      await settle(t);
      expect(written, isNull);
      expect(t.takeException(), isNull);
      await scrollAll(t, 'copy_${scale}x');
      final commit = find.byWidgetPredicate(
        (w) => w is BigButton && w.onTap != null,
      );
      final paragraph = t.renderObject<RenderParagraph>(
        find.descendant(of: commit, matching: find.byType(Text)).first,
      );
      // The complete commit label stays visible at accessibility sizes.
      expect(paragraph.didExceedMaxLines, false);
      await t.ensureVisible(commit);
      await t.tap(commit);
      await settle(t);
      await t.pumpAndSettle();
      expect(written!.length, 4);
      expect(written!.last.kcal, isNull);
      expect(find.text('Copy a day'), findsNothing);
      await t.pumpWidget(const SizedBox());
    });
  }
}

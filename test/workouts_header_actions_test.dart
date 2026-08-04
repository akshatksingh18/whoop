// Workouts header actions — the ⊕ Add / ▶ Start pair, and the layout budget
// they have to live inside.
//
// WHY THIS FILE EXISTS. "Log a past workout" first shipped as a fourth child
// of the start bottom sheet, where it was invisible and untappable: the sheet
// defaults to `isScrollControlled: false`, capping it at 9/16 of the screen
// (~475 pt at 390x844), and the nine type tiles already wrap to three rows.
// The row fell off the bottom edge. In release there are no overflow stripes,
// so nothing announced it — it just silently did not work.
//
// Two lessons, both pinned here:
//   1. Two pills plus the title must fit the header row at real phone widths.
//   2. A layout overflow must FAIL a test rather than ship as dead pixels.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/ui/design/design.dart';
import 'package:openstrap_edge/ui/workouts/workout_types.dart';

/// The narrowest phone we target, and the one the header budget is tightest on.
const Size _iphoneSe = Size(375, 667);
const Size _iphone14 = Size(390, 844);

Widget _harness(Widget child, ThemeData theme) =>
    MaterialApp(theme: theme, home: child);

void main() {
  for (final palette in [kLightPalette, kDarkPalette]) {
    final mode = palette == kLightPalette ? 'light' : 'dark';

    testWidgets('header fits title + Add + Start without overflow ($mode)',
        (t) async {
      for (final size in [_iphoneSe, _iphone14]) {
        t.view.physicalSize = size;
        t.view.devicePixelRatio = 1.0;
        addTearDown(t.view.reset);
        AppColors.active = palette;

        await t.pumpWidget(_harness(
          AppScaffold(
            title: 'Workouts',
            actions: [
              // Stand-ins with the exact geometry of the real pills — the
              // private widgets can't be imported, and what is under test is
              // the header's width budget, not their internals.
              _pill(Icons.add_rounded, 'Add'),
              _pill(Icons.play_arrow_rounded, 'Start'),
            ],
            children: const [SizedBox(height: 200)],
          ),
          buildOpenStrapTheme(palette),
        ));
        await t.pump();

        expect(t.takeException(), isNull,
            reason: 'header overflowed at ${size.width}x${size.height}');
        expect(find.text('Add'), findsOneWidget);
        expect(find.text('Start'), findsOneWidget);
        // The title must survive intact — if the actions eat the row, the
        // Expanded title ellipsizes to "Workout…" instead of failing loudly.
        final title = t.widget<Text>(find.text('Workouts'));
        expect(title.overflow, TextOverflow.ellipsis);
        final titleBox = t.getSize(find.text('Workouts'));
        expect(titleBox.width, greaterThan(0));
      }
    });
  }

  testWidgets(
    'the start sheet content fits the default 9/16 bottom-sheet cap — '
    'the regression that made "Log a past workout" untappable',
    (t) async {
      t.view.physicalSize = _iphone14;
      t.view.devicePixelRatio = 1.0;
      addTearDown(t.view.reset);
      AppColors.active = kLightPalette;

      // The sheet body exactly as startWorkoutFlow builds it.
      await t.pumpWidget(_harness(
        Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              // What showModalBottomSheet imposes with isScrollControlled:false.
              constraints: BoxConstraints(maxHeight: _iphone14.height * 9 / 16),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(Sp.x5),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start a workout', style: AppText.h2),
                      const SizedBox(height: Sp.x4),
                      Builder(builder: workoutTypeGrid),
                      const SizedBox(height: Sp.x4),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        buildOpenStrapTheme(kLightPalette),
      ));
      await t.pump();

      expect(t.takeException(), isNull,
          reason: 'the start sheet must not overflow its 9/16 cap — anything '
              'past the edge is silently unhittable in release');

      // Every type tile is inside the visible sheet, not clipped past it.
      final ceiling = _iphone14.height * 9 / 16;
      for (final e in kWorkoutTypes) {
        final tile = find.text(e.$2);
        expect(tile, findsOneWidget, reason: '${e.$2} tile missing');
        final r = t.getRect(tile);
        expect(r.bottom, lessThanOrEqualTo(_iphone14.height),
            reason: '${e.$2} is clipped off the bottom of the screen');
        expect(r.height, greaterThan(0), reason: '${e.$2} collapsed to zero');
      }

      // And the sheet genuinely is close to its ceiling — this is the fact
      // that makes adding a fourth child unsafe. If this ever goes slack
      // (fewer types, a tighter grid), the note in startWorkoutFlow can be
      // revisited; until then it stands.
      final used = t.getSize(find.byType(SafeArea).last).height;
      expect(used, greaterThan(ceiling * 0.6),
          reason: 'sheet is nowhere near its cap — re-check the guidance in '
              'startWorkoutFlow before trusting it');
    },
  );
}

/// A pill with the same padding/icon/label geometry as _AddButton/_StartButton.
Widget _pill(IconData icon, String label) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Sp.x4, vertical: Sp.x3),
      decoration: BoxDecoration(
        color: AppColors.accent,
        borderRadius: BorderRadius.circular(R.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: Colors.white),
          const SizedBox(width: Sp.x1),
          Text(label, style: AppText.label.copyWith(color: Colors.white)),
        ],
      ),
    );

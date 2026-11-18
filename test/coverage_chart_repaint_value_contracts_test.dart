// Existing timeline/gallery painter consumers, through Flutter's real repaint
// dispatch. No dormant renderer, alternate screen mode or new layout is added.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ui2/charts.dart';
import 'package:whoop_companion/ui2/theme.dart';

class ObservedPainter extends CustomPainter {
  ObservedPainter(this.actual);
  final CustomPainter actual;
  bool? requested;
  int paints = 0;
  @override
  void paint(Canvas canvas, Size size) {
    paints++;
    actual.paint(canvas, size);
  }

  @override
  bool shouldRepaint(covariant ObservedPainter oldDelegate) =>
      requested = actual.shouldRepaint(oldDelegate.actual);
}

void main() {
  final macro = MacroRing(.2, C.orange, const P(false).track);
  final circadian = <List<double>?>[
    [.2, .5],
  ];
  final spectrum = <double>[1, 2, 3];
  final night = <List<double?>>[
    [60, null, 70],
  ];
  final gaps = <(double, double)>[(.1, .2)];
  final rest = <(double, double, Color)>[(.2, .4, C.blue)];
  final work = <(double, double, Color)>[(.5, .6, C.orange)];
  final movement = <double?>[null, 0, .2, .6];
  DayLanes lane({
    List<(double, double)>? g,
    List<(double, double, Color)>? r,
    List<(double, double, Color)>? w,
    List<double?>? m,
  }) => DayLanes(
    p: const P(false),
    gaps: g ?? gaps,
    rest: r ?? rest,
    work: w ?? work,
    movement: m ?? movement,
  );

  final cases = <(String, CustomPainter, CustomPainter, CustomPainter)>[
    (
      'gallery macro value',
      macro,
      MacroRing(.8, C.orange, const P(false).track),
      MacroRing(.2, C.orange, const P(false).track),
    ),
    (
      'gallery circadian rows',
      Actogram(circadian, C.blue),
      Actogram(<List<double>?>[
        [.8, .9],
      ], C.blue),
      Actogram(circadian, C.blue),
    ),
    (
      'gallery spectrum samples',
      Spectrum(spectrum),
      Spectrum(<double>[3, 2, 1]),
      Spectrum(spectrum),
    ),
    (
      'gallery night samples',
      NightStack(night, [C.blue]),
      NightStack(
        <List<double?>>[
          [65, null, 75],
        ],
        [C.blue],
      ),
      NightStack(night, [C.blue]),
    ),
    ('timeline gaps', lane(), lane(g: [(.1, .3)]), lane()),
    ('timeline rest', lane(), lane(r: [(.2, .45, C.blue)]), lane()),
    ('timeline workouts', lane(), lane(w: [(.5, .7, C.orange)]), lane()),
    ('timeline movement', lane(), lane(m: [null, 0, .3, .8]), lane()),
  ];
  for (final (name, before, changed, same) in cases) {
    testWidgets(
      '$name requests repaint for changed evidence and retains its stable-input contract',
      (t) async {
        Future<void> draw(ObservedPainter painter) => t.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: SizedBox(
                width: 240,
                height: 120,
                child: CustomPaint(painter: painter),
              ),
            ),
          ),
        );
        final original = ObservedPainter(before);
        await draw(original);
        expect(original.paints, greaterThan(0));
        final update = ObservedPainter(changed);
        await draw(update);
        expect(update.requested, true);
        expect(update.paints, greaterThan(0));
        // Compare the original evidence identities again, not newly allocated
        // lists that the existing contract correctly treats as replacements.
        await draw(ObservedPainter(before));
        final stable = ObservedPainter(same);
        await draw(stable);
        expect(stable.requested, false);
        expect(t.takeException(), isNull);
      },
    );
  }

  test(
    'Axis value/hash membership distinguishes scale, tick count and label formatter',
    () {
      const base = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
      const same = AxisSpec(min: 0, max: 100, ticks: 3, format: axisInt);
      expect(base, same);
      expect(base.hashCode, same.hashCode);
    expect(<AxisSpec>{}..addAll([base, same]), hasLength(1));
      for (final other in <Object>[
        const AxisSpec(min: -1, max: 100, ticks: 3, format: axisInt),
        const AxisSpec(min: 0, max: 101, ticks: 3, format: axisInt),
        const AxisSpec(min: 0, max: 100, ticks: 5, format: axisInt),
        const AxisSpec(min: 0, max: 100, ticks: 3, format: axisFixed),
        '0..100',
      ]) {
        expect(base == other, false);
      }
    },
  );
}

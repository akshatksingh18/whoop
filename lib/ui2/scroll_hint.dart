// A row that scrolls, and admits it.
//
// `SubTabs` is a horizontal `ListView`, and its fifth entry lands off-screen
// on every phone we ship to. Measured, not guessed (see
// `test/ui2_scroll_hint_test.dart`, which holds the same numbers as an
// assertion): Wellness — Mind · Recovery · Habits · Medication · Cycle — wants
// 421 pt of chips inside the 358 pt the row actually gets on a 390 pt phone,
// so "Cycle" shows 3 pt of its own left padding and no letters. Health shows
// 19 pt of "Labs". At 360 pt both show exactly zero, and the row reads as if
// it simply ends at Medication / Vitals — which is how two finished screens
// went undiscovered by the person who built them.
//
// Not scrolling would be better than any affordance, so that was priced
// first, and it does not work. Cutting the chip padding from S.x4 to S.x2 —
// by which point it is not a chip — still leaves Wellness 13 pt over at
// 360 pt, and at 1.5x text every set is already half again wider than the
// viewport. The row has to scroll, so it has to say so.
//
// What it says: the tail of the content dissolves and a chevron sits at the
// edge, both scaled by how much is genuinely left to reach. Nothing is drawn
// at all when nothing is off-screen — no mask, no layer, no widget — and both
// are gone by the last pixel of the scroll. An edge treatment that is always
// on is decoration, and decoration that lies is worse than nothing.
//
// The chevron is not garnish on the fade. A fade only reads as "more" when
// there are glyphs under it to dissolve, and on a 390 pt phone the Health row
// clips 3 pt into "Labs" and Wellness 13 pt into "Medication" — both under
// the 40 pt tail, both nearly nothing to bite on. Fade alone was measured on
// that config and rejected there; the chevron is what carries it.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'theme.dart';

/// The width of the dissolve, and the scroll distance the whole hint eases out
/// over. Doubling as both is deliberate: it means the hint is at full strength
/// exactly while there is more than one fade's worth left, and is proportional
/// — not binary — through the last stretch, so a row that overflows by a pixel
/// and a half (Health does, on a 430 pt phone) claims a pixel and a half.
const double _tail = S.x10;

/// Wraps a horizontally scrolling child and marks the edge it continues past.
///
/// Marks nothing unless the child reports content off its trailing edge, and
/// stops marking it at the end of the scroll. Purely visual: the overlay never
/// takes a touch, so the chip underneath stays tappable to its last pixel.
class ScrollHint extends StatefulWidget {
  final Widget child;

  const ScrollHint({super.key, required this.child});

  @override
  State<ScrollHint> createState() => _ScrollHintState();
}

class _ScrollHintState extends State<ScrollHint> {
  double _after = 0;

  // Both notifications are needed and neither substitutes for the other.
  // `ScrollNotification` covers the finger; `ScrollMetricsNotification` covers
  // everything else that changes the answer without anybody scrolling — first
  // layout, rotation, and the text-size slider, which is the one that turns a
  // row that fitted into a row that does not. It is dispatched off a
  // microtask, never inside layout, so calling setState from it is safe.
  void _sync(ScrollMetrics m) {
    if (m.axis != Axis.horizontal || !m.hasContentDimensions) return;
    final after = m.extentAfter;
    if ((after - _after).abs() < 0.5) return;
    setState(() => _after = after);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return NotificationListener<ScrollMetricsNotification>(
      onNotification: (n) {
        _sync(n.metrics);
        return false;
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: (n) {
          _sync(n.metrics);
          return false;
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: (_after / _tail).clamp(0.0, 1.0)),
          duration: motion(c, Motion.fast),
          child: widget.child,
          builder: (c, t, child) {
            // The mask stays MOUNTED at rest, drawing a fully opaque gradient
            // over the row, rather than being lifted off when there is nothing
            // to say. Returning the bare child at t == 0 was the first version
            // and it is a trap: it moves the scrollable to a different slot in
            // the tree, so Flutter remounts it, the fresh ScrollPosition
            // starts at offset 0, and the row you had just scrolled to the end
            // of springs back to the start — which reports content off the
            // edge again, which brings the mask back, which remounts it again.
            // The hint has to be able to vanish without the row moving under
            // it, so what varies is the gradient, never the shape of the tree.
            // Covered by 'keeps its place when the hint goes away'.
            return Stack(
              fit: StackFit.passthrough,
              children: [
                ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    // Only the alpha of these two is read — `dstIn` multiplies
                    // the child by the mask's alpha and ignores its hue. An
                    // opaque ink is used rather than a raw white because the
                    // vocabulary has no raw colours in it.
                    colors: [
                      p.ink.withValues(alpha: 1),
                      p.ink.withValues(alpha: 1),
                      const Color(0x00000000),
                    ],
                    stops: [0, (1 - _tail * t / r.width).clamp(0.0, 1.0), 1],
                  ).createShader(r),
                  child: child,
                ),
                // The chevron IS lifted off, because it is a leaf: nothing
                // below it holds state worth keeping, so there is no reason to
                // pay for a widget that paints nothing.
                if (t > 0)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Opacity(
                          opacity: t,
                          child: Icon(LucideIcons.chevronRight,
                              size: S.x4, color: p.ink3),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

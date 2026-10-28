// The stat row the workout summary and the workout history detail share.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../theme.dart';

/// One stat: a ringed glyph, the label in caps, the value with its unit.
/// The workout summary and the history detail print the same row.
///
/// [ink] is the ink to set the value in; null takes the page's own, so the row
/// works on a card as well as on a photo. The label and the unit are derived
/// from it rather than passed, so a caller cannot half-theme the row.
class StatRow extends StatelessWidget {
  final IconData icon;

  /// Printed in caps. Pass it in sentence case.
  final String label;

  final String value;

  /// Trails the value, smaller and muted. Null for a bare count.
  final String? unit;

  final Color accent;

  /// The value's ink. Null resolves to the page's — see the class note.
  final Color? ink;

  const StatRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    this.unit,
    this.ink,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final on = ink ?? p.ink;
    final muted = ink == null ? p.ink3 : ink!.withValues(alpha: .62);
    // The mark grows with the type, up to a point: beside 34 pt type a fixed
    // 24 pt ring reads as a bullet. Clamped at 2× because past that the mark
    // starts costing the value its width.
    final k = MediaQuery.textScalerOf(c).scale(1).clamp(1.0, 2.0);
    return Row(children: [
      Container(
        width: S.x6 * k,
        height: S.x6 * k,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withValues(alpha: .55)),
        ),
        child: Icon(icon, size: 12 * k, color: accent),
      ),
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label.toUpperCase(),
                style: F.over.copyWith(color: muted, letterSpacing: 1),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
            // scaleDown rather than ellipsis, for the same reason the hero
            // uses it: '2,310 kcal' and '52 bpm' are both real and are not the
            // same width, and a truncated number is not a number.
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value, style: F.n17.copyWith(color: on), maxLines: 1),
                  if (unit != null) ...[
                    const SizedBox(width: S.x1),
                    Text(unit!, style: F.cap.copyWith(color: muted)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    ]);
  }
}

/// Split a formatted stat into its number and its unit.
///
/// A stat arrives as one string. A row sets the two halves differently, so it has to take them apart — and it
/// only does so when the tail actually LOOKS like a unit. '1h 02m' is a
/// duration whose last word is not a unit of anything, and splitting it would
/// print '1h' in the value slot.
(String, String?) splitStatUnit(String s) {
  final m = RegExp(r'^(.+?)\s+([a-zA-Z/][a-zA-Z/]*)$').firstMatch(s.trim());
  return m == null ? (s, null) : (m.group(1)!, m.group(2)!);
}

/// The glyph for a stat every kind of session can print; [statIcon] in
/// summary.dart adds the session-only ones and falls back to this.
/// Anything unrecognised gets the neutral mark rather than a guess.
IconData commonStatIcon(String name) => switch (name) {
      'Time' => LucideIcons.timer,
      'Distance' => LucideIcons.ruler,
      'Pace' => LucideIcons.gauge,
      'Steps' => LucideIcons.footprints,
      'Heart rate' => LucideIcons.heart,
      'Calories' || 'Budget active' || 'ACSM active' => LucideIcons.flame,
      'Elevation' => LucideIcons.mountain,
      'Volume' => LucideIcons.dumbbell,
      'Sets' => LucideIcons.layers,
      'Laps' => LucideIcons.repeat,
      _ => LucideIcons.activity,
    };

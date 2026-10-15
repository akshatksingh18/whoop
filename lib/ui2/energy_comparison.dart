import 'package:flutter/material.dart';
import 'grammar.dart';
import 'theme.dart';
import 'screens/home_screen.dart' show thousands;

/// An unqualified distance extrapolation must not wear an
/// ACSM label. Values and all breakdown rows remain visible at large text sizes.
class EnergyComparison extends StatelessWidget {
  const EnergyComparison({
    required this.budget,
    required this.acsm,
    this.note = '',
    this.compact = false,
    this.budgetParts = const [],
    this.acsmParts = const [],
    this.equationLabel = 'Movement estimate',
  });
  final double? budget, acsm;
  final String note, equationLabel;
  final bool compact;
  final List<(String, double)> budgetParts, acsmParts;
  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget column(
      String label,
      double? value,
      Color color,
      List<(String, double)> parts,
    ) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: S.x2),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Text(
            value == null ? 'Unavailable' : thousands(value),
            softWrap: false,
            style: (compact ? F.n17 : F.n24).copyWith(
              color: value == null ? p.ink3 : p.on(color),
            ),
          ),
        ),
        if (value != null) Text('kcal', style: F.cap.copyWith(color: p.ink2)),
        for (final part in parts)
          Padding(
            padding: const EdgeInsets.only(top: S.x1),
            child: Wrap(
              spacing: S.x2,
              children: [
                Text(part.$1, style: F.over.copyWith(color: p.ink3)),
                Text(thousands(part.$2), style: F.over.copyWith(color: p.ink2)),
              ],
            ),
          ),
      ],
    );
    final left = column('Budget', budget, C.green, budgetParts);
    final right = column(equationLabel, acsm, C.teal, acsmParts);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (bigText(c)) ...[
          left,
          const SizedBox(height: S.x4),
          right,
        ] else
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: S.x5),
              Expanded(child: right),
            ],
          ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: S.x3),
          Text(note, style: F.cap.copyWith(color: p.ink3, height: 1.4)),
        ],
      ],
    );
  }
}

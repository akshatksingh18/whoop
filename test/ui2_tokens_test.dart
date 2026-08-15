// The token guard for lib/ui2.
//
// A design system is only a system while every screen spends the same
// vocabulary. The one it replaces did not have this test, and the audit found
// the result: 223 call sites on a caption colour that fails AA, raw hex
// scattered through screens, a dozen one-off font sizes, and thirteen infinite
// animation loops with nothing gating them.
//
// None of that is caught by review at the fortieth screen. It is caught here,
// on the first one.
//
// Built on test/support/dart_source.dart so a token named inside a comment or
// a string literal is not a violation — the naive per-line regex this
// replaced flagged its own documentation.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// Where the vocabulary is *defined*. This one file is allowed to write raw
/// colours and sizes; it is the only place they may appear.
const _tokenFile = 'lib/ui2/theme.dart';

/// Where `Pressable` is defined — the one place a raw gesture is legal.
const _gestureFile = 'lib/ui2/grammar.dart';

final _rules = <_Rule>[
  _Rule(
    'raw fontSize:',
    RegExp(r'\bfontSize\s*:'),
    'Type comes from F (F.body, F.cap, F.n34 …). Seven steps, no eighth.',
    allow: {_tokenFile},
  ),
  _Rule(
    'raw Color(0x…)',
    // Fully transparent is not a colour, it is the absence of one, and every
    // theme agrees on it.
    RegExp(r'Color\(0x(?!00000000\))'),
    'Colour comes from C / P. If a new pigment is genuinely needed it is '
        'declared in theme.dart and swept by ui2_contrast_test.',
    allow: {_tokenFile},
  ),
  _Rule(
    'Colors.white / Colors.black',
    RegExp(r'\bColors\.(white|black)\b'),
    'Hard white is a hole in a dark card. Use p.card / p.ink / p.inkOnFill.',
  ),
  _Rule(
    'numeric BorderRadius.circular',
    RegExp(r'BorderRadius\.circular\(\s*\d'),
    'Radii come from R (R.rSm … R.rPill).',
    allow: {_tokenFile},
  ),
  _Rule(
    'infinite .repeat()',
    RegExp(r'\.repeat\s*\('),
    'A loop that never ends cannot be stopped by the reduced-motion gate. '
        'Drive ambient motion from a caller-owned phase value instead — see '
        'BreathRing.t.',
  ),
  _Rule(
    'ungated Duration(',
    // `motion(context, …)` is the gate. Motion.fast/base/slow are the token
    // constants it is fed.
    RegExp(r'Duration\((?!\s*\))'),
    'Durations come from Motion.fast/base/slow and pass through '
        'motion(context, …) so reduced motion collapses them to zero.',
    allow: {_tokenFile},
  ),
  _Rule(
    'raw gesture detector',
    RegExp(r'\b(GestureDetector|InkWell|RawGestureDetector)\b'),
    'Pressable is the only gesture primitive — it is what applies the 44 pt '
        'minimum tap target, so a call site that bypasses it is a call site '
        'that opts out of it.',
    allow: {_gestureFile},
  ),
];

class _Rule {
  final String name;
  final RegExp pattern;
  final String why;
  final Set<String> allow;
  _Rule(this.name, this.pattern, this.why, {this.allow = const {}});
}

void main() {
  final root = Directory('lib/ui2');

  test('lib/ui2 exists and is where the design system lives', () {
    expect(root.existsSync(), isTrue,
        reason: 'run this from the package root');
    expect(
      root.listSync().whereType<File>().where((f) => f.path.endsWith('.dart')),
      isNotEmpty,
    );
  });

  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  for (final rule in _rules) {
    test('no ${rule.name} outside the token boundary', () {
      final hits = <String>[];
      for (final f in files) {
        final rel = f.path.replaceFirst(RegExp(r'^\./'), '');
        if (rule.allow.contains(rel)) continue;
        final lines = codeLines(f.readAsStringSync());
        for (var i = 0; i < lines.length; i++) {
          if (rule.pattern.hasMatch(lines[i])) {
            hits.add('$rel:${i + 1}  ${lines[i].trim()}');
          }
        }
      }
      expect(hits, isEmpty, reason: '${rule.why}\n\n${hits.join('\n')}');
    });
  }

  test('every ui2 file is reachable from the barrel', () {
    final barrel = File('lib/ui2/ui2.dart').readAsStringSync();
    // The VOCABULARY is what the barrel publishes — the files directly in
    // lib/ui2. Screens live in subdirectories (onboarding/, profile/,
    // screens/) and are imported by the router by path: exporting them from
    // the barrel every screen imports would be a cycle, and a screen nobody
    // can reach is caught by the router failing to compile, not by a grep.
    // The token rules above still sweep every file, subdirectories included.
    for (final f in root.listSync().whereType<File>()) {
      final name = f.uri.pathSegments.last;
      if (!name.endsWith('.dart') || name == 'ui2.dart') continue;
      expect(barrel, contains("export '$name';"),
          reason: '$name is not exported from lib/ui2/ui2.dart — a component '
              'nobody can import is a component nobody will use.');
    }
  });
}

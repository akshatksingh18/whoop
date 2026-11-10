// Personal iPhone priority contract:retain policy/mapper guards and transition
// observability;the separately approved Android actuator is retired.
// Comments and string literals are stripped by the retained shared scanner.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'support/dart_source.dart';

/// The two members this test pins, matched as written.
const _applySig = 'Future<void> _applyLinkPriority()';
const _mapperSig =
    'ConnectionPriority connectionPriorityFor(LinkPriority want)';

/// Every `.dart` file under `lib/`, as (path, code-only lines).
List<MapEntry<String, List<String>>> _libSources() {
  final lib = Directory('lib');
  expect(lib.existsSync(), isTrue, reason: 'run from the package root');
  final out = <MapEntry<String, List<String>>>[];
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // POSIX-normalise. Directory.listSync returns NATIVE separators, so on
    // Windows every key here is `lib\ble\ble_engine.dart` while every assertion
    // below is written `lib/ble/ble_engine.dart`. Nothing about what this file
    // pins is platform-specific, so the paths it reasons about should not be
    // either — normalising once here keeps the assertions readable as the
    // single spelling they already use.
    //
    // Replacing Platform.pathSeparator rather than a literal backslash: on
    // POSIX that is a no-op, whereas a blanket `\` replacement would corrupt
    // the (legal, if perverse) filename that contains one.
    out.add(MapEntry(
      entity.path.replaceAll(Platform.pathSeparator, '/'),
      codeLines(entity.readAsStringSync()),
    ));
  }
  out.sort((a, b) => a.key.compareTo(b.key));
  return out;
}

/// Inclusive line range of the member whose signature contains [signature],
/// found by brace depth so it survives reformatting and nested blocks.
///
/// Handles a braced body and an `=>` body closed by `;`, so the mapper can be
/// an expression member without silently vacating the check.
/// Returns null when the signature is absent.
({int start, int end})? _bodyRange(List<String> lines, String signature) {
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].contains(signature)) continue;
    var depth = 0;
    var opened = false;
    for (var j = i; j < lines.length; j++) {
      for (final ch in lines[j].split('')) {
        if (ch == '{') {
          depth++;
          opened = true;
        } else if (ch == '}') {
          depth--;
        }
      }
      if (opened && depth == 0) return (start: i, end: j);
      // `=> …;` with no braces at all: the member ends at the first `;`.
      if (!opened && depth == 0 && lines[j].contains(';')) {
        return (start: i, end: j);
      }
    }
    return null; // unbalanced — treat as not found rather than guessing
  }
  return null;
}

List<String> _engine() => _libSources()
    .firstWhere((e) => e.key.endsWith('ble/ble_engine.dart'))
    .value;

void main() {
  // A method call, not the API name appearing in prose or a log string.
  final callSite = RegExp(r'\.requestConnectionPriority\s*\(');
  final literal = RegExp(r'ConnectionPriority\.\w+');
  final policyDecl = RegExp(r'^\s*LinkPriority\s+desiredLinkPriority\s*\(');

  test('the personal iPhone build never issues an Android priority request',
      () {
    final calls = <String>[];
    for (final entry in _libSources()) {
      for (var i = 0; i < entry.value.length; i++) {
        if (callSite.hasMatch(entry.value[i])) {
          calls.add('${entry.key}:${i + 1}');
        }
      }
    }
    expect(
      calls,
      isEmpty,
      reason: 'the unsupported Android actuator is retired. Found: $calls',
    );
  });

  test('the transition point retains its callback and async contract', () {
    final engine = _engine();
    final range = _bodyRange(engine, _applySig);
    expect(range, isNotNull,
        reason: '$_applySig must exist in ble/ble_engine.dart');

    // Joined, because the call and its argument sit on different lines.
    final body = engine.sublist(range!.start, range.end + 1).join('\n');

    expect(
      callSite.hasMatch(body),
      isFalse,
      reason: 'the retained transition point must not issue a radio request',
    );
    expect(body, contains('debugOnPriorityRequest?.call()'));
    expect(engine[range.start], contains('async'));
  });

  test('every ConnectionPriority literal is inside the mapper', () {
    final offences = <String>[];
    for (final entry in _libSources()) {
      final range = _bodyRange(entry.value, _mapperSig);
      for (var i = 0; i < entry.value.length; i++) {
        if (!literal.hasMatch(entry.value[i])) continue;
        final inMapper = range != null && i >= range.start && i <= range.end;
        if (!inMapper) {
          offences.add('${entry.key}:${i + 1} → ${entry.value[i].trim()}');
        }
      }
    }
    expect(
      offences,
      isEmpty,
      reason: 'a hard-coded ConnectionPriority outside the mapping switch is '
          'how issue #200 shipped. Route it through desiredLinkPriority.',
    );
  });

  test('the mapper is declared once, in the engine, and stays testable', () {
    final decls = <String>[];
    for (final entry in _libSources()) {
      for (var i = 0; i < entry.value.length; i++) {
        if (entry.value[i].contains(_mapperSig)) {
          decls.add('${entry.key}:${i + 1}');
        }
      }
    }
    expect(decls, hasLength(1), reason: 'Found: $decls');
    expect(decls.single, startsWith('lib/ble/ble_engine.dart:'));

    // Without @visibleForTesting a refactor can make it private, and the
    // arm-by-arm coverage in link_priority_policy_test.dart — the only thing
    // standing between a future edit and #200 itself — quietly disappears.
    final engine = _engine();
    final at = int.parse(decls.single.split(':').last) - 1;
    expect(
      engine
          .sublist((at - 3).clamp(0, at), at)
          .any((l) => l.contains('@visibleForTesting')),
      isTrue,
      reason: 'connectionPriorityFor must stay @visibleForTesting so the '
          'mapping keeps its arm-by-arm test',
    );
  });

  test('exactly one desiredLinkPriority declaration, in sync_policy.dart', () {
    final decls = <String>[];
    for (final entry in _libSources()) {
      for (var i = 0; i < entry.value.length; i++) {
        if (policyDecl.hasMatch(entry.value[i])) {
          decls.add('${entry.key}:${i + 1}');
        }
      }
    }
    expect(
      decls,
      hasLength(1),
      reason: 'a second policy copy would satisfy the per-file literal check '
          'while the engine stopped being the single decision point. '
          'Found: $decls',
    );
    expect(decls.single, startsWith('lib/sync/sync_policy.dart:'));
  });
}

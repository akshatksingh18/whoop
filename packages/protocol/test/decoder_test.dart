// Synthetic header contracts and optional private captured-header replay.
import 'dart:convert';
import 'dart:io';
import 'package:whoop_protocol/whoop_protocol.dart';
import 'package:test/test.dart';
import 'support/private_capture.dart';

void main() {
  test(
      'synthetic counter, epoch, subsecond and HR headers match authored inputs',
      () {
    final cases = json.decode(
      File('test/fixtures/synthetic_protocol.json').readAsStringSync(),
    ) as List;
    final headers = cases.where((c) => c['kind'] == 'r24' && c['out'] != null);
    expect(headers.length, greaterThan(5));
    for (final c in headers) {
      final r = parseR24(hexToBytes(c['hex'] as String))!;
      final expected = c['out'] as Map;
      expect(r.counter, expected['counter']);
      expect(r.tsEpoch, expected['ts_epoch']);
      expect(r.tsSubsec, expected['ts_subsec']);
      expect(r.hr, expected['hr']);
    }
  });

  final capture = privateCapture('dart_header.json');
  test('private captured headers retain all 550 original cases', () {
    final cases = json.decode(capture!.readAsStringSync()) as List;
    expect(cases.length, 550);
    for (final c in cases) {
      final r = parseR24(hexToBytes(c['hex'] as String))!;
      expect(r.counter, c['counter']);
      expect(r.tsEpoch, c['ts_epoch']);
      expect(r.tsSubsec, c['ts_subsec']);
      expect(r.hr, c['hr']);
    }
  },
      skip: capture == null
          ? 'Private header corpus absent; not public CI evidence'
          : null);
}

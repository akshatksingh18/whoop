// Isolate-safe preparation handoffs over authored samples, no captured night.
import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derive_prepare.dart';
import 'package:whoop_companion/compute/substrate.dart';

String raw(int ts, int hr) {
  final x = Uint8List(89);
  x[0] = 47;
  x[1] = 24;
  ByteData.sublistView(x)
    ..setUint32(7, ts, Endian.little)
    ..setFloat32(33, .5, Endian.little)
    ..setFloat32(45, 1, Endian.little);
  x[17] = hr;
  return x.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

Future<Map> worker(List<Map> messages) async {
  final port = ReceivePort();
  final it = StreamIterator(port);
  final isolate = await Isolate.spawn(derivationPrepareWorker, port.sendPort);
  try {
    expect(await it.moveNext(), true);
    final send = it.current as SendPort;
    for (final m in messages) send.send(m);
    send.send({'type': 'finish'});
    expect(await it.moveNext().timeout(const Duration(seconds: 10)), true);
    return it.current as Map;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    await it.cancel();
    port.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final legacy in [false, true]) {
    test(
      'COV-44 prepared handoff retains separate day sleep and midnight nap buffers $legacy',
      () {
        final day = Substrate.fromJson({
          'ts_sec': [100, 101],
          'hr': [60, 61],
        });
        final sleep = Substrate.fromJson({
          'ts_sec': [90, 91],
          'hr': [50, 51],
        });
        final nap = Substrate.fromJson({
          'ts_sec': [100, 101, 102],
          'hr': [60, 61, 62],
        });
        final original = PreparedDerivationPayload(
          dataNowSec: 999,
          days: [
            PreparedDerivationDay(
              date: '2021-04-06',
              endSec: 102,
              confidence: .6,
              flags: ['synthetic-gap'],
              sleepJson: {'tst_sec': 0},
              hypnoStages: ['wake', 'light'],
              sleepOnsetSec: 90,
              sleepOffsetSec: 92,
              sleepSource: 'manual',
              daySub: day,
              sleepSub: sleep,
              napSub: nap,
            ),
          ],
        );
        final json = original.toJson();
        if (legacy) (json['days'] as List).single.remove('nap_sub');
        final restored = PreparedDerivationPayload.fromJson(json);
        final got = restored.days.single;
        expect(restored.dataNowSec, 999);
        expect(got.date, '2021-04-06');
        expect(got.endSec, 102);
        expect(got.confidence, .6);
        expect(got.flags, ['synthetic-gap']);
        expect(got.sleepJson, {'tst_sec': 0});
        expect(got.hypnoStages, ['wake', 'light']);
        expect(got.sleepOnsetSec, 90);
        expect(got.sleepOffsetSec, 92);
        expect(got.sleepSource, 'manual');
        expect(got.daySub.toJson(), day.toJson());
        expect(got.sleepSub.toJson(), sleep.toJson());
        expect(got.napSub.toJson(), legacy ? day.toJson() : nap.toJson());
      },
    );
  }
  test(
    'COV-44 old empty preparation JSON stays absent rather than inventing data',
    () {
      final p = PreparedDerivationPayload.fromJson({
        'days': [{}],
      });
      expect(p.dataNowSec, 0);
      final d = p.days.single;
      expect(d.date, '');
      expect(d.confidence, 0);
      expect(d.sleepSource, 'auto');
      expect(d.daySub.isEmpty, true);
      expect(d.sleepSub.isEmpty, true);
      expect(d.napSub.isEmpty, true);
      expect(d.flags, isEmpty);
      expect(d.hypnoStages, isEmpty);
    },
  );
  for (final mode in ['substrate', 'prepared_day']) {
    test(
      'COV-44 raw page worker preserves timestamp ordering in $mode mode',
      () async {
        final ts = DateTime(2021, 4, 6, 12).millisecondsSinceEpoch ~/ 1000;
        final result = await worker([
          {'type': 'config', 'target_day': '2021-04-06', 'mode': mode},
          {
            'type': 'page',
            'hexes': [raw(ts + 1, 61), 'not-hex', raw(ts, 60)],
          },
        ]);
        expect(result['type'], 'result');
        expect(result['kind'], mode);
        final payload = (result['payload'] as Map).cast<String, dynamic>();
        if (mode == 'substrate') {
          final s = Substrate.fromJson(payload);
          expect(s.tsSec, [ts, ts + 1]);
          expect(s.hr, [60, 61]);
        } else {
          final p = PreparedDerivationPayload.fromJson(payload);
          expect(p.dataNowSec, ts + 1);
          expect(p.days.single.date, '2021-04-06');
          expect(p.days.single.daySub.tsSec, [ts, ts + 1]);
        }
      },
    );
  }
}

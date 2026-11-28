// Actual historical R10 producer/store -> range coordinator -> worker boundary.
// Worker-failure/retry cases are cloud-only;no physical-radio/night-score claim.
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_protocol/whoop_protocol.dart' as p;
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';
import '../compute/prepare_handoff_test.dart' show raw;
import '../ble/r10_durable_beat_contract_test.dart' show authoredR10;
import '../support/coverage_store.dart';

const _day = '2025-10-09', _receipt = 'authored sparse RR pages:';
void _reportPages(SendPort main) {
  final port = ReceivePort();
  main.send(port.sendPort);
  final frames = <int>[], beats = <Map>[], tails = <List<Map>>[];
  port.listen((message) {
    if (message is! Map) return;
    if (message['type'] == 'page') {
      final fs = (message['frames'] as List).cast<Map>();
      final rs = (message['rr'] as List).cast<Map>();
      frames.addAll(fs.map((f) => (f['rec_ts'] as num).toInt()));
      beats.addAll(rs);
      if (fs.isEmpty && rs.isNotEmpty) tails.add(rs);
    }
    if (message['type'] == 'finish') {
      // A refused worker result deliberately tests preservation of this real input.
      main.send({
        'type': 'error',
        'error':
            _receipt +
            jsonEncode({'frames': frames, 'beats': beats, 'tails': tails}),
      });
      port.close();
    }
  });
}

String _hex(Uint8List b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
Future<int> _seed(int count) async {
  final ts = localDayStartSec(_day)! + 3600;
  final middle = p.hexToBytes(raw(ts, 60));
  ByteData.sublistView(middle).setUint32(3, 1, Endian.little);
  final record = p.parseR24(middle)!;
  final one = Sample(
    tsEpoch: record.tsEpoch,
    counter: record.counter,
    hr: record.hr,
    rrIntervalsMs: record.rrIntervalsMs,
    ax: record.accelG[0],
    ay: record.accelG[1],
    az: record.accelG[2],
  );
  final raws = <RawRecord>[
    RawRecord(
      counter: 1,
      packetType: 47,
      hex: _hex(middle),
      capturedAt: ts * 1000,
      recTs: ts,
    ),
  ];
  final samples = <Sample?>[one];
  for (final (counter, second) in [(2, ts - 20), (3, ts + 20)]) {
    final bytes = authoredR10(count);
    ByteData.sublistView(bytes)
      ..setUint32(3, counter, Endian.little)
      ..setUint32(7, second, Endian.little);
    final r = p.parseR10Lite(bytes)!;
    expect(r.rrIntervalsMs, [for (var i = 0; i < count; i++) 800 + i]);
    raws.add(
      RawRecord(
        counter: counter,
        packetType: 47,
        hex: _hex(bytes),
        capturedAt: second * 1000,
        recTs: second,
      ),
    );
    samples.add(
      Sample(
        tsEpoch: r.tsEpoch,
        counter: r.counter,
        hr: r.hr,
        rrIntervalsMs: r.rrIntervalsMs,
      ),
    );
  }
  await SyncLedgerStore.commitBatch(raws, samples, deviceFamily: 'gen4');
  return ts;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-rr-tail-recovery', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  test(
    'authored R10-only seconds persist both beat boundaries without manufactured1Hz sensors',
    () async {
      final ts = await _seed(8), db = await LocalDb.instance;
      final frames = await db.query('decoded_onehz', orderBy: 'rec_ts');
      expect(frames, hasLength(1));
      expect(frames.single['rec_ts'], ts);
      expect(frames.single['hr'], 60);
      final rr = await LocalDb.decodedRrByRecTsRange(
        fromRecTs: ts - 20,
        toRecTs: ts + 20,
      );
      expect(rr, hasLength(16));
      expect(rr.take(8).every((r) => r['rec_ts'] == ts - 20), true);
      expect(rr.skip(8).every((r) => r['rec_ts'] == ts + 20), true);
      expect(rr.map((r) => r['rr_ms']).toList(), [
        for (var j = 0; j < 2; j++)
          for (var i = 0; i < 8; i++) 800 + i,
      ]);
    },
  );
  for (final mode in ['ordinary', 'rescan']) {
    for (final count in [5, 8]) {
      test(
        '$mode coordinator retains $count leading/trailing R10 beats across a refused worker result and real retry',
        () async {
          final ts = await _seed(count), db = await LocalDb.instance;
          await DayResultStore.put(
            dayId: _day,
            algoVersion: kAlgoVersion,
            payloadJson:
                '{"scalars":{"rhr":55},"authored":"retain RR recovery"}',
            windowJson: '{"authored":"retain window"}',
            rhr: 55,
            series: {'rhr': 55},
          );
          final banked = await db.query('day_result'),
              series = await db.query('metric_series'),
              frames = await db.query('decoded_onehz'),
              rr = await LocalDb.decodedRrByRecTsRange(
                fromRecTs: ts - 20,
                toRecTs: ts + 20,
              );
          final logs = <String>[],
              engine = DerivationEngine(
                background: true,
                log: logs.add,
                prepareWorkerEntry: _reportPages,
              );
          Future<int> run(DerivationEngine e) => mode == 'ordinary'
              ? e.run(const Profile(), force: true)
              : e.rescanRecent(const Profile());
          expect(await run(engine), 0);
          expect(engine.running, false);
          final logged = logs.firstWhere((s) => s.contains(_receipt));
          final begin = logged.indexOf(_receipt) + _receipt.length;
          final observed =
              jsonDecode(logged.substring(begin, logged.lastIndexOf('}') + 1))
                  as Map;
          expect(observed['frames'], [ts]);
          expect(observed['beats'], rr);
          final tails = observed['tails'] as List;
          expect(tails, hasLength(1));
          expect(tails.single, rr.skip(count).toList());
          expect(await db.query('day_result'), banked);
          expect(await db.query('metric_series'), series);
          expect(await db.query('decoded_onehz'), frames);
          expect(
            await LocalDb.decodedRrByRecTsRange(
              fromRecTs: ts - 20,
              toRecTs: ts + 20,
            ),
            rr,
          );
          final retry = DerivationEngine(background: true);
          expect(await run(retry), 1);
          expect(retry.running, false);
          expect(await db.query('decoded_onehz'), frames);
          expect(
            await LocalDb.decodedRrByRecTsRange(
              fromRecTs: ts - 20,
              toRecTs: ts + 20,
            ),
            rr,
          );
          expect((await DayResultStore.read(_day))!['rhr'], 55);
          expect(
            (await DayResultStore.read(_day))!['window_json'],
            '{"authored":"retain window"}',
          );
        },
        timeout: const Timeout(Duration(minutes: 2)),
      );
    }
  }
}

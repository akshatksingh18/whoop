// Saved-session recovery and unjudged naps through real current compute paths.
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/nap_edits.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-saved-recovery'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final manual in [false, true]) {
    test(
      'COV-44 an unjudged nap day preserves authored entries without inventing detection $manual',
      () {
        final bundle = <String, dynamic>{}, scalars = <String, dynamic>{};
        final result = DerivationEngine.debugAttachNaps(
          bundle,
          scalars,
          Substrate.fromJson({}),
          0,
          0,
          napEdits: [
            if (manual)
              const NapEdit(
                kind: NapEditKind.added,
                startSec: 1000,
                endSec: 2800,
              ),
          ],
        );
        final naps = bundle['naps'] as Map;
        if (manual) {
          expect(result, hasLength(1));
          expect(naps['detected'], isNull);
          expect(naps['confidence'], isNull);
          expect(naps['tier'], 'AUTH');
          expect(naps['inputs_used'], ['user']);
          expect(scalars['nap_min'], 30);
          expect(result!.single['duration_min'], 30);
          expect(result.single['source'], 'manual');
        } else {
          expect(result, isNull);
          expect(naps['value'], isNull);
          expect(naps['count'], isNull);
          expect(scalars.containsKey('nap_min'), false);
        }
      },
    );
  }
  for (final ended in [false, true]) {
    test(
      'COV-44 imported derivation retains saved workout bounds and recovery $ended',
      () async {
        const day = '2021-04-06';
        final ts = localDayStartSec(day)! + 12 * 3600;
        const n = 600;
        await LocalDb.putSession({
          'id': 'synthetic-recovery',
          'type': 'cycling',
          'start_ts': ts,
          'end_ts': ended ? ts + 300 : null,
          'status': ended ? 'done' : 'live',
          'created_at': ts * 1000,
          'source': 'manual',
        });
        final sub = Substrate(
          tsSec: [for (var i = 0; i < n; i++) ts + i],
          hr: [
            for (var i = 0; i < n; i++)
              i <= 300 ? 170 : (70 + 100 * math.exp(-(i - 300) / 30)).round(),
          ],
          rrTsMs: [],
          rrMs: [],
          ax: [for (var i = 0; i < n; i++) i % 2 == 0 ? 0.6 : -0.6],
          ay: List.filled(n, 0.0),
          az: List.filled(n, 1.0),
          spo2Red: List.filled(n, null),
          spo2Ir: List.filled(n, null),
          skinTemp: List.filled(n, null),
          skinContact: List.filled(n, null),
          deviceFamily: 'whoop4',
        );
        var revisions = 0;
        final engine = DerivationEngine(
          background: true,
          onSessionChanged: () => revisions++,
        );
        expect(
          await engine.deriveImportedDays(
            sub,
            const Profile(ageYears: 30, sex: 'f', weightKg: 70, heightCm: 170),
            {day},
          ),
          1,
        );
        final row = (await LocalDb.dayResult(day))!;
        final bundle = jsonDecode(row['payload_json'] as String) as Map;
        expect(bundle, isNotEmpty);
        expect(engine.running, false);
        final session = (await LocalDb.session('synthetic-recovery'))!;
        expect(session['start_ts'], ts);
        expect(session['end_ts'], ended ? ts + 300 : isNull);
        if (ended) {
          expect(revisions, greaterThan(0));
          expect(session['hrr_bpm'], greaterThan(12));
        } else {
          expect(revisions, 0);
          expect(session['hrr_bpm'], isNull);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }
}

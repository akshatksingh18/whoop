// Full authored-night ingestion and scheduler orchestration: Linux CI only.
// This verifies publication/error isolation, not physiological or phone accuracy.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/data/models.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'coverage_derived_effort_handoff_test.dart' show authored;
import 'support/coverage_store.dart';

class App extends AppState {
  App() : super.forTesting();
  @override
  Future<void> syncNow() async {} // No radio is part of this test.
}

class Reader extends LocalRepositoryImpl {
  Reader(this.refuse)
    : super(
        getProfileMap: () => {
          'age': 30,
          'sex': 'f',
          'weight_kg': 70,
          'height_cm': 170,
        },
      );
  final bool refuse;
  int repairs = 0, rescores = 0;
  @override
  Future<int> repairSessionCalorieBasis() async {
    repairs++;
    return super.repairSessionCalorieBasis();
  }

  @override
  Future<int> rescoreRecentSessions({int sinceDays = 3}) async {
    rescores++;
    if (refuse) throw StateError('synthetic session rescore refusal');
    return super.rescoreRecentSessions(sinceDays: sinceDays);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('app-derive-publication'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final refuse in [false, true]) {
    test(
      'queued pull publishes its authored day while session rescore ${refuse ? 'refusal stays isolated' : 'runs once'}',
      () async {
        final substrate = authored();
        final date = todayLabel(
          DateTime.now().subtract(const Duration(days: 1)),
        );
        final start = localDayStartSec(date)! + 3600;
        final samples = <Sample?>[], raws = <RawRecord>[];
        for (var i = 0; i < substrate.tsSec.length; i++) {
          final ts = start + i;
          raws.add(
            RawRecord(
              counter: i + 1,
              packetType: 47,
              hex: 'authored-app-publish-$i',
              capturedAt: ts * 1000,
              recTs: ts,
            ),
          );
          samples.add(
            Sample(
              tsEpoch: ts,
              counter: i + 1,
              hr: substrate.hr[i],
              rrIntervalsMs: [substrate.rrMs[i].round()],
              ax: substrate.ax[i],
              ay: substrate.ay[i],
              az: substrate.az[i],
            ),
          );
        }
        await LocalDb.upsertDevice(adapterId: 'gen4');
        await LocalDb.commitSyncBatch(raws, samples, deviceFamily: 'gen4');
        final app = App()
          ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
        final repo = Reader(refuse);
        app.repo = repo;
        final previous = NotificationCenter.instance.presentSink;
        NotificationCenter.instance.presentSink =
            (_, {bool allowPermissionPrompt = true}) async => false;
        try {
          final revision = app.insightsRevision.value;
          final note = await app.pullRefresh(
            timeout: const Duration(seconds: 75),
          );
          // The pull is capped for the screen. Wait for its durable calculation,
          // even if the spinner finished before the older day.
          final deadline = DateTime.now().add(const Duration(seconds: 75));
          while ((app.deriving || app.derivePending) &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          expect(app.deriving || app.derivePending, false);
          final row = await LocalDb.dayResult(date);
          expect(row, isNotNull);
          expect(row!['partial'], 0);
          expect(row['skipped'], 0);
          expect(app.insightsRevision.value, greaterThan(revision));
          expect(repo.repairs, 1);
          expect(repo.rescores, 1);
          expect(note, 'Band not connected');
          expect(
            await LocalDb.getCursorInt('rec_ts_hw'),
            start + substrate.tsSec.length - 1,
          );
          expect(
            await LocalDb.lastDecodedRecTs(),
            start + substrate.tsSec.length - 1,
          );
        } finally {
          app.dispose();
          await app.engine.disconnect();
          NotificationCenter.instance.presentSink = previous;
        }
      },
      timeout: const Timeout(Duration(minutes: 4)),
    );
  }
}

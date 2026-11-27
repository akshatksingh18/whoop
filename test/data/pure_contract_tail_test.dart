// Pure value, formatter and fallback contracts that current screens reach only
// through other hosts. Authored synthetic inputs; no physical or native claim.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/adapters/_registry.dart';
import 'package:whoop_companion/compute/crossday_pipeline.dart';
import 'package:whoop_companion/compute/manual_session.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/live_coverage_policy.dart';
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/data/progress_review.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/models/metric.dart';
import 'package:whoop_companion/notify/notification_log.dart';
import 'package:whoop_companion/sync/sync_policy.dart';
import 'package:whoop_companion/ui2/profile/alarm.dart';
import 'package:whoop_companion/ui2/recent_hrv_card.dart';
import 'package:whoop_companion/ui2/screens/home_screen.dart';
import 'package:whoop_companion/ui2/screens/readiness_detail.dart';

String _hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// A 0x28 compact live-HR frame: ts u32 LE at [2], rr count at [9], rr i16 LE
/// from [10]. [length] 12 is the shortest frame that still carries one beat.
String _liveRr(int ts, List<int> rr, {int length = 20}) {
  final b = Uint8List(length);
  final v = ByteData.view(b.buffer);
  b[0] = 0x28;
  v.setUint32(2, ts, Endian.little);
  b[9] = rr.length;
  for (var i = 0; i < rr.length; i++) {
    v.setInt16(10 + 2 * i, rr[i], Endian.little);
  }
  return _hex(b);
}

void main() {
  test('diagnostic value types describe themselves', () {
    expect(
      const LiveCoverageWindow(5, 65).toString(),
      'LiveCoverageWindow(5..65, 60s)',
    );
    expect(
      const ManualWindowException(ManualWindowError.tooShort).toString(),
      'ManualWindowException: A workout has to be at least a minute.',
    );
    expect(
      RepositoryException(409, 'authored conflict').toString(),
      'Repository error 409: authored conflict',
    );
  });

  test('fixed progress ranges', () {
    expect(ProgressRange.week.from('2024-03-10'), '2024-03-04');
    expect(ProgressRange.month.from('2024-03-10'), '2024-02-10');
  });

  test('empty-sync tracker reset clears a run below the threshold', () {
    final t = EmptySyncTracker(threshold: 2);
    expect(
      t.recordCompletedSync(bankedSensorRecords: false, consoleOnly: true),
      isFalse,
    );
    t.reset();
    expect(
      t.recordCompletedSync(bankedSensorRecords: false, consoleOnly: true),
      isFalse,
    );
    expect(
      t.recordCompletedSync(bankedSensorRecords: false, consoleOnly: true),
      isTrue,
    );
  });

  test('low-density band span outside every confirmed-still hour is kept', () {
    final r = resolveDaySteps([
      const CoverageSpan(startTs: 0, endTs: 3600, steps: 0, fromBand: false),
      const CoverageSpan(
        startTs: 7200,
        endTs: 10800,
        steps: 30,
        fromBand: true,
      ),
    ], bandSteps: true);
    expect(r.hasPhoneCoverage, isTrue);
    expect(r.phone, 0);
  });

  test(
    'manual stats keep the raw peak when every sample is above the ceiling',
    () {
      final s = computeManualSessionStats(
        hrTs: const [100, 101, 102],
        hrBpm: const [251, 252, 253],
        profile: const Profile(),
        hrMax: null,
      );
      expect(s.maxHr, 253);
    },
  );

  test('JSON sanitizer drops a non-string key and records its path', () {
    final dropped = <String>[];
    final out = sanitizeForJson({
      'kept': 1,
      'nested': {7: 'lost', 'ok': true},
      3: 'root key',
    }, dropped);
    expect(out, {
      'kept': 1,
      'nested': {'ok': true},
    });
    expect(dropped, ['nested.<key:7>', '<key:3>']);
  });

  test('a scalar metric uses the separate flag confidence', () {
    final m = Metric.parse(4.5, flag: const {'c': 0.25, 'unit': 'h'});
    expect(m.confidence, 0.25);
    expect(m.unit, 'h');
  });

  test('a one-time occurrence after the window start is returned once', () {
    final first = DateTime(2024, 5, 2, 7);
    expect(
      NotificationLog.occurrences(
        first,
        PlanRepeat.once,
        DateTime(2024, 5, 1),
        DateTime(2024, 5, 9),
      ),
      [first],
    );
  });

  test('alarm state label for no alarm', () {
    expect(AlarmScreenView.stateLabel(AlarmArmState.none), 'Not set');
  });

  test('recent HRV sentence without a prior average', () {
    expect(
      RecentHrvCard.sentence((
        day: '2024-05-10',
        nights: const [],
        usual: (lo: 40.0, hi: 60.0),
        avg7: null,
        before: null,
        last: 30.0,
        lastDate: '2024-05-10',
      ), today: '2024-05-10'),
      '30 ms last night, below your usual 40–60.',
    );
  });

  test('unknown driver keys are humanised, blank keys stay blank', () {
    expect(driverLabel(''), '');
    expect(driverLabel(null), '');
    expect(driverLabel('resp_rate_slope'), 'Resp rate slope');
    expect(driverLabel('_'), '');
  });

  test('a sleep-correction note explains the unscored day first', () {
    expect(
      readinessGap({'sleep_correction': 'authored'}, hasDay: true),
      'authored',
    );
  });

  test('an unparseable day has no active windows', () {
    final c = WorkoutClock('authored', DateTime(2024, 5, 1, 7));
    expect(c.onDay('not-a-day'), isEmpty);
  });

  test('a pause recorded before the session start is clamped to the start', () {
    final start = DateTime(2024, 5, 1, 9);
    final s = PushupSession(
      day: '2024-05-01',
      started: start,
      ended: start.add(const Duration(hours: 1)),
      interval: 30,
      state: PushupState.ended,
      events: [
        PushupEvent(
          at: start.subtract(const Duration(minutes: 5)),
          kind: PushupEventKind.pause,
        ),
        PushupEvent(
          at: start.add(const Duration(minutes: 10)),
          kind: PushupEventKind.resume,
        ),
      ],
    );
    final day = PushupDay.of('2024-05-01', [
      s,
    ], start.add(const Duration(hours: 2)))!;
    expect(day.pauses.first.from, start);
  });

  test('notify-only band entry has no envelope offsets', () {
    // ignore: prefer_const_constructors
    final e = BandEntry.notify(
      id: 'authored-notify',
      label: 'Authored notify band',
      service: '0000180d-0000-1000-8000-00805f9b34fb',
      characteristics: const ['00002a37-0000-1000-8000-00805f9b34fb'],
      timeAnchor: TimeAnchor.measured,
    );
    expect(e.isFramed, isFalse);
    expect(e.innerOpcodeOffset, -1);
    expect(e.innerVersionOffset, -1);
    expect(e.innerCounterOffset, -1);
    expect(e.servicePrefix, '0000180d');
  });

  test('a short compact live frame is timed by its own timestamp', () {
    expect(
      LocalDb.decodeRecTs(
        _liveRr(1700000000, [900], length: 12),
        fallbackSec: 7,
      ),
      1700000000,
    );
  });
}

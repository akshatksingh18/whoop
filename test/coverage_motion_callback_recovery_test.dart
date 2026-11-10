// Authored cadence channel replies and persisted motion shapes. Current
// source ownership and accepted calorie methods are unchanged.
import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/gps/live_cadence.dart';
import 'package:whoop_companion/gps/motion_window.dart';

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('whoop/phone_cadence');
  for (final failure in [
    MissingPluginException('authored unsupported sensor'),
    PlatformException(code: 'authored sensor permission refusal'),
  ]) {
    test(
      'Cadence ${failure.runtimeType} stays unknown and a later generation can recover',
      () async {
        final starts = <int>[];
        final calls = <MethodCall>[];
        var refusing = true, notices = 0;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'start') {
            starts.add((call.arguments as Map)['generation'] as int);
            if (refusing) throw failure;
          }
          return null;
        });
        final cadence = PhoneCadence();
        Future<void> receive(int generation, double rate) async {
          const codec = StandardMethodCodec();
          final reply = Completer<ByteData?>();
          binding.channelBuffers.push(
            channel.name,
            codec.encodeMethodCall(
              MethodCall('cadence', {
                'generation': generation,
                'stepsPerSecond': rate,
                'atMs': DateTime.utc(2021, 4, 6, 12).millisecondsSinceEpoch,
              }),
            ),
            reply.complete,
          );
          expect(codec.decodeEnvelope((await reply.future)!), isNull);
        }

        try {
          await cadence.start(() => notices++);
          expect(cadence.reading, isNull);
          expect(notices, 0);
          refusing = false;
          await cadence.start(() => notices++);
          expect(starts, [1, 2]);
          await receive(starts.first, 2);
          expect(notices, 0);
          expect(cadence.reading, isNull);
          await receive(starts.last, 2);
          expect(cadence.reading!.spm, 120);
          expect(notices, 1);
          cadence.stop();
          await Future<void>.delayed(Duration.zero);
          expect(cadence.reading, isNull);
          expect(calls.last.method, 'stop');
          expect(calls.last.arguments, isNull);
        } finally {
          cadence.stop();
          binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          );
        }
      },
    );
  }
  test(
    'Motion roundtrip retains explicit chunk times and partial final duration',
    () {
      final at = DateTime.utc(2021, 4, 6, 12);
      final motion = MotionWindow(
        at,
        60,
        [60, 5],
        [80, 6],
        seconds: [60, 5],
        timesMs: [
          at.millisecondsSinceEpoch,
          at.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
        ],
      );
      final saved = motion.toJson();
      final restored = MotionWindow.fromJson(saved)!;
      expect(restored.toJson(), saved);
      expect(restored.totalSteps, 65);
      expect(restored.totalMeters, 86);
      expect(restored.activeMinutes, closeTo(65 / 60, 1e-12));
      expect(saved['times'], [
        at.millisecondsSinceEpoch,
        at.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
      ]);
    },
  );
  test(
    'Journal metric value membership retains midnight, explicit zero and absent occurrence separately',
    () {
      const midnight = JournalMetricValue(0, atMinuteOfDay: 0);
      const same = JournalMetricValue(0, atMinuteOfDay: 0);
      const unknown = JournalMetricValue(0);
      const later = JournalMetricValue(0, atMinuteOfDay: 1);
      expect(midnight, same);
      expect(midnight.hashCode, same.hashCode);
    expect(<JournalMetricValue>{}..addAll([midnight, same, unknown, later]), hasLength(3));
      expect(midnight.toString(), 'JournalMetricValue(0.0, at: 0)');
      expect(unknown.toString(), 'JournalMetricValue(0.0, at: null)');
      expect(midnight == unknown, false);
      expect(midnight == const JournalMetricValue(1, atMinuteOfDay: 0), false);
    },
  );
}

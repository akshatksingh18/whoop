import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:openstrap_edge/health/health_export.dart';
import 'package:openstrap_edge/health/health_sleep_session.dart';

int _seconds(DateTime value) => value.millisecondsSinceEpoch ~/ 1000;

Map<String, Object> _segment(DateTime start, DateTime end, String stage) => {
  'start': _seconds(start),
  'end': _seconds(end),
  'stage': stage,
};

Map<String, dynamic> _overnightBundle() {
  final start = DateTime(2026, 8, 4, 23, 55);
  final end = DateTime(2026, 8, 5, 7, 46);
  final at0011 = DateTime(2026, 8, 5, 0, 11);
  final at0241 = DateTime(2026, 8, 5, 2, 41);
  final at0257 = DateTime(2026, 8, 5, 2, 57);
  final at0545 = DateTime(2026, 8, 5, 5, 45);
  final at0720 = DateTime(2026, 8, 5, 7, 20);
  final at0736 = DateTime(2026, 8, 5, 7, 36);

  return {
    'sleep': {
      'window': {
        'value': {
          'onset_ms': start.millisecondsSinceEpoch,
          'offset_ms': end.millisecondsSinceEpoch,
        },
      },
    },
    'series': {
      // Intentionally out of order: normalization must use timestamps, not
      // the input list order.
      'hypnogram': [
        _segment(at0545, at0720, 'rem'), // 95 min
        _segment(start, at0011, 'wake'), // 16 min awake
        _segment(at0257, at0545, 'light'), // 168 min
        _segment(at0720, at0736, 'awake'), // 16 min awake
        _segment(at0241, at0257, 'deep'), // 16 min
        _segment(at0011, at0241, 'light'), // 150 min
      ],
    },
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Health Connect sleep-session export regression', () {
    test(
      'successful priority sleep bypasses retry backoff and cap for same-day bulk',
      () {
        final now = DateTime(2026, 8, 6, 12);

        expect(
          shouldAttemptHealthBulkExport(
            attempts: 2,
            maxAttempts: 6,
            now: now,
            lastAttempt: now.subtract(const Duration(seconds: 1)),
            backoff: const Duration(hours: 2),
            prioritySleepAlreadyWritten: true,
          ),
          isTrue,
        );
        expect(
          shouldAttemptHealthBulkExport(
            attempts: 6,
            maxAttempts: 6,
            now: now,
            lastAttempt: now.subtract(const Duration(seconds: 1)),
            backoff: const Duration(hours: 2),
            prioritySleepAlreadyWritten: false,
          ),
          isFalse,
        );
        expect(
          shouldAttemptHealthBulkExport(
            attempts: 6,
            maxAttempts: 6,
            now: now,
            lastAttempt: now.subtract(const Duration(days: 1)),
            backoff: const Duration(hours: 2),
            prioritySleepAlreadyWritten: true,
          ),
          isTrue,
        );
      },
    );

    test(
      'newest detected sleep is written before bulk and only once',
      () async {
        final writes = <Map<String, dynamic>>[];
        final newestSleep = _overnightBundle();

        final result = await exportNewestPrioritySleep(
          newestFirstDays: [
            MapEntry('2026-08-06', <String, dynamic>{}),
            MapEntry('2026-08-05', newestSleep),
            MapEntry('2026-08-04', _overnightBundle()),
          ],
          write: (bundle) async {
            writes.add(bundle);
            return true;
          },
        );

        expect(result.date, '2026-08-05');
        expect(result.succeeded, isTrue);
        expect(writes, hasLength(1));
        expect(writes.single, same(newestSleep));
      },
    );

    test('failed priority sleep write reports failure', () async {
      var writes = 0;

      final result = await exportNewestPrioritySleep(
        newestFirstDays: [MapEntry('2026-08-05', _overnightBundle())],
        write: (bundle) async {
          writes++;
          return false;
        },
      );

      expect(result.date, '2026-08-05');
      expect(result.succeeded, isFalse);
      expect(writes, 1);
    });

    test('failed priority sleep never invokes the bulk callback', () async {
      var priorityWrites = 0;
      var bulkWrites = 0;

      final result = await exportPrioritySleepBeforeBulk(
        newestFirstDays: [MapEntry('2026-08-05', _overnightBundle())],
        write: (bundle) async {
          priorityWrites++;
          return false;
        },
        exportBulk: (androidSleepAlreadyWritten) async {
          bulkWrites++;
        },
      );

      expect(result.date, '2026-08-05');
      expect(result.succeeded, isFalse);
      expect(priorityWrites, 1);
      expect(bulkWrites, 0);
    });

    test('thrown priority sleep never invokes the bulk callback', () async {
      var bulkWrites = 0;

      await expectLater(
        exportPrioritySleepBeforeBulk(
          newestFirstDays: [MapEntry('2026-08-05', _overnightBundle())],
          write: (bundle) async => throw StateError('priority write failed'),
          exportBulk: (androidSleepAlreadyWritten) async {
            bulkWrites++;
          },
        ),
        throwsA(isA<StateError>()),
      );

      expect(bulkWrites, 0);
    });

    test('priority success leaves shared retry state for the bulk export', () {
      final source = File('lib/health/health_export.dart').readAsStringSync();
      final priorityCallback = source.substring(
        source.indexOf(
          'final priorityResult = await exportPrioritySleepBeforeBulk(',
        ),
        source.indexOf('exportBulk = (String? androidSleepAlreadyWritten)'),
      );

      expect(
        priorityCallback,
        isNot(contains('retryState.remove(priorityDay!.key)')),
        reason: 'only the full-day bulk result may clear a shared retry entry',
      );
    });

    test(
      'successful priority sleep invokes bulk once without another sleep',
      () async {
        var priorityWrites = 0;
        var totalSleepWrites = 0;
        final bulkPriorityDates = <String?>[];

        final result = await exportPrioritySleepBeforeBulk(
          newestFirstDays: [MapEntry('2026-08-05', _overnightBundle())],
          write: (bundle) async {
            priorityWrites++;
            totalSleepWrites++;
            return true;
          },
          exportBulk: (androidSleepAlreadyWritten) async {
            bulkPriorityDates.add(androidSleepAlreadyWritten);
            if (androidSleepAlreadyWritten == null) totalSleepWrites++;
          },
        );

        expect(result.date, '2026-08-05');
        expect(result.succeeded, isTrue);
        expect(priorityWrites, 1);
        expect(totalSleepWrites, 1);
        expect(bulkPriorityDates, ['2026-08-05']);
      },
    );

    test('Android generic cleanup never deletes sleep records', () {
      final types = healthDeleteTypes(isApplePlatform: false);

      expect(types, contains(HealthDataType.STEPS));
      expect(
        types,
        isNot(contains(HealthDataType.HEART_RATE)),
        reason: 'Android native replacement owns heart-rate cleanup',
      );
      expect(
        types,
        isNot(
          containsAll(<HealthDataType>[
            HealthDataType.SLEEP_DEEP,
            HealthDataType.SLEEP_REM,
            HealthDataType.SLEEP_LIGHT,
            HealthDataType.SLEEP_AWAKE,
            HealthDataType.SLEEP_SESSION,
          ]),
        ),
      );
      expect(types.where((type) => type.name.startsWith('SLEEP_')), isEmpty);
    });

    test('Apple generic cleanup retains heart-rate records', () {
      expect(
        healthDeleteTypes(isApplePlatform: true),
        contains(HealthDataType.HEART_RATE),
      );
    });

    test('Apple and Android share one hypnogram stage vocabulary', () {
      expect(healthSleepStageOf('wake'), HealthSleepStage.awake);
      expect(healthSleepStageOf('awake'), HealthSleepStage.awake);
      expect(healthSleepStageOf('rem'), HealthSleepStage.rem);
      expect(healthSleepStageOf('light'), HealthSleepStage.light);
      expect(healthSleepStageOf('nrem'), HealthSleepStage.light);
      expect(healthSleepStageOf('deep'), HealthSleepStage.deep);
      expect(healthSleepStageOf('unknown'), isNull);
    });

    test('manual sync bypasses retry backoff and attempt cap', () {
      final now = DateTime(2026, 8, 5, 13);

      expect(
        shouldAttemptHealthExport(
          attempts: 6,
          maxAttempts: 6,
          now: now,
          lastAttempt: now.subtract(const Duration(seconds: 1)),
          backoff: const Duration(hours: 1),
        ),
        isFalse,
      );
      expect(
        shouldAttemptHealthExport(
          attempts: 6,
          maxAttempts: 6,
          now: now,
          lastAttempt: now.subtract(const Duration(seconds: 1)),
          backoff: const Duration(hours: 1),
          force: true,
        ),
        isTrue,
      );
    });

    test(
      'manual health exports are single-flight and reset after completion',
      () async {
        final gate = HealthExportSingleFlight();
        final firstResult = Completer<int>();
        var calls = 0;

        Future<int> export() {
          calls++;
          return calls == 1 ? firstResult.future : Future<int>.value(2);
        }

        final first = gate.run(export);
        final overlapping = gate.run(export);
        expect(calls, 1);

        firstResult.complete(1);
        expect(await first, 1);
        expect(await overlapping, 1);
        expect(await gate.run(export), 2);
        expect(calls, 2);
      },
    );

    test('single-flight preserves synchronous errors and resets', () async {
      final gate = HealthExportSingleFlight();

      await expectLater(
        gate.run(() => throw StateError('boom')),
        throwsA(isA<StateError>()),
      );
      expect(await gate.run(() async => 3), 3);
    });

    test('AppState centralizes every full health export behind one gate', () {
      final source = File('lib/state/app_state.dart').readAsStringSync();
      final directCalls = RegExp(
        r'_healthExport\.exportAll\(',
      ).allMatches(source);

      expect(
        directCalls,
        hasLength(1),
        reason: 'automatic and forced exports must share one guarded method',
      );
      expect(source, contains('Future<int> _runHealthExport('));
    });

    test('normalizes one complete cross-midnight session with every stage', () {
      final session = normalizeHealthSleepSession(_overnightBundle());

      expect(session, isNotNull);
      expect(session!.start, DateTime(2026, 8, 4, 23, 55));
      expect(session.end, DateTime(2026, 8, 5, 7, 46));
      expect(session.stages, hasLength(6));

      for (var i = 0; i < session.stages.length; i++) {
        final stage = session.stages[i];
        expect(stage.start.isBefore(stage.end), isTrue);
        expect(stage.start.isBefore(session.start), isFalse);
        expect(stage.end.isAfter(session.end), isFalse);
        if (i > 0) {
          expect(
            stage.start.isBefore(session.stages[i - 1].end),
            isFalse,
            reason: 'sleep stages must be ordered and non-overlapping',
          );
        }
      }

      final minutesByStage = <HealthSleepStage, int>{};
      for (final stage in session.stages) {
        minutesByStage.update(
          stage.stage,
          (value) => value + stage.duration.inMinutes,
          ifAbsent: () => stage.duration.inMinutes,
        );
      }
      expect(minutesByStage, {
        HealthSleepStage.awake: 32,
        HealthSleepStage.rem: 95,
        HealthSleepStage.light: 318,
        HealthSleepStage.deep: 16,
      });
    });

    test(
      'clips stages to the parent and removes overlap and zero duration',
      () {
        final start = DateTime(2026, 8, 4, 23, 55);
        final end = DateTime(2026, 8, 5, 0, 25);
        final bundle = {
          'sleep': {
            'window': {
              'value': {
                'onset_ms': start.millisecondsSinceEpoch,
                'offset_ms': end.millisecondsSinceEpoch,
              },
            },
          },
          'series': {
            'hypnogram': [
              _segment(
                start.subtract(const Duration(minutes: 5)),
                start.add(const Duration(minutes: 10)),
                'light',
              ),
              _segment(
                start.add(const Duration(minutes: 8)),
                start.add(const Duration(minutes: 20)),
                'deep',
              ),
              _segment(end, end, 'rem'),
              _segment(
                start.add(const Duration(minutes: 20)),
                end.add(const Duration(minutes: 5)),
                'rem',
              ),
            ],
          },
        };

        final session = normalizeHealthSleepSession(bundle)!;

        expect(session.stages, hasLength(3));
        expect(session.stages[0].start, start);
        expect(session.stages[0].end, start.add(const Duration(minutes: 10)));
        expect(session.stages[1].start, start.add(const Duration(minutes: 10)));
        expect(session.stages[1].end, start.add(const Duration(minutes: 20)));
        expect(session.stages[2].start, start.add(const Duration(minutes: 20)));
        expect(session.stages[2].end, end);
      },
    );

    test('one channel call carries one parent and every stage', () async {
      const channel = MethodChannel('openstrap/test_health_connect_sleep');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return true;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
      });

      final exporter = HealthConnectSleepSessionExporter(
        writer: MethodChannelHealthConnectSleepSessionWriter(channel: channel),
      );

      expect(await exporter.replace(_overnightBundle()), isTrue);
      expect(calls, hasLength(1));
      expect(calls.single.method, 'replaceSleepSession');
      final args = (calls.single.arguments as Map).cast<String, Object?>();
      expect(
        args['startTime'],
        DateTime(2026, 8, 4, 23, 55).millisecondsSinceEpoch,
      );
      expect(
        args['endTime'],
        DateTime(2026, 8, 5, 7, 46).millisecondsSinceEpoch,
      );
      expect(args['stages'] as List, hasLength(6));
    });

    test(
      'an empty normalized hypnogram is retryable and never replaces native data',
      () async {
        const channel = MethodChannel('openstrap/test_health_connect_empty');
        var calls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls++;
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final exporter = HealthConnectSleepSessionExporter(
          writer: MethodChannelHealthConnectSleepSessionWriter(
            channel: channel,
          ),
        );
        final bundle = _overnightBundle();
        ((bundle['series'] as Map)['hypnogram'] as List).clear();

        expect(await exporter.replace(bundle), isFalse);
        expect(calls, 0, reason: 'empty stages must not delete native sleep');
      },
    );

    test(
      're-export uses the replace operation and a false result propagates',
      () async {
        const channel = MethodChannel('openstrap/test_health_connect_replace');
        final storedParents = <Map<String, Object?>>[];
        var writes = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              writes++;
              final args = (call.arguments as Map).cast<String, Object?>();
              storedParents
                ..clear()
                ..add(args);
              return writes == 1;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final exporter = HealthConnectSleepSessionExporter(
          writer: MethodChannelHealthConnectSleepSessionWriter(
            channel: channel,
          ),
        );

        expect(await exporter.replace(_overnightBundle()), isTrue);
        expect(await exporter.replace(_overnightBundle()), isFalse);
        expect(writes, 2, reason: 'each export sends exactly one replace call');
        expect(storedParents.single['stages'] as List, hasLength(6));
      },
    );

    test(
      'overlapping exports never enter the native replace concurrently',
      () async {
        const channel = MethodChannel(
          'openstrap/test_health_connect_concurrency',
        );
        final firstEntered = Completer<void>();
        final releaseFirst = Completer<bool>();
        var calls = 0;
        var activeCalls = 0;
        var maxActiveCalls = 0;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls++;
              activeCalls++;
              if (activeCalls > maxActiveCalls) maxActiveCalls = activeCalls;
              if (calls == 1) {
                firstEntered.complete();
                await releaseFirst.future;
              }
              activeCalls--;
              return true;
            });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null);
        });
        final exporter = HealthConnectSleepSessionExporter(
          writer: MethodChannelHealthConnectSleepSessionWriter(
            channel: channel,
          ),
        );

        final first = exporter.replace(_overnightBundle());
        await firstEntered.future;
        final second = exporter.replace(_overnightBundle());
        await pumpEventQueue();

        expect(calls, 1, reason: 'the second native replace must stay queued');
        releaseFirst.complete(true);
        expect(await first, isTrue);
        expect(await second, isTrue);
        expect(calls, 2);
        expect(maxActiveCalls, 1);
      },
    );
  });
}

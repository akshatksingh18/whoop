// Durable scheduler -> AppState -> notification handoff over authored saved rows.
// No decoded input is present, so these short probes perform no night derivation.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/notify/notification_center.dart';
import 'package:whoop_companion/notify/notification_event.dart';
import 'package:whoop_companion/notify/notification_prefs.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/sync/file_log.dart';

import 'support/coverage_store.dart';

class _App extends AppState {
  _App() : super.forTesting();
  @override
  Future<void> syncNow() async {} // The queued calculation is independent of radio.
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('recovery-ready-handoff'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final field in ['scalars', 'sleep', 'accounting']) {
    for (final wrong in <Object>[0, <Object>[]]) {
      test(
        'saved $field ${wrong.runtimeType} shape keeps unavailable overnight detail honest',
        () async {
          final date = todayLabel();
          final payload = <String, dynamic>{
            'scalars': <String, dynamic>{},
            'sleep': <String, dynamic>{
              'accounting': {
                'value': {'tst_sec': 3600},
              },
            },
          };
          if (field == 'accounting') {
            (payload['sleep'] as Map)['accounting'] = wrong;
          } else {
            payload[field] = wrong;
          }
          await LocalDb.putDayResult(
            dayId: date,
            algoVersion: kAlgoVersion,
            payloadJson: jsonEncode(payload),
            windowJson: '{}',
            readiness: 72,
          );
          final before = await LocalDb.dayResult(date);
          await LocalDb.refreshComputeFreshness();
          final row = (await LocalDb.computeFreshness('today'))!;
          final state = jsonDecode(row['payload_json'] as String) as Map;
          expect(state['activity_state'], 'ready');
          expect(
            state['recovery_day'],
            date,
            reason: 'the separate saved scalar remains authoritative',
          );
          expect(
            state['overnight_state'],
            field == 'scalars' ? 'ready' : 'missing',
          );
          expect(state['overnight_day'], field == 'scalars' ? date : isNull);
          expect(
            state['overnight_no_sleep_today'],
            false,
            reason: 'unreadable detail is not a decided no-sleep night',
          );
          expect(await LocalDb.dayResult(date), before);
        },
      );
    }
  }
  for (final kind in [
    'ready',
    'refused',
    'missing-score',
    'invalid-sleep',
    'invalid-accounting',
    'invalid-scalars',
  ]) {
    test(
      '$kind saved recovery retains notification retry and deduplication',
      () async {
        final date = todayLabel();
        final payload = jsonEncode({
          if (kind == 'invalid-scalars')
            'scalars': 'authored incompatible scalar detail',
          'sleep': kind == 'invalid-sleep'
              ? 'authored incompatible sleep detail'
              : {
                  'accounting': kind == 'invalid-accounting'
                      ? 'authored incompatible accounting detail'
                      : {
                          'value': {'tst_sec': 7 * 3600 + 17 * 60},
                        },
                },
        });
        await LocalDb.putDayResult(
          dayId: date,
          algoVersion: kAlgoVersion,
          finalized: true,
          payloadJson: payload,
          windowJson: '{}',
          readiness: kind == 'missing-score' ? null : 72,
        );
        final before = await LocalDb.dayResult(date);
        final app = _App()
          ..user = {'age': 30, 'sex': 'f', 'weight_kg': 70, 'height_cm': 170};
        app.repo = LocalRepositoryImpl(getProfileMap: () => app.user);
        final center = NotificationCenter.instance,
            previous = NotificationCenter.instance.presentSink;
        final events = <NotificationEvent>[];
        var accepted = kind != 'refused';
        center.presentSink =
            (event, {bool allowPermissionPrompt = true}) async {
              events.add(event);
              return accepted;
            };
        await const NotificationPrefs(quietEnabled: false).save();
        Future<void> runQueued() async {
          expect(await LocalDb.lastDecodedRecTs(), isNull);
          await LocalDb.enqueueDeriveJob(
            type: 'derive_heavy',
            reason: 'authored restored job',
          );
          await app.pullRefresh(timeout: const Duration(seconds: 15));
          final deadline = DateTime.now().add(const Duration(seconds: 10));
          while ((app.deriving || app.derivePending) &&
              DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          expect(app.deriving || app.derivePending, false);
          // The existing callback intentionally finishes outside the scheduler job.
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }

        try {
          await runQueued();
          final prefs = await SharedPreferences.getInstance();
          if (kind == 'missing-score') {
            expect(events, isEmpty);
            expect(prefs.getString('last_recovery_notif_day'), isNull);
          } else {
            expect(events, hasLength(1));
            expect(events.single.title, 'Your recovery is ready');
            expect(events.single.date, date);
            expect(
              events.single.body,
              kind == 'invalid-sleep' || kind == 'invalid-accounting'
                  ? 'Recovery 72.'
                  : 'Recovery 72, slept 7h 17m.',
            );
            expect(
              prefs.getString('last_recovery_notif_day'),
              accepted ? date : isNull,
            );
            if (!accepted) {
              accepted = true;
              await runQueued();
              expect(events, hasLength(2));
              expect(prefs.getString('last_recovery_notif_day'), date);
            }
            final count = events.length;
            await runQueued();
            expect(events, hasLength(count));
          }
          expect(await LocalDb.dayResult(date), before);
          final freshness =
              jsonDecode(
                    (await LocalDb.computeFreshness('today'))!['payload_json']
                        as String,
                  )
                  as Map;
          expect(
            freshness['overnight_state'],
            kind == 'invalid-sleep' || kind == 'invalid-accounting'
                ? 'missing'
                : 'ready',
          );
          expect(await LocalDb.lastDecodedRecTs(), isNull);
          expect(
            app.logLines.any(
              (s) => s.contains('[derive-scheduler] running heavy pass'),
            ),
            true,
          );
        } finally {
          app.dispose();
          await app.engine.disconnect();
          center.presentSink = previous;
          await FileLog.write('Authored recovery handoff barrier');
        }
      },
      timeout: const Timeout(Duration(seconds: 45)),
    );
  }
}

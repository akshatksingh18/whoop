import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/activity/catalogue.dart';
import 'package:whoop_companion/ui2/screens/log_workout.dart';

import 'nutrition_root_test.dart' show io;
import '../../support/audit_visual.dart' show loadAuditFonts;
import '../../support/coverage_store.dart';
import '../../support/localized_coverage.dart';

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('scored-manual-workout-handoff', fresh: true);
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final retime in [false, true]) {
    testWidgets(
      'scored workout returns to its caller after commit: retime $retime',
      (tester) async {
        final onset = DateTime(2021, 4, 6, 15);
        final end = onset.add(const Duration(minutes: 4));
        final startSec = onset.millisecondsSinceEpoch ~/ 1000;
        final endSec = end.millisecondsSinceEpoch ~/ 1000;
        const originalId = 'authored-retime-session';
        final db = await LocalDb.instance;
        for (var minute = 0; minute < 4; minute++) {
          final second = startSec + minute * 60 + 5;
          await db.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': second * 1000,
            'rec_ts': second,
            'counter': minute + 1,
            'hr': 120,
            'device_family': 'gen4',
          });
        }
        if (retime) {
          await SessionStore.put({
            'id': originalId,
            'start_ts': startSec + 60,
            'end_ts': endSec,
            'status': 'done',
            'source': 'manual',
            'created_at': 1,
            'type': 'yoga',
            'rpe': 6,
            'private': 1,
          });
        }
        final samples = await db.query('decoded_onehz', orderBy: 'rec_ts');
        var published = 0;
        final app = AppState.forTesting()
          ..repo = LocalRepositoryImpl(
            getProfileMap: () => const {
              'age': 30,
              'sex': 'f',
              'weight_kg': 69,
              'resting_hr': 57,
            },
            onSessionChanged: () => published++,
          );
        final theme = ThemeController.seed(
          AppThemeChoice.light,
          Brightness.light,
        );
        addTearDown(app.dispose);
        addTearDown(theme.dispose);
        bool? returned;
        await localizedPage(
          tester,
          Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  returned = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => LogWorkout(
                        sessionId: retime ? originalId : null,
                        start: onset,
                        end: end,
                        now: end.add(const Duration(hours: 1)),
                        activity: activityByName('Yoga'),
                      ),
                    ),
                  );
                },
                child: const Text('Open workout form'),
              ),
            ),
          ),
          app: app,
          themeController: theme,
        );
        await tester.tap(find.text('Open workout form'));
        await io(tester);
        expect(returned, isNull);
        final save = find.text(retime ? 'Save the new times' : 'Log it');
        await reveal(tester, save);
        await tester.tap(save);
        await io(tester);

        expect(returned, isTrue);
        expect(find.byType(LogWorkout), findsNothing);
        expect(find.text('Open workout form'), findsOneWidget);
        expect(published, 1);
        final row = (await db.query('sessions')).single;
        expect(row['start_ts'], startSec);
        expect(row['end_ts'], endSec);
        expect(row['duration_min'], 4);
        expect(row['avg_hr'], 120);
        expect(row['max_hr'], 120);
        expect(row['type'], 'yoga');
        if (retime) {
          expect(row['id'], originalId);
          expect(row['created_at'], 1);
          expect(row['rpe'], 6);
          expect(row['private'], 1);
        }
        expect(await db.query('decoded_onehz', orderBy: 'rec_ts'), samples);
      },
    );
  }
}

// Authored manifests through the actual picker, confirmation and SQLite import.
// Conflicting weights and unselected photos must stay explicit before any write.
import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'coverage_body_history_actions_test.dart' show flush;
import 'coverage_data_actions_test.dart' show Picker;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late FilePicker previous;
  late Picker picker;
  late Directory root;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-import-preview-handoff', fresh: true);
    root = await Directory(
      'build/coverage-remainder/body-preview-inputs',
    ).create(recursive: true);
    FilePicker.platform = Picker();
  });
  setUp(() async {
    await resetCoverageStore();
    previous = FilePicker.platform;
    picker = Picker();
    FilePicker.platform = picker;
    app = AppState.forTesting()..user = {'weight_kg': 71.0};
    await BodyLogDb.putWeight('2021-04-05', 71, 'kg', historyOnly: true);
  });
  tearDown(() {
    FilePicker.platform = previous;
    app.dispose();
  });
  tearDownAll(LocalDb.close);

  // The page remains busy while the confirmation waits for the user's choice.
  // Advance real file I/O and frames without settling its intentional spinner.
  Future<void> until(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 100; i++) {
      if (ready()) return;
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 50));
    }
    fail('The actual import handoff did not reach its expected state');
  }

  for (final generated in [false, true]) {
    for (final scale in [1.0, 3.1]) {
      for (final accept in [false, true]) {
        testWidgets(
          'Body ${generated ? 'generated' : 'legacy'} preview '
          '${accept ? 'Import' : 'Cancel'} at $scale keeps conflicts and missing photos honest',
          (t) async {
            final text = jsonEncode({
              'version': 1,
              if (generated) 'format': 'whoop-body-history',
              if (generated) 'source': 'authored',
              'weights': [
                for (final day in ['2021-04-05', '2021-04-06'])
                  {
                    'id': 'authored-$day',
                    if (generated) 'date': day else 'day': day,
                    if (generated) 'value': 160 else 'pounds': 160,
                    if (generated) 'unit': 'lb',
                  },
              ],
              'photos': [
                {
                  'id': 'authored-unselected-photo',
                  'day': '2021-04-06',
                  'pose': 'side',
                  'recordedAt': 639489600,
                },
              ],
            });
            picker.file = await t.runAsync(
              () => File('${root.path}/body-history.json').writeAsString(text),
            );
            final db = await LocalDb.instance;
            final original = await db.query('body_weight_reading');
            final originalUser = Map<String, dynamic>.from(app.user!);
            final revision = app.insightsRevision.value;
            await localizedPage(t, const DataScreen(), app: app, scale: scale);
            await flush(t);
            final action = find.text('Import body history');
            await reveal(t, action);
            await t.tap(action);
            await until(
              t,
              () => find
                  .text(
                    'Import from ${generated ? 'authored' : 'AkshatOS Body'}?',
                  )
                  .evaluate()
                  .isNotEmpty,
            );
            await t.pump(const Duration(milliseconds: 300));
            expect(
              find.text(
                'Import from ${generated ? 'authored' : 'AkshatOS Body'}?',
              ),
              findsOneWidget,
            );
            final disclosure = find.textContaining(
              'photos listed but not selected',
            );
            expect(disclosure, findsOneWidget);
            final body = t.widget<Text>(disclosure).data!;
            expect(
              body,
              contains(
                '1 photos listed but not selected: they will be missing.',
              ),
            );
            expect(
              body,
              contains(
                '1 days already hold a different weight; those stay as they are.',
              ),
            );
            expect(
              body,
              contains('1 weights (2021-04-06 to 2021-04-06) as history only.'),
            );
            expect(
              await t.runAsync(() => db.query('body_weight_reading')),
              original,
            );
            expect(await t.runAsync(BodyLogDb.photos), isEmpty);
            final decision = find.text(accept ? 'Import' : 'Cancel').last;
            await t.ensureVisible(decision);
            await t.pump(const Duration(milliseconds: 300));
            await t.tap(decision);
            await until(
              t,
              () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
            );
            await flush(t);
            final weights = (await t.runAsync(
              () => db.query('body_weight_reading'),
            ))!;
            expect(weights, hasLength(accept ? 2 : 1));
            expect(
              weights.singleWhere((r) => r['date'] == '2021-04-05'),
              original.single,
            );
            if (accept) {
              final added = (await t.runAsync(
                BodyLogDb.weights,
              ))!.singleWhere((w) => w.date == '2021-04-06');
              expect(added.historyOnly, isTrue);
              expect(added.source, generated ? 'authored' : 'akshatos');
              expect(added.entered, 160);
              expect(added.unit, 'lb');
              expect(
                find.textContaining('1 records imported.'),
                findsOneWidget,
              );
              expect(
                find.textContaining('1 photos were not in the selection.'),
                findsOneWidget,
              );
              expect(find.text('That did not work'), findsOneWidget);
              expect(app.insightsRevision.value, revision + 1);
              final count = (await t.runAsync(() => planBodyImport(text)))!;
              expect(count.alreadyHere, 1);
              expect(count.sameDayConflicts, hasLength(1));
              expect(count.missingPhotoFiles, hasLength(1));
              expect(count.isEmpty, isTrue);
            } else {
              expect(app.insightsRevision.value, revision);
              expect(find.textContaining('records imported.'), findsNothing);
            }
            expect(await t.runAsync(BodyLogDb.photos), isEmpty);
            expect(await t.runAsync(BodyLogDb.measures), isEmpty);
            expect(app.user, originalUser);
            expect(await t.runAsync(() => picker.file!.readAsString()), text);
          },
        );
      }
    }
  }
}

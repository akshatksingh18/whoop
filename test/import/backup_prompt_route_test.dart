// Settings chooses the encrypted-file prompt from content and handles cancel.
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/backup_crypto.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart' show ImportReport;
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;

import '../ui2/onboarding/boundaries_test.dart' show Picker;
import '../ui2/screens/session_destination_boundaries_test.dart' show io;
import '../support/audit_visual.dart' show loadAuditFonts;
import '../support/coverage_store.dart';
import '../support/localized_coverage.dart';

void main() {
  late FilePicker previous;
  late File renamed;
  late AppState app;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('backup-prompt-route', fresh: true);
    final root = File(LocalDb.dbName).parent;
    renamed = await File(
      '${root.path}/authored-renamed.csv',
    ).writeAsBytes(kBackupMagic);
    FilePicker.platform = Picker();
  });
  setUp(() async {
    await resetCoverageStore();
    previous = FilePicker.platform;
    FilePicker.platform = Picker()
      ..mode = 'ready'
      ..file = renamed;
    app = AppState.forTesting();
    await JournalStore.put(
      '2021-04-06',
      '["travel"]',
      'Retained authored note',
    );
  });
  tearDown(() {
    FilePicker.platform = previous;
    app.dispose();
  });
  tearDownAll(LocalDb.close);

  for (final cancel in [true, false]) {
    testWidgets(
      'renamed encrypted backup cancel $cancel leaves SQLite intact',
      (t) async {
        final before = await JournalStore.entries();
        await localizedPage(t, const DataScreen(), app: app);
        final row = find.widgetWithText(SetRow, 'Import a file');
        await reveal(t, row);
        await t.tap(row);
        final dialog = find.byType(AlertDialog);
        for (var frame = 0; frame < 45 && dialog.evaluate().isEmpty; frame++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await t.pump(const Duration(milliseconds: 25));
        }
        await t.pump(const Duration(milliseconds: 400));
        expect(dialog, findsOneWidget);
        final input = find.descendant(
          of: dialog,
          matching: find.byType(TextField),
        );
        expect(input, findsOneWidget);
        expect(t.widget<TextField>(input).obscureText, isTrue);
        expect(
          find.text('The one you chose when this backup was written.'),
          findsOneWidget,
        );
        if (cancel) {
          await t.tap(find.text('Cancel'));
        } else {
          await t.enterText(input, 'authored cancelled backup');
          await t.testTextInput.receiveAction(TextInputAction.done);
        }

        for (var frame = 0; frame < 80; frame++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 15)),
          );
          await t.pump(const Duration(milliseconds: 25));
          if (dialog.evaluate().isEmpty &&
              find.byType(CircularProgressIndicator).evaluate().isEmpty) {
            break;
          }
        }
        await io(t);
        expect(dialog, findsNothing);
        expect(t.widget<SetRow>(row).onTap, isNotNull);
        expect(find.text('That did not work'), findsNothing);
        expect(
          find.byType(ImportReport),
          cancel ? findsNothing : findsOneWidget,
        );
        if (!cancel) {
          expect(
            t.widget<ImportReport>(find.byType(ImportReport)).o.readError,
            contains('backup'),
          );
        }
        expect(await t.runAsync(JournalStore.entries), before);
        expect(await t.runAsync(renamed.readAsBytes), kBackupMagic);
        final staging = await t.runAsync(
          () => renamed.parent
              .list()
              .where((f) => f.uri.pathSegments.last.startsWith('restore-'))
              .toList(),
        );
        expect(staging, isEmpty);
      },
    );
  }
}

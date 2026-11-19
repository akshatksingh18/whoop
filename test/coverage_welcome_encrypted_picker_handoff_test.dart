// The real Welcome host opens its own passphrase modal and runs the real import.
// Only the OS file picker is substituted. Authored files fail before derivation.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/backup_crypto.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'coverage_onboarding_boundaries_test.dart' show Picker;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

Future<String> _hash(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

void main() {
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('welcome-encrypted-picker-handoff', fresh: true);
    FilePicker.platform = Picker();
  });
  setUp(() async {
    await resetCoverageStore();
    await BodyLogDb.putWeight('2021-04-06', 70, 'kg');
  });
  tearDownAll(LocalDb.close);
  for (final scale in [1.0, 3.1]) {
    for (final mode in [
      'cancel',
      'wrong key',
      'tampered',
      'invalid database',
    ]) {
      testWidgets(
        'Welcome encrypted picker $mode preserves failed/cancelled onboarding $scale',
        (t) async {
          const pass = 'authored modal fixture';
          final fixture = (await t.runAsync(() async {
            final temp = await getTemporaryDirectory();
            final dir = await temp.createTemp('authored-picker-');
            final input = await File(
              '${dir.path}/source.bin',
            ).writeAsString('Authored non-SQLite input;no real backup data.');
            final sealed = File('${dir.path}/renamed.attachment');
            await encryptBackupFile(input, sealed, pass, iterations: 1000);
            if (mode == 'tampered') {
              final bytes = await sealed.readAsBytes();
              bytes[BackupHeader.byteLength + 1] ^= 1;
              await sealed.writeAsBytes(bytes);
            }
            final sealedHash = await _hash(sealed),
                inputHash = await _hash(input);
            return (
              temp: temp,
              input: input,
              sealed: sealed,
              sealedHash: sealedHash,
              inputHash: inputHash,
            );
          }))!;
          final temp = fixture.temp,
              input = fixture.input,
              sealed = fixture.sealed;
          final sealedHash = fixture.sealedHash, inputHash = fixture.inputHash;
          final originalPicker = FilePicker.platform;
          FilePicker.platform = Picker()
            ..mode = 'ready'
            ..file = sealed;
          addTearDown(() => FilePicker.platform = originalPicker);
          // Welcome is hosted only after startup has finished.
          final app = AppState.forTesting()..initialized = true;
          addTearDown(app.dispose);
          expect(app.route, AppRoute.welcome);
          final db = await LocalDb.instance;
          final before = await db.query('body_weight_reading', orderBy: 'id');
          final prefs = await SharedPreferences.getInstance();
          await localizedPage(t, const WelcomeScreen(), app: app, scale: scale);
          for (var attempt = 0; attempt < 2; attempt++) {
            final view = t.widget<WelcomeView>(find.byType(WelcomeView));
            Future<void>? pending;
            await t.runAsync(() async {
              final dynamic action = view.onImport;
              pending = Future<void>.sync(() => action());
              await Future<void>.delayed(const Duration(milliseconds: 40));
            });
            // The busy Welcome host keeps a spinner running behind this
            // modal. Pump its route animation without waiting for that busy
            // indicator to settle before the user has answered.
            await t.pump(const Duration(milliseconds: 350));
            expect(find.byType(AlertDialog), findsOneWidget);
            expect(t.widget<WelcomeView>(find.byType(WelcomeView)).busy, true);
            expect(find.byType(TextField), findsOneWidget);
            expect(
              t.widget<TextField>(find.byType(TextField)).obscureText,
              true,
            );
            if (mode == 'cancel') {
              await t.tap(find.text('Cancel'));
            } else {
              await t.enterText(
                find.byType(TextField),
                mode == 'wrong key' ? 'authored wrong key' : pass,
              );
              await t.testTextInput.receiveAction(TextInputAction.done);
            }
            await t.runAsync(() => pending!);
            await t.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
            final current = t.widget<WelcomeView>(find.byType(WelcomeView));
            expect(current.busy, false);
            if (mode == 'cancel') {
              expect(current.outcome, isNull);
            } else if (mode == 'invalid database') {
              expect(current.outcome!.error, isNotEmpty);
            } else {
              expect(current.outcome!.nothingLanded, true);
              expect(
                current.outcome!.readError,
                'wrong passphrase, or this backup has been modified',
              );
              expect(current.outcome!.records, 0);
              expect(current.outcome!.days, 0);
            }
            expect(app.route, AppRoute.welcome);
            expect(prefs.getString('onboarding_choice'), isNull);
            expect(
              await t.runAsync(
                () => db.query('body_weight_reading', orderBy: 'id'),
              ),
              before,
            );
            expect(await t.runAsync(() => _hash(sealed)), sealedHash);
            expect(await t.runAsync(() => _hash(input)), inputHash);
            expect(
              await t.runAsync(
                () => temp
                    .list()
                    .where(
                      (f) => f.path
                          .split(Platform.pathSeparator)
                          .last
                          .startsWith('restore-'),
                    )
                    .toList(),
              ),
              isEmpty,
            );
            expect(t.takeException(), isNull);
          }
        },
        timeout: const Timeout(Duration(seconds: 45)),
      );
    }
  }
}

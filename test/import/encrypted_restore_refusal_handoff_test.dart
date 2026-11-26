// Authored ciphertext through the real import handoff. No real backup or import
// worker is used; refused inputs must never change the already-stored record.
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/backup_crypto.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import '../support/coverage_store.dart';

const _pass = 'authored restore fixture only';

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('encrypted-refusal-handoff', fresh: true));
  setUp(() async {
    await resetCoverageStore();
    await BodyLogDb.putWeight('2021-04-06', 70, 'kg');
  });
  tearDownAll(LocalDb.close);

  for (final mode in [
    'wrong passphrase',
    'tampered ciphertext',
    'no prompt',
    'cancel',
  ]) {
    test(
      'encrypted restore $mode preserves source and stored history',
      () async {
        final dir = await (await getTemporaryDirectory()).createTemp(
          'authored-',
        );
        final input = await File('${dir.path}/source.bin').writeAsString(
          'Entirely authored bytes; not a real database or health capture.',
        );
        // An unrelated extension establishes magic-based admission, not filename
        // routing. The existing test-only KDF floor keeps this probe bounded.
        final sealed = File('${dir.path}/attachment.renamed');
        await encryptBackupFile(input, sealed, _pass, iterations: 1000);
        if (mode == 'tampered ciphertext') {
          final bytes = await sealed.readAsBytes();
          bytes[BackupHeader.byteLength + 2] ^= 1;
          await sealed.writeAsBytes(bytes);
        }
        final original = await _hash(sealed);
        final sourceHash = await _hash(input);
        final db = await LocalDb.instance;
        final before = await db.query('body_weight_reading', orderBy: 'id');
        final daily = await db.query('body_weight', orderBy: 'date');
        final app = AppState.forTesting();
        addTearDown(app.dispose);
        var prompts = 0;
        Future<String?> prompt() async {
          prompts++;
          if (mode == 'cancel') return null;
          return mode == 'wrong passphrase' ? 'authored wrong key' : _pass;
        }

        if (mode == 'cancel') {
          await expectLater(
            runImport(app, [sealed.path], askPassphrase: prompt),
            throwsA(isA<PassphraseCancelled>()),
          );
        } else {
          final result = await runImport(app, [
            sealed.path,
          ], askPassphrase: mode == 'no prompt' ? null : prompt);
          expect(result.nothingLanded, true);
          expect(result.source, 'Nothing selected');
          expect(result.readError, isNotEmpty);
          expect(result.error, isNull);
          expect(result.rollupError, isNull);
          expect(result.days, 0);
          expect(result.records, 0);
          expect(result.workouts, 0);
          expect(result.journalRows, 0);
          expect(result.rejectedRows, isEmpty);
          if (mode == 'no prompt') {
            expect(result.readError, contains('encrypted backup'));
            expect(result.readError, contains('passphrase'));
          }
        }
        expect(prompts, mode == 'no prompt' ? 0 : 1);
        expect(await db.query('body_weight_reading', orderBy: 'id'), before);
        expect(await db.query('body_weight', orderBy: 'date'), daily);
        expect(await _hash(sealed), original);
        expect(await _hash(input), sourceHash);
        final temp = await getTemporaryDirectory();
        expect(
          await temp
              .list()
              .where((f) => f.uri.pathSegments.last.startsWith('restore-'))
              .toList(),
          isEmpty,
        );
        // A move verifies the original source handle was released. Retain the
        // authored fixture as evidence rather than removing its directory.
        expect(
          await _hash(await sealed.rename('${sealed.path}.retained')),
          original,
        );
      },
    );
  }
}

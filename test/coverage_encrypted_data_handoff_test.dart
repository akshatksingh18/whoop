// Real encrypted export workers run in Linux CI. The share boundary only reads
// authored local bytes and never opens a system share sheet or sends a file.
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/backup_crypto.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'coverage_data_export_handoff_test.dart' show LocalShare;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late AppState app;
  late SharePlatform previous;
  late LocalShare share;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('encrypted-data-handoff', fresh: true);
  });
  setUp(() async {
    await resetCoverageStore();
    app = AppState.forTesting();
    previous = SharePlatform.instance;
    share = LocalShare();
    SharePlatform.instance = share;
    await BodyLogDb.putWeight('2021-04-06', 70, 'kg', historyOnly: true);
  });
  tearDown(() {
    app.dispose();
    SharePlatform.instance = previous;
  });
  tearDownAll(LocalDb.close);
  Future<void> prompt(WidgetTester t) async {
    await localizedPage(t, const DataScreen(), app: app);
    final row = find.ancestor(
      of: find.text('Export an encrypted backup'),
      matching: find.byType(SetRow),
    );
    await reveal(t, row);
    t.widget<SetRow>(row).onTap!();
    // The export remains busy under the modal until the passphrase is chosen.
    // Its progress indicator intentionally keeps scheduling frames.
    await t.pump(const Duration(milliseconds: 400));
    expect(find.text('Encrypt'), findsOneWidget);
  }

  Future<void> encrypt(WidgetTester t) async {
    for (var i = 0; i < 2; i++) {
      await t.enterText(
        find.byType(TextField).at(i),
        'authored backup fixture',
      );
    }
    await t.tap(find.text('Encrypt'));
    await t.pump(const Duration(milliseconds: 400));
  }

  for (final media in [false, true]) {
    testWidgets(
      'encrypted ${media ? 'media' : 'database'} export seals authored records and removes temporary plaintext',
      (t) async {
        if (media) {
          await t.runAsync(
            () => BodyLogDb.addPhoto(
              img.encodeJpg(img.Image(width: 8, height: 12)),
              date: '2021-04-06',
              pose: 'front',
            ),
          );
        }
        await prompt(t);
        await encrypt(t);
        // PBKDF2 and streaming encryption are real worker work: this test is CI-only.
        for (var i = 0; i < 180; i++) {
          // The passphrase route's exit still needs frames. A single runAsync
          // wait leaves that route future parked before the worker can start.
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 200)),
          );
          await t.pump(const Duration(milliseconds: 30));
          if (share.paths.isNotEmpty &&
              share.bytes.length == share.paths.length &&
              share.paths.every((p) => !File(p).existsSync())) {
            break;
          }
        }
        expect(
          share.paths,
          hasLength(1),
          reason: t
              .widgetList<Text>(find.byType(Text))
              .map((w) => w.data ?? '')
              .join(' '),
        );
        await flush(t);
        final header = BackupHeader.parse(
          Uint8List.fromList(share.bytes.single),
        );
        expect(
          header.version,
          media ? kBackupFormatVersionMedia : kBackupFormatVersion,
        );
        expect(header.iterations, kDefaultIterations);
        expect(share.bytes.single.length, greaterThan(BackupHeader.byteLength));
        for (final path in share.paths) {
          expect(File(path).existsSync(), false);
          expect(
            File(path.substring(0, path.length - '.osbk'.length)).existsSync(),
            false,
          );
        }
        expect(
          (await readPage(t)).join(' '),
          contains('Encrypted database + ${media ? 1 : 0} photo files'),
        );
        expect((await t.runAsync(BodyLogDb.weights))!.single.kg, 70);
        expect((await t.runAsync(BodyLogDb.photos))!, hasLength(media ? 1 : 0));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );
  }
  testWidgets('cancelling encrypted export does not write or share a backup', (
    t,
  ) async {
    await prompt(t);
    await t.tap(find.text('Cancel'));
    await flush(t);
    expect(share.paths, isEmpty);
    expect((await t.runAsync(BodyLogDb.weights))!.single.kg, 70);
  });
  testWidgets(
    'a referenced missing photo refuses export before encryption and preserves its record',
    (t) async {
      final ph = (await t.runAsync(
        () => BodyLogDb.addPhoto(
          img.encodeJpg(img.Image(width: 8, height: 12)),
          date: '2021-04-06',
          pose: 'front',
        ),
      ))!;
      await t.runAsync(() async => (await BodyLogDb.photoFile(ph)).delete());
      await prompt(t);
      await encrypt(t);
      await flush(t);
      expect(share.paths, isEmpty);
      expect(find.text('That did not work'), findsOneWidget);
      expect((await t.runAsync(BodyLogDb.photos))!.single.id, ph.id);
      expect((await t.runAsync(BodyLogDb.weights))!.single.kg, 70);
    },
  );
}

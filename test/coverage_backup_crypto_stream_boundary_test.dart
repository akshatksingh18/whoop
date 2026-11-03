// Actual authored files around the encrypted backup pump's 1 MiB boundary.
// The established test-only KDF floor keeps these small probes quick; production
// randomness, iteration default, format and cipher code remain unchanged.
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/import/backup_crypto.dart';

const boundary = 1 << 20;
const fixturePassphrase = 'authored-stream-boundary-only';

Future<String> fingerprint(File f) async =>
    (await sha256.bind(f.openRead()).first).toString();

void main() {
  late Directory root;
  setUp(() async {
    root = await (await Directory(
      'build/coverage-remainder/crypto-stream-boundary',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });

  File at(String name) => File('${root.path}/$name');

  Future<File> authored(int bytes) async {
    final file = at('authored.bin');
    final out = file.openWrite();
    final block = Uint8List.fromList(
      List.generate(4096, (i) => (i * 31 + 7) & 0xff),
    );
    for (var left = bytes; left > 0;) {
      final count = left < block.length ? left : block.length;
      out.add(Uint8List.sublistView(block, 0, count));
      left -= count;
    }
    await out.close();
    return file;
  }

  for (final (size, version) in [
    (boundary - 1, kBackupFormatVersion),
    (boundary, kBackupFormatVersionMedia),
    (boundary + 1, kBackupFormatVersion),
    (boundary + 17, kBackupFormatVersionMedia),
  ]) {
    test(
      'format $version round-trips $size bytes without block or stream loss',
      () async {
        final input = await authored(size);
        final original = await fingerprint(input);
        final encrypted = at('authored.encrypted');
        await encryptBackupFile(
          input,
          encrypted,
          fixturePassphrase,
          iterations: 1000,
          version: version,
        );
        final sealed = await fingerprint(encrypted);
        final output = at('restored.bin');
        expect(
          await decryptBackupFile(encrypted, output, fixturePassphrase),
          version,
        );
        expect(await output.length(), size);
        expect(await fingerprint(output), original);
        expect(await fingerprint(input), original);
        expect(await fingerprint(encrypted), sealed);
        expect(
          await encrypted.length(),
          size + BackupHeader.byteLength + kTagBytes,
        );
        final retained = await encrypted.rename('${encrypted.path}.retained');
        expect(await fingerprint(retained), sealed);
      },
    );
  }

  test(
    'late ciphertext tampering removes every partially restored byte and preserves input',
    () async {
      final input = await authored(boundary + 17);
      final original = await fingerprint(input);
      final encrypted = at('authored.encrypted');
      await encryptBackupFile(
        input,
        encrypted,
        fixturePassphrase,
        iterations: 1000,
      );
      final sealedBytes = await encrypted.readAsBytes();
      final offset = BackupHeader.byteLength + boundary + 3;
      // A deterministic bit flip inside ciphertext: writing a fixed byte could
      // accidentally leave the random ciphertext unchanged. This fixture is
      // bounded to about1MiB; production encryption/decryption remain streamed.
      sealedBytes[offset] ^= 1;
      await encrypted.writeAsBytes(sealedBytes);
      expect(
        await encrypted.length(),
        boundary + 17 + BackupHeader.byteLength + kTagBytes,
      );
      final tampered = await fingerprint(encrypted);
      final output = at('refused.bin');
      await expectLater(
        decryptBackupFile(encrypted, output, fixturePassphrase),
        throwsA(isA<BackupFormatException>()),
      );
      expect(await output.exists(), false);
      expect(await fingerprint(input), original);
      expect(await fingerprint(encrypted), tampered);
      final retained = await encrypted.rename('${encrypted.path}.retained');
      expect(await fingerprint(retained), tampered);
    },
  );

  test(
    'a complete header without ciphertext or tag is refused and releases its source',
    () async {
      final header = BackupHeader(
        version: kBackupFormatVersion,
        kdf: kKdfPbkdf2HmacSha256,
        iterations: 1000,
        salt: Uint8List(kSaltBytes),
        nonce: Uint8List(kNonceBytes),
      );
      final input = await at(
        'authored-header-only',
      ).writeAsBytes(header.toBytes());
      final original = await fingerprint(input);
      final output = at('refused.bin');
      await expectLater(
        decryptBackupFile(input, output, fixturePassphrase),
        throwsA(
          isA<BackupFormatException>().having(
            (e) => e.toString(),
            'readable refusal',
            startsWith('BackupFormatException: '),
          ),
        ),
      );
      expect(await output.exists(), false);
      expect(await fingerprint(input), original);
      final retained = await input.rename('${input.path}.retained');
      expect(await fingerprint(retained), original);
    },
  );
}

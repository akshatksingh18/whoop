// Host checks of the Dart file reader, not a signature, entitlement, installed
// build or phone-acceptance claim. All bundle bytes and dates are authored.
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/platform/signing_profile.dart';

void main() {
  late Directory root;
  setUp(() async {
    root = await (await Directory(
      'build/coverage-remainder/signing-bundle-reader',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });

  String getExecutable() => '${root.path}/AuthoredRunner';
  File profile() => File('${root.path}/embedded.mobileprovision');

  for (final (description, bytes, expected) in <(String, List<int>, DateTime?)>[
    (
      'binary wrapper with an explicit UTC expiry',
      [
        0xff,
        0,
        0x80,
        ...ascii.encode(
          '<key>ExpirationDate</key>\n<date>2021-04-07T12:00:00Z</date>',
        ),
        0xfe,
      ],
      DateTime.utc(2021, 4, 7, 12),
    ),
    (
      'whitespace and explicit offset',
      ascii.encode(
        '<key>ExpirationDate</key> <date> 2021-04-07T14:00:00+02:00 </date>',
      ),
      DateTime.utc(2021, 4, 7, 12),
    ),
    (
      'no expiry key',
      ascii.encode('<key>AuthoredOther</key><date>2021-04-07</date>'),
      null,
    ),
    (
      'truncated date',
      ascii.encode('<key>ExpirationDate</key><date>2021-04'),
      null,
    ),
    (
      'unreadable date',
      ascii.encode('<key>ExpirationDate</key><date>authored-invalid</date>'),
      null,
    ),
    ('empty bundle profile', const [], null),
  ]) {
    test(
      '$description reads honestly without changing the bundle file',
      () async {
        final f = await profile().writeAsBytes(bytes);
        final value = await readSigningExpiry(
          isIOS: true,
          executablePath: getExecutable(),
        );
        expect(value?.toUtc(), expected);
        expect(await f.readAsBytes(), bytes);
        final retained = await f.rename('${f.path}.retained');
        expect(await retained.readAsBytes(), bytes);
      },
    );
  }

  test('a missing profile remains unknown and does not create one', () async {
    expect(
      await readSigningExpiry(isIOS: true, executablePath: getExecutable()),
      isNull,
    );
    expect(await root.list().toList(), isEmpty);
  });

  test(
    'an explicit non-iOS host never uses an adjacent authored profile',
    () async {
      final bytes = ascii.encode(
        '<key>ExpirationDate</key><date>2021-04-07T12:00:00Z</date>',
      );
      final f = await profile().writeAsBytes(bytes);
      expect(
        await readSigningExpiry(isIOS: false, executablePath: getExecutable()),
        isNull,
      );
      expect(await f.readAsBytes(), bytes);
      expect(await readSigningExpiry(), isNull);
    },
  );
}

// Issues #199 / #160: every import failed with `FormatException: Unexpected
// extension byte (at offset 10)` / `Invalid UTF-8 byte (at offset 10)`.
//
// The decisive detail is that offset. A ZIP's first ten bytes (PK\x03\x04,
// version, flags, method) are all < 0x80, so a UTF-8 decoder always survives
// exactly that far before hitting byte 10 — the low byte of the DOS mod time.
// These tests build a REAL ZIP and assert both halves: that the old code path
// fails precisely where the users said it did (so the diagnosis is pinned, not
// assumed), and that the new sniff classifies and unwraps it instead.

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/import/import_container.dart';

List<int> _zipOf(Map<String, String> members) {
  final a = Archive();
  members.forEach((name, body) {
    final bytes = utf8.encode(body);
    a.addFile(ArchiveFile(name, bytes.length, bytes));
  });
  return ZipEncoder().encode(a);
}

int _findSig(Uint8List b, List<int> sig, [int from = 0]) {
  outer:
  for (var i = from; i <= b.length - sig.length; i++) {
    for (var j = 0; j < sig.length; j++) {
      if (b[i + j] != sig[j]) continue outer;
    }
    return i;
  }
  throw StateError('signature not found');
}

void _writeU32LE(Uint8List b, int offset, int value) {
  b[offset] = value & 0xff;
  b[offset + 1] = (value >> 8) & 0xff;
  b[offset + 2] = (value >> 16) & 0xff;
  b[offset + 3] = (value >> 24) & 0xff;
}

int _readU32LE(Uint8List b, int offset) =>
    b[offset] | (b[offset + 1] << 8) | (b[offset + 2] << 16) | (b[offset + 3] << 24);

/// Patch the ONE central-directory entry's declared uncompressed-size field
/// (offset +24 from its `PK\x01\x02` signature) down by [by] bytes, leaving
/// the compressed data and its CRC-32 untouched — the exact shape of the real
/// bug this guards: the size field went stale, the content did not.
Uint8List _understateCentralDirectorySize(List<int> zipBytes, {required int by}) {
  final b = Uint8List.fromList(zipBytes);
  final cdr = _findSig(b, const [0x50, 0x4B, 0x01, 0x02]);
  _writeU32LE(b, cdr + 24, _readU32LE(b, cdr + 24) - by);
  return b;
}

/// Corrupt the declared CRC-32 in BOTH the local file header (offset +14) and
/// the central-directory entry (offset +16), independent of which one the
/// decoder trusts — genuine damage, not merely a stale size field.
Uint8List _corruptDeclaredCrc32(List<int> zipBytes) {
  final b = Uint8List.fromList(zipBytes);
  final lfh = _findSig(b, const [0x50, 0x4B, 0x03, 0x04]);
  _writeU32LE(b, lfh + 14, _readU32LE(b, lfh + 14) ^ 0xFFFFFFFF);
  final cdr = _findSig(b, const [0x50, 0x4B, 0x01, 0x02]);
  _writeU32LE(b, cdr + 16, _readU32LE(b, cdr + 16) ^ 0xFFFFFFFF);
  return b;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('import_container_test_');
  });
  tearDown(() async {
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  Future<String> write(String name, List<int> bytes) async {
    final f = File('${tmp.path}/$name');
    await f.writeAsBytes(bytes);
    return f.path;
  }

  group('the reported failure is a container, not an encoding', () {
    test('a ZIP with a real DOS mod-time fails at exactly offset 10', () {
      // A local file header as a real zip tool writes it: PK\x03\x04, version
      // 20, flags, method 8, then the DOS mod time. Every byte before offset 10
      // is < 0x80, so the decoder always reaches the mod time and dies there —
      // which is the offset BOTH issue reports quote.
      final header = <int>[
        0x50, 0x4B, 0x03, 0x04, // PK\x03\x04
        0x14, 0x00, // version needed
        0x08, 0x00, // flags
        0x08, 0x00, // method: deflate
        0x9A, 0x7C, // DOS mod time  <- offset 10, high bit set
        0x51, 0x59, // DOS mod date
        ...utf8.encode('rest'),
      ];
      expect(
        () => utf8.decode(header),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('at offset 10'), contains('extension byte')),
          ),
        ),
        reason:
            'this is what users saw — it pins the diagnosis to the container, '
            'not to a localized or mis-encoded CSV',
      );
    });

    test('any ZIP is undecodable, whatever its mod-time bytes', () {
      // `archive`'s encoder writes a ZERO mod time for reproducible output, so
      // its first high-bit byte is the CRC at offset 14-17 instead. The precise
      // offset therefore depends on the writing tool — which is exactly why the
      // two issue reports quote different offsets (10 and 18). The invariant we
      // rely on is only that a ZIP is never valid UTF-8.
      expect(
        () => utf8.decode(_zipOf({'physiological_cycles.csv': 'a,b\n1,2\n'})),
        throwsA(isA<FormatException>()),
      );
    });

    test('a latin1 CSV fails DIFFERENTLY, so it is not this bug', () {
      // "frecuencía" in latin1 — the "it's a Spanish export" theory.
      final latin1Csv = latin1.encode('unix_s,frecuencía\n1,2\n');
      expect(
        () => utf8.decode(latin1Csv),
        throwsA(
          isA<FormatException>().having(
            (e) => e.toString(),
            'message',
            contains('Missing extension byte'),
          ),
        ),
      );
    });
  });

  group('sniffImportContainer', () {
    test('classifies the containers users actually pick', () {
      expect(
        sniffImportContainer(_zipOf({'a.csv': 'x'})),
        ImportContainer.zip,
      );
      expect(
        sniffImportContainer(utf8.encode('SQLite format 3\x00rest')),
        ImportContainer.sqlite,
      );
      expect(sniffImportContainer([0x1F, 0x8B, 0x08, 0x00]),
          ImportContainer.gzip);
      expect(
        sniffImportContainer(utf8.encode('unix_s,iso_utc,stream\n')),
        ImportContainer.text,
      );
    });

    test('a BOM and non-ASCII text still count as text', () {
      // Dart's Utf8Decoder strips a leading BOM, so a BOM'd CSV is importable
      // and must not be rejected as binary.
      expect(
        sniffImportContainer([0xEF, 0xBB, 0xBF, ...utf8.encode('unix_s,a\n')]),
        ImportContainer.text,
      );
      expect(
        sniffImportContainer(latin1.encode('fecha,frecuencía\n')),
        ImportContainer.text,
      );
    });

    test('an empty head is text, not a crash', () {
      expect(sniffImportContainer(const []), ImportContainer.text);
    });
  });

  group('resolveImportCsvPaths', () {
    test('unwraps a WHOOP-style ZIP of CSVs', () async {
      final path = await write(
        'my_whoop_data.zip',
        _zipOf({
          'physiological_cycles.csv': 'Cycle start time\n2026-01-01\n',
          'sleeps.csv': 'Sleep onset\n2026-01-01\n',
          'readme.txt': 'not a csv',
        }),
      );
      final out = await resolveImportCsvPaths([path], flavor: 'WHOOP');
      expect(out.paths, hasLength(2));
      expect(
        out.paths.map((p) => p.split('/').last).toSet(),
        {'physiological_cycles.csv', 'sleeps.csv'},
      );
      expect(
        await File(out.paths.first).readAsString(),
        contains('Cycle start time'),
      );
      // Extraction is temp-only, and disposing removes every trace of it.
      await out.dispose();
      for (final f in out.paths) {
        expect(File(f).existsSync(), isFalse);
      }
    });

    test('a .noopbak yields its database, unpacked', () async {
      final path = await write(
        'backup.noopbak',
        _zipOf({
          'settings.json': '{"age":30}',
          'noop-backup.sqlite': 'SQLite format 3 ...',
        }),
      );
      final db = await resolveNoopDatabase(path);
      expect(db, isNotNull);
      expect(db!.path.endsWith('noop-backup.sqlite'), isTrue);
      expect(await File(db.path).readAsString(), startsWith('SQLite format 3'));
      // Nothing is left behind once the importer has read it.
      await db.dispose();
      expect(File(db.path).existsSync(), isFalse);
    });

    test('the largest database member wins over a sidecar', () async {
      final path = await write(
        'big.noopbak',
        _zipOf({
          'noop-backup.sqlite-wal': 'x',
          'noop-backup.sqlite': 'SQLite format 3 ${'y' * 500}',
        }),
      );
      final db = await resolveNoopDatabase(path);
      expect(db!.path.endsWith('noop-backup.sqlite'), isTrue);
      await db.dispose();
    });

    // A real NOOP backup (10.5.0, measured 2026-08) unpacked to more bytes
    // than its own zip declared: the central directory's uncompressed-size
    // field for `noop-backup.sqlite` undercounted the true content by a few
    // thousand pages, while the CRC-32 — computed over the FULL decompressed
    // stream regardless of that field — still matched. `unzip -t` calls that
    // file OK for the same reason. Reproduced here by encoding a normal zip
    // and then patching just the declared size downward, the same shape the
    // real writer's bug leaves: content and CRC untouched, only the size lie.
    test('an uncompressed-size field that undercounts the real content is '
        'not treated as damage when the CRC still matches', () async {
      final content = utf8.encode('SQLite format 3 ${'z' * 5000}');
      final zipBytes = _zipOf({'noop-backup.sqlite': String.fromCharCodes(content)});
      final patched = _understateCentralDirectorySize(zipBytes, by: 37);
      final path = await write('undercounted.noopbak', patched);

      final db = await resolveNoopDatabase(path);
      expect(db, isNotNull);
      expect(await File(db!.path).readAsBytes(), content);
      await db.dispose();
    });

    test('an uncompressed-size mismatch with a WRONG crc is still refused',
        () async {
      final content = utf8.encode('SQLite format 3 ${'z' * 5000}');
      final zipBytes = _zipOf({'noop-backup.sqlite': String.fromCharCodes(content)});
      // Undercount the size (as above) AND corrupt the declared CRC-32 fields
      // themselves, leaving the compressed data untouched. The archive still
      // decodes; what it actually produces no longer matches what it CLAIMS
      // to have produced, which is real damage rather than a stale size field
      // and must still be refused.
      final tampered =
          _corruptDeclaredCrc32(_understateCentralDirectorySize(zipBytes, by: 37));
      final path = await write('tampered.noopbak', tampered);

      await expectLater(
        resolveNoopDatabase(path),
        throwsA(isA<ImportFormatException>().having(
          (e) => e.message,
          'message',
          contains('does not hold what it says'),
        )),
      );
    });

    test('a loose database is taken as-is and never deleted', () async {
      final path = await write('loose-noop.sqlite', utf8.encode('SQLite format 3  '));
      final db = await resolveNoopDatabase(path);
      expect(db!.path, path);
      // Disposing must NOT delete a file we did not unpack — it is the user's
      // only copy of their history.
      await db.dispose();
      expect(File(path).existsSync(), isTrue);
    });

    test('a zip of CSVs is not mistaken for a backup', () async {
      final path = await write(
        'whoop.zip',
        _zipOf({'sleeps.csv': 'Cycle start time\n1\n'}),
      );
      expect(await resolveNoopDatabase(path), isNull);
    });

    test('a bare SQLite file is explained, not decoded', () async {
      final path = await write(
        'noop-backup.sqlite',
        utf8.encode('SQLite format 3\x00whatever'),
      );
      await expectLater(
        resolveImportCsvPaths([path], flavor: 'NOOP'),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'message',
            contains('database file'),
          ),
        ),
      );
    });

    test('a plain CSV passes through untouched', () async {
      final path = await write(
        'noop-raw-sensors-1785567300.csv',
        utf8.encode('unix_s,iso_utc,stream\n1,2,hr\n'),
      );
      final out = await resolveImportCsvPaths([path], flavor: 'NOOP');
      expect(out.paths, [path]);
      // Nothing was extracted, so disposing must not delete the user's file.
      await out.dispose();
      expect(File(path).existsSync(), isTrue);
    });

    test('members sharing a basename both survive', () async {
      // Flattening onto one destination dropped a file and parsed the
      // survivor twice.
      final path = await write(
        'export.zip',
        _zipOf({
          'daily/data.csv': 'a\n1\n',
          'workouts/data.csv': 'b\n2\n',
        }),
      );
      final out = await resolveImportCsvPaths([path], flavor: 'WHOOP');
      expect(out.paths, hasLength(2));
      expect(out.paths.toSet(), hasLength(2), reason: 'no shared destination');
      final bodies = [
        for (final f in out.paths) await File(f).readAsString(),
      ];
      expect(bodies, containsAll(<String>['a\n1\n', 'b\n2\n']));
      await out.dispose();
    });

    test('two archives with the same member name both survive', () async {
      final a = await write('one.zip', _zipOf({'data.csv': 'a\n1\n'}));
      final b = await write('two.zip', _zipOf({'data.csv': 'b\n2\n'}));
      final out = await resolveImportCsvPaths([a, b], flavor: 'WHOOP');
      expect(out.paths, hasLength(2));
      expect(out.paths.toSet(), hasLength(2));
      final bodies = [
        for (final f in out.paths) await File(f).readAsString(),
      ];
      expect(bodies, containsAll(<String>['a\n1\n', 'b\n2\n']));
      await out.dispose();
    });

    test('a malformed archive fails with a message, not a decoder crash',
        () async {
      // A ZIP magic number on bytes that are not a ZIP.
      final path = await write(
        'broken.zip',
        [0x50, 0x4B, 0x03, 0x04, ...List<int>.filled(64, 0x41)],
      );
      await expectLater(
        resolveImportCsvPaths([path], flavor: 'WHOOP'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('an archive with no CSVs at all says so', () async {
      final path = await write(
        'empty.zip',
        _zipOf({'readme.txt': 'nothing here'}),
      );
      await expectLater(
        resolveImportCsvPaths([path], flavor: 'WHOOP'),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'message',
            contains('no CSV files'),
          ),
        ),
      );
    });

    test('a later bad file does not strand an earlier extraction', () async {
      final zip = await write(
        'export.zip',
        _zipOf({'sleeps.csv': 'Sleep onset\n2026-01-01\n'}),
      );
      final db = await write(
        'noop-backup.sqlite',
        utf8.encode('SQLite format 3 whatever'),
      );
      // Scope the check to dirs this call creates — other tests in this file
      // extract too, so a bare scan of the temp root proves nothing.
      Set<String> importDirs() => Directory.systemTemp
          .listSync()
          .whereType<Directory>()
          .map((d) => d.path)
          .where((d) => d.contains('openstrap_import_'))
          .toSet();
      final before = importDirs();
      await expectLater(
        resolveImportCsvPaths([zip, db], flavor: 'WHOOP'),
        throwsA(isA<ImportFormatException>()),
      );
      expect(
        importDirs().difference(before),
        isEmpty,
        reason: 'the extraction from the first file was cleaned up',
      );
    });

    test('AppleDouble resource forks are not mistaken for CSVs', () async {
      final path = await write(
        'export.zip',
        _zipOf({
          '__MACOSX/._sleeps.csv': '\x00\x01binary',
          'sleeps.csv': 'Sleep onset\n2026-01-01\n',
        }),
      );
      final out = await resolveImportCsvPaths([path], flavor: 'WHOOP');
      expect(out.paths, hasLength(1));
      expect(out.paths.single, endsWith('sleeps.csv'));
    });
  });

  // gzip used to be a flat refusal ("unzip it first and pick the CSV inside").
  // It is inflated now: it is what every command-line tool produces when
  // someone compresses a CSV, and it is the shape this app's own auto-backups
  // take (`openstrap-….db.gz`).
  group('gzip', () {
    test('a gzipped CSV is inflated and imported', () async {
      const csv = 'Cycle start time,Recovery score';
      final path = await write('data.csv.gz', gzip.encode(utf8.encode(csv)));
      final out = await resolveImportCsvPaths([path], flavor: 'WHOOP');
      try {
        expect(out.paths, hasLength(1));
        expect(out.paths.single, endsWith('data.csv'));
        expect(File(out.paths.single).readAsStringSync(), csv);
      } finally {
        await out.dispose();
      }
    });

    test('a gzipped database is claimed as a database, not a CSV', () async {
      // The auto-backup shape. Only the SQLite magic decides, so a gzipped CSV
      // still falls through to the CSV path.
      final db = <int>[
        ...utf8.encode('SQLite format 3'),
        0,
        ...List.filled(64, 0),
      ];
      final path =
          await write('openstrap-20260810-120000.db.gz', gzip.encode(db));
      final resolved = await resolveNoopDatabase(path);
      expect(resolved, isNotNull);
      try {
        expect(
          File(resolved!.path).readAsBytesSync().take(15).toList(),
          utf8.encode('SQLite format 3'),
        );
      } finally {
        await resolved!.dispose();
      }
    });

    test('a gzipped CSV is NOT claimed by the database path', () async {
      final path =
          await write('data.csv.gz', gzip.encode(utf8.encode('a,b')));
      expect(await resolveNoopDatabase(path), isNull);
    });

    test('a gzip wrapping something that is not a CSV is refused', () async {
      final path = await write(
        'nested.gz',
        gzip.encode(_zipOf({'inner.csv': 'a,b'})),
      );
      await expectLater(
        resolveImportCsvPaths([path], flavor: 'WHOOP'),
        throwsA(isA<ImportFormatException>()),
      );
    });

    test('a corrupt gzip fails with guidance and leaves nothing behind',
        () async {
      // Valid magic so the sniff routes it here, garbage where the deflate
      // stream should be. The deflate stream itself rejects this one; the two
      // tests below cover the damage the decoder does NOT notice.
      final path = await write('broken.csv.gz', <int>[
        0x1F, 0x8B, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03,
        ...List<int>.generate(64, (i) => (i * 37 + 11) & 0xFF),
      ]);
      final dir = await Directory.systemTemp.createTemp('gz_partial_');
      try {
        await expectLater(
          inflateGzip(path, dir),
          throwsA(isA<ImportFormatException>()),
        );
        expect(
          dir.listSync(),
          isEmpty,
          reason: 'a half-inflated file must not be left for a caller to read',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('a truncated gzip is refused instead of restored short', () async {
      // The half-synced-backup case, and the one that mattered: `gzip.decoder`
      // returns what it managed to inflate from a stream that just stops, with
      // no error. A backup cut at 99.9% inflated, sniffed as SQLite, merged and
      // reported success one row short of the data the user was restoring.
      final body = utf8.encode(
        List.generate(400, (i) => 'row,$i,${i * 7},value-$i').join('\n'),
      );
      final full = gzip.encode(body);
      final path = await write(
        'cut.csv.gz',
        full.sublist(0, full.length - (full.length ~/ 200) - 1),
      );
      final dir = await Directory.systemTemp.createTemp('gz_cut_');
      try {
        await expectLater(
          inflateGzip(path, dir),
          throwsA(isA<ImportFormatException>()),
        );
        expect(
          dir.listSync(),
          isEmpty,
          reason: 'a short inflate must not be left where a caller can read it',
        );
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('a gzip whose contents no longer match its checksum is refused',
        () async {
      // The boundary of the case above: when the stream is COMPLETE, zlib
      // reaches the trailer and checks it itself, so this is refused whether or
      // not inflateGzip verifies anything. Pinned because that is exactly why
      // truncation was missed — the checking only ever happened at the end of a
      // stream that arrived, and a cut file never gets there.
      final full = <int>[
        ...gzip.encode(utf8.encode('a,b,c\n' * 500)),
      ];
      final crcAt = full.length - 8;
      full[crcAt] = full[crcAt] ^ 0xFF;
      final path = await write('flipped.csv.gz', full);
      final dir = await Directory.systemTemp.createTemp('gz_crc_');
      try {
        await expectLater(
          inflateGzip(path, dir),
          throwsA(isA<ImportFormatException>()),
        );
        expect(dir.listSync(), isEmpty);
      } finally {
        await dir.delete(recursive: true);
      }
    });

    test('a non-gzip file is not claimed by inflateGzip', () async {
      final path = await write('plain.csv', utf8.encode('a,b'));
      final dir = await Directory.systemTemp.createTemp('gz_none_');
      try {
        expect(await inflateGzip(path, dir), isNull);
      } finally {
        await dir.delete(recursive: true);
      }
    });
  });

  // The other half of #160/#199: the file was classified correctly here and
  // then handed to the wrong importer anyway, because the router read the
  // extension. What a file HOLDS decides now.
  group('isNoopExport ignores the extension', () {
    test('a NOOP raw-sensor CSV is claimed whatever it is called', () async {
      final path = await write(
        'export (1).csv',
        utf8.encode('unix_s,iso_utc,stream,hr_bpm\n1754000000,x,hr,61\n'),
      );
      expect(await isNoopExport(path), isTrue);
    });

    test('a WHOOP My Data ZIP is NOT a NOOP export', () async {
      final path = await write(
        'my_whoop_data.zip',
        _zipOf({
          'physiological_cycles.csv': 'Cycle start time,Recovery score %\n',
          'sleeps.csv': 'Cycle start time,Sleep performance %\n',
          'workouts.csv': 'Workout start time,Activity name\n',
        }),
      );
      expect(await isNoopExport(path), isFalse);
    });

    test('a WHOOP CSV on its own is NOT a NOOP export', () async {
      final path = await write('sleeps.csv',
          utf8.encode('Cycle start time,Sleep performance %\n2026-08-01,88\n'));
      expect(await isNoopExport(path), isFalse);
    });

    test('a .noopbak is claimed by its database member', () async {
      final path = await write(
        'backup.noopbak',
        _zipOf({'noop-backup.sqlite': 'SQLite format 3\x00 rows'}),
      );
      expect(await isNoopExport(path), isTrue);
    });

    test('a loose database is claimed by its magic', () async {
      final path =
          await write('unnamed', utf8.encode('SQLite format 3\x00 rows'));
      expect(await isNoopExport(path), isTrue);
    });

    test('a single CSV zipped by hand is still a NOOP export', () async {
      final path = await write('archive.zip',
          _zipOf({'raw_sensor.csv': 'unix_s,iso_utc,stream\n1,x,hr\n'}));
      expect(await isNoopExport(path), isTrue);
    });

    test('junk is claimed by nobody here', () async {
      final path = await write('junk.bin', [0x00, 0x01, 0x02, 0x03]);
      expect(await isNoopExport(path), isFalse);
    });
  });

  // The router judged byte ZERO; the reader skips blank and `#` lines first and
  // falls back to the documented positional layout when there is no header at
  // all. Anything the reader would take, the router has to route — otherwise a
  // valid export goes to the vendor importer and is refused with a confident
  // wrong message, which is #160/#199 all over again.
  group('the router uses the reader\'s own first-record rule', () {
    test('a leading comment does not lose the file', () async {
      final path = await write(
        'export.csv',
        utf8.encode('# noop raw sensor export\n# v3\n'
            'unix_s,iso_utc,stream,hr_bpm\n1754000000,x,hr,61\n'),
      );
      expect(await isNoopExport(path), isTrue);
    });

    test('leading blank lines do not lose the file', () async {
      final path = await write(
        'export.csv',
        utf8.encode('\n\r\n\nunix_s,iso_utc,stream,hr_bpm\n1754000000,x,hr,61\n'),
      );
      expect(await isNoopExport(path), isTrue);
    });

    test('a headerless export is claimed, as the reader claims it', () async {
      // The positional layout in `NoopImporter._defaultCols`, no header row.
      final path = await write(
        'raw.csv',
        utf8.encode('1754000000,2026-08-01T00:00:00Z,hr,61,,,,,,,,,,,,,\n'
            '1754000001,2026-08-01T00:00:01Z,hr,62,,,,,,,,,,,,,\n'),
      );
      expect(await isNoopExport(path), isTrue);
    });

    test('a vendor CSV behind a comment is still not ours', () async {
      final path = await write(
        'sleeps.csv',
        utf8.encode('# exported 2026-08-01\n'
            'Cycle start time,Sleep performance %\n2026-08-01,88\n'),
      );
      expect(await isNoopExport(path), isFalse);
    });

    test('a comma-heavy row that is not an epoch is not ours', () async {
      // The headerless signature is structural on purpose: 17 columns is not
      // enough, column zero has to be unix seconds.
      final path = await write(
        'other.csv',
        utf8.encode('${List.filled(17, 'x').join(',')}\n'),
      );
      expect(await isNoopExport(path), isFalse);
    });

    test('an all-comment file claims nothing', () async {
      final path = await write('notes.csv', utf8.encode('# nothing\n# here\n'));
      expect(await isNoopExport(path), isFalse);
    });

    test('a file exactly as long as the read window keeps its last record',
        () async {
      // A full buffer used to MEAN truncated, so a file whose length is exactly
      // the window — and whose final record has no trailing newline — had that
      // record thrown away and went to the vendor importer.
      final body = '${'# pad\n' * 678}unix_s,iso_utc,stream,hr_bpm';
      expect(body.length, 4096);
      final path = await write('export.csv', utf8.encode(body));
      expect(await isNoopExport(path), isTrue);
    });

    test('a header past the read ceiling is not guessed at', () async {
      // 4 KB of comments, then the header. Bounded read means bounded answer:
      // it declines rather than materialising the file to be sure.
      final path = await write(
        'export.csv',
        utf8.encode('${'# pad\n' * 1200}unix_s,iso_utc,stream\n1754000000,x,hr\n'),
      );
      expect(await isNoopExport(path), isFalse);
    });
  });
}

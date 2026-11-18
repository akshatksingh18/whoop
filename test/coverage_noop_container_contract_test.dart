// Authored small containers. Heavy derivation alone is substituted at its handoff.
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derivation_engine.dart';
import 'package:whoop_companion/compute/profile.dart';
import 'package:whoop_companion/compute/substrate.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/import_container.dart';
import 'package:whoop_companion/import/noop_import.dart';
import 'support/coverage_store.dart';

class CaptureEngine extends DerivationEngine {
  final inputs = <Substrate>[];
  final dates = <Set<String>>[];
  int finalizations = 0;
  @override
  Future<int> deriveImportedDays(
    Substrate sub,
    Profile profile,
    Set<String> days, {
    void Function(String day)? onDayDone,
  }) async {
    inputs.add(sub);
    dates.add({...days});
    return days.length;
  }

  @override
  Future<void> finalizeImport(Profile profile) async {
    finalizations++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUpAll(() => coverageStore('noop-container-contract'));
  setUp(() async {
    await resetCoverageStore();
    root = await (await Directory(
      'build/coverage-remainder/noop-container-contract',
    ).absolute.create(recursive: true)).createTemp('authored-');
  });
  tearDownAll(LocalDb.close);
  const profile = Profile(ageYears: 30, sex: 'f', heightCm: 170, weightKg: 70);
  Future<File> file(String name, List<int> data) =>
      File('${root.path}/$name').writeAsBytes(data);
  List<int> zip(Map<String, String> members) {
    final archive = Archive();
    for (final e in members.entries) {
      final data = utf8.encode(e.value);
      archive.addFile(ArchiveFile(e.key, data.length, data));
    }
    return ZipEncoder().encode(archive);
  }

  for (final rawNames in [false, true]) {
    test(
      'ambiguous ${rawNames ? 'raw-sensor' : 'generic'} archive refuses before derivation and keeps its exact source',
      () async {
        final names = rawNames
            ? ['a/raw-sensor-a.csv', 'b/raw-sensor-b.csv']
            : ['a/first.csv', 'b/second.csv'];
        final bytes = zip({
          for (final n in names) n: 'unix_s,iso_utc,stream\n',
        });
        final source = await file('authored.zip', bytes);
        final engine = CaptureEngine();
        await expectLater(
          NoopImporter.importFile(source.path, profile, engine),
          throwsA(
            isA<ImportFormatException>().having(
              (e) => e.message,
              'ambiguity',
              contains('holds 2 CSV files'),
            ),
          ),
        );
        expect(engine.inputs, isEmpty);
        expect(engine.finalizations, 0);
        expect(await source.readAsBytes(), bytes);
        expect(await (await LocalDb.instance).query('day_result'), isEmpty);
        final renamed = await source.rename('${source.path}.retained');
        expect(
          await renamed.readAsBytes(),
          bytes,
          reason: 'Reader released its input',
        );
      },
    );
  }

  test(
    'an archive with no CSV is refused without deriving or replacing history',
    () async {
      final bytes = zip({'readme.txt': 'Authored metadata'});
      final source = await file('empty-export.zip', bytes);
      final engine = CaptureEngine();
      await LocalDb.setCursor('authored_recovery', 'kept');
      await expectLater(
        NoopImporter.importFile(source.path, profile, engine),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'empty export',
            contains('archive with no CSV files'),
          ),
        ),
      );
      expect(engine.inputs, isEmpty);
      expect(await LocalDb.getCursor('authored_recovery'), 'kept');
      expect(await source.readAsBytes(), bytes);
    },
  );

  test(
    'unrecognized text supplies its format explanation without creating a day',
    () async {
      final bytes = utf8.encode('date,not_a_sensor\n2021-04-06,authored\n');
      final source = await file('wrong.csv', bytes);
      final engine = CaptureEngine();
      await expectLater(
        NoopImporter.importFile(source.path, profile, engine),
        throwsA(
          isA<ImportFormatException>().having(
            (e) => e.message,
            'format reason',
            contains('no "unix_s'),
          ),
        ),
      );
      expect(engine.inputs, isEmpty);
      expect(engine.finalizations, 0);
      expect(await source.readAsBytes(), bytes);
      expect(await (await LocalDb.instance).query('day_result'), isEmpty);
    },
  );

  test(
    'named sparse optical channels reach the single derivation seam without invented HR',
    () async {
      final bytes = utf8.encode(
        'unix_s,iso_utc,stream,spo2_red,spo2_ir\n1760000040,,spo2,101,202\n1760000041,,spo2,,203\n',
      );
      final source = await file('raw-sensor.csv', bytes);
      final engine = CaptureEngine();
      final result = await NoopImporter.importFile(
        source.path,
        profile,
        engine,
      );
      expect(result.rows, 2);
      expect(result.days, 1);
      expect(result.steps, 0);
      expect(engine.inputs, hasLength(1));
      expect(engine.finalizations, 1);
      final sub = engine.inputs.single;
      expect(sub.tsSec, [1760000040, 1760000041]);
      expect(sub.spo2Red, [101, 101]);
      expect(sub.spo2Ir, [202, 203]);
      expect(sub.hr, [0, 0]);
      expect(sub.rrMs, isEmpty);
      expect(await source.readAsBytes(), bytes);
    },
  );
}

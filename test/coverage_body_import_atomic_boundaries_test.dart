// Authored Body manifests/pixels and real SQLite transactions. No health export
// or personal image is used; rejected/rolled-back imports keep existing evidence.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/calculation_store.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('body-import-atomic-boundaries', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  String manifest(Map<String, Object?> extra) =>
      jsonEncode({'version': 1, 'weights': [], ...extra});
  final pixels = img.encodeJpg(img.Image(width: 8, height: 12));

  for (final generated in [false, true]) {
    test(
      'Body ${generated ? 'generated' : 'legacy'} duplicate dates refuse the whole preview',
      () async {
        await BodyLogDb.putWeight('2021-04-05', 70, 'kg', historyOnly: true);
        final before = await (await LocalDb.instance).query(
          'body_weight_reading',
        );
        final text = manifest({
          if (generated) 'format': 'whoop-body-history',
          'weights': [
            for (final id in ['authored-one', 'authored-two'])
              generated
                  ? {'id': id, 'date': '2021-04-06', 'value': 160, 'unit': 'lb'}
                  : {'id': id, 'day': '2021-04-06', 'pounds': 160},
          ],
        });
        await expectLater(
          planBodyImport(text),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'conflict',
              'Two weights on 2021-04-06',
            ),
          ),
        );
        expect(
          await (await LocalDb.instance).query('body_weight_reading'),
          before,
        );
      },
    );
  }

  for (final value in [4.99, 80.01]) {
    test(
      'Body out-of-range tape $value is rejected before any rows or settings change',
      () async {
        await CalculationStore.write(BodyLogDb.weekdayKey, '4');
        final db = await LocalDb.instance;
        final before = await db.query('baselines');
        await expectLater(
          planBodyImport(
            manifest({
              'measurementWeekday': 2,
              'measurements': [
                {
                  'id': 'authored-tape',
                  'day': '2021-04-06',
                  'recordedAt': 639489600,
                  'inches': {'waistNavel': value},
                },
              ],
            }),
          ),
          throwsA(
            isA<FormatException>().having(
              (e) => e.message,
              'range refusal',
              'Measurement out of range on 2021-04-06',
            ),
          ),
        );
        expect(await db.query('body_measure'), isEmpty);
        expect(await db.query('baselines'), before);
      },
    );
  }

  for (final optIn in [false, true]) {
    test(
      'Body weekday import respects explicit apply choice $optIn and calendar numbering',
      () async {
        await CalculationStore.write(BodyLogDb.weekdayKey, '4');
        final plan = await planBodyImport(manifest({'measurementWeekday': 1}));
        expect(plan.measureWeekday, 7); // Swift Sunday -> ISO Sunday.
        expect(
          await applyBodyImport(
            plan,
            encode: (_) async => pixels,
            applyWeekday: optIn,
          ),
          0,
        );
        expect(
          await CalculationStore.read(BodyLogDb.weekdayKey),
          optIn ? '7' : '4',
        );
        expect(await BodyLogDb.weights(), isEmpty);
        expect(await BodyLogDb.measures(), isEmpty);
      },
    );
  }

  test(
    'Body CSV joins tape-only dates and converts kg without fabricating absent sites',
    () async {
      await BodyLogDb.putWeight('2021-04-06', 70, 'kg', historyOnly: true);
      await BodyLogDb.putMeasure(
        BodyMeasure(
          id: 'authored-older',
          date: '2021-04-06',
          recordedAt: DateTime(2021, 4, 6, 8),
          inches: {'waistNavel': 33},
        ),
      );
      await BodyLogDb.putMeasure(
        BodyMeasure(
          id: 'authored-newer',
          date: '2021-04-06',
          recordedAt: DateTime(2021, 4, 6, 10),
          inches: {'waistNavel': 32},
        ),
      );
      await BodyLogDb.putMeasure(
        BodyMeasure(
          id: 'authored-tape-only',
          date: '2021-04-07',
          recordedAt: DateTime(2021, 4, 7, 10),
          inches: {'neck': 15},
        ),
      );
      final db = await LocalDb.instance;
      final weights = await db.query('body_weight_reading');
      final tape = await db.query('body_measure');
      final lines = (await BodyLogDb.csv()).trimRight().split('\n');
      expect(lines, hasLength(3));
      expect(lines[1].split(','), [
        '2021-04-06',
        '154.32',
        '32',
        '',
        '',
        '',
        '',
        '',
        '',
        '',
      ]);
      expect(lines[2].split(','), [
        '2021-04-07',
        '',
        '',
        '',
        '',
        '15',
        '',
        '',
        '',
        '',
      ]);
      expect(await db.query('body_weight_reading'), weights);
      expect(await db.query('body_measure'), tape);
    },
  );

  test(
    'Body re-import recognizes an existing photo without requiring or rewriting its source',
    () async {
      final photo = await BodyLogDb.addPhoto(
        pixels,
        id: 'authored-existing',
        date: '2021-04-06',
        pose: 'front',
      );
      final file = await BodyLogDb.photoFile(photo);
      final bytes = await file.readAsBytes();
      final before = await (await LocalDb.instance).query('body_photo');
      final plan = await planBodyImport(
        manifest({
          'photos': [
            {
              'id': photo.id,
              'day': photo.date,
              'pose': 'front',
              'recordedAt': 639489600,
            },
          ],
        }),
      );
      expect(plan.alreadyHere, 1);
      expect(plan.photos, isEmpty);
      expect(plan.missingPhotoFiles, isEmpty);
      expect(
        await applyBodyImport(
          plan,
          encode: (_) async {
            fail('Existing photos must not be decoded again');
          },
        ),
        0,
      );
      expect(await (await LocalDb.instance).query('body_photo'), before);
      expect(await file.readAsBytes(), bytes);
    },
  );

  test(
    'Body late settings refusal rolls back rows and only this import photo, then retries',
    () async {
      final retained = await BodyLogDb.addPhoto(
        pixels,
        id: 'authored-retained',
        date: '2021-04-05',
        pose: 'front',
      );
      final retainedFile = await BodyLogDb.photoFile(retained);
      final retainedBytes = await retainedFile.readAsBytes();
      await CalculationStore.write(BodyLogDb.weekdayKey, '4');
      final db = await LocalDb.instance;
      final beforePhotos = await db.query('body_photo');
      final beforeSettings = await db.query('baselines');
      final plan = await planBodyImport(
        manifest({
          'measurementWeekday': 1,
          'weights': [
            {
              'id': 'authored-import-weight',
              'day': '2021-04-06',
              'pounds': 160,
            },
          ],
          'photos': [
            {
              'id': 'authored-new-photo',
              'day': '2021-04-06',
              'pose': 'side',
              'recordedAt': 639489600,
            },
          ],
        }),
        files: {'authored-new-photo.jpg': 'authored-input.jpg'},
      );
      expect(plan.photos, hasLength(1));
      final newFile = await BodyLogDb.photoFile(plan.photos.single.photo);
      await db.execute(
        "CREATE TRIGGER authored_weekday_refusal BEFORE INSERT ON baselines "
        "WHEN NEW.key='${CalculationStore.prefix}${BodyLogDb.weekdayKey}' "
        "BEGIN SELECT RAISE(ABORT,'authored weekday refusal'); END",
      );
      var encodes = 0;
      Future<List<int>> encode(String path) async {
        expect(path, 'authored-input.jpg');
        encodes++;
        return pixels;
      }

      try {
        await expectLater(
          applyBodyImport(plan, encode: encode, applyWeekday: true),
          throwsA(predicate((e) => '$e'.contains('authored weekday refusal'))),
        );
        expect(await db.query('body_weight_reading'), isEmpty);
        expect(await db.query('body_photo'), beforePhotos);
        expect(await db.query('baselines'), beforeSettings);
        expect(await CalculationStore.read(BodyLogDb.weekdayKey), '4');
        expect(await newFile.exists(), false);
        expect(await retainedFile.readAsBytes(), retainedBytes);
      } finally {
        await db.execute('DROP TRIGGER authored_weekday_refusal');
      }
      expect(
        await applyBodyImport(plan, encode: encode, applyWeekday: true),
        2,
      );
      expect(encodes, 2);
      expect(await newFile.readAsBytes(), pixels);
      expect(await retainedFile.readAsBytes(), retainedBytes);
      expect(await CalculationStore.read(BodyLogDb.weekdayKey), '7');
      expect((await BodyLogDb.weights()).single.historyOnly, true);
      expect((await BodyLogDb.weights()).single.source, 'akshatos');
      expect(await db.query('body_photo'), hasLength(2));
    },
  );

  test(
    'Body actual validation errors retain their explanation for the caller',
    () async {
      await expectLater(
        BodyLogDb.putWeight('2021-04-06', -1, 'kg'),
        throwsA(
          isA<BodyLogError>().having(
            (e) => e.toString(),
            'message',
            isNot(contains('Instance of')),
          ),
        ),
      );
      expect(await BodyLogDb.weights(), isEmpty);
      expect(
        await (await LocalDb.instance).query('body_weight_reading'),
        isEmpty,
      );
    },
  );
}

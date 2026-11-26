// The real mixed selection retains committed input and both importer failures.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';

import '../../import/partial_results_test.dart' show App;
import '../../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('combined-import-refusals', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final journal in [true, false]) {
    test(
      'retains the accepted ${journal ? 'journal' : 'backup'} and reports both failed formats',
      () async {
        final app = App()..refuseVendor = true;
        addTearDown(app.dispose);
        final dir = File(LocalDb.dbName).parent;
        final files = <String, String>{
          if (journal)
            'accepted-journal.csv':
                'date,tags,note\n2021-04-06,Authored,Retained note\n'
          else
            'accepted.db': 'Authored backup boundary',
          'refused-raw.csv':
              'unix_s,iso_utc,stream,hr_bpm,rr_ms,grav_x,grav_y,grav_z\n'
              '1617710400,2021-04-06T12:00:00Z,hr,60,,,,\n',
          'refused-vendor.csv': 'Authored vendor header\nAuthored value\n',
        };
        final inputs = [
          for (final e in files.entries)
            await File('${dir.path}/${e.key}').writeAsString(e.value),
        ];
        final result = await runImport(app, [
          for (final file in inputs) file.path,
        ]);

        expect(result.readError, contains('refused-raw.csv'));
        expect(result.readError, contains('synthetic raw refusal'));
        expect(result.readError, contains('synthetic vendor refusal'));
        expect(result.nothingLanded, isFalse);
        expect(result.records, journal ? 0 : 1);
        expect(result.journalRows, journal ? 1 : 0);
        expect(app.raw, [inputs[1].path]);
        expect(app.vendor, [inputs[2].path]);
        if (journal) {
          expect((await LocalDb.journalRows()).single['note'], 'Retained note');
          expect(app.backups, isEmpty);
        } else {
          expect(app.backups, ['accepted.db']);
          expect(await LocalDb.session('accepted.db'), isNotNull);
          expect(await LocalDb.journalRows(), isEmpty);
        }
        for (var i = 0; i < inputs.length; i++) {
          expect(await inputs[i].readAsString(), files.values.elementAt(i));
        }
      },
    );
  }
}

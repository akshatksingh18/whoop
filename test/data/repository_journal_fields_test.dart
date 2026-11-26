// The repository's journal-field seam over real SQLite: a custom definition it
// stores is offered back, and a changed value with no definition is kept as
// entered rather than clamped against a guessed range. Authored values only.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/journal_fields.dart';
import 'package:whoop_companion/data/local_repository_impl.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('repository-journal-fields'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  const day = '2021-04-06';

  test('a stored custom field is offered with the built-in ones', () async {
    final repo = LocalRepositoryImpl(getProfileMap: () => {});
    const spec = JournalFieldSpec(
      key: 'custom_authored',
      label: 'Authored dose',
      kind: JournalFieldKind.dose,
      unit: 'mg',
      max: 100,
      step: 5,
      custom: true,
    );
    await repo.postCustomJournalField(spec);
    final fields = await repo.getJournalFields();
    expect(fields.length, kJournalFields.length + 1);
    expect(fields.last.key, 'custom_authored');
    expect(fields.last.max, 100);
  });

  test('a value with no definition is saved as entered', () async {
    final repo = LocalRepositoryImpl(getProfileMap: () => {});
    await repo.saveJournalEdit(
      day,
      changes: {'custom_unknown': const JournalMetricValue(12345)},
      base: const {},
    );
    expect((await repo.getJournalMetrics(day))['custom_unknown']?.value, 12345);
  });
}

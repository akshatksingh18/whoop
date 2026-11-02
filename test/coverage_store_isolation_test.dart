// A cloud preflight and its full suite may run the same media fixture twice.
// Fresh fixture containers isolate both rows and orphan files without deleting
// any previous run's authored evidence. No encryption worker runs in this check.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(LocalDb.close);
  test(
    'fresh coverage containers isolate retained media and database rows',
    () async {
      await coverageStore('media-isolation', fresh: true);
      await resetCoverageStore();
      final firstDb = LocalDb.dbName;
      final firstMedia = await BodyLogDb.photoDir();
      final orphan = await File(
        '${firstMedia.path}/authored-orphan.jpg',
      ).writeAsBytes([1, 2, 3]);
      await BodyLogDb.putWeight('2021-04-06', 70, 'kg', historyOnly: true);
      await coverageStore('media-isolation', fresh: true);
      await resetCoverageStore();
      final secondMedia = await BodyLogDb.photoDir();
      expect(LocalDb.dbName, isNot(firstDb));
      expect(secondMedia.path, isNot(firstMedia.path));
      expect(await secondMedia.list().toList(), isEmpty);
      expect(await BodyLogDb.weights(), isEmpty);
      expect(await BodyLogDb.photos(), isEmpty);
      expect(await orphan.readAsBytes(), [1, 2, 3]);
      expect(await File(firstDb).exists(), true);
    },
  );
}

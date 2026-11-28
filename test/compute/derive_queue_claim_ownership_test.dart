// Two scheduler owners can see the same durable intent. Only one may run it.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/compute/derive_scheduler.dart';
import 'package:whoop_companion/data/db.dart';

import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('derive-queue-claim-ownership'));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);

  for (final kind in DeriveJobKind.values) {
    test(
      'one durable ${kind.name} claim is visible to both scheduler owners',
      () async {
        final earlierRead = <DeriveJobKind>[];
        final winningRead = <DeriveJobKind>[];
        final won = Completer<void>();
        final earlier = DeriveScheduler(
          run: ({required kind}) async => earlierRead.add(kind),
          lightSettle: const Duration(seconds: 1),
          heavySettle: const Duration(seconds: 1),
          onChanged: () {},
          log: (_) {},
        );
        final winner = DeriveScheduler(
          run: ({required kind}) async {
            winningRead.add(kind);
            won.complete();
          },
          lightSettle: const Duration(milliseconds: 10),
          heavySettle: const Duration(milliseconds: 10),
          onChanged: () {},
          log: (_) {},
        );
        addTearDown(earlier.dispose);
        addTearDown(winner.dispose);
        await ComputeJobStore.enqueueDerive(
          type: 'derive_${kind.name}',
          reason: 'authored restart',
        );
        await earlier.init();
        expect(earlier.pendingLight || earlier.pendingHeavy, isTrue);
        await winner.init();
        await won.future.timeout(const Duration(seconds: 3));

        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while ((earlier.pendingLight ||
                earlier.pendingHeavy ||
                winner.running) &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(earlier.pendingLight || earlier.pendingHeavy, isFalse);
        expect(winner.running, isFalse);
        expect(earlierRead, isEmpty);
        expect(winningRead, [kind]);
        final db = await LocalDb.instance;
        expect(await db.query('compute_jobs'), isEmpty);
      },
    );
  }
}

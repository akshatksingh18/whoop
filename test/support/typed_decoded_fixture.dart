// Read tiny authored fixtures through the active paged decoded reader and
// typed mapper. No legacy-table fallback or production API is recreated.
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/models.dart';

Future<List<Sample>> readTypedDecodedFixture(int from, int to) async {
  final samples = <Sample>[];
  int? afterTs, afterCounter;
  while (true) {
    final rows = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 64,
      fromRecTs: from,
      toRecTs: to,
      afterRecTs: afterTs,
      afterCounter: afterCounter,
    );
    if (rows.isEmpty) return samples;
    samples.addAll(rows.map(Sample.fromDecodedRow));
    afterTs = (rows.last['rec_ts'] as num).toInt();
    afterCounter = (rows.last['counter'] as num).toInt();
  }
}

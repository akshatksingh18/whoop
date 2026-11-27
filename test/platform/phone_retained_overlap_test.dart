// Retained older-schema band windows can still partition a phone query.
// No band-step producer is enabled;only the native pedometer reply is authored.
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/platform/phone_pedometer.dart';
import '../support/coverage_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => coverageStore('phone-retained-overlap', fresh: true));
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final measuredZero in [false, true]) {
    for (final shape in [
      'before-day',
      'after-day',
      'whole-day',
      'across-hour',
    ]) {
      test(
        'phone-only ${measuredZero ? 'zero' : 'measured'} count clips retained $shape coverage without counting its old steps',
        () async {
          expect(LocalDb.debugBandSteps, false);
          final now = DateTime.now();
          final day = DateTime(now.year, now.month, now.day - 1);
          final end = DateTime(day.year, day.month, day.day + 1);
          final lo = day.millisecondsSinceEpoch ~/ 1000;
          final hi = end.millisecondsSinceEpoch ~/ 1000;
          final (a, b) = switch (shape) {
            'before-day' => (lo - 900, lo + 900),
            'after-day' => (hi - 900, hi + 900),
            'whole-day' => (lo - 900, hi + 900),
            _ => (lo + 1800, lo + 5400),
          };
          final db = await LocalDb.instance;
          // Represents a legacy row retained by restore/migration,not a new
          // current-band observation. The personal writer remains disabled.
          await db.insert('live_coverage', {
            'start_ts': a,
            'end_ts': b,
            'steps': 9999,
            'day': dayLabelOf(day),
            'source': LocalDb.kStepSourceBand,
          });
          final legacy = await db.query('live_coverage');
          await LocalDb.setCursor('authored-unrelated', 'keep');
          final asked = <(DateTime, DateTime)>[];
          final pedometer = PhonePedometer(
            stepReader: (from, to) async {
              asked.add((from, to));
              expect(from.isBefore(day), false);
              expect(to.isAfter(end), false);
              expect(to.isAfter(from), true);
              return measuredZero ? 0 : to.difference(from).inMinutes;
            },
          );
          final expected = measuredZero ? 0 : end.difference(day).inMinutes;
          expect(await pedometer.syncDay(day), expected);
          expect(asked, isNotEmpty);
          expect(asked.first.$1, day);
          expect(asked.last.$2, end);
          for (var i = 1; i < asked.length; i++) {
            expect(
              asked[i].$1,
              asked[i - 1].$2,
              reason: 'Queries neither overlap nor invent an uncovered gap',
            );
          }
          final phone = await db.query(
            'live_coverage',
            where: 'source = ?',
            whereArgs: [LocalDb.kStepSourcePhone],
            orderBy: 'start_ts',
          );
          expect(phone.first['start_ts'], lo);
          expect(phone.last['end_ts'], hi);
          expect(
            phone.fold<int>(0, (s, r) => s + (r['steps'] as num).toInt()),
            expected,
          );
          expect(
            (await LocalDb.resolvedStepsForDay(dayLabelOf(day))).total,
            expected,
          );
          expect(
            await db.query(
              'live_coverage',
              where: 'source = ?',
              whereArgs: [LocalDb.kStepSourceBand],
            ),
            legacy,
          );
          expect(await LocalDb.getCursor('authored-unrelated'), 'keep');
          expect(LocalDb.debugBandSteps, false);
        },
      );
    }
  }
  for (final boundary in ['DELETE', 'INSERT']) {
    test(
      'a native $boundary refusal rolls back the phone-day replacement and preserves retry evidence',
      () async {
        final now = DateTime.now();
        final day = DateTime(now.year, now.month, now.day - 1);
        final end = DateTime(day.year, day.month, day.day + 1);
        final lo = day.millisecondsSinceEpoch ~/ 1000;
        final hi = end.millisecondsSinceEpoch ~/ 1000;
        final id = dayLabelOf(day);
        await LocalDb.replacePhoneCoverageForDay(
          id,
          [(startTs: lo, endTs: hi, steps: 60)],
          distances: {'$lo-$hi': 1000},
        );
        await LocalDb.setCursor('authored-retained', 'keep');
        final db = await LocalDb.instance;
        final before = await db.query('live_coverage', orderBy: 'id');
        final selector = boundary == 'DELETE' ? 'OLD' : 'NEW';
        await db.execute(
          "CREATE TRIGGER authored_phone_day_refusal BEFORE $boundary ON live_coverage WHEN $selector.source = '${LocalDb.kStepSourcePhone}' BEGIN SELECT RAISE(ABORT,'authored phone-day replacement refusal'); END",
        );
        var reads = 0;
        final phone = PhonePedometer(
          stepReader: (a, b) async {
            reads++;
            return b.difference(a).inMinutes;
          },
        );
        try {
          expect(await phone.syncDay(day), isNull);
          expect(reads, greaterThan(0));
          expect(await db.query('live_coverage', orderBy: 'id'), before);
          expect((await LocalDb.resolvedStepsForDay(id)).total, 60);
          expect(await LocalDb.getCursor('authored-retained'), 'keep');
        } finally {
          await db.execute('DROP TRIGGER authored_phone_day_refusal');
        }
        final expected = end.difference(day).inMinutes;
        expect(await phone.syncDay(day), expected);
        expect((await LocalDb.resolvedStepsForDay(id)).total, expected);
        expect(await LocalDb.getCursor('authored-retained'), 'keep');
        expect(LocalDb.debugBandSteps, false);
      },
    );
  }
}

// Approved Body milestone A: real paragraphs, positions and evidence labels.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/progress_milestones.dart';
import 'package:whoop_companion/data/progress_review.dart' show ProgressRange;
import 'package:whoop_companion/ui2/screens/progress_routes.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_localized_progress_test.dart' show progress;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-milestone-layout');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  for (final range in [ProgressRange.all, ProgressRange.sinceStart]) {
    for (final (width, scale) in [
      (390.0, 1.0),
      (390.0, 1.3),
      (390.0, 1.31),
      (320.0, 2.0),
      (430.0, 3.1),
    ]) {
      if (range == ProgressRange.sinceStart && scale == 1.3) continue;
      testWidgets(
        'COV-48 Body milestone dates ${range.name} ${width.toInt()} ${scale}x retain whole evidence',
        (t) async {
          final data = progress(true);
          final today = todayLabel();
          final from = range.from(
            today,
            baseline: data.baseline,
            earliest: data.earliest,
          );
          final notes = bodyMilestones(data.measures, from, today);
          expect(notes, hasLength(3));
          final db = await LocalDb.instance;
          final before = <String, List<Map<String, Object?>>>{
            for (final table in [
              'body_measure',
              'body_weight',
              'body_weight_reading',
            ])
              table: await db.query(table),
          };
          await localizedPage(
            t,
            progressDetailPage(
              ProgressDest.weight,
              initial: data,
              range: range,
            ),
            scale: scale,
          );
          t.view.physicalSize = Size(width, 844);
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 80)),
          );
          await t.pumpAndSettle();
          await reveal(t, find.text('Milestones'));
          final section = find.byWidgetPredicate(
            (w) => w is Section && w.title == 'Milestones',
          );
          for (final note in notes) {
            final at = DateTime.parse(note.date);
            final dateLabel =
                '${formatShortDate(at)}${at.year == DateTime.now().year ? '' : ', ${at.year}'}';
            final date = find.descendant(
              of: section,
              matching: find.text(dateLabel),
            );
            final title = find.descendant(
              of: section,
              matching: find.text(note.title),
            );
            expect(date, findsOneWidget);
            expect(title, findsOneWidget);
            expect(
              find.descendant(of: section, matching: find.text(note.sub)),
              findsOneWidget,
            );
            expect(
              find.byWidgetPredicate(
                (w) =>
                    w is Semantics &&
                    w.properties.label ==
                        '$dateLabel: ${note.title}. ${note.sub}',
              ),
              findsOneWidget,
            );
            final paragraph = t.renderObject<RenderParagraph>(date);
            final dateRect = t.getRect(date), titleRect = t.getRect(title);
            if (scale > 1.3) {
              expect(
                paragraph.getBoxesForSelection(
                  TextSelection(baseOffset: 0, extentOffset: dateLabel.length),
                ),
                hasLength(1),
                reason:
                    'the complete enlarged date must be readable on one line',
              );
              expect(
                titleRect.top,
                greaterThanOrEqualTo(dateRect.bottom + 7.9),
              );
              expect(titleRect.left, closeTo(dateRect.left, .1));
            } else {
              expect(titleRect.left, greaterThan(dateRect.right));
              expect(titleRect.top, closeTo(dateRect.top, .1));
            }
          }
          final allText = await readPage(t);
          expect(
            allText,
            containsAll([
              'Milestones',
              'All history',
              'No photos yet',
              '7-DAY AVERAGE',
              '70.6 kg',
            ]),
          );
          expect(find.byTooltip('Add body entry'), findsOneWidget);
          await reveal(t, find.byTooltip('Body settings'));
          expect(find.byTooltip('Body settings'), findsOneWidget);
          for (final entry in before.entries) {
            expect(await t.runAsync(() => db.query(entry.key)), entry.value);
          }
          expect(t.takeException(), isNull);
        },
      );
    }
  }
}

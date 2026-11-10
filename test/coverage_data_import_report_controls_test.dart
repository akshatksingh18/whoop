// Your data uses the shared import router/report. Expensive import/derive calls
// return explicit authored outcomes here; no file leaves the local test store.
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/import/whoop_import.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_onboarding_boundaries_test.dart' show Picker;
import 'coverage_body_history_actions_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class App extends AppState {
  App() : super.forTesting();
  int imports = 0, rebuilds = 0;
  bool refuseImport = false, refuseRebuild = false;
  @override
  Future<int> importWhoopCsvs(
    List<String> paths, {
    void Function(int)? onProgress,
  }) async {
    imports++;
    if (refuseImport) throw StateError('synthetic import refusal');
    lastWhoopImport = WhoopImportResult(1, 2, 3);
    return 1;
  }

  @override
  Future<int> reanalyzeAll() async {
    rebuilds++;
    if (refuseRebuild) throw StateError('synthetic rebuild refusal');
    return 2;
  }
}

void main() {
  late App app;
  late FilePicker previous;
  late Picker picker;
  late File file;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('data-import-report-controls');
    file = await File(
      '${Directory('build/coverage-remainder/cov44-data-import-report-controls').absolute.path}/synthetic-vendor.csv',
    ).writeAsString('Synthetic vendor column\nAuthored row\n');
    FilePicker.platform = Picker();
  });
  setUp(() async {
    await resetCoverageStore();
    app = App();
    previous = FilePicker.platform;
    picker = Picker()
      ..mode = 'ready'
      ..file = file;
    FilePicker.platform = picker;
  });
  tearDown(() {
    app.dispose();
    FilePicker.platform = previous;
  });
  tearDownAll(LocalDb.close);
  for (final mode in [
    'cancel',
    'picker-refused',
    'import-refused',
    'accepted',
  ]) {
    testWidgets(
      'Your data import $mode preserves cancellation, failure and typed partial-result reporting',
      (t) async {
        picker.mode = mode == 'accepted' || mode == 'import-refused'
            ? 'ready'
            : mode;
        app.refuseImport = mode == 'import-refused';
        if (mode == 'accepted') {
          app.importRollupError = 'synthetic retained summary warning';
        }
        await localizedPage(t, const DataScreen(), app: app);
        await flush(t);
        final row = find.byWidgetPredicate(
          (w) => w is SetRow && w.title == 'Import a file',
        );
        await reveal(t, row);
        await invokeControl(t, t.widget<SetRow>(row).onTap);
        await flush(t);
        expect(
          app.imports,
          mode == 'accepted' || mode == 'import-refused' ? 1 : 0,
        );
        if (mode == 'cancel') {
          expect(find.byType(ImportReport), findsNothing);
          expect(find.text('That did not work'), findsNothing);
        } else if (mode == 'picker-refused' || mode == 'import-refused') {
          expect(find.text('That did not work'), findsOneWidget);
          expect(
            find.textContaining(
              mode == 'picker-refused'
                  ? 'synthetic picker refusal'
                  : 'synthetic import refusal',
            ),
            findsOneWidget,
          );
          expect(find.byType(ImportReport), findsNothing);
        } else {
          final report = t.widget<ImportReport>(find.byType(ImportReport)).o;
          expect(report.days, 1);
          expect(report.workouts, 2);
          expect(report.skippedDays, 3);
          expect(report.error, isNull);
          expect(
            find.text('The days landed, the summaries did not'),
            findsOneWidget,
          );
          final warning = find.byWidgetPredicate(
            (w) =>
                w is StatusCard &&
                w.what == 'The days landed, the summaries did not',
          );
          app.refuseRebuild = true;
          await invokeControl(t, t.widget<StatusCard>(warning).onFix);
          expect(app.rebuilds, 1);
          expect(
            find.textContaining('synthetic rebuild refusal'),
            findsOneWidget,
          );
          app.refuseRebuild = false;
          await invokeControl(t, t.widget<StatusCard>(warning).onFix);
          expect(app.rebuilds, 2);
          expect(find.text('2 days re-analyzed.'), findsOneWidget);
          expect(
            report.workouts,
            2,
            reason:
                'A rebuild outcome cannot rewrite the completed import report',
          );
        }
      },
    );
  }
}

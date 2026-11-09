// Actual DataScreen and cadence persistence. Completed backup work is substituted;
// these controls make no encryption,physical keychain or off-device backup claim.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/profile/profile.dart' show SetRow;
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';

class _CompletedBackup extends AppState {
  _CompletedBackup(this.outcome) : super.forTesting() {
    hasBackupPassphrase = true;
  }
  final BackupOutcome outcome;
  int calls = 0;
  @override
  Future<void> refreshBackupPassphraseState() async {
    hasBackupPassphrase = true;
  }

  @override
  Future<BackupOutcome> runBackupNow() async {
    calls++;
    // Model the completed worker/status publication contract. The real
    // setBackupCadence and its transactional preference save run unchanged.
    await Prefs.saveValues({Prefs.backupLastError: outcome.error ?? ''});
    lastBackupWarning = outcome.warning;
    notifyListeners();
    return outcome;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('backup-cadence-feedback');
  });
  setUp(resetCoverageStore);
  tearDownAll(LocalDb.close);
  Future<void> flush(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 15)),
      );
      await t.pump(const Duration(milliseconds: 40));
    }
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final language in ['en', 'es']) {
    for (final result in ['success', 'warning', 'failure', 'off']) {
      testWidgets(
        'COV-67 $language cadence $result preserves result meaning and saved choice',
        (t) async {
          t.view.physicalSize = const Size(430, 1800);
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          final outcome = switch (result) {
            'warning' => const BackupOutcome(
              path: 'authored-valid.osbk',
              warning:
                  'Authored backup published;retention bookkeeping refused',
            ),
            'failure' => const BackupOutcome(
              error: 'Authored destination refused',
            ),
            _ => const BackupOutcome(path: 'authored-valid.osbk'),
          };
          final app = _CompletedBackup(outcome);
          addTearDown(app.dispose);
          await Prefs.saveValues({
            Prefs.backupCadence: result == 'off' ? 'weekly' : 'off',
            'authored-unrelated-choice': 'retain',
          });
          final strings = lookupAppLocalizations(Locale(language));
          await t.pumpWidget(
            ChangeNotifierProvider<AppState>.value(
              value: app,
              child: MaterialApp(
                locale: Locale(language),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                theme: buildTheme(Brightness.light),
                home: const DataScreen(),
              ),
            ),
          );
          await flush(t);
          final row = find.byWidgetPredicate(
            (w) => w is SetRow && w.title == strings.dataHowOften,
          );
          await t.scrollUntilVisible(
            row,
            400,
            scrollable: find.byType(Scrollable).first,
          );
          await t.ensureVisible(row);
          await t.pumpAndSettle();
          await t.tap(row);
          await flush(t);
          expect(
            app.backupCadence,
            result == 'off' ? BackupCadence.off : BackupCadence.daily,
          );
          expect(Prefs.getString('authored-unrelated-choice', ''), 'retain');
          expect(app.calls, result == 'off' ? 0 : 1);
          final feedback = switch (result) {
            'warning' => outcome.warning!,
            'failure' => strings.dataBackupFailed(outcome.error!),
            'success' => 'Automatic backup is on. The first one is written.',
            _ => '',
          };
          if (feedback.isNotEmpty) {
            expect(
              find.text(feedback),
              result == 'warning' ? findsNWidgets(2) : findsOneWidget,
            );
            expect(
              find.text(strings.dataThatDidNotWork),
              result == 'success' ? findsNothing : findsOneWidget,
            );
          } else {
            expect(
              find.text('Automatic backup is on. The first one is written.'),
              findsNothing,
            );
          }
          expect(find.byType(DataScreen), findsOneWidget);
          await t.pumpWidget(const SizedBox());
          await flush(t);
        },
      );
    }
  }
}

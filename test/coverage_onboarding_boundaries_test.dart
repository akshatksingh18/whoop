// Onboarding owns the outcome shown after picker, import and pairing decisions.
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/ui2/onboarding/welcome.dart';
import 'package:whoop_companion/ui2/onboarding/pairing.dart';
import 'package:whoop_companion/ui2/onboarding/profile_setup.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class Picker extends FilePicker {
  String mode = 'cancel';
  File? file;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    expect(allowMultiple, true);
    expect(withReadStream, false);
    if (mode == 'picker-refused') throw StateError('synthetic picker refusal');
    if (mode == 'cancel') return null;
    return FilePickerResult([
      PlatformFile(
        name: 'synthetic.csv',
        path: file!.path,
        size: await file!.length(),
      ),
    ]);
  }
}

class App extends AppState {
  App() : super.forTesting();
  String mode = 'ready';
  int imports = 0, completed = 0, newCalls = 0, scanCalls = 0, pairedCalls = 0;
  @override
  Future<int> importWhoopCsvs(
    List<String> paths, {
    void Function(int)? onProgress,
  }) async {
    imports++;
    if (mode == 'import-refused') throw StateError('synthetic import refusal');
    return 1;
  }

  @override
  Future<void> completeImportOnboard() async {
    completed++;
    if (mode == 'setup-refused') throw StateError('synthetic setup refusal');
  }

  @override
  Future<void> chooseNewUser() async {
    newCalls++;
    if (mode == 'setup-refused') throw StateError('synthetic setup refusal');
  }

  @override
  Future<bool> accessorySetupSupported() async => mode == 'accessory';
  @override
  Future<void> pairViaAccessorySetup({String? serial}) async {
    pairedCalls++;
  }

  @override
  Future<BluetoothDevice?> scanForBand() async {
    scanCalls++;
    if (mode == 'scan-cancelled')
      throw StateError('synthetic picker cancelled');
    if (mode == 'scan-refused') throw StateError('synthetic scanning failed');
    return mode == 'not-found'
        ? null
        : BluetoothDevice.fromId('synthetic-device');
  }

  @override
  Future<void> pairWith(BluetoothDevice device, {String? serial}) async {
    pairedCalls++;
  }
}

void main() {
  late App app;
  late Picker picker;
  late FilePicker original;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('onboarding-boundaries');
    FilePicker.platform = Picker();
  });
  setUp(() async {
    await resetCoverageStore();
    app = App();
    original = FilePicker.platform;
    picker = Picker();
    FilePicker.platform = picker;
    picker.file = await File(
      '${Directory('build/coverage-remainder/cov44-onboarding-boundaries').absolute.path}/synthetic.csv',
    ).writeAsString('Synthetic vendor column\nSynthetic row\n');
  });
  tearDown(() {
    FilePicker.platform = original;
    app.dispose();
  });
  Future<void> flush(WidgetTester t) async {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  }

  for (final mode in [
    'cancel',
    'picker-refused',
    'ready',
    'import-refused',
    'setup-refused',
  ]) {
    testWidgets(
      'COV-47 welcome import $mode reports only work actually accepted',
      (t) async {
        app.mode = mode;
        picker.mode = mode;
        await localizedPage(t, const WelcomeScreen(), app: app);
        final view = t.widget<WelcomeView>(find.byType(WelcomeView));
        await invokeControl(t, view.onImport);
        final current = t.widget<WelcomeView>(find.byType(WelcomeView));
        expect(current.busy, false);
        if (mode == 'cancel') {
          expect(app.imports, 0);
          expect(current.outcome, isNull);
        } else if (mode == 'picker-refused') {
          expect(app.imports, 0);
          expect(current.outcome!.source, 'File picker');
          expect(current.outcome!.error, contains('synthetic picker refusal'));
        } else if (mode == 'import-refused') {
          expect(app.imports, 1);
          expect(app.completed, 0);
          expect(current.outcome!.error, contains('synthetic import refusal'));
        } else {
          expect(app.imports, 1);
          expect(app.completed, 1);
          expect(current.outcome!.days, 1);
          expect(current.outcome!.error, isNull);
          if (mode == 'setup-refused')
            expect(
              find.textContaining(
                'History is imported. Setup could not continue',
              ),
              findsOneWidget,
            );
        }
        await invokeControl(t, current.onNew);
        expect(app.newCalls, 1);
        if (mode == 'setup-refused') {
          await t.pump(const Duration(seconds: 5));
          await t.pumpAndSettle();
          expect(
            find.text('Setup could not continue. Please try again.'),
            findsOneWidget,
          );
        }
      },
    );
  }
  for (final mode in [
    'ready',
    'accessory',
    'not-found',
    'scan-cancelled',
    'scan-refused',
  ]) {
    testWidgets(
      'COV-47 pairing $mode keeps success, cancellation and scan failure distinct',
      (t) async {
        app.mode = mode;
        var skips = 0;
        await localizedPage(t, PairingScreen(onSkip: () => skips++), app: app);
        await invokeControl(
          t,
          t.widget<PairingView>(find.byType(PairingView)).onPair,
        );
        final view = t.widget<PairingView>(find.byType(PairingView));
        expect(view.phase, switch (mode) {
          'ready' || 'accessory' => PairPhase.paired,
          'not-found' => PairPhase.notFound,
          'scan-cancelled' => PairPhase.cancelled,
          _ => PairPhase.failed,
        });
        expect(app.scanCalls, mode == 'accessory' ? 0 : 1);
        expect(app.pairedCalls, mode == 'ready' || mode == 'accessory' ? 1 : 0);
        view.onSkip!();
        expect(skips, 1);
        await flush(t);
      },
    );
  }
  for (final value in ['30.5', '0', '121', 'bad']) {
    testWidgets(
      'COV-47 initial profile rejects unreadable or out-of-range age $value',
      (t) async {
        var saved = 0;
        await localizedPage(
          t,
          ProfileSetupView(
            initial: const {'sex': 'f'},
            onSave: (_) async => saved++,
          ),
        );
        await t.enterText(find.byType(TextField).first, value);
        final button = t.widget<BigButton>(find.byType(BigButton));
        await invokeControl(t, button.onTap);
        expect(saved, 0);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(
          t.widget<TextField>(find.byType(TextField).first).controller!.text,
          value,
        );
      },
    );
  }
}

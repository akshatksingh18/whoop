// Your data actions: real synthetic exports, OS outcomes, cleanup and retries.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/data/lift_log.dart';
import 'package:whoop_companion/data/pushups.dart';
import 'package:whoop_companion/l10n/app_localizations.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/ui2/profile/data.dart';
import 'package:whoop_companion/ui2/ui2.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

class _Share extends SharePlatform {
  var status = ShareResultStatus.success;
  var fail = false;
  int calls = 0;
  Completer<void>? hold;
  List<String> paths = [];
  Map<String, String> textFiles = {};
  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    calls++;
    paths = files.map((x) => x.path).toList();
    for (final f in files) {
      if (!f.path.endsWith('.db'))
        textFiles[f.name] = await File(f.path).readAsString();
      expect(
        await File(f.path).exists(),
        isTrue,
        reason: 'available during native share',
      );
    }
    if (hold != null) await hold!.future;
    if (fail) throw StateError('synthetic share refusal');
    return ShareResult('synthetic', status);
  }
}

class _Picker extends FilePicker {
  File? file;
  bool fail = false;
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
    if (fail) throw StateError('synthetic picker refusal');
    if (file == null) return null;
    return FilePickerResult([
      PlatformFile(
        name: file!.uri.pathSegments.last,
        path: file!.path,
        size: await file!.length(),
      ),
    ]);
  }
}

class _App extends AppState {
  _App() : super.forTesting();
  BackupOutcome outcome = const BackupOutcome(skipped: true);
  int backupCalls = 0;
  int rebuildCalls = 0;
  bool rebuildFails = false;
  bool heightFails = false;
  int heightCalls = 0;
  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    heightCalls++;
    if (heightFails) throw StateError('synthetic height refusal');
    return user = {...?user, ...fields};
  }

  @override
  Future<void> refreshBackupPassphraseState() async {
    hasBackupPassphrase = true;
  }

  @override
  Future<BackupOutcome> runBackupNow() async {
    backupCalls++;
    return outcome;
  }

  @override
  Future<int> reanalyzeAll() async {
    rebuildCalls++;
    if (rebuildFails) throw StateError('synthetic rebuild refusal');
    return 2;
  }
}

Future<void> drain(WidgetTester t) async {
  for (var i = 0; i < 18; i++) {
    await t.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 12)),
    );
    await t.pump(const Duration(milliseconds: 40));
  }
}

Future<void> until(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 60 && !done(); i++) await drain(t);
  expect(done(), isTrue);
  expect(t.takeException(), isNull);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late _Share share;
  late _Picker picker;
  late _App app;
  late SharePlatform previousShare;
  late FilePicker previousPicker;
  setUpAll(() async {
    FilePicker.platform = _Picker();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    root = (await Directory(
      'build/coverage-expansion/data',
    ).create(recursive: true)).absolute;
    PathProviderPlatform.instance = _Paths(root.path);
    LocalDb.dbName = '${root.path}/synthetic.sqlite';
    await LocalDb.close();
    await databaseFactory.deleteDatabase(LocalDb.dbName);
    await LocalDb.instance;
  });
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
    await LocalDb.wipeAll();
    previousShare = SharePlatform.instance;
    previousPicker = FilePicker.platform;
    share = _Share();
    SharePlatform.instance = share;
    picker = _Picker();
    FilePicker.platform = picker;
    app = _App();
    await BodyLogDb.putWeight('2026-01-02', 150, 'lb', historyOnly: true);
    final w = LiftWorkout(
      startedAt: DateTime(2026, 1, 2, 10),
      sessionId: 'synthetic-lift',
    );
    final e = w.addExercise(
      name: 'Synthetic press',
      loadMode: LiftLoadMode.perHand,
    );
    w.addSet(e, reps: 8, load: 20, at: DateTime(2026, 1, 2, 10, 1));
    w.finish(DateTime(2026, 1, 2, 10, 10));
    await LiftLogDb.save(w);
  });
  tearDown(() {
    SharePlatform.instance = previousShare;
    FilePicker.platform = previousPicker;
    app.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(WidgetTester t, {bool localized = false}) async {
    t.view.physicalSize = const Size(700, 2200);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      ChangeNotifierProvider<AppState>.value(
        value: app,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: localized
              ? AppLocalizations.localizationsDelegates
              : null,
          supportedLocales: localized
              ? AppLocalizations.supportedLocales
              : const [Locale('en')],
          theme: buildTheme(Brightness.light),
          home: const DataScreen(),
        ),
      ),
    );
    await drain(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    await t.scrollUntilVisible(
      find.text(label),
      450,
      scrollable: find.byType(Scrollable).first,
    );
    await t.ensureVisible(find.text(label));
    await t.pumpAndSettle();
    await t.tap(find.text(label));
  }

  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await drain(t);
    expect(t.takeException(), isNull);
  }

  for (final label in [
    'Export Body CSV',
    'Export Lift Log',
    'Export Pushups',
  ]) {
    for (final status in ShareResultStatus.values) {
      testWidgets(
        '$label ${status.name} reports the OS outcome and removes temporary files',
        (t) async {
          share.status = status;
          await open(t);
          await tap(t, label);
          await until(
            t,
            () => share.calls == 1 && find.text('Done').evaluate().isNotEmpty,
          );
          final expected = switch (status) {
            ShareResultStatus.success => 'handed to the selected action',
            ShareResultStatus.dismissed => 'Sharing cancelled.',
            ShareResultStatus.unavailable => 'Delivery could not be confirmed.',
          };
          expect(find.textContaining(expected), findsOneWidget);
          for (final path in share.paths)
            expect(await t.runAsync(() => File(path).exists()), isFalse);
          if (label == 'Export Body CSV') {
            expect(share.textFiles.values.single, contains('2026-01-02,150'));
          } else if (label == 'Export Lift Log') {
            final data =
                jsonDecode(
                      share.textFiles.entries
                          .singleWhere((e) => e.key.endsWith('.json'))
                          .value,
                    )
                    as Map;
            expect(data['workouts'], hasLength(1));
            expect(
              share.textFiles.entries
                  .singleWhere((e) => e.key.endsWith('.csv'))
                  .value,
              contains('perHand'),
            );
          } else {
            final data = jsonDecode(share.textFiles.values.single) as Map;
            expect(data['sessions'], isEmpty);
            expect(data['settings']['goal'], await t.runAsync(PushupDb.goal));
          }
          await clean(t);
        },
      );
    }
  }
  testWidgets(
    'share failure is retryable and cleans the failed temporary export',
    (t) async {
      share.fail = true;
      await open(t);
      await tap(t, 'Export Body CSV');
      await until(
        t,
        () => find.text('That did not work').evaluate().isNotEmpty,
      );
      expect(find.textContaining('synthetic share refusal'), findsOneWidget);
      for (final path in share.paths)
        expect(await t.runAsync(() => File(path).exists()), isFalse);
      share.fail = false;
      await tap(t, 'Export Body CSV');
      await until(
        t,
        () => share.calls == 2 && find.text('Done').evaluate().isNotEmpty,
      );
      await clean(t);
    },
  );
  for (final label in [
    'Import a file',
    'Import body history',
    'Import from AkshatOS',
    'Import Pushups from AkshatOS',
  ]) {
    testWidgets(
      '$label cancellation adds nothing and is not reported as failure',
      (t) async {
        await open(t);
        await tap(t, label);
        await drain(t);
        expect(find.text('That did not work'), findsNothing);
        expect(find.text('Done'), findsNothing);
        expect((await t.runAsync(BodyLogDb.weights))!, hasLength(1));
        expect((await t.runAsync(LiftLogDb.finished))!, hasLength(1));
        await clean(t);
      },
    );
  }
  testWidgets(
    'picker refusal explains the failure and a cancellation can retry cleanly',
    (t) async {
      picker.fail = true;
      await open(t);
      await tap(t, 'Import a file');
      await drain(t);
      expect(
        find.textContaining('Could not open the file picker'),
        findsOneWidget,
      );
      picker.fail = false;
      await tap(t, 'Import a file');
      await drain(t);
      expect(find.text('That did not work'), findsNothing);
      await clean(t);
    },
  );
  for (final outcome in [
    const BackupOutcome(path: 'synthetic-valid.osbk'),
    const BackupOutcome(
      path: 'synthetic-valid.osbk',
      warning: 'Synthetic bookkeeping refused',
    ),
    const BackupOutcome(error: 'Synthetic disk refusal'),
    const BackupOutcome(skipped: true),
  ]) {
    testWidgets(
      'backup result ${outcome.path}/${outcome.warning}/${outcome.error} retains its meaning',
      (t) async {
        app.outcome = outcome;
        await open(t);
        await tap(t, 'Back up now');
        await drain(t);
        expect(app.backupCalls, 1);
        expect(
          find.textContaining(
            outcome.warning ??
                outcome.error ??
                (outcome.skipped ? 'Backup skipped.' : 'Backed up to'),
          ),
          findsOneWidget,
        );
        expect(
          find.text('That did not work'),
          findsNWidgets(
            outcome.warning != null || outcome.error != null ? 1 : 0,
          ),
        );
        await clean(t);
      },
    );
  }
  testWidgets('rebuild reports failure then permits another explicit rebuild', (
    t,
  ) async {
    app.rebuildFails = true;
    await open(t);
    await tap(t, 'Re-analyze everything');
    await drain(t);
    expect(find.text('That did not work'), findsOneWidget);
    app.rebuildFails = false;
    await tap(t, 'Re-analyze everything');
    await drain(t);
    expect(app.rebuildCalls, 2);
    expect(find.text('2 days re-analyzed.'), findsOneWidget);
    await clean(t);
  });
  for (final choice in ['Keep mine', 'Use it', 'Use it with refusal']) {
    testWidgets(
      'body-history import preserves provenance and handles height: $choice',
      (t) async {
        app.heightFails = choice.endsWith('refusal');
        picker.file = await t.runAsync(
          () => File('${root.path}/body-history.json').writeAsString(
            jsonEncode({
              'format': 'whoop-body-history',
              'version': 1,
              'source': 'synthetic',
              'heightInches': 68,
              'weights': [
                {
                  'id': 'synthetic-new-weight',
                  'date': '2026-01-03',
                  'value': 152,
                  'unit': 'lb',
                },
              ],
            }),
          ),
        );
        await open(t);
        await tap(t, 'Import body history');
        await until(
          t,
          () => find.text('Import from synthetic?').evaluate().isNotEmpty,
        );
        expect(
          (await t.runAsync(BodyLogDb.weights))!,
          hasLength(1),
          reason: 'review has not imported anything',
        );
        await t.tap(find.text('Import').last);
        await until(
          t,
          () => find.text('Use the Body height?').evaluate().isNotEmpty,
        );
        await t.tap(
          find.text(choice.startsWith('Use') ? 'Use it' : 'Keep mine').last,
        );
        await until(t, () => find.text('Done').evaluate().isNotEmpty);
        final weights = (await t.runAsync(BodyLogDb.weights))!;
        expect(weights, hasLength(2));
        final imported = weights.singleWhere((w) => w.date == '2026-01-03');
        expect(imported.historyOnly, isTrue);
        expect(imported.source, 'synthetic');
        expect(app.heightCalls, choice.startsWith('Use') ? 1 : 0);
        if (app.heightFails)
          expect(
            find.textContaining('height could not be saved'),
            findsOneWidget,
          );
        else if (choice == 'Use it')
          expect(app.user!['height_cm'], 172.7);
        await clean(t);
      },
    );
  }
  for (final error in [false, true]) {
    testWidgets(
      'localized backup ${error ? 'failure' : 'skip'} preserves its actual outcome',
      (t) async {
        app.outcome = error
            ? const BackupOutcome(error: 'Authored disk refusal')
            : const BackupOutcome(skipped: true);
        await open(t, localized: true);
        await tap(t, 'Back up now');
        await drain(t);
        expect(app.backupCalls, 1);
        expect(
          find.text(
            error ? 'Backup failed: Authored disk refusal' : 'Backup skipped.',
          ),
          findsOneWidget,
        );
        expect(find.text('That did not work'), findsNWidgets(error ? 1 : 0));
        expect(await t.runAsync(BodyLogDb.weights), hasLength(1));
        expect(await t.runAsync(LiftLogDb.finished), hasLength(1));
        await clean(t);
      },
    );
  }
  testWidgets(
    'repeating a lift backup without splits leaves the existing workout unchanged',
    (t) async {
      final before = (await t.runAsync(LiftLogDb.finished))!.single.toJson();
      picker.file = await t.runAsync(() async {
        final payload =
            jsonDecode(await exportLiftLogBackup()) as Map<String, dynamic>;
        payload.remove('splits');
        return File(
          '${root.path}/authored-repeat-lift.json',
        ).writeAsString(jsonEncode(payload));
      });
      await open(t, localized: true);
      await tap(t, 'Import from AkshatOS');
      await until(
        t,
        () => find
            .textContaining('Nothing new: 1 already here')
            .evaluate()
            .isNotEmpty,
      );
      expect((await t.runAsync(LiftLogDb.finished))!.single.toJson(), before);
      expect(app.rebuildCalls, 0);
      expect(find.text('Import 1 workouts?'), findsNothing);
      await clean(t);
    },
  );
  for (final conflict in [false, true]) {
    testWidgets(
      'a repeated body day ${conflict ? 'conflict' : 'match'} keeps the saved weight and provenance',
      (t) async {
        final before = await t.runAsync(
          () async => (await LocalDb.instance).query('body_weight'),
        );
        picker.file = await t.runAsync(
          () => File('${root.path}/authored-repeat-body.json').writeAsString(
            jsonEncode({
              'format': 'whoop-body-history',
              'version': 1,
              'source': 'authored',
              'weights': [
                {
                  'id': 'authored-repeated-weight',
                  'date': '2026-01-02',
                  'value': conflict ? 151 : 150,
                  'unit': 'lb',
                },
              ],
            }),
          ),
        );
        await open(t, localized: true);
        await tap(t, 'Import body history');
        await until(
          t,
          () => find.textContaining('Nothing new:').evaluate().isNotEmpty,
        );
        expect(
          find.textContaining(
            conflict
                ? 'different weight and were left alone'
                : '1 already here',
          ),
          findsOneWidget,
        );
        expect(
          await t.runAsync(
            () async => (await LocalDb.instance).query('body_weight'),
          ),
          before,
        );
        expect(app.heightCalls, 0);
        expect(app.rebuildCalls, 0);
        await clean(t);
      },
    );
  }
  for (final accept in [false, true]) {
    testWidgets(
      'lift import review ${accept ? 'commits accepted history and splits' : 'cancels without a write'}',
      (t) async {
        picker.file = await t.runAsync(() async {
          final payload =
              jsonDecode(await exportLiftLogBackup()) as Map<String, dynamic>;
          payload['workouts'][0]['id'] = 'synthetic-imported-lift';
          payload['splits'] = [
            LiftSplit(
              id: 'synthetic-incoming-split',
              name: 'Incoming synthetic split',
            ).toJson(),
          ];
          return File(
            '${root.path}/lift-log.json',
          ).writeAsString(jsonEncode(payload));
        });
        await open(t);
        await tap(t, 'Import from AkshatOS');
        await until(
          t,
          () => find.text('Import 1 workouts?').evaluate().isNotEmpty,
        );
        expect((await t.runAsync(LiftLogDb.finished))!, hasLength(1));
        await t.tap(find.text(accept ? 'Import' : 'Cancel').last);
        if (accept) {
          await until(
            t,
            () => find.text('Use its splits too?').evaluate().isNotEmpty,
          );
          await t.tap(find.text('Use them').last);
          await until(t, () => find.text('Done').evaluate().isNotEmpty);
          expect((await t.runAsync(LiftLogDb.finished))!, hasLength(2));
          expect(
            (await t.runAsync(LiftLogDb.splits))!.single.name,
            'Incoming synthetic split',
          );
          final imported = (await t.runAsync(
            LiftLogDb.finished,
          ))!.singleWhere((w) => w.id == 'synthetic-imported-lift');
          expect(imported.sessionId, isNull);
          expect(imported.exercises.single.loadMode, LiftLoadMode.perHand);
          expect(
            find.textContaining('1 workouts imported. Splits saved.'),
            findsOneWidget,
          );
        } else {
          await drain(t);
          expect((await t.runAsync(LiftLogDb.finished))!, hasLength(1));
          expect(find.text('Done'), findsNothing);
        }
        await clean(t);
      },
    );
  }
  testWidgets(
    'a non-manifest body selection explains the required file without importing',
    (t) async {
      picker.file = await t.runAsync(
        () => File(
          '${root.path}/synthetic-photo.jpg',
        ).writeAsString('synthetic, not an image'),
      );
      await open(t);
      await tap(t, 'Import body history');
      await until(
        t,
        () => find.text('That did not work').evaluate().isNotEmpty,
      );
      expect(find.textContaining('Select body-log.json'), findsOneWidget);
      expect((await t.runAsync(BodyLogDb.weights))!, hasLength(1));
      await clean(t);
    },
  );
  for (final fail in [false, true]) {
    testWidgets(
      'an export finishing after navigation ${fail ? 'failure' : 'success'} cannot use disposed UI',
      (t) async {
        share.hold = Completer<void>();
        share.fail = fail;
        await open(t);
        await tap(t, 'Export Body CSV');
        await until(t, () => share.calls == 1);
        await t.pumpWidget(const SizedBox());
        await t.pump();
        share.hold!.complete();
        await drain(t);
        expect(t.takeException(), isNull);
        for (final path in share.paths)
          expect(await t.runAsync(() => File(path).exists()), isFalse);
      },
    );
  }
}

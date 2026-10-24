// All analysis ranges through the actual Your data picker, report writer and
// temporary-file cleanup. The OS share sheet and pending rebuild are substitutes.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
// ignore: depend_on_referenced_packages
import 'package:share_plus_platform_interface/platform_interface/share_plus_platform.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/analysis_export.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/ui2/profile/data.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart' show SetRow;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'support/audit_visual.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _Repo extends LocalRepository {
  int reads = 0;
  @override
  Future<Map<String, dynamic>> getChart(
    String key, {
    int? from,
    int? to,
  }) async {
    reads++;
    return {};
  }
}

class _Share extends SharePlatform {
  var status = ShareResultStatus.success;
  bool refuse = false;
  final paths = <String>[];
  final reports = <String>[];
  @override
  Future<ShareResult> shareXFiles(
    List<XFile> files, {
    String? subject,
    String? text,
    Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    for (final file in files) {
      expect(await File(file.path).exists(), isTrue);
      paths.add(file.path);
      reports.add(await File(file.path).readAsString());
    }
    if (refuse) throw StateError('synthetic analysis share refusal');
    return ShareResult('synthetic share result', status);
  }
}

class _App extends AppState {
  _App(_Repo source) : super.forTesting() {
    repo = source;
  }
  final pending = Completer<int>();
  int rebuilds = 0;
  @override
  Future<void> refreshBackupPassphraseState() async {}
  @override
  Future<int> reanalyzeAll() {
    rebuilds++;
    return pending.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Repo repo;
  late _App app;
  late _Share share;
  late SharePlatform previousShare;
  setUpAll(() async {
    await loadAuditFonts();
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    final root = (await Directory(
      'build/coverage-remainder/analysis-picker',
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
    DayClock.install([], []);
    repo = _Repo();
    app = _App(repo);
    share = _Share();
    previousShare = SharePlatform.instance;
    SharePlatform.instance = share;
  });
  tearDown(() {
    SharePlatform.instance = previousShare;
    app.dispose();
  });
  tearDownAll(LocalDb.close);

  Future<void> open(WidgetTester t, {double scale = 1}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      RepaintBoundary(
        key: auditCaptureKey,
        child: ChangeNotifierProvider<AppState>.value(
          value: app,
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(
                c,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: w!,
            ),
            home: const DataScreen(),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> action(WidgetTester t, String text) async {
    await t.scrollUntilVisible(
      find.text(text),
      300,
      maxScrolls: 80,
      scrollable: find.byType(Scrollable).first,
    );
    await t.pumpAndSettle();
    await t.tap(find.text(text));
    // The working spinner intentionally remains active until the action returns.
    await t.pump();
    await t.pump(const Duration(milliseconds: 450));
    await t.pump(const Duration(milliseconds: 450));
    expect(t.takeException(), isNull);
  }

  Future<void> drain(WidgetTester t, bool Function() ready) async {
    for (var i = 0; i < 160 && !ready(); i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 8)),
      );
      await t.pump(const Duration(milliseconds: 40));
    }
    expect(ready(), isTrue);
    expect(t.takeException(), isNull);
  }

  Future<void> clean(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    if (!app.pending.isCompleted) app.pending.complete(0);
    await t.pumpAndSettle();
    for (final path in share.paths) {
      expect(await t.runAsync(() => File(path).exists()), isFalse);
      expect(await t.runAsync(() => File(path).parent.exists()), isFalse);
    }
    expect(t.takeException(), isNull);
  }

  Future<void> choose(WidgetTester t, AnalysisRange range) async {
    await t.ensureVisible(find.text(range.label));
    await t.pump(const Duration(milliseconds: 100));
    await t.tap(find.text(range.label));
    await t.pump(const Duration(milliseconds: 400));
    await drain(
      t,
      () =>
          find.text('Done').evaluate().isNotEmpty ||
          find.text('That did not work').evaluate().isNotEmpty,
    );
  }

  for (final scale in [1.0, 2.0, 3.1]) {
    for (final range in AnalysisRange.values) {
      testWidgets(
        'analysis ${range.name} selection exports its exact range at ${scale}x',
        (t) async {
          await open(t, scale: scale);
          await action(t, 'Export for AI analysis');
          expect(share.paths, isEmpty);
          expect(
            repo.reads,
            0,
            reason: 'opening the picker must not generate a report',
          );
          if (range == AnalysisRange.lifetime) {
            await captureWorking(
              t,
              'analysis_picker_$scale',
              find
                  .descendant(
                    of: find.byType(SingleChildScrollView),
                    matching: find.byType(Scrollable),
                  )
                  .last,
            );
          }
          await choose(t, range);
          expect(share.reports, hasLength(1));
          expect(
            share.reports.single,
            startsWith('# WHOOP app data export — ${range.label}'),
          );
          expect(
            find.textContaining('handed to the selected action'),
            findsOneWidget,
          );
          expect(find.text('That did not work'), findsNothing);
          expect(repo.reads, 6);
          await clean(t);
        },
      );
    }
    testWidgets('analysis picker cancellation creates no report at ${scale}x', (
      t,
    ) async {
      await open(t, scale: scale);
      await action(t, 'Export for AI analysis');
      await t.binding.handlePopRoute();
      await t.pumpAndSettle();
      expect(share.paths, isEmpty);
      expect(repo.reads, 0);
      expect(find.text('Working. Keep this screen open.'), findsNothing);
      expect(find.text('That did not work'), findsNothing);
      await clean(t);
    });
    testWidgets(
      'Your data working disclosure wraps and blocks repeat actions at ${scale}x',
      (t) async {
        await open(t, scale: scale);
        await action(t, 'Re-analyze everything');
        expect(app.rebuilds, 1);
        final visibleRows = t.widgetList<SetRow>(find.byType(SetRow)).toList();
        expect(visibleRows, isNotEmpty);
        expect(visibleRows.every((row) => row.onTap == null), isTrue);
        final paragraph = t.renderObject<RenderParagraph>(
          find.text('Working. Keep this screen open.'),
        );
        final text = paragraph.text.toPlainText();
        final tail = paragraph
            .getBoxesForSelection(
              TextSelection(
                baseOffset: text.length - 5,
                extentOffset: text.length,
              ),
            )
            .last;
        expect(tail.right, lessThanOrEqualTo(paragraph.size.width + .5));
        expect(tail.bottom, lessThanOrEqualTo(paragraph.size.height + .5));
        await captureWorking(
          t,
          'data_working_$scale',
          find.byType(Scrollable).first,
        );
        await clean(t);
      },
    );
  }
  for (final status in [
    ShareResultStatus.dismissed,
    ShareResultStatus.unavailable,
  ]) {
    testWidgets(
      'analysis ${status.name} reports an honest share outcome and cleans up',
      (t) async {
        share.status = status;
        await open(t);
        await action(t, 'Export for AI analysis');
        await choose(t, AnalysisRange.twoWeeks);
        expect(
          find.textContaining(
            status == ShareResultStatus.dismissed
                ? 'Sharing cancelled.'
                : 'Delivery could not be confirmed.',
          ),
          findsOneWidget,
        );
        await clean(t);
      },
    );
  }
  testWidgets(
    'analysis share refusal cleans its temporary report and permits retry',
    (t) async {
      share.refuse = true;
      await open(t);
      await action(t, 'Export for AI analysis');
      await choose(t, AnalysisRange.month);
      expect(
        find.textContaining('synthetic analysis share refusal'),
        findsOneWidget,
      );
      for (final path in share.paths)
        expect(await t.runAsync(() => File(path).exists()), isFalse);
      share.refuse = false;
      await action(t, 'Export for AI analysis');
      await choose(t, AnalysisRange.month);
      expect(share.reports, hasLength(2));
      expect(find.text('That did not work'), findsNothing);
      await clean(t);
    },
  );
}

Future<void> captureWorking(WidgetTester t, String name, Finder scroll) async {
  if (!const bool.fromEnvironment('UI_CAPTURE')) return;
  final pos = t.state<ScrollableState>(scroll).position;
  pos.jumpTo(0);
  await t.pump(const Duration(milliseconds: 400));
  await t.pump(const Duration(milliseconds: 400));
  for (var i = 0; i < 60; i++) {
    final boundary = t.renderObject<RenderRepaintBoundary>(
      find.byKey(auditCaptureKey),
    );
    boundary.markNeedsPaint();
    await t.pump();
    await t.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1.5);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final dir = await Directory('build/ui_capture').create(recursive: true);
      await File(
        '${dir.path}/coverage102_${name}_$i.png',
      ).writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
    if (pos.extentAfter < .5) return;
    pos.jumpTo(
      (pos.pixels + pos.viewportDimension * .75).clamp(0, pos.maxScrollExtent),
    );
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
  }
  fail('Full working view not captured');
}

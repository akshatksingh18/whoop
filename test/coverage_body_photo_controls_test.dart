// Authored pixels only: existing picker, date and photo-retention contracts.
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/ui2/screens/progress_screen.dart';
import 'package:whoop_companion/ui2/ui2.dart';
import 'coverage_body_entry_decisions_test.dart' show input;
import 'coverage_body_history_actions_test.dart' show App, flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class PhotoPicker extends FilePicker {
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
    expect(type, FileType.image);
    expect(allowMultiple, isFalse);
    if (file == null) return null;
    return FilePickerResult([
      PlatformFile(
        name: 'authored.png',
        path: file!.path,
        size: await file!.length(),
      ),
    ]);
  }
}

Finder action(String name) =>
    find.byWidgetPredicate((w) => w is Pressable && w.semanticLabel == name);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  final picker = PhotoPicker();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  Uint8List? camera;
  bool refuseCamera = false;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('body-photo-controls');
    FilePicker.platform = picker;
  });
  setUp(() async {
    await resetCoverageStore();
    picker.file = null;
    camera = null;
    refuseCamera = false;
    app = App()..user = {'weight_kg': 70};
    messenger.setMockMethodCallHandler(const MethodChannel('whoop/camera'), (
      _,
    ) async {
      if (refuseCamera) {
        throw PlatformException(
          code: 'synthetic',
          message: 'Synthetic camera refusal',
        );
      }
      return camera;
    });
  });
  tearDown(() {
    messenger.setMockMethodCallHandler(
      const MethodChannel('whoop/camera'),
      null,
    );
    app.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> photos(WidgetTester t) async {
    await localizedPage(
      t,
      const BodyEntryScreen(unit: 'kg', date: '2021-04-06'),
      app: app,
      push: true,
    );
    await flush(t);
    final f = find.text('Photos').first;
    await reveal(t, f);
    await t.tap(f);
    await flush(t);
  }

  Future<void> choose(WidgetTester t, String label) async {
    final f = action(label);
    await reveal(t, f);
    await invokeControl(t, t.widget<Pressable>(f).onTap);
    await flush(t);
  }

  for (final cancelledCamera in [false, true]) {
    testWidgets(
      'cancelled ${cancelledCamera ? 'camera' : 'photo picker'} keeps the draft and no photo row',
      (t) async {
        await photos(t);
        await choose(
          t,
          cancelledCamera ? 'Take a front photo' : 'Choose a front photo',
        );
        expect((await t.runAsync(BodyLogDb.photos))!, isEmpty);
        expect(find.byType(BodyEntryScreen), findsOneWidget);
        expect(app.profileWrites, isEmpty);
        expect(t.widget<BigButton>(find.byType(BigButton)).onTap, isNotNull);
      },
    );
  }
  testWidgets(
    'camera permission refusal stays visible and the draft is editable',
    (t) async {
      refuseCamera = true;
      await photos(t);
      await choose(t, 'Take a side photo');
      expect(find.text('Synthetic camera refusal'), findsOneWidget);
      expect((await t.runAsync(BodyLogDb.photos))!, isEmpty);
      expect(t.widget<BigButton>(find.byType(BigButton)).onTap, isNotNull);
    },
  );
  testWidgets('unreadable picked bytes save no photo and can be retried', (
    t,
  ) async {
    picker.file = await t.runAsync(
      () async => File(
        '${(await BodyLogDb.photoDir()).parent.path}/authored-bad.png',
      ).writeAsBytes([1, 2, 3]),
    );
    await photos(t);
    await choose(t, 'Choose a front photo');
    expect(find.text('That photo could not be added.'), findsOneWidget);
    expect((await t.runAsync(BodyLogDb.photos))!, isEmpty);
    expect(t.widget<BigButton>(find.byType(BigButton)).onTap, isNotNull);
  });
  testWidgets(
    'chosen authored pixels are re-encoded on the worker and belong to the viewed day',
    (t) async {
      final bytes = img.encodePng(img.Image(width: 8, height: 12));
      picker.file = await t.runAsync(
        () async => File(
          '${(await BodyLogDb.photoDir()).parent.path}/authored-good.png',
        ).writeAsBytes(bytes),
      );
      await photos(t);
      await choose(t, 'Choose a side photo');
      final ph = (await t.runAsync(BodyLogDb.photos))!.single;
      expect(ph.date, '2021-04-06');
      expect(ph.pose, 'side');
      final file = (await t.runAsync(() => BodyLogDb.photoFile(ph)))!;
      final saved = img.decodeJpg((await t.runAsync(file.readAsBytes))!);
      expect(saved!.width, 8);
      expect(saved.height, 12);
      expect(find.textContaining('1 for this day'), findsOneWidget);
      expect(find.text('side'), findsOneWidget);
      expect((await t.runAsync(BodyLogDb.weights))!, isEmpty);
      expect(app.profileWrites, isEmpty);
    },
  );
  for (final typed in [false, true]) {
    testWidgets(
      'choosing another date ${typed ? 'keeps typed weight' : 'clears the old loaded weight'}',
      (t) async {
        await BodyLogDb.putWeight('2021-04-06', 70, 'kg');
        await localizedPage(
          t,
          const BodyEntryScreen(unit: 'lb', date: '2021-04-06'),
          app: app,
          push: true,
        );
        await flush(t);
        final field = input('Weight (lb)');
        expect(t.widget<TextField>(field).controller!.text, startsWith('154'));
        if (typed) await t.enterText(field, '160');
        await t.tap(find.text('Change'));
        await t.pumpAndSettle();
        Navigator.of(
          t.element(find.byType(DatePickerDialog)),
        ).pop(DateTime(2021, 4, 5));
        await flush(t);
        expect(t.widget<TextField>(field).controller!.text, typed ? '160' : '');
        expect(find.textContaining('Edit Apr 5'), findsOneWidget);
        expect((await t.runAsync(BodyLogDb.weights))!, hasLength(1));
        expect(app.profileWrites, isEmpty);
      },
    );
  }
  testWidgets(
    'empty comparison is explicit and missing retained files never become fabricated photos',
    (t) async {
      await localizedPage(t, const PhotoCompareScreen(photos: []));
      expect(find.text('No photos yet'), findsOneWidget);
    },
  );
  testWidgets(
    'comparison retains the record and explains a missing file on both panels',
    (t) async {
      final ph = (await t.runAsync(
        () => BodyLogDb.addPhoto(
          img.encodeJpg(img.Image(width: 8, height: 12)),
          date: '2021-04-06',
          pose: 'front',
        ),
      ))!;
      await t.runAsync(() async => (await BodyLogDb.photoFile(ph)).delete());
      await localizedPage(t, PhotoCompareScreen(photos: [ph]));
      await flush(t);
      expect(find.text('File missing'), findsNWidgets(2));
      expect((await t.runAsync(BodyLogDb.photos))!.single.id, ph.id);
      expect(find.byType(PhotoCompareScreen), findsOneWidget);
    },
  );
}

// Real Settings callbacks; only app reset/phone permission and folder refusal are substituted.
// Every file is created under the isolated coverage store, never an installed app folder.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:whoop_companion/data/auto_backup.dart';
import 'package:whoop_companion/data/body_log.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/prefs.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/ui2/profile/gallery.dart';
import 'package:whoop_companion/ui2/profile/settings.dart';
import 'coverage_settings_controls_test.dart' show flush;
import 'support/audit_visual.dart' show loadAuditFonts;
import 'support/coverage_store.dart';
import 'support/localized_coverage.dart';

class Paths extends PathProviderPlatform {
  Paths(this.root);
  final String root;
  bool refuseDocuments = false;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (refuseDocuments) throw StateError('synthetic folder refusal');
    return root;
  }

  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getTemporaryPath() async => root;
}

class App extends AppState {
  App() : super.forTesting();
  int wipes = 0, starts = 0, stops = 0;
  bool refuseReset = true, failFolderAfterReset = false;
  late Paths paths;
  Map<String, dynamic>? profileWrite;
  @override
  Future<void> resetAllData() async {
    wipes++;
    if (refuseReset) throw StateError('synthetic reset refusal');
    await LocalDb.wipeAll();
    if (failFolderAfterReset) paths.refuseDocuments = true;
  }

  @override
  Future<bool> requestPhoneSteps() async {
    starts++;
    phoneStepsEnabled = true;
    notifyListeners();
    return true;
  }

  @override
  Future<void> disablePhoneSteps() async {
    stops++;
    phoneStepsEnabled = false;
    notifyListeners();
  }

  @override
  Future<Map<String, dynamic>> updateProfile(
    Map<String, dynamic> fields,
  ) async {
    profileWrite = {...fields};
    return user = {...?user, ...fields};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late App app;
  late UnitsController units;
  late ThemeController theme;
  late Paths paths;
  late PathProviderPlatform previousPaths;
  late File backup, photo;
  setUpAll(() async {
    await loadAuditFonts();
    await coverageStore('settings-owned-flows');
  });
  setUp(() async {
    await resetCoverageStore();
    previousPaths = PathProviderPlatform.instance;
    final dir = await BodyLogDb.photoDir();
    paths = Paths(dir.parent.path);
    PathProviderPlatform.instance = paths;
    app = App()
      ..paths = paths
      ..user = {
        'name': 'Synthetic',
        'age': 30,
        'sex': 'f',
        'height_cm': 170,
        'weight_kg': 70,
      };
    units = UnitsController.seed(UnitSystem.metric);
    theme = ThemeController.seed(AppThemeChoice.light, Brightness.light);
    PackageInfo.setMockInitialValues(
      appName: 'Authored',
      packageName: 'synthetic.app',
      version: '1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    backup = await File(
      '${(await backupDirectory()).path}/${backupFileName(DateTime(2021, 4, 6))}',
    ).writeAsString('authored file, not a backup');
    photo = await File(
      '${dir.path}/synthetic-photo.jpg',
    ).writeAsString('authored placeholder');
  });
  tearDown(() {
    PathProviderPlatform.instance = previousPaths;
    app.dispose();
    units.dispose();
    theme.dispose();
  });
  tearDownAll(LocalDb.close);
  Future<void> open(
    WidgetTester t, {
    Widget page = const MoreSettings(),
  }) async {
    await localizedPage(
      t,
      ChangeNotifierProvider<UnitsController>.value(value: units, child: page),
      app: app,
      themeController: theme,
      push: true,
    );
    await flush(t);
  }

  MoreSettingsView view(WidgetTester t) =>
      t.widget<MoreSettingsView>(find.byType(MoreSettingsView));
  Future<void> confirm(WidgetTester t) async {
    view(t).onReset!();
    await t.pumpAndSettle();
    await t.tap(find.text('Delete everything'));
    await flush(t);
  }

  testWidgets(
    'seven version taps reveal the real developer controls and can turn them off',
    (t) async {
      await open(t);
      for (var i = 0; i < kDevTaps - 1; i++) {
        view(t).onVersionTap!();
      }
      await t.pumpAndSettle();
      expect(view(t).devMode, isFalse);
      view(t).onVersionTap!();
      await flush(t);
      expect(view(t).devMode, isTrue);
      expect(Prefs.getBool(Prefs.devMode, false), isTrue);
      view(t).onGallery!();
      await t.pumpAndSettle();
      expect(find.byType(GalleryScreen), findsOneWidget);
      Navigator.of(t.element(find.byType(GalleryScreen))).pop();
      await t.pumpAndSettle();
      view(t).onToggleDev!();
      await flush(t);
      expect(view(t).devMode, isFalse);
      expect(Prefs.getBool(Prefs.devMode, false), isFalse);
    },
  );
  testWidgets(
    'appearance cycles independently and the phone-step toggle follows its current state',
    (t) async {
      await open(t);
      for (final want in [
        AppThemeChoice.dark,
        AppThemeChoice.system,
        AppThemeChoice.light,
      ]) {
        await invokeControl(t, view(t).onCycleAppearance);
        expect(theme.choice, want);
      }
      await invokeControl(t, view(t).onTogglePhoneSteps);
      expect(app.starts, 1);
      expect(view(t).phoneSteps, isTrue);
      await invokeControl(t, view(t).onTogglePhoneSteps);
      expect(app.stops, 1);
      expect(view(t).phoneSteps, isFalse);
      expect(units.weightUnit, 'kg');
    },
  );
  testWidgets(
    'profile wrapper sends cleared fields explicitly and returns after saving',
    (t) async {
      await open(t, page: const EditProfile());
      final form = t.widget<EditProfileView>(find.byType(EditProfileView));
      await t.runAsync(() => form.onSave({'age': 31}));
      await t.pumpAndSettle();
      expect(app.profileWrite, {
        'name': null,
        'sex': null,
        'age': 31,
        'height_cm': null,
        'weight_kg': null,
      });
      expect(find.text('Closed test page'), findsOneWidget);
    },
  );
  testWidgets(
    'a refused reset can close without claiming deletion or removing files',
    (t) async {
      await open(t);
      await confirm(t);
      expect(find.text('Retry reset'), findsOneWidget);
      await t.tap(find.text('Close'));
      await flush(t);
      expect(app.wipes, 1);
      expect(find.byType(MoreSettings), findsOneWidget);
      expect((await t.runAsync(backup.exists))!, isTrue);
      expect((await t.runAsync(photo.exists))!, isTrue);
    },
  );
  for (final retryFiles in [false, true]) {
    testWidgets(
      'reset retry keeps folder cleanup honest and ${retryFiles ? 'retries cleanup' : 'can leave refused files'}',
      (t) async {
        await open(t);
        await confirm(t);
        app.refuseReset = false;
        app.failFolderAfterReset = true;
        await t.tap(find.text('Retry reset'));
        await flush(t);
        expect(find.text('Some files were not deleted'), findsOneWidget);
        expect(app.wipes, 2);
        expect((await t.runAsync(backup.exists))!, isTrue);
        if (retryFiles) {
          paths.refuseDocuments = false;
          await t.tap(find.text('Try again'));
        } else {
          await t.tap(find.text('Leave them'));
        }
        await flush(t);
        expect(find.text('Closed test page'), findsOneWidget);
        expect((await t.runAsync(backup.exists))!, !retryFiles);
        expect((await t.runAsync(photo.exists))!, !retryFiles);
      },
    );
  }
}

// Run the real entrypoint through to onboarding with an optional plugin failure.
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/main.dart' as entry;
import 'package:whoop_companion/app.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/state/app_state.dart';
import 'package:whoop_companion/state/units_controller.dart';
import 'package:whoop_companion/state/locale_controller.dart';
import 'package:whoop_companion/theme/theme_controller.dart';
import 'package:whoop_companion/sync/ios_bg_task.dart';
import 'package:whoop_companion/ble/ios_ble_restore.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'cold entry paints onboarding and preserves units when notifications fail',
    (t) async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final root = Directory('build/coverage-audit/cold-boot').absolute
        ..createSync(recursive: true);
      PathProviderPlatform.instance = _Paths(root.path);
      LocalDb.dbName = '${root.path}/synthetic.sqlite';
      await t.runAsync(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(LocalDb.dbName);
        await LocalDb.instance;
      });
      SharedPreferences.setMockInitialValues({
        'body.unit': 'lb',
        'units.distance': 'mi',
      });
      AndroidFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('dexterous.com/flutter/local_notifications'),
            (call) async => throw PlatformException(
              code: 'synthetic_optional_service_unavailable',
            ),
          );
      final prior = FlutterError.onError;
      final asyncPrior = PlatformDispatcher.instance.onError;
      addTearDown(() async {
        FlutterError.onError = prior;
        PlatformDispatcher.instance.onError = asyncPrior;
        IosBgTask.foregroundPull = null;
        IosBleRestore.onWake = null;
        await LocalDb.close();
      });
      await t.runAsync(entry.main);
      await t.pump();
      final context = t.element(find.byType(WhoopApp));
      final app = context.read<AppState>();
      final units = context.read<UnitsController>();
      final theme = context.read<ThemeController>();
      final locale = context.read<LocaleController>();
      for (
        var i = 0;
        i < 150 && !app.initialized && app.initError == null;
        i++
      ) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await t.pump();
      }
      await t.pumpAndSettle();
      expect(app.initialized, isTrue);
      expect(app.route, AppRoute.welcome);
      expect(find.text('Set up my band'), findsOneWidget);
      expect(units.weightUnit, 'lb');
      expect(units.distanceUnit, 'mi');
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      theme.dispose();
      units.dispose();
      locale.dispose();
      await t.runAsync(
        () async => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );
}

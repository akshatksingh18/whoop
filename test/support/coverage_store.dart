// Isolated authored store shared by focused COV-44 component tests.
import 'dart:io';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:whoop_companion/data/day_label.dart';
import 'package:whoop_companion/data/db.dart';
import 'package:whoop_companion/gps/workout_clock.dart';
import 'package:whoop_companion/state/prefs.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

Future<void> coverageStore(String name) async {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  final root = (await Directory(
    'build/coverage-remainder/cov44-$name',
  ).create(recursive: true)).absolute;
  PathProviderPlatform.instance = _Paths(root.path);
  await LocalDb.close();
  LocalDb.dbName = '${root.path}/synthetic.sqlite';
  await databaseFactory.deleteDatabase(LocalDb.dbName);
}

Future<void> resetCoverageStore() async {
  await WorkoutClock.flushWrites();
  WorkoutClock.current = null;
  SharedPreferences.setMockInitialValues({});
  await Prefs.ensureLoaded();
  DayClock.install([], []);
  await LocalDb.wipeAll();
}

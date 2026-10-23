import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:openstrap_edge/platform/error_log.dart';
import 'package:openstrap_edge/sync/file_log.dart';

class _Paths extends PathProviderPlatform {
  var failures = 1;
  @override
  Future<String?> getApplicationDocumentsPath() async {
    if (failures-- > 0)
      throw StateError('synthetic path-provider start failure');
    return (await Directory(
      'build/coverage-audit/error-log',
    ).create(recursive: true)).absolute.path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'a transient log-directory failure does not silence future diagnostics',
    () async {
      PathProviderPlatform.instance = _Paths();
      await FileLog.write('first cannot land');
      await FileLog.write('second recovers');
      final path = await FileLog.path();
      expect(path, isNotNull);
      expect(await File(path!).readAsString(), contains('second recovers'));
    },
  );

  test(
    'error hooks retain logs even when the prior framework handler throws',
    () async {
      PathProviderPlatform.instance = _Paths()..failures = 0;
      final framework = FlutterError.onError;
      final asynchronous = PlatformDispatcher.instance.onError;
      addTearDown(() {
        FlutterError.onError = framework;
        PlatformDispatcher.instance.onError = asynchronous;
      });
      var calls = 0;
      FlutterError.onError = (_) {
        calls++;
        throw StateError('synthetic prior failure');
      };
      PlatformDispatcher.instance.onError = (_, _) {
        calls++;
        return true;
      };
      installErrorLog();
      await FileLog.clear();
      expect(
        () => FlutterError.onError!(
          FlutterErrorDetails(
            exception: StateError('synthetic framework error'),
            library: 'synthetic library',
          ),
        ),
        throwsStateError,
      );
      expect(
        PlatformDispatcher.instance.onError!(
          StateError('synthetic async error'),
          StackTrace.current,
        ),
        isTrue,
      );
      await FileLog.write('barrier');
      final text = await File((await FileLog.path())!).readAsString();
      expect(text, contains('synthetic framework error'));
      expect(text, contains('synthetic async error'));
      expect(calls, 2);
    },
  );
}

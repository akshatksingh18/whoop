// Uncaught errors go to the app log (Settings → Status → app log), and
// nowhere else: nothing leaves the phone.

import 'package:flutter/foundation.dart';

import '../sync/file_log.dart';

String _clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// Write [message] (and its stack) to the app log as one `[error]` entry.
void logError(String message, [Object? stack]) {
  final trace = stack == null ? '' : '\n${_clip('$stack', 4000)}';
  FileLog.write('[error] ${_clip(message, 2000)}$trace');
}

/// Route framework and uncaught async errors to [logError], keeping whatever
/// handler was installed before (the debug console in development).
void installErrorLog() {
  final prior = FlutterError.onError;
  FlutterError.onError = (details) {
    logError(
      '${details.library ?? 'flutter'}: ${details.exceptionAsString()}',
      details.stack,
    );
    prior?.call(details);
  };
  final priorAsync = PlatformDispatcher.instance.onError;
  PlatformDispatcher.instance.onError = (error, stack) {
    logError('$error', stack);
    return priorAsync?.call(error, stack) ?? false;
  };
}

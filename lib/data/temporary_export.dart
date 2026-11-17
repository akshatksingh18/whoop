import 'dart:io';

/// Only newly generated export copies belong here, never source documents.
/// Cleanup runs after the platform finishes, including cancel/error paths.
Future<T> withTemporaryExport<T>(
  List<String> paths,
  Future<T> Function() share,
) async {
  try {
    return await share();
  } finally {
    var failed = false;
    for (final path in paths) {
      try {
        final file = File(path);
        if (await file.exists()) await file.delete();
      } catch (_) {
        failed = true;
      }
    }
    if (failed)
      throw const FileSystemException(
        'Could not remove a temporary export copy.',
      );
  }
}

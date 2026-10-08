// The app log: every line keeps its own wall-clock time, and lines fired
// without awaiting (AppState._log) never overwrite each other. The build-82
// iPhone log had neither: no times, and fragments like "drift=0s)." where
// overlapping appends landed at the same offset.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('file_log_test');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDownAll(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('stamp is local date and time to the millisecond', () {
    expect(
      FileLog.stamp(DateTime(2026, 10, 7, 9, 5, 3, 42)),
      '2026-10-07 09:05:03.042',
    );
  });

  test('unawaited writes all land whole, in order, each stamped', () async {
    await FileLog.clear();
    final lines = [
      for (var i = 0; i < 200; i++)
        i.isEven ? 'short $i' : 'a much longer line $i ${'x' * 120}',
    ];
    final pending = [for (final l in lines) FileLog.write(l)];
    await Future.wait(pending);
    final written = await File((await FileLog.path())!).readAsLines();
    expect(written, hasLength(lines.length));
    final stamped = RegExp(r'^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\.\d{3} (.*)$');
    for (var i = 0; i < lines.length; i++) {
      final m = stamped.firstMatch(written[i]);
      expect(m, isNotNull, reason: written[i]);
      expect(m!.group(1), lines[i]);
    }
  });
}

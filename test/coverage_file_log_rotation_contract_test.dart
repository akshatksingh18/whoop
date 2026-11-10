// Authored files in a fresh test container;real serialized logger,not a mock sink.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:path/path.dart' as p;
import 'package:whoop_companion/migration/legacy_names.dart';
import 'package:whoop_companion/sync/file_log.dart';

class _Paths extends PathProviderPlatform {
  _Paths(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late File live, rotated;
  late String carried;
  late bool legacyRemains;
  const oldText = 'Authored earlier diagnostic evidence\n';
  const bound = 2 * 1024 * 1024;
  setUpAll(() async {
    final parent = await Directory(
      'build/coverage-remainder/file-log-rotation',
    ).create(recursive: true);
    root = (await parent.createTemp('authored-')).absolute;
    PathProviderPlatform.instance = _Paths(root.absolute.path);
    final legacy = File('${root.path}/${LegacyNames.syncLog}');
    await legacy.writeAsString(oldText);
    live = File((await FileLog.path())!);
    carried = await live.readAsString();
    legacyRemains = await legacy.exists();
    rotated = File('${live.path}.1');
  });
  setUp(FileLog.clear);
  tearDown(() async {
    // Only the collision directory and its exact authored leaf belong to this fixture.
    final collision = Directory(rotated.path);
    if (await collision.exists()) {
      expect(p.isWithin(root.path, collision.absolute.path), true);
      await File('${collision.path}/authored-sentinel').delete();
      await collision.delete();
    }
  });
  test(
    'COV-65 cold logger carries legacy evidence before appending with owned name',
    () async {
      expect(carried, oldText);
      expect(legacyRemains, false);
      expect(
        p.normalize(live.path),
        p.normalize(p.join(root.path, 'whoop_sync.log')),
      );
      await live.writeAsString(carried);
      await FileLog.write('authored new event');
      expect(await live.readAsString(), startsWith(oldText));
      expect(await live.readAsString(), contains('authored new event'));
    },
  );
  test(
    'COV-65 bounded rotation retains every serialized message exactly once',
    () async {
      final payload = 'x' * bound;
      await live.writeAsString(payload);
      await rotated.writeAsString('authored previous rotation');
      final messages = [
        for (var i = 0; i < 129; i++) 'authored-rotation-event-$i-END',
      ];
      await Future.wait([
        for (final message in messages) FileLog.write(message),
      ]);
      final old = await rotated.readAsString();
      final current = await live.readAsString();
      expect(old, startsWith(payload));
      expect(old, isNot(contains('authored previous rotation')));
      expect(current, isNot(startsWith(payload)));
      for (final message in messages) {
        expect(
          RegExp(RegExp.escape(message)).allMatches('$old\n$current'),
          hasLength(1),
        );
      }
      expect(current.length, lessThan(bound));
    },
  );
  test(
    'COV-65 refused rotation preserves both existing evidence and new messages',
    () async {
      final payload = 'y' * bound;
      await live.writeAsString(payload);
      final collision = await Directory(rotated.path).create();
      final sentinel = File('${collision.path}/authored-sentinel');
      await sentinel.writeAsString('authored other evidence');
      final messages = [
        for (var i = 0; i < 129; i++) 'authored-refused-rotation-$i-END',
      ];
      await Future.wait([
        for (final message in messages) FileLog.write(message),
      ]);
      final current = await live.readAsString();
      expect(current, startsWith(payload));
      expect(await sentinel.readAsString(), 'authored other evidence');
      for (final message in messages) {
        expect(
          RegExp(RegExp.escape(message)).allMatches(current),
          hasLength(1),
        );
      }
    },
  );
  test(
    'COV-65 queued clear removes prior rotations and retains later writes',
    () async {
      await FileLog.write('authored before clear');
      await rotated.writeAsString('authored older bounded log');
      final cleared = FileLog.clear();
      final appended = FileLog.write('authored after clear');
      await Future.wait([cleared, appended]);
      final current = await live.readAsString();
      expect(current, contains('authored after clear'));
      expect(current, isNot(contains('authored before clear')));
      expect(await rotated.exists(), false);
      expect(await FileLog.path(), live.path);
    },
  );
}

// Retained local notification wording; a tap must not substitute newer evidence.
import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../data/calculation_store.dart';
import '../data/db.dart';

class NotificationReport {
  static const prefix = 'notification.report.';
  static Future<String> save(String title, String body, String day) async {
    final id =
        '$day-${sha256.convert(utf8.encode('$title\n$body')).toString().substring(0, 16)}';
    await CalculationStore.write(
      '$prefix$id',
      jsonEncode({'title': title, 'body': body, 'day': day}),
    );
    final keys = await (await LocalDb.instance).query(
      'baselines',
      columns: ['key'],
      where: 'key LIKE ?',
      whereArgs: ['calculation:$prefix%'],
      orderBy: 'key DESC',
    );
    for (final r in keys.skip(32)) {
      await CalculationStore.remove(
        (r['key'] as String).substring(CalculationStore.prefix.length),
      );
    }
    return id;
  }

  static Future<Map<String, dynamic>?> read(String id) async {
    final value = await CalculationStore.read('$prefix$id');
    return value == null
        ? null
        : (jsonDecode(value) as Map).cast<String, dynamic>();
  }
}

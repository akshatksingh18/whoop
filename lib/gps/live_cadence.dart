import 'package:flutter/services.dart';

/// Phone cadence is a measured rate, not steps inferred from GPS speed.
class CadenceReading {
  final double spm;
  final DateTime at;
  const CadenceReading(this.spm, this.at);
  static CadenceReading? fromMap(Map data) {
    final rate = data['stepsPerSecond'], ms = data['atMs'];
    if (rate is! num ||
        ms is! num ||
        !rate.isFinite ||
        rate < 0 ||
        rate > 5 ||
        !ms.isFinite ||
        ms.abs() > 8640000000000000)
      return null;
    return CadenceReading(
      rate.toDouble() * 60,
      DateTime.fromMillisecondsSinceEpoch(ms.toInt()),
    );
  }

  bool fresh(DateTime now) {
    final age = now.difference(at).inMilliseconds;
    return age >= -2000 && age <= 20000;
  }
}

class PhoneCadence {
  static const _channel = MethodChannel('openstrap/phone_cadence');
  int _generation = 0;
  bool _listening = false;
  CadenceReading? reading;
  Future<void> start(void Function() changed) async {
    final token = ++_generation;
    _listening = true;
    reading = null;
    _channel.setMethodCallHandler((call) async {
      if (token != _generation || call.method != 'cadence') return;
      final args = call.arguments;
      if (args is! Map || args['generation'] != token) return;
      reading = CadenceReading.fromMap(args);
      changed();
    });
    try {
      await _channel.invokeMethod('start', {'generation': token});
    } on MissingPluginException {
      /* Other platforms retain wrist fallback. */
    } on PlatformException {
      /* Missing sensor/permission is unknown. */
    }
  }

  void stop() {
    _generation++;
    reading = null;
    if (!_listening) return;
    _listening = false;
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('stop').catchError((Object _) {});
  }
}

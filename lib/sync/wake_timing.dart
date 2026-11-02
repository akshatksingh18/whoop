import 'dart:async';
import 'file_log.dart';

/// Local diagnostics only. Never awaited by transfer/commit/ACK decisions.
class WakeTiming {
  WakeTiming(this.reason, {void Function(String)? log})
    : _log = log ?? _fileLog,
      id = '${DateTime.now().microsecondsSinceEpoch}-${_next++}' {
    event('start');
  }
  static int _next = 0;
  static final Object _zoneKey = Object();
  static final Set<WakeTiming> _active = {};
  final String reason, id;
  final void Function(String) _log;
  final Stopwatch _clock = Stopwatch()..start();
  bool _finished = false;
  int _committedRecords = 0;
  static void _fileLog(String line) {
    unawaited(FileLog.write(line));
  }

  static WakeTiming? get current {
    final t = Zone.current[_zoneKey] as WakeTiming?;
    return t?._finished == false ? t : null;
  }

  // BLE subscriptions can predate a wake's async zone. Attribute only when
  // there is exactly one active wake; ambiguous attribution stays absent.
  static WakeTiming? get forTransfer =>
      current ?? (_active.length == 1 ? _active.single : null);

  static Future<T> run<T>(
    String reason,
    Future<T> Function() action, {
    void Function(String)? log,
  }) async {
    if (current != null) return action();
    final t = WakeTiming(reason, log: log);
    _active.add(t);
    try {
      return await runZoned(action, zoneValues: {_zoneKey: t});
    } finally {
      t.event('end');
      t._finished = true;
      t._clock.stop();
      _active.remove(t);
    }
  }

  static void expire(Set<String> reasons) {
    for (final t in _active.where((t) => reasons.contains(t.reason))) {
      t.event('expiry');
    }
  }

  void event(String stage, {int? records, int? connectionRecords}) {
    if (_finished) return;
    if (stage == 'commit') _committedRecords += records ?? 0;
    try {
      _log(
        '[WAKE] id=$id reason=$reason stage=$stage '
        'at_ms=${DateTime.now().millisecondsSinceEpoch} elapsed_ms=${_clock.elapsedMilliseconds}'
        ' committed_records=$_committedRecords'
        '${records == null ? '' : ' records=$records'}'
        '${connectionRecords == null ? '' : ' connection_records_total=$connectionRecords'}',
      );
    } catch (_) {
      /* Diagnostics cannot change durable sync decisions. */
    }
  }
}

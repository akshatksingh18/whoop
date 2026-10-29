import 'dart:convert';

/// Bounded, process-local reuse of pure calculations. Fingerprinting and all
/// lookups run inside the cancellable worker, never on the UI isolate. Nothing
/// here skips persistence, finalization, live activity or baseline evaluation.
class InputReuse {
  final int version;
  final _entries = <String, ({String stamp, Object? value})>{};
  int hits = 0;
  int misses = 0;

  InputReuse(this.version);

  String stamp(Object inputs) => jsonEncode([version, inputs]);

  T get<T>(String key, String stamp, T Function() calculate) {
    final entry = _entries[key];
    if (entry != null && entry.stamp == stamp && entry.value is T) {
      hits++;
      return entry.value as T;
    }
    // Failed computations never displace the last completed result.
    final value = calculate();
    misses++;
    _entries[key] = (stamp: stamp, value: value);
    return value;
  }
}

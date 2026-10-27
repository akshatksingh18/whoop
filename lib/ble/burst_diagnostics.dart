/// Observed timestamp continuity, not proof that a missing interval was lost.
/// Count semantics remain advisory on generations without a confirmed gate.
class BurstDiagnostics {
  (int, int)? _previous;
  int _number = 0;
  String observe({
    required int? announced,
    required int traffic,
    required int historical,
    required int records,
    required (int, int)? range,
  }) {
    final before = _previous;
    _previous = range;
    final delta = before == null || range == null ? null : range.$1 - before.$2;
    final continuity = delta == null
        ? 'unknown'
        : delta == 1
        ? 'contiguous'
        : delta <= 0
        ? 'overlap_or_replay'
        : 'gap';
    return '[BURST] n=${++_number} announced=${announced ?? 'unknown'} '
        'received_traffic=$traffic received_historical=$historical records=$records '
        'first_ts=${range?.$1 ?? 'unknown'} last_ts=${range?.$2 ?? 'unknown'} '
        'previous_last_ts=${before?.$2 ?? 'unknown'} '
        'delta_sec=${delta ?? 'unknown'} continuity=$continuity';
  }
}

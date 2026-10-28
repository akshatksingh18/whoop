import 'dart:async';

enum BandOwnerKind { foreground, headless }

class BandLease {
  BandLease._(this.kind, this.token);

  final BandOwnerKind kind;
  final int token;
}

/// Process-local guard so only one BLE session owns the band at a time.
///
/// Foreground is authoritative: once the UI intends to connect, new headless
/// work must back off.
class BandOwnership {
  BandOwnership._();

  static BandOwnerKind? _owner;
  static int? _token;
  static int _nextToken = 1;
  static bool _foregroundIntent = false;
  static Completer<void>? _released;

  /// How the running headless drain is asked to let go (B88-05). Set by
  /// that drain for the life of its lease; null when none is running.
  static void Function(String reason)? _headlessStop;
  static int? _headlessStopToken;

  static BandOwnerKind? get owner => _owner;
  static bool get foregroundIntent => _foregroundIntent;
  static String get debugState =>
      'owner=${_owner?.name ?? "none"} token=${_token ?? "-"} '
      'foregroundIntent=$_foregroundIntent';

  static void markForegroundIntent(bool active) {
    _foregroundIntent = active;
  }

  /// The running headless drain registers how to stop it. A stop
  /// disconnects; whatever was committed stays, nothing uncommitted is ACKed,
  /// and the next connect resumes from the band's cursor.
  static void registerHeadlessStop(
    BandLease lease,
    void Function(String reason) stop,
  ) {
    if (lease.kind != BandOwnerKind.headless || _token != lease.token) return;
    _headlessStop = stop;
    _headlessStopToken = lease.token;
  }

  /// Ask the running headless drain, if any, to stop now. Used when the app
  /// comes to the foreground and when iOS expires a background task.
  static void requestHeadlessStop(String reason) {
    final stop = _headlessStop;
    if (stop == null || _owner != BandOwnerKind.headless) return;
    if (_token != _headlessStopToken) return;
    stop(reason);
  }

  /// B88-05: the foreground no longer waits without limit for a headless
  /// drain that can run 600 s. It asks the drain to stop, waits at most
  /// [deadline] for its own release, then force-clears the headless owner
  /// (the engine's single-owner claim lets the foreground preempt it).
  static Future<BandLease> acquireForeground({
    Duration poll = const Duration(milliseconds: 50),
    Duration deadline = const Duration(seconds: 20),
  }) async {
    _foregroundIntent = true;
    if (_owner == BandOwnerKind.headless) {
      requestHeadlessStop('foreground_acquire');
    }
    final until = DateTime.now().add(deadline);
    while (_owner != null && _owner != BandOwnerKind.foreground) {
      final left = until.difference(DateTime.now());
      if (left <= Duration.zero) {
        forceReleaseHeadless();
        break;
      }
      try {
        await (_released ??= Completer<void>()).future.timeout(left);
      } on TimeoutException {
        continue;
      }
      await Future<void>.delayed(poll);
    }
    if (_owner == BandOwnerKind.foreground && _token != null) {
      return BandLease._(BandOwnerKind.foreground, _token!);
    }
    final lease = BandLease._(BandOwnerKind.foreground, _nextToken++);
    _owner = lease.kind;
    _token = lease.token;
    return lease;
  }

  static BandLease? tryAcquireHeadless() {
    if (_foregroundIntent || _owner != null) return null;
    final lease = BandLease._(BandOwnerKind.headless, _nextToken++);
    _owner = lease.kind;
    _token = lease.token;
    return lease;
  }

  static void release(BandLease lease) {
    if (_token != lease.token || _owner != lease.kind) return;
    _owner = null;
    _token = null;
    _headlessStop = null;
    _headlessStopToken = null;
    final released = _released;
    _released = null;
    released?.complete();
  }

  /// Force-clears a headless owner whose run was abandoned by
  /// HeadlessSyncGate.runCeiling rather than released by its own `finally`.
  ///
  /// `release()` requires the caller's own lease token, but the three iOS
  /// gate entry points (ios_ble_restore.dart, ios_bg_task.dart) call
  /// `runHeadlessSync()` with no lease argument, so it self-acquires one
  /// internally and only that orphaned call frame ever sees the token. If
  /// that frame is truly wedged (not just slow), nothing else can present
  /// the matching token to `release()` — the band stays headless-owned for
  /// the rest of the process, and `acquireForeground()`'s wait loop would
  /// spin forever waiting on `_released`, which nothing left alive can ever
  /// complete. Only clears a headless owner — never touches a
  /// foreground-owned lease, since only headless work runs through the gate.
  static void forceReleaseHeadless() {
    if (_owner != BandOwnerKind.headless) return;
    _owner = null;
    _token = null;
    _headlessStop = null;
    _headlessStopToken = null;
    final released = _released;
    _released = null;
    released?.complete();
  }

  static void resetForTest() {
    _owner = null;
    _token = null;
    _nextToken = 1;
    _foregroundIntent = false;
    _released = null;
    _headlessStop = null;
    _headlessStopToken = null;
  }
}

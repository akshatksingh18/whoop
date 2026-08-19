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

  static BandOwnerKind? get owner => _owner;
  static bool get foregroundIntent => _foregroundIntent;
  static String get debugState =>
      'owner=${_owner?.name ?? "none"} token=${_token ?? "-"} '
      'foregroundIntent=$_foregroundIntent';

  static void markForegroundIntent(bool active) {
    _foregroundIntent = active;
  }

  static Future<BandLease> acquireForeground({
    Duration poll = const Duration(milliseconds: 50),
  }) async {
    _foregroundIntent = true;
    while (_owner != null && _owner != BandOwnerKind.foreground) {
      await (_released ??= Completer<void>()).future;
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
  }
}

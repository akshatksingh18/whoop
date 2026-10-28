// Status — the few facts that decide whether this install keeps working.
//
// The personal sideload lives on a seven-day signature, a band that has to be
// drained, and backups that only exist if they actually ran. None of those is
// a health metric, and all of them used to be invisible from the phone. One
// screen, plain words, no numbers that need a legend.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../data/db.dart' show LocalDb;
import '../../data/auto_backup.dart' show BackupCadence;
import '../../state/app_state.dart';
import '../ui2.dart';
import 'data.dart';
import 'profile.dart';

/// The commit this binary was built from, injected by the personal iOS
/// workflow (`SOURCE_REVISION` in its `.env`). Empty for a local build.
const String kSourceRevision = String.fromEnvironment('SOURCE_REVISION');

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> with RevisionReload {
  String _version = '';

  /// B88-12 (C5): last background wake, transfer and calculation.
  ({
    int? wakeAt,
    String? wakeSource,
    int? transferAt,
    String? transferStatus,
    int? calculatedAt,
  })?
  _health;
  bool _healthFailed = false;

  /// Build 94 (Codex N19): the panel is re-read whenever durable data moves
  /// (a transfer, a calculation), on return to the app and when newer band
  /// data arrives, so it never describes an older operation than the
  /// "Newest band data" row below it.
  DateTime? _healthAtRecord;
  late final AppLifecycleListener _life;

  @override
  void reload() => _readHealth();

  Future<void> _readHealth() async {
    final t = beginRead(#health);
    try {
      final h = await LocalDb.syncHealth();
      if (stillNewest(#health, t)) {
        setState(() => (_health = h, _healthFailed = false));
      }
    } catch (_) {
      if (stillNewest(#health, t)) setState(() => _healthFailed = true);
    }
  }

  @override
  void dispose() {
    _life.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    // Re-read on open, not only on resume: this is the screen a warning lands
    // on, and it must show the profile as it is now.
    app.refreshSigningStatus();
    app.refreshBackupPassphraseState();
    _life = AppLifecycleListener(onResume: _readHealth);
    _healthAtRecord = app.lastRecordAt;
    _readHealth();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = '${i.version} (${i.buildNumber})');
    }, onError: (_) {});
  }

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final p = P.of(c);
    final now = DateTime.now();
    final expiry = app.signingExpiry;
    final left = expiry?.difference(now);
    final newestAt = app.lastRecordAt;
    if (newestAt != _healthAtRecord) {
      _healthAtRecord = newestAt;
      WidgetsBinding.instance.addPostFrameCallback((_) => _readHealth());
    }
    final backupErr = app.lastBackupError;
    final backupOn = app.backupCadence != BackupCadence.off;

    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: S.x4),
              child: NavBar('Status'),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
                children: [
                  if (left != null && left.inHours < 48) ...[
                    StatusCard(
                      left.isNegative
                          ? 'Signing has expired'
                          : 'Signing ends in ${_span(left)}',
                      'Refresh WHOOP with Sideloadly on your PC — over Wi-Fi, or '
                      'with the USB cable if the phone is not found. Install '
                      'over the existing app; do not delete it first.',
                      icon: LucideIcons.triangleAlert,
                    ),
                    const SizedBox(height: S.x5),
                  ],
                  settingsGroup(c, 'This install', [
                    SetRow(
                      LucideIcons.badgeCheck,
                      C.green,
                      'App signing',
                      sub: expiry == null
                          ? 'Could not read the installed signing profile'
                          : 'Until ${_stamp(expiry)}. You get a '
                                'reminder 48 and 24 hours before it ends',
                      value: left == null
                          ? ''
                          : left.isNegative
                          ? 'Expired'
                          : _span(left),
                      chevron: false,
                    ),
                    SetRow(
                      LucideIcons.info,
                      C.n500,
                      'Version',
                      value: _version,
                      chevron: false,
                    ),
                    SetRow(
                      LucideIcons.gitCommitHorizontal,
                      C.n500,
                      'Source',
                      sub: kSourceRevision.isEmpty
                          ? 'Not recorded — a local build'
                          : kSourceRevision,
                      value: kSourceRevision.isEmpty
                          ? ''
                          : kSourceRevision.substring(
                              0,
                              kSourceRevision.length.clamp(0, 7),
                            ),
                      chevron: false,
                    ),
                  ]),
                  if (_healthFailed && _health == null) ...[
                    const SizedBox(height: S.x5),
                    StatusCard(
                      'Sync health could not be read',
                      'Your band data is intact.',
                      fix: 'Retry',
                      onFix: _readHealth,
                    ),
                  ],
                  if (_health case final h?) ...[
                    const SizedBox(height: S.x5),
                    settingsGroup(c, 'Sync health', [
                      for (final (icon, title, at, what) in [
                        (
                          LucideIcons.alarmClock,
                          'Last background wake',
                          h.wakeAt,
                          switch (h.wakeSource) {
                            'ble_restore' => 'Band came back in range',
                            'bg_refresh' => 'iOS background refresh',
                            'bg_task' => 'iOS background task',
                            null => null,
                            final s => s,
                          },
                        ),
                        (
                          LucideIcons.arrowDownToLine,
                          'Last band transfer',
                          h.transferAt,
                          switch (h.transferStatus) {
                            'complete' => 'Finished',
                            'partial' => 'Stopped part way',
                            'idle' => 'Nothing new to send',
                            null => null,
                            final s => s,
                          },
                        ),
                        (
                          LucideIcons.calculator,
                          'Last calculation',
                          h.calculatedAt,
                          null,
                        ),
                      ])
                        SetRow(
                          icon,
                          C.n500,
                          title,
                          sub: at == null
                              ? 'Not yet'
                              : [
                                  _stamp(
                                    DateTime.fromMillisecondsSinceEpoch(at),
                                  ),
                                  ?what,
                                ].join(' · '),
                          value: at == null
                              ? ''
                              : '${_span(now.difference(DateTime.fromMillisecondsSinceEpoch(at)))} ago',
                          chevron: false,
                        ),
                    ]),
                  ],
                  const SizedBox(height: S.x5),
                  settingsGroup(c, 'Your data', [
                    SetRow(
                      LucideIcons.bluetooth,
                      C.blue,
                      'Newest band data',
                      sub: newestAt == null
                          ? 'Nothing synced from the band yet'
                          : _stamp(newestAt),
                      value: newestAt == null
                          ? ''
                          : '${_span(now.difference(newestAt))} ago',
                      chevron: false,
                    ),
                    SetRow(
                      LucideIcons.hardDriveDownload,
                      C.purple,
                      'Automatic backup',
                      sub: !backupOn
                          ? 'Off — turn it on in Your data'
                          : backupErr != null
                          ? 'The last attempt failed: $backupErr'
                          : app.lastBackupAt == null
                          ? 'No backup written yet'
                          : 'Last one ${_stamp(app.lastBackupAt!)}. '
                                'Encrypted, kept on this phone only',
                      value: backupOn ? app.backupCadence.label : 'Off',
                      onTap: () => goto(c, const DataScreen()),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "3 d 4 h", "5 h", "12 min" — the one unit that matters at that range.
String _span(Duration d) {
  final a = d.abs();
  if (a.inDays >= 1) {
    final h = a.inHours % 24;
    return h == 0 ? '${a.inDays} d' : '${a.inDays} d $h h';
  }
  if (a.inHours >= 1) return '${a.inHours} h';
  return '${a.inMinutes} min';
}

String _stamp(DateTime t) {
  final l = t.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)} ${formatClock(l)}';
}

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

import '../../build_profile.dart';
import '../../data/auto_backup.dart' show BackupCadence;
import '../../live/live_activity.dart';
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

class _StatusScreenState extends State<StatusScreen> {
  String _version = '';
  Map<String, Object?> _la = const {};
  bool _testing = false;

  Future<void> _readLa() async {
    final s = await LiveActivity.status();
    if (mounted) setState(() => _la = s);
  }

  Future<void> _testLa() async {
    if (_testing) return;
    setState(() => _testing = true);
    final s = await LiveActivity.test();
    if (!mounted) return;
    setState(() => (_la = s, _testing = false));
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          s['ok'] == true
              ? 'Started. Lock the phone: a sample shows for one minute.'
              : 'Not shown: ${laReason(s)}',
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    final app = context.read<AppState>();
    // Re-read on open, not only on resume: this is the screen a warning lands
    // on, and it must show the profile as it is now.
    app.refreshSigningStatus();
    app.refreshBackupPassphraseState();
    _readLa();
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
    final newest = app.lastSynced?.tsEpoch;
    final newestAt = newest == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(newest * 1000);
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
                      sub: switch ((kPersonalSideload, expiry)) {
                        (false, _) => 'Only tracked on the sideloaded build',
                        (true, null) =>
                          'Could not read the installed signing profile',
                        (true, final e?) =>
                          'Until ${_stamp(e)}. You get a '
                              'reminder 48 and 24 hours before it ends',
                      },
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
                  if (_la.isNotEmpty) ...[
                    const SizedBox(height: S.x5),
                    settingsGroup(c, 'Lock screen', [
                      SetRow(
                        LucideIcons.lockKeyhole,
                        C.green,
                        'Live Activity',
                        sub: _testing
                            ? 'Starting a sample…'
                            : '${laReason(_la)}. Tap to show a one-minute sample',
                        value: _la['enabled'] == true ? 'On' : 'Off',
                        onTap: _testLa,
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
  return '${l.year}-${two(l.month)}-${two(l.day)} ${two(l.hour)}:${two(l.minute)}';
}

/// The bridge's status in one line: the first thing that stops the lock-screen
/// card, or the last outcome when nothing does.
String laReason(Map<String, Object?> s) {
  if (s['enabled'] == false) {
    return 'Off for WHOOP: Settings → WHOOP → Live Activities';
  }
  if (s['extensionOk'] == false) {
    final ext = (s['extensions'] as List?)?.join(', ') ?? '';
    return ext.isEmpty
        ? 'The lock-screen extension is missing from this install'
        : 'The extension is installed as $ext, not under ${s['app']}';
  }
  final r = s['reason']?.toString() ?? '';
  return r.isEmpty ? 'Ready' : '${r[0].toUpperCase()}${r.substring(1)}';
}

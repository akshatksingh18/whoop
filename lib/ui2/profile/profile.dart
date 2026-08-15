// Profile.
//
// Reached from the Home avatar, never a sixth tab — the shell has five
// destinations and the type system says so.
//
// The reference design had a Premium badge and a Following/Followers pair.
// Both are gone, and not for lack of screen space: there is no account and no
// social graph, so a follower count would have to be invented and a premium
// tier would have to be sold. What replaces them is what this app actually
// knows — how much it has measured, and from what.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../ui2.dart';
import 'devices.dart';
import 'settings.dart';

// ══════════════════ shared list furniture ══════════════════

/// One row in a settings list. Shared by all three profile screens.
class SetRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub, value;
  final bool danger, chevron;
  final VoidCallback? onTap;

  const SetRow(this.icon, this.color, this.title,
      {super.key,
      this.sub = '',
      this.value = '',
      this.danger = false,
      this.chevron = true,
      this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final accent = danger ? C.red : color;
    return Pressable(
      onTap: onTap,
      semanticLabel: sub.isEmpty ? title : '$title. $sub',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: p.wash(accent), borderRadius: R.rSm),
            child: Icon(icon, size: 16, color: p.on(accent)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title,
                  style: F.body.copyWith(color: danger ? p.on(C.red) : p.ink)),
              if (sub.isNotEmpty)
                Text(sub, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          if (value.isNotEmpty) ...[
            const SizedBox(width: S.x2),
            Text(value, style: F.cap.copyWith(color: p.ink3)),
          ],
          if (chevron && !danger) ...[
            const SizedBox(width: S.x2),
            Icon(LucideIcons.chevronRight, size: 17, color: p.ink3),
          ],
        ]),
      ),
    );
  }
}

/// A titled card of [SetRow]s, hairline-separated.
Widget settingsGroup(BuildContext c, String title, List<Widget> rows) {
  final p = P.of(c);
  return Section(
    title,
    Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1) Divider(color: p.line, height: 1),
        ],
      ]),
    ),
  );
}

/// Push a screen, keeping the enclosing domain accent.
void goto(BuildContext c, Widget w) =>
    Navigator.of(c).push(MaterialPageRoute<void>(builder: (_) => w));

/// The one way into the profile stack. Home's avatar calls this — profile is
/// a pushed route, never a sixth tab.
void openProfile(BuildContext c) => goto(c, const ProfileHome());

/// Human-readable byte size. No dependency for four lines of arithmetic.
String formatBytes(int b) {
  if (b < 1024) return '$b B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var v = b / 1024;
  var i = 0;
  while (v >= 1024 && i < units.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v < 10 ? v.toStringAsFixed(1) : v.round()} ${units[i]}';
}

// ══════════════════ 1 · PROFILE HOME ══════════════════

/// Everything the profile header can honestly count.
class ProfileStats {
  final String? name;
  final int workouts, records, days, sources, sessions;
  final int? storageBytes;

  const ProfileStats({
    this.name,
    this.workouts = 0,
    this.records = 0,
    this.days = 0,
    this.sources = 0,
    this.sessions = 0,
    this.storageBytes,
  });
}

class ProfileHome extends StatefulWidget {
  const ProfileHome({super.key});

  @override
  State<ProfileHome> createState() => _ProfileHomeState();
}

class _ProfileHomeState extends State<ProfileHome> {
  late final Future<ProfileStats> _stats = _load();

  Future<ProfileStats> _load() async {
    final app = context.read<AppState>();
    final repo = app.repo;
    final sources = liveSources(app).length;
    if (repo == null) {
      return ProfileStats(
          name: app.user?['name'] as String?, sources: sources);
    }
    final records = await repo.getRecords();
    final year = await repo.getWorkouts(range: 'year');
    final bytes = await app.dataFileBytes();
    return ProfileStats(
      name: app.user?['name'] as String?,
      workouts: (records['workouts_tracked'] as num?)?.toInt() ?? 0,
      records: (records['records'] as List?)?.length ?? 0,
      days: (records['days_tracked'] as num?)?.toInt() ?? 0,
      sessions: ((year['summary'] as Map?)?['count'] as num?)?.toInt() ?? 0,
      sources: sources,
      storageBytes: bytes,
    );
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<ProfileStats>(
        future: _stats,
        builder: (c, snap) => ProfileHomeView(
          stats: snap.data,
          onDevices: () => goto(c, const MyDevices()),
          onSettings: () => goto(c, const MoreSettings()),
          onEdit: () => goto(c, const EditProfile()),
        ),
      );
}

class ProfileHomeView extends StatelessWidget {
  /// Null while the counts are still being read — the numbers are absent, not
  /// zero, and a zero rendered during a load is a wrong number on screen.
  final ProfileStats? stats;
  final VoidCallback? onDevices, onSettings, onEdit;

  const ProfileHomeView(
      {super.key, this.stats, this.onDevices, this.onSettings, this.onEdit});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = stats;
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar('Profile',
                trailing: Pressable(
                  onTap: onSettings,
                  semanticLabel: 'Settings',
                  child: Icon(LucideIcons.settings, size: 20, color: p.ink2),
                )),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                const SizedBox(height: S.x4),
                Center(
                  child: Container(
                    width: 96,
                    height: 96,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.wash(C.green, strength: 2),
                    ),
                    child:
                        Icon(LucideIcons.user, size: 42, color: p.on(C.green)),
                  ),
                ),
                const SizedBox(height: S.x4),
                Center(
                  child: Text(
                    (s?.name?.trim().isNotEmpty ?? false) ? s!.name! : 'You',
                    style: F.t2.copyWith(color: p.ink),
                  ),
                ),
                const SizedBox(height: S.x3),
                const Center(
                    child: Pill('Local · no cloud', C.green,
                        icon: LucideIcons.shieldCheck)),
                const SizedBox(height: S.x6),
                if (s == null)
                  const StatusCard(
                    'Counting your history',
                    'Reading the day store. These are counts of measured '
                        'days and sessions, not an account summary.',
                    icon: LucideIcons.loader,
                  )
                else
                  Surface(
                    child: Row(children: [
                      _stat(p, '${s.workouts}', 'Workouts'),
                      _div(p),
                      _stat(p, '${s.records}', 'Records'),
                      _div(p),
                      _stat(p, '${s.days}', 'Days'),
                      _div(p),
                      _stat(p, '${s.sources}', 'Sources'),
                    ]),
                  ),
                settingsGroup(c, 'Quick access', [
                  SetRow(LucideIcons.watch, C.blue, 'My devices',
                      sub: s == null
                          ? ''
                          : '${s.sources} source${s.sources == 1 ? '' : 's'}',
                      onTap: onDevices),
                  SetRow(LucideIcons.userPen, C.purple, 'Edit profile',
                      sub: 'Sex, age, height, weight', onTap: onEdit),
                  SetRow(LucideIcons.history, C.teal, 'Activity history',
                      sub: s == null ? '' : '${s.sessions} sessions this year',
                      onTap: onSettings),
                ]),
                settingsGroup(c, 'Your data', [
                  SetRow(LucideIcons.database, C.green, 'Storage',
                      value: s?.storageBytes == null
                          ? ''
                          : formatBytes(s!.storageBytes!),
                      chevron: false),
                  SetRow(LucideIcons.settings, C.n500, 'More settings',
                      sub: 'Export, import, units, reset', onTap: onSettings),
                ]),
                const SizedBox(height: S.x6),
                const StatusCard(
                  'Everything stays on this device',
                  'There is no account, no sync and no analytics. Your data '
                      'leaves this phone only when you export it yourself.',
                  icon: LucideIcons.shieldCheck,
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _stat(P p, String v, String l) => Expanded(
        child: Column(children: [
          Text(v, style: F.n24.copyWith(color: p.ink)),
          const SizedBox(height: 3),
          Text(l,
              style: F.over.copyWith(color: p.ink3),
              maxLines: 1,
              overflow: TextOverflow.ellipsis),
        ]),
      );

  Widget _div(P p) => Container(width: 1, height: 30, color: p.line);
}

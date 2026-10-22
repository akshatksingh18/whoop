// Notifications (Build 95, Akshat): every notification this app showed in the
// last 90 days, by day, newest first. Tapping one opens what it was about, so
// a notification that was swiped away or tapped once is not gone for good.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../notify/notification_log.dart';
import '../../state/app_state.dart';
import '../ui2.dart';
import 'home_screen.dart' show prettyDay;
import 'metric_detail.dart' show detailScaffold;

/// The bell on Today: opens the page, with a dot while anything is unread.
class NotificationsBell extends StatelessWidget {
  const NotificationsBell({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ValueListenableBuilder<int>(
      valueListenable: NotificationLog.instance.unread,
      builder: (c, n, _) => Pressable(
        semanticLabel: n == 0 ? 'Notifications' : 'Notifications, $n unread',
        onTap: () => Navigator.of(c).push(
          MaterialPageRoute<void>(builder: (_) => const NotificationsScreen()),
        ),
        child: SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: p.card,
                ),
                child: Icon(LucideIcons.bell, size: 18, color: p.ink2),
              ),
              if (n > 0)
                Positioned(
                  top: 7,
                  right: 8,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: p.on(C.orange),
                      border: Border.all(color: p.card, width: 2),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.entries});

  /// Shown as is, never read from the phone (tests, the gallery).
  final List<LoggedNotification>? entries;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<LoggedNotification>? _all;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _all = widget.entries;
    if (_all == null) {
      NotificationLog.instance.revision.addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    NotificationLog.instance.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await NotificationLog.instance.entries();
      if (mounted) setState(() => (_all = all, _failed = false));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  Future<void> _open(BuildContext c, LoggedNotification e) async {
    if (widget.entries != null) return;
    try {
      await NotificationLog.instance.markRead(e.key);
    } catch (_) {
      if (c.mounted)
        ScaffoldMessenger.of(c).showSnackBar(
          const SnackBar(content: Text('Could not mark it read. Try again.')),
        );
      return;
    }
    final route = e.route;
    if (route == null || !c.mounted) return;
    // The shell pops back to itself before it opens the destination, so
    // this page closes on the way.
    c.read<AppState>().openRoute(route);
  }

  static IconData _icon(String category) => switch (category) {
    'device' => LucideIcons.watch,
    'health' => LucideIcons.heartPulse,
    'recovery' => LucideIcons.leaf,
    _ => LucideIcons.bell,
  };

  static Color _tone(String category) => switch (category) {
    'device' => C.blue,
    'health' => C.red,
    'recovery' => C.recovery,
    _ => C.body,
  };

  String _dayTitle(String day) {
    final today = todayLabel();
    final t = DateTime.parse(today);
    final yesterday = dayLabelOf(DateTime(t.year, t.month, t.day - 1));
    if (day == today) return 'Today';
    if (day == yesterday) return 'Yesterday';
    return prettyDay(day);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final all = _all;
    final anyUnread = all?.any((e) => !e.read) ?? false;
    final days = <String, List<LoggedNotification>>{};
    for (final e in all ?? const <LoggedNotification>[]) {
      days.putIfAbsent(dayLabelOf(e.at), () => []).add(e);
    }
    final time = MaterialLocalizations.of(c);
    return detailScaffold(c, 'Notifications', [
      if (_failed)
        StatusCard(
          'Notifications could not load',
          'Your saved history has not been marked read.',
          fix: 'Retry',
          onFix: _load,
        ),
      if (anyUnread)
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: widget.entries != null
                ? null
                : () async {
                    try {
                      await NotificationLog.instance.markAllRead();
                    } catch (_) {
                      if (c.mounted)
                        ScaffoldMessenger.of(c).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Could not mark them read. Try again.',
                            ),
                          ),
                        );
                    }
                  },
            child: Text(
              'Mark all read',
              style: F.cap.copyWith(
                color: p.on(C.recovery),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      if (all == null)
        const SizedBox.shrink()
      else if (all.isEmpty)
        Surface(
          child: Text(
            'Nothing yet. Sent notifications and due reminders appear here, by day, '
            'for 90 days.',
            style: F.body.copyWith(color: p.ink2),
          ),
        )
      else
        for (final MapEntry(key: day, value: rows) in days.entries)
          Section(
            _dayTitle(day),
            Surface(
              pad: const EdgeInsets.symmetric(horizontal: S.x4),
              child: Column(
                children: [
                  for (var i = 0; i < rows.length; i++) ...[
                    if (i > 0) Divider(color: p.line, height: 1),
                    _row(c, p, rows[i], time),
                  ],
                ],
              ),
            ),
          ),
      if (all != null && all.isNotEmpty)
        Padding(
          padding: const EdgeInsets.fromLTRB(S.x1, S.x4, S.x1, 0),
          child: Text(
            'Sent to iOS records submission; scheduled entries record due times. '
            'Neither confirms a banner was displayed. Older entries have no '
            'delivery record. Tap to open. Kept here for 90 days.',
            style: F.cap.copyWith(color: p.onGround),
          ),
        ),
    ]);
  }

  Widget _row(
    BuildContext c,
    P p,
    LoggedNotification e,
    MaterialLocalizations time,
  ) {
    final at = time.formatTimeOfDay(TimeOfDay.fromDateTime(e.at));
    final tone = _tone(e.category);
    final origin = switch (e.origin) {
      NotificationOrigin.submitted => 'Sent to iOS',
      NotificationOrigin.scheduled => 'Scheduled time passed',
      NotificationOrigin.unknown => 'Delivery not recorded',
    };
    return Pressable(
      semanticLabel:
          '${e.read ? '' : 'Unread. '}${e.title}. ${e.body} $at. $origin.'
          '${e.route == null ? '' : ' Opens what it was about'}',
      onTap: () => _open(c, e),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: p.wash(tone),
                borderRadius: R.rMd,
              ),
              child: Icon(_icon(e.category), size: 18, color: p.on(tone)),
            ),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (bigText(c))
                    Text(
                      '${e.read ? '' : 'Unread · '}$at',
                      style: F.cap.copyWith(color: p.ink2),
                    ),
                  Text(
                    e.title,
                    style: F.body.copyWith(
                      color: p.ink,
                      fontWeight: e.read ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  Text(origin, style: F.cap.copyWith(color: p.ink2)),
                  if (e.body.isNotEmpty)
                    Text(
                      e.body,
                      style: F.cap.copyWith(color: p.ink2, height: 1.4),
                    ),
                ],
              ),
            ),
            if (!bigText(c)) const SizedBox(width: S.x2),
            if (!bigText(c))
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(at, style: F.cap.copyWith(color: p.ink2)),
                  if (!e.read) ...[
                    const SizedBox(height: S.x1),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: p.on(C.orange),
                      ),
                    ),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }
}

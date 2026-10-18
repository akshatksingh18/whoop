// Build 89 (Akshat): Food's day picker. A week strip of days under the title,
// each showing whether that day counts toward averages, logged food or is
// empty, and the date above it opening a month calendar for older days.
// Replaces the ‹ Today › row on Food's Today tab; swiping still moves a day.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../data/nutrition_store.dart';
import '../grammar.dart';
import 'food_diary.dart' show dayTitle, shiftDay;
import 'home_screen.dart' show monthName;
import '../theme.dart';

/// What one day of food reads as on the strip and the calendar.
enum FoodDayMark { counted, logged, empty }

FoodDayMark foodDayMarkOf(DayLogState s) => switch (s) {
  DayLogState.complete => FoodDayMark.counted,
  DayLogState.none => FoodDayMark.empty,
  _ => FoodDayMark.logged,
};

/// Marks for every day of the calendar months [from]…[to] covers.
Future<Map<String, FoodDayMark>> loadFoodMarks(String from, String to) async {
  final db = await LocalDb.instance;
  final out = <String, FoodDayMark>{};
  var m = DateTime.parse('${from.substring(0, 7)}-01');
  final last = DateTime.parse('${to.substring(0, 7)}-01');
  while (!m.isAfter(last)) {
    final label = '${m.year}-${m.month.toString().padLeft(2, '0')}';
    for (final d in (await NutritionDb.month(db, label)).days) {
      out[d.date] = foodDayMarkOf(d.state);
    }
    m = DateTime(m.year, m.month + 1);
  }
  return out;
}

const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Monday of the week holding [date] (Monday weeks, B88).
String mondayOf(String date) {
  final d = DateTime.parse(date);
  return dayLabelOf(DateTime(d.year, d.month, d.day - (d.weekday - 1)));
}

/// The seven days, Monday to Sunday, of the week holding [date]. Tap a day to
/// open it; days after today are shown but cannot be opened.
class FoodWeekStrip extends StatefulWidget {
  const FoodWeekStrip({
    super.key,
    required this.date,
    required this.onDay,
    this.marks,
  });

  final String date;
  final ValueChanged<String> onDay;

  /// Fixed marks (the gallery); null reads them from the food log.
  final Map<String, FoodDayMark>? marks;

  @override
  State<FoodWeekStrip> createState() => _FoodWeekStripState();
}

class _FoodWeekStripState extends State<FoodWeekStrip> {
  Map<String, FoodDayMark> _marks = const {};

  /// Build 92 (Codex audit concern 2): the newest read wins, and a week
  /// whose marks could not be read shows no marks rather than "nothing
  /// logged".
  int _seq = 0;
  String? _readWeek;
  final _selectedDay = GlobalKey();
  String? _revealed;

  @override
  void initState() {
    super.initState();
    NutritionDb.revision.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(FoodWeekStrip old) {
    super.didUpdateWidget(old);
    if (mondayOf(old.date) != mondayOf(widget.date)) _load();
  }

  @override
  void dispose() {
    NutritionDb.revision.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.marks != null) return;
    final mon = mondayOf(widget.date);
    final seq = ++_seq;
    try {
      final m = await loadFoodMarks(mon, shiftDay(mon, 6));
      if (mounted && seq == _seq) {
        setState(() => (_marks = m, _readWeek = mon));
      }
    } catch (_) {
      // The strip still works; this week just shows no marks.
      if (mounted && seq == _seq) setState(() => _readWeek = null);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final marks = widget.marks ?? _marks;
    final mon = mondayOf(widget.date);
    final today = todayLabel();
    Widget cell(int i) {
      final day = shiftDay(mon, i);
      final future = day.compareTo(today) > 0;
      final selected = day == widget.date;
      final known = widget.marks != null || _readWeek == mon;
      final mark = future || !known ? null : (marks[day] ?? FoodDayMark.empty);
      return Pressable(
        key: selected ? _selectedDay : null,
        semanticLabel:
            '${dayTitle(day)}${switch (mark) {
              FoodDayMark.counted => ', counted',
              FoodDayMark.logged => ', food logged, not counted',
              FoodDayMark.empty => ', nothing logged',
              null => '',
            }}',
        onTap: future ? null : () => widget.onDay(day),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(vertical: S.x2),
          decoration: BoxDecoration(
            color: selected ? p.card : null,
            borderRadius: R.rMd,
          ),
          child: Column(
            children: [
              Text(
                _weekdays[i],
                style: F.over.copyWith(color: selected ? p.ink : p.onGround),
              ),
              const SizedBox(height: 2),
              Text(
                '${DateTime.parse(day).day}',
                style: F.body.copyWith(
                  color: future
                      ? p.onGround.withValues(alpha: .55)
                      : selected
                      ? p.ink
                      : p.onGround,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: S.x1),
              _MarkDot(mark, size: 14),
            ],
          ),
        ),
      );
    }

    Widget legend(FoodDayMark mark, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MarkDot(mark, size: 10),
        const SizedBox(width: S.x1),
        Text(label, style: F.over.copyWith(color: p.onGround)),
      ],
    );
    return LayoutBuilder(
      builder: (c, box) {
        final large = bigText(c);
        final cellWidth = MediaQuery.textScalerOf(c).scale(34) + S.x3;
        final token = '${widget.date}/${box.maxWidth}/$cellWidth';
        if (!large) _revealed = null;
        if (large && _revealed != token) {
          _revealed = token;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final context = _selectedDay.currentContext;
            final object = context?.findRenderObject();
            if (mounted &&
                context != null &&
                object != null &&
                object.attached) {
              Scrollable.of(
                context,
              ).position.ensureVisible(object, alignment: .5);
            }
          });
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (large)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      SizedBox(width: cellWidth, child: cell(i)),
                  ],
                ),
              )
            else
              Row(
                children: [
                  for (var i = 0; i < 7; i++) Expanded(child: cell(i)),
                ],
              ),
            const SizedBox(height: S.x1),
            Wrap(
              spacing: S.x3,
              runSpacing: S.x1,
              children: [
                legend(FoodDayMark.counted, 'Counted'),
                legend(FoodDayMark.logged, 'Logged'),
                legend(FoodDayMark.empty, 'Empty'),
              ],
            ),
          ],
        );
      },
    );
  }
}

/// Counted: a filled check. Logged but not counted: a dashed ring. Nothing
/// logged: a plain ring. Null (a future day): an empty space.
class _MarkDot extends StatelessWidget {
  const _MarkDot(this.mark, {required this.size});
  final FoodDayMark? mark;
  final double size;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return SizedBox(
      width: size,
      height: size,
      child: switch (mark) {
        FoodDayMark.counted => DecoratedBox(
          decoration: BoxDecoration(
            color: p.fill(C.recovery),
            shape: BoxShape.circle,
          ),
          child: Icon(LucideIcons.check, size: size * .6, color: p.inkOnFill),
        ),
        FoodDayMark.logged => Icon(
          LucideIcons.circleDashed,
          size: size,
          color: p.ink2,
        ),
        FoodDayMark.empty => Icon(
          LucideIcons.circle,
          size: size,
          color: p.ink3,
        ),
        null => const SizedBox.shrink(),
      },
    );
  }
}

/// A month of days to jump to, from the date above Food's title. Returns the
/// chosen day, or null when closed.
Future<String?> showFoodCalendar(BuildContext c, String current) =>
    showModalBottomSheet<String>(
      context: c,
      useSafeArea: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: P.of(c).card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (_) => FoodCalendar(current: current),
    );

/// The month grid inside [showFoodCalendar]: Monday weeks, the chosen day
/// filled, today in the food colour, and each past day's mark under its
/// number.
class FoodCalendar extends StatefulWidget {
  const FoodCalendar({super.key, required this.current, this.marks});
  final String current;

  /// Fixed marks (the gallery); null reads them from the food log.
  final Map<String, FoodDayMark>? marks;

  @override
  State<FoodCalendar> createState() => _FoodCalendarState();
}

class _FoodCalendarState extends State<FoodCalendar> {
  late DateTime _month;
  Map<String, FoodDayMark> _marks = const {};

  /// Months whose marks were read (Build 92): a failed or pending month shows
  /// no marks instead of "nothing logged", and a slower earlier read never
  /// lands on the month now shown.
  final Set<String> _readMonths = {};
  bool _failed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    final d = DateTime.parse(widget.current);
    _month = DateTime(d.year, d.month);
    _load();
  }

  Future<void> _load() async {
    if (widget.marks != null) return;
    final label = dayLabelOf(_month);
    final seq = ++_seq;
    try {
      final m = await loadFoodMarks(label, label);
      if (!mounted) return;
      setState(() {
        _marks = {..._marks, ...m};
        _readMonths.add(label.substring(0, 7));
        if (seq == _seq) _failed = false;
      });
    } catch (_) {
      if (mounted && seq == _seq) setState(() => _failed = true);
    }
  }

  void _shift(int by) {
    setState(() => _month = DateTime(_month.year, _month.month + by));
    _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final marks = widget.marks ?? _marks;
    final now = DateTime.now();
    final today = todayLabel();
    final atNow = _month.year == now.year && _month.month == now.month;
    final lead = DateTime(_month.year, _month.month).weekday - 1;
    final days = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <String?>[
      for (var i = 0; i < lead; i++) null,
      for (var d = 1; d <= days; d++)
        dayLabelOf(DateTime(_month.year, _month.month, d)),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(S.x5, S.x4, S.x5, S.x5),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${monthName(_month.month, null)} ${_month.year}',
                  style: F.head.copyWith(color: p.ink),
                ),
              ),
              IconButton(
                tooltip: 'Previous month',
                onPressed: () => _shift(-1),
                icon: Icon(LucideIcons.chevronLeft, color: p.ink),
              ),
              IconButton(
                tooltip: 'Next month',
                onPressed: atNow ? null : () => _shift(1),
                icon: Icon(
                  LucideIcons.chevronRight,
                  color: atNow ? p.line : p.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: S.x2),
          Row(
            children: [
              for (final w in _weekdays)
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      w,
                      textAlign: TextAlign.center,
                      style: F.over.copyWith(color: p.ink2),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: S.x2),
          for (var r = 0; r * 7 < cells.length; r++)
            Row(
              children: [
                for (var i = r * 7; i < r * 7 + 7; i++)
                  Expanded(
                    child: i >= cells.length || cells[i] == null
                        ? const SizedBox(height: 52)
                        : _cell(c, p, cells[i]!, today, marks),
                  ),
              ],
            ),
          const SizedBox(height: S.x2),
          Wrap(
            spacing: S.x4,
            runSpacing: S.x1,
            children: [
              for (final (m, label) in const [
                (FoodDayMark.counted, 'Counted'),
                (FoodDayMark.logged, 'Logged, not counted'),
                (FoodDayMark.empty, 'Nothing logged'),
              ])
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _MarkDot(m, size: 14),
                    const SizedBox(width: S.x1),
                    // Wraps at large text sizes instead of overflowing.
                    Flexible(
                      child: Text(label, style: F.cap.copyWith(color: p.ink2)),
                    ),
                  ],
                ),
            ],
          ),
          if (_failed) ...[
            const SizedBox(height: S.x2),
            Pressable(
              semanticLabel: 'Day marks could not load. Retry',
              onTap: _load,
              child: Text(
                'Day marks could not load. Tap to retry.',
                style: F.cap.copyWith(color: p.on(C.alert)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext c,
    P p,
    String day,
    String today,
    Map<String, FoodDayMark> marks,
  ) {
    final future = day.compareTo(today) > 0;
    final selected = day == widget.current;
    final isToday = day == today;
    return Pressable(
      semanticLabel: dayTitle(day),
      onTap: future ? null : () => Navigator.of(c).pop(day),
      child: SizedBox(
        height: 52,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: selected
                  ? BoxDecoration(
                      color: p.wash(C.food),
                      shape: BoxShape.circle,
                      border: Border.all(color: p.on(C.food), width: 1.5),
                    )
                  : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '${DateTime.parse(day).day}',
                  style: F.body.copyWith(
                    color: future
                        ? p.ink3.withValues(alpha: .5)
                        : isToday
                        ? p.on(C.food)
                        : p.ink,
                    fontWeight: isToday || selected
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
            ),
            if (!future &&
                (widget.marks != null ||
                    _readMonths.contains(day.substring(0, 7))))
              _MarkDot(marks[day] ?? FoodDayMark.empty, size: 10),
          ],
        ),
      ),
    );
  }
}

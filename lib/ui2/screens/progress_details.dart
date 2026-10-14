// Build 90: Progress's detail pages — Body (weight, every tape site, steps,
// entries, photos and estimates), Strength (every exercise on its own setup)
// and Food, training and recovery. Each explores any History range; none of
// them produces a goal verdict (that is the overview's, on fixed weeks).
// Opened from the overview's rows and from other tabs through openProgress.

part of 'progress_screen.dart';

/// The page [dest] opens on. Weight and Waist share the Body page with the
/// matching measurement selected; food, training and recovery share one.
Widget progressDetailPage(ProgressDest dest, {ProgressData? initial}) =>
    _ProgressDetail(dest: dest, initial: initial);

enum _DetailKind { body, strength, context }

_DetailKind _kindOf(ProgressDest d) => switch (d) {
  ProgressDest.strength => _DetailKind.strength,
  ProgressDest.food ||
  ProgressDest.training ||
  ProgressDest.recovery => _DetailKind.context,
  _ => _DetailKind.body,
};

class _ProgressDetail extends StatefulWidget {
  const _ProgressDetail({required this.dest, this.initial});
  final ProgressDest dest;
  final ProgressData? initial;
  @override
  State<_ProgressDetail> createState() => _ProgressDetailState();
}

class _ProgressDetailState extends State<_ProgressDetail>
    with RevisionReload, _ProgressCommon {
  ProgressRange _range = ProgressRange.threeMonths;
  late String _metricKey = widget.dest == ProgressDest.waist
      ? BodySite.waistNavel.name
      : 'weight';
  bool _trend = true;
  int? _cursor;

  @override
  ProgressData? get _fixed => null;

  @override
  void initState() {
    super.initState();
    _d = widget.initial;
    _prefs();
  }

  @override
  void _prefsLoaded(SharedPreferences p) {
    setState(() {
      _range =
          ProgressRange.values
              .where((r) => r.name == p.getString('progress.range'))
              .firstOrNull ??
          _range;
      // A link names its measurement; the plain Body page keeps the last one.
      if (widget.dest == ProgressDest.overview ||
          widget.dest == ProgressDest.entry) {
        final metric = p.getString('progress.metric');
        if (metric == 'weight' ||
            metric == 'steps' ||
            BodySite.parse(metric ?? '') != null) {
          _metricKey = metric!;
        }
      }
    });
  }

  ProgressMetric get _metric => switch (_metricKey) {
    'steps' => const StepsMetric(),
    'weight' => WeightMetric(_unit),
    _ => SiteMetric(BodySite.parse(_metricKey) ?? BodySite.waistNavel),
  };

  @override
  Widget build(BuildContext c) {
    final d = _d;
    final kind = _kindOf(widget.dest);
    return detailScaffold(
      c,
      switch (kind) {
        _DetailKind.body => 'Body',
        _DetailKind.strength => 'Strength',
        _DetailKind.context => 'Food, training and recovery',
      },
      [
        if (_failed)
          StatusCard(
            'Progress could not load',
            'Your saved records are intact.',
            fix: 'Retry',
            onFix: reload,
          ),
        if (d == null && !_failed)
          const Center(child: CircularProgressIndicator()),
        if (d != null) ...[
          if (d.readErrors.isNotEmpty) _readErrors(c, d),
          ..._page(c, d, kind),
        ],
      ],
      trailing: kind == _DetailKind.body && d != null
          ? IconButton(
              tooltip: 'Add body entry',
              onPressed: () => _addEntry(c, d),
              icon: Icon(LucideIcons.plus, color: P.of(c).on(C.teal)),
            )
          : null,
    );
  }

  List<Widget> _page(BuildContext c, ProgressData d, _DetailKind kind) {
    final p = P.of(c);
    final today = todayLabel();
    final per = progressPeriod(
      _range,
      today,
      baseline: d.baseline,
      earliest: d.earliest,
    );
    final from = per.shownFrom, to = per.shownTo;
    return [
      Text('HISTORY RANGE', style: F.label.copyWith(color: p.onGround)),
      const SizedBox(height: S.x1),
      _periodPicker(c, p),
      const SizedBox(height: S.x1),
      Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.x1),
              child: Text(per.words, style: F.cap.copyWith(color: p.onGround)),
            ),
          ),
          _morePeriods(c, p),
        ],
      ),
      const SizedBox(height: S.x3),
      ...switch (kind) {
        _DetailKind.body => [
          _beforeNow(c, p, d, per),
          const SizedBox(height: S.x4),
          Surface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Body', style: F.head.copyWith(color: p.ink)),
                    ),
                    IconButton(
                      tooltip: 'Body settings',
                      onPressed: () => _settings(c, d),
                      icon: Icon(LucideIcons.settings2, color: p.ink2),
                    ),
                  ],
                ),
                _metricChips(c, p),
                ..._bodySection(c, p, d, from, to),
                ..._entries(c, p, d, _metric, from, to),
                const SizedBox(height: S.x2),
                _photoCard(c, p, d),
              ],
            ),
          ),
          ..._bodyMilestones(c, p, d, from, to),
        ],
        _DetailKind.strength => [
          ..._strengthSection(
            c,
            p,
            d,
            from,
            to,
            before: per.before,
            after: per.after,
          ),
          ..._liftMilestones(c, p, d, from, to),
        ],
        _DetailKind.context => [
          ..._foodSection(c, p, d, from, to),
          const SizedBox(height: S.x5),
          ..._activitySection(c, p, d, from, to),
        ],
      },
    ];
  }

  /// Earlier value → current value → change for the range's two halves, with
  /// their dates. Observations only: no verdict here.
  Widget _beforeNow(BuildContext c, P p, ProgressData d, ProgressPeriod per) {
    final before = per.before, after = per.after;
    if (before == null || after == null) {
      return Surface(
        child: Text(
          'This range has no earlier stretch to compare with. Its readings are '
          'below.',
          style: F.body.copyWith(color: p.ink2),
        ),
      );
    }
    double u(double kg) => _unit == 'lb' ? kg * kLbPerKg : kg;
    final ws = weightSeries(d.weights, unit: 'kg');
    final wb = weightWindow(ws, before), wa = weightWindow(ws, after);
    String line(double? a, double? b, String unit, int places) =>
        a == null || b == null
        ? '—'
        : '${_num(a, places)} → ${_num(b, places)} $unit '
              '(${b - a >= 0 ? '+' : '−'}${_num((b - a).abs(), places)})';
    final rows = <(String, String, String)>[
      if (wa.mean != null && wb.mean != null)
        (
          'Average weight',
          line(u(wb.mean!), u(wa.mean!), _unit, 1),
          '${wb.count} and ${wa.count} weigh-ins',
        )
      // A known average stays visible when there is nothing to compare.
      else if (wa.mean != null)
        (
          'Average weight',
          '${_num(u(wa.mean!))} $_unit',
          '${wa.count} weigh-ins · none in ${_md(before.from)} – '
              '${_md(before.to)} to compare',
        )
      else if (wb.mean != null)
        (
          'Average weight',
          '${_num(u(wb.mean!))} $_unit earlier',
          'No weigh-in since ${_md(after.from)}',
        ),
    ];
    for (final site in BodySite.values) {
      final s = siteSeries(d.measures, site);
      final b = readingNear(s, before.from);
      final a = inRange(s, after.from, after.to).lastOrNull;
      if (a == null || b == null || a.date == b.date) continue;
      rows.add((
        site.title,
        line(b.value, a.value, 'in', 2),
        '${_md(b.date)} → ${_md(a.date)}',
      ));
    }
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${_md(before.from)} – ${_md(before.to)} → ${_md(after.from)} – ${_md(after.to)}',
            style: F.label.copyWith(color: p.ink2),
          ),
          for (final (k, v, sub) in rows)
            Padding(
              padding: const EdgeInsets.only(top: S.x3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(k, style: F.body.copyWith(color: p.ink)),
                        Text(sub, style: F.cap.copyWith(color: p.ink3)),
                      ],
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  Flexible(
                    child: Text(
                      v,
                      textAlign: TextAlign.end,
                      style: F.n17.copyWith(color: p.ink),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── milestones (Build 90, D5): dated facts from recorded readings ──

  List<Widget> _bodyMilestones(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String to,
  ) {
    final notes = bodyMilestones(d.measures, from, to);
    if (notes.isEmpty) return const [];
    return [
      const SizedBox(height: S.x5),
      Section(
        'Milestones',
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Text(n, style: F.body.copyWith(color: p.ink)),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  List<Widget> _liftMilestones(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String to,
  ) {
    final notes = liftMilestones(d.lifts, from, to);
    if (notes.isEmpty) return const [];
    return [
      const SizedBox(height: S.x5),
      Section(
        'Milestones',
        Surface(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in notes)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x1),
                  child: Text(n, style: F.body.copyWith(color: p.ink)),
                ),
            ],
          ),
        ),
      ),
    ];
  }

  /// The page's one period: four tabs, the rest under More.
  Widget _periodPicker(BuildContext c, P p) => SubTabs(
    // "Start" here; the line under the tabs says what it compares.
    const ['Week', 'Month', '3 months', 'Start'],
    _mainPeriods.indexOf(_range),
    (i) {
      setState(() {
        _range = _mainPeriods[i];
        _cursor = null;
      });
      _save('progress.range', _mainPeriods[i].name);
    },
    color: C.body,
  );

  static const _mainPeriods = [
    ProgressRange.week,
    ProgressRange.month,
    ProgressRange.threeMonths,
    ProgressRange.sinceStart,
  ];

  /// 2 months, 6 months, 1 year and All, beside the period's description.
  Widget _morePeriods(BuildContext c, P p) {
    final more = [
      for (final r in ProgressRange.values)
        if (!_mainPeriods.contains(r)) r,
    ];
    final inMore = more.contains(_range);
    return PopupMenuButton<ProgressRange>(
      tooltip: 'More periods',
      onSelected: (r) {
        setState(() {
          _range = r;
          _cursor = null;
        });
        _save('progress.range', r.name);
      },
      itemBuilder: (_) => [
        for (final r in more) PopupMenuItem(value: r, child: Text(r.label)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              inMore ? _range.label : 'More',
              style: F.cap.copyWith(
                color: p.onGround,
                fontWeight: inMore ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
            Icon(LucideIcons.chevronDown, size: 16, color: p.onGround),
          ],
        ),
      ),
    );
  }

  /// What the Body card charts: weight, steps or a tape site.
  Widget _metricChips(BuildContext c, P p) {
    final options = <(String, String)>[
      ('weight', 'Weight'),
      ('steps', 'Steps'),
      for (final s in BodySite.values) (s.name, s.title),
    ];
    // Every chip built (a scroll view, not a lazy list), so each is reachable
    // at any text size.
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final (key, label) in options)
            Padding(
              padding: const EdgeInsets.only(right: S.x2),
              child: Pressable(
                semanticLabel: 'Chart $label',
                onTap: () => _setMetric(key),
                child: Center(
                  child: Pill(label, _metricKey == key ? C.teal : C.n400),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _setMetric(String k) {
    setState(() {
      _metricKey = k;
      _cursor = null;
    });
    _save('progress.metric', k);
  }

  // ── body ──

  List<Widget> _bodySection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final m = _metric;
    final family = m is WeightMetric
        ? 'Weight'
        : m is StepsMetric
        ? 'steps'
        : 'Measurements';
    final List<DatedValue> series = switch (m) {
      WeightMetric() => weightSeries(d.weights, unit: _unit),
      StepsMetric() => d.steps,
      SiteMetric(:final site) => siteSeries(d.measures, site),
    };
    final r = inRange(series, from, today);
    final summary = m is StepsMetric ? null : bodySummary(r);
    final steps = m is StepsMetric ? stepsSummary(r) : null;
    final labels = daysBetween(from, today);
    final readings = {for (final x in r) x.date: x.value};
    final List<double?> points = [
      for (final day in labels)
        if (m is WeightMetric && _trend)
          switch (BodyLogDb.sevenDayMean(d.weights, day)) {
            final mean? => _unit == 'lb' ? mean.kg * kLbPerKg : mean.kg,
            _ => null,
          }
        else
          readings[day],
    ];
    final axis = AxisSpec.of(
      points.whereType<double>(),
      format: axisFixedOrInt,
    );
    final cursor = _cursor == null || labels.isEmpty
        ? null
        : _cursor!.clamp(0, labels.length - 1);
    String describe(int i) =>
        '${_md(labels[i])} · ${points[i] == null ? 'Not recorded' : '${_num(points[i]!)} ${m.unit}'}';
    return [
      Surface(
        framed: false,
        pad: const EdgeInsets.symmetric(vertical: S.x3),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (m is WeightMetric)
              Row(
                children: [
                  Expanded(
                    child: SubTabs(
                      const ['Readings', '7-day mean'],
                      _trend ? 1 : 0,
                      (i) => setState(() {
                        _trend = i == 1;
                        _cursor = null;
                      }),
                      color: C.teal,
                    ),
                  ),
                  const SizedBox(width: S.x2),
                  TextButton(
                    onPressed: () {
                      final u = _unit == 'kg' ? 'lb' : 'kg';
                      setState(() => _unit = u);
                      _save('body.unit', u);
                    },
                    child: Text(_unit),
                  ),
                ],
              ),
            const SizedBox(height: S.x3),
            if (r.isEmpty)
              Text(
                d.readErrors.contains(family)
                    ? 'Records unavailable. Retry above.'
                    : 'Nothing recorded in ${_range.label.toLowerCase()}.',
                style: F.cap.copyWith(color: p.ink3),
              )
            else ...[
              ChartFrame(
                title: m is WeightMetric && _trend ? '7-day average' : m.label,
                unit: m.unit,
                height: 160,
                yAxis: axis,
                xLabels: [_md(from), _md(today)],
                series: points,
                readout: cursor == null ? null : describe(cursor),
                child: Scrubber(
                  value: cursor == null || labels.length < 2
                      ? null
                      : cursor / (labels.length - 1),
                  label: 'Dated ${m.label} chart',
                  step: labels.length < 2 ? 1 : 1 / (labels.length - 1),
                  describe: (v) => describe((v * (labels.length - 1)).round()),
                  onChanged: (v) => setState(
                    () => _cursor = (v * (labels.length - 1)).round(),
                  ),
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: LineChart(
                      points,
                      p.on(C.teal),
                      axis: axis,
                      cursor: cursor,
                      fill: false,
                      dots: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: S.x2),
              if (summary != null)
                Row(
                  children: [
                    _stat(
                      p,
                      'Start',
                      '${_num(summary.start.value)} ${m.unit}',
                      _md(summary.start.date),
                    ),
                    _stat(
                      p,
                      'Latest',
                      '${_num(summary.latest.value)} ${m.unit}',
                      _md(summary.latest.date),
                    ),
                    _stat(
                      p,
                      'Change',
                      summary.count < 2
                          ? '—'
                          : '${summary.change >= 0 ? '+' : '−'}${_num(summary.change.abs())} ${m.unit}',
                      '${summary.count} ${summary.count == 1 ? 'reading' : 'readings'}',
                    ),
                  ],
                ),
              if (steps != null)
                Row(
                  children: [
                    _stat(
                      p,
                      'Total',
                      thousands(steps.total),
                      '${steps.days} days measured',
                    ),
                    _stat(
                      p,
                      'Average',
                      steps.average == null ? '—' : thousands(steps.average!),
                      'per measured day',
                    ),
                  ],
                ),
              if (m is WeightMetric && d.weights.isNotEmpty)
                if (BodyLogDb.sevenDayMean(d.weights, today) case final mean?)
                  Padding(
                    padding: const EdgeInsets.only(top: S.x2),
                    child: Text(
                      '7-day average ${_num(_unit == 'lb' ? mean.kg * kLbPerKg : mean.kg)} $_unit '
                      'from ${mean.count} ${mean.count == 1 ? 'reading' : 'readings'}',
                      style: F.cap.copyWith(color: p.ink3),
                    ),
                  ),
              if (m is WeightMetric)
                if (_blockLine(d, today) case final line?)
                  Text(line, style: F.cap.copyWith(color: p.ink3)),
              if (m is SiteMetric && m.site == BodySite.waistNavel)
                ..._estimates(p, d, today),
            ],
          ],
        ),
      ),
    ];
  }

  /// Current block's observed mean and the actual earlier recorded block date,
  /// for the block holding [today]; null when it has no reading.
  String? _blockLine(ProgressData d, String today) {
    // B88-08: weight weeks run Monday–Sunday, the same weeks as the Review;
    // the measurement weekday only schedules the tape reminder.
    final blocks = BodyLogDb.weekBlocks([
      for (final w in d.weights)
        if (w.date.compareTo(today) <= 0) w,
    ], DateTime.monday);
    final now = BodyLogDb.blockStart(today, DateTime.monday);
    final b = blocks.where((x) => x.from == now).firstOrNull;
    if (b == null) return null;
    final previous = blocks
        .where((x) => x.from.compareTo(b.from) < 0)
        .firstOrNull;
    double u(double kg) => _unit == 'lb' ? kg * kLbPerKg : kg;
    return [
      'This week (from ${_md(b.from)}) ${_num(u(b.kg))} $_unit from '
          '${b.count} ${b.count == 1 ? 'reading' : 'readings'}',
      if (b.change case final ch? when previous != null)
        '${ch >= 0 ? '+' : '−'}${_num(u(ch.abs()))} vs ${_md(previous.from)}',
    ].join(' · ');
  }

  List<Widget> _estimates(P p, ProgressData d, String today) {
    final latest = d.measures
        .where(
          (x) =>
              x.date.compareTo(today) <= 0 &&
              x.value(BodySite.waistNavel) != null,
        )
        .firstOrNull;
    final h = d.heightCm == null ? null : d.heightCm! / 2.54;
    if (latest == null || h == null || !h.isFinite || h <= 0) return const [];
    final waist = latest.value(BodySite.waistNavel)!;
    // G5 (`build-90-research.md`): ± 3.5% is the equation's standard error of
    // estimate (Hodgdon and Beckett 1984, NHRC 84-11).
    // B88-08: the US Navy formula here is the MALE form, so it is shown only
    // for a stated male profile, with a neck reading within 30 days of the
    // waist reading, and only inside 3–50%. Both dates are printed.
    final male =
        (d.user['sex'] as String?)?.toLowerCase().startsWith('m') ?? false;
    int daysApart(String a, String b) =>
        DateTime.parse(a).difference(DateTime.parse(b)).inHours.abs() ~/ 24;
    final neck = d.measures
        .where(
          (x) =>
              x.date.compareTo(today) <= 0 &&
              x.value(BodySite.neck) != null &&
              daysApart(x.date, latest.date) <= 30,
        )
        .firstOrNull;
    final raw = male
        ? BodyLogDb.navyBodyFat(waist, neck?.value(BodySite.neck), h)
        : null;
    final bf = raw == null || raw < 3 || raw > 50 ? null : raw;
    return [
      Padding(
        padding: const EdgeInsets.only(top: S.x2),
        child: Text(
          'Estimates from ${_md(latest.date)}: waist-to-height ${(waist / h).toStringAsFixed(2)}'
          '${bf == null ? '' : ' · US Navy body fat about ${bf.toStringAsFixed(0)}% ± 3.5% (waist ${_md(latest.date)}, neck ${_md(neck!.date)})'}. '
          'The trend matters, not the exact number.',
          style: F.cap.copyWith(color: p.ink3),
        ),
      ),
    ];
  }

  List<Widget> _entries(
    BuildContext c,
    P p,
    ProgressData d,
    ProgressMetric m,
    String from,
    String today,
  ) {
    if (m is StepsMetric) return const [];
    final rows = <Widget>[];
    if (m is WeightMetric) {
      final ws = [
        for (final w in d.weights.reversed)
          if (w.date.compareTo(from) >= 0 && w.date.compareTo(today) <= 0) w,
      ];
      for (final w in ws.take(3)) {
        rows.add(
          _entryRow(
            c,
            p,
            w.date,
            bodyWeightText(w, unit: _unit),
            w.historyOnly
                ? (w.source == 'whoop' ? 'Added later' : 'Imported')
                : '',
            () => _editWeight(c, w),
          ),
        );
      }
    } else if (m is SiteMetric) {
      final ms = [
        for (final x in d.measures)
          if (x.date.compareTo(from) >= 0 &&
              x.date.compareTo(today) <= 0 &&
              x.value(m.site) != null)
            x,
      ];
      for (final x in ms.take(3)) {
        final ch = BodyLogDb.changeSince(d.measures, x, m.site);
        rows.add(
          _entryRow(
            c,
            p,
            x.date,
            '${_num(x.value(m.site)!, 2)} in',
            ch == null
                ? ''
                : '${ch >= 0 ? '+' : '−'}${_num(ch.abs(), 2)} in since the last',
            () => _editMeasure(c, x),
          ),
        );
      }
    }
    return [
      Section(
        'Entries',
        Surface(
          framed: false,
          pad: EdgeInsets.zero,
          child: rows.isEmpty
              ? const SizedBox.shrink()
              : Column(children: rows),
        ),
        action: 'All history',
        onAction: () async {
          await Navigator.of(c).push(
            MaterialPageRoute<void>(builder: (_) => BodyHistoryScreen(data: d)),
          );
          reload();
        },
      ),
    ];
  }

  Widget _entryRow(
    BuildContext c,
    P p,
    String date,
    String value,
    String sub,
    VoidCallback onTap,
  ) {
    final photosThatDay = (_d?.photos ?? const [])
        .where((x) => x.date == date)
        .length;
    return Pressable(
      semanticLabel: '${_md(date)}, $value',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_md(date), style: F.body.copyWith(color: p.ink)),
                  if (sub.isNotEmpty)
                    Text(sub, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
            if (photosThatDay > 0) ...[
              Icon(LucideIcons.image, size: 15, color: p.ink3),
              const SizedBox(width: S.x2),
            ],
            Text(value, style: F.n17.copyWith(color: p.ink)),
          ],
        ),
      ),
    );
  }

  // ── photos ──

  Widget _photoCard(BuildContext c, P p, ProgressData d) => Surface(
    onTap: d.photos.isEmpty
        ? null
        : () => Navigator.of(c).push(
            MaterialPageRoute<void>(
              builder: (_) => PhotoCompareScreen(photos: d.photos),
            ),
          ),
    semanticLabel: 'Compare photos',
    child: Row(
      children: [
        Icon(LucideIcons.images, size: 20, color: p.ink2),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Photos',
                style: F.body.copyWith(
                  color: p.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                d.photos.isEmpty
                    ? 'No photos yet'
                    : '${d.photos.length} photos · ${_md(d.photos.last.date)}',
                style: F.cap.copyWith(color: p.ink3),
              ),
            ],
          ),
        ),
        if (d.photos.isNotEmpty)
          Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ],
    ),
  );

  // ── strength ──

  List<Widget> _strengthSection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today, {
    DayWindow? before,
    DayWindow? after,
  }) {
    final lifts = [
      for (final w in d.lifts)
        if (dayLabelOf(w.startedAt).compareTo(from) >= 0 &&
            dayLabelOf(w.startedAt).compareTo(today) <= 0)
          w,
    ];
    // Build 89: the page's own comparison, not a split of its own — the
    // answer card and this card compare the same two periods.
    final dates = daysBetween(from, today);
    final mid = DateTime.parse(dates[(dates.length - 1) ~/ 2]);
    final first =
        before ?? (from: from, to: dayLabelOf(mid), days: 0, partial: false);
    final second =
        after ??
        (
          from: dayLabelOf(DateTime(mid.year, mid.month, mid.day + 1)),
          to: today,
          days: 0,
          partial: false,
        );
    final cmp = dates.length < 2
        ? <LiftComparison>[]
        : liftComparisons(d.lifts, first, second);
    final sets = lifts.fold<int>(0, (n, w) => n + w.setCount);
    String setText(LiftComparison x, LiftSet s) =>
        '${liftWeightText(s.load)} ${x.mode.shortUnit} × ${s.reps}';
    return [
      Section(
        'Strength',
        Surface(
          framed: false,
          pad: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${lifts.length} workouts · $sets sets',
                style: F.cap.copyWith(color: p.ink3),
              ),
              Text(
                dates.length < 2
                    ? 'No earlier period to compare'
                    : '${_md(first.from)} – ${_md(first.to)} vs ${_md(second.from)} – ${_md(second.to)}',
                style: F.over.copyWith(color: p.ink3),
              ),
              if (cmp.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: S.x2),
                  child: Text(
                    lifts.isEmpty
                        ? 'No sets logged in this range.'
                        : 'No comparable lifts in these periods.',
                    style: F.cap.copyWith(color: p.ink3),
                  ),
                ),
              for (final x in cmp) ...[
                const SizedBox(height: S.x3),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        x.exercise,
                        style: F.body.copyWith(color: p.ink),
                      ),
                    ),
                    Icon(
                      switch (x.change) {
                        SetVerdict.better => LucideIcons.trendingUp,
                        SetVerdict.worse => LucideIcons.trendingDown,
                        SetVerdict.same => LucideIcons.equal,
                        SetVerdict.incomparable => LucideIcons.minus,
                      },
                      size: 16,
                      color: p.ink2,
                    ),
                  ],
                ),
                Text(
                  'Best ${setText(x, x.before)} → ${setText(x, x.after)}',
                  style: F.cap.copyWith(color: p.ink3),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  // ── food ──

  List<Widget> _foodSection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final w = (
      from: from,
      to: today,
      days: daysBetween(from, today).length,
      partial: true,
    );
    final f = foodWindow(d.food, w);
    return [
      Section(
        'Food',
        Surface(
          framed: false,
          pad: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _stat(
                    p,
                    'Calories',
                    f.kcal == null ? '—' : thousands(f.kcal!),
                    '${f.kcalDays} of ${f.windowDays} days',
                  ),
                  _stat(
                    p,
                    'Protein',
                    f.protein == null ? '—' : '${f.protein!.round()} g',
                    '${f.proteinDays} complete days',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }

  // ── activity and recovery ──

  List<Widget> _activitySection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
  ) {
    final ss = [
      for (final s in d.sessions)
        if (s.date.compareTo(from) >= 0 && s.date.compareTo(today) <= 0) s,
    ];
    final lifts = ss.where((s) => isLiftType(s.type)).length;
    final runs = ss.where((s) => isRunType(s.type)).length;
    final walks = ss.where((s) => isWalkType(s.type)).length;
    final st = stepsSummary(inRange(d.steps, from, today));
    double? mean(List<DatedValue> v) =>
        v.isEmpty ? null : v.fold<double>(0, (a, x) => a + x.value) / v.length;
    final sleep = inRange(d.sleepMin, from, today);
    final rec = inRange(d.recovery, from, today);
    final sm = mean(sleep), rm = mean(rec);
    return [
      Section(
        'Activity and recovery',
        Surface(
          framed: false,
          pad: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  _stat(
                    p,
                    'Workouts',
                    '${ss.length}',
                    '$lifts lift · $runs run · $walks walk · ${ss.length - lifts - runs - walks} other',
                  ),
                  _stat(
                    p,
                    'Steps',
                    st.average == null ? '—' : thousands(st.average!),
                    '${st.days} days measured',
                  ),
                ],
              ),
              const SizedBox(height: S.x3),
              Row(
                children: [
                  _stat(
                    p,
                    'Sleep',
                    sm == null ? '—' : '${sm ~/ 60}h ${(sm % 60).round()}m',
                    '${sleep.length} nights',
                  ),
                  _stat(
                    p,
                    'Recovery',
                    rm == null ? '—' : '${rm.round()}%',
                    '${rec.length} days',
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ];
  }
}

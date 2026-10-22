// Build 90: Progress's detail pages — Body (weight, every tape site, steps,
// entries, photos and estimates), Strength (every exercise on its own setup)
// and Food, training and recovery. Each explores any History range; none of
// them produces a goal verdict (that is the overview's, on fixed weeks).
// Opened from the overview's rows and from other tabs through openProgress.

part of 'progress_screen.dart';

/// The page [dest] opens on. Weight and Waist share the Body page with the
/// matching measurement selected; food, training and recovery share one.
/// [range], when given, opens the page on that period and leaves the
/// remembered history range alone (Build 91, Codex audit F04: a 7-day
/// number on the overview opens on the same 7 days).
Widget progressDetailPage(
  ProgressDest dest, {
  ProgressData? initial,
  ProgressRange? range,
}) => _ProgressDetail(dest: dest, initial: initial, range: range);

enum _DetailKind { body, strength, context }

_DetailKind _kindOf(ProgressDest d) => switch (d) {
  ProgressDest.strength => _DetailKind.strength,
  ProgressDest.food ||
  ProgressDest.training ||
  ProgressDest.recovery => _DetailKind.context,
  _ => _DetailKind.body,
};

class _ProgressDetail extends StatefulWidget {
  const _ProgressDetail({required this.dest, this.initial, this.range});
  final ProgressDest dest;
  final ProgressData? initial;
  final ProgressRange? range;
  @override
  State<_ProgressDetail> createState() => _ProgressDetailState();
}

class _ProgressDetailState extends State<_ProgressDetail>
    with RevisionReload, _ProgressCommon {
  late ProgressRange _range = widget.range ?? ProgressRange.threeMonths;
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
      if (widget.range == null) {
        _range =
            ProgressRange.values
                .where((r) => r.name == p.getString('progress.range'))
                .firstOrNull ??
            _range;
      }
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
              icon: Icon(LucideIcons.plus, color: P.of(c).on(C.body)),
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
      // Clear of the title bar above (Build 90 spacing audit).
      const SizedBox(height: S.x3),
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
      // The More button's tap height already spaces this row from what
      // follows (Build 90 spacing audit).
      const SizedBox(height: S.x1),
      ...switch (kind) {
        _DetailKind.body => [
          _bodySummary(c, p, d, per, today),
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
          ..._foodSection(c, p, d, from, to, _comparable(per)),
          // The next Section brings its own space above its heading.
          ..._activitySection(c, p, d, from, to, _comparable(per)),
        ],
      },
    ];
  }

  /// "3-month average", for the selected period's row.
  static String _averageLabel(ProgressRange r) => switch (r) {
    ProgressRange.week => '7-day average',
    ProgressRange.month => '30-day average',
    ProgressRange.twoMonths => '2-month average',
    ProgressRange.threeMonths => '3-month average',
    ProgressRange.sixMonths => '6-month average',
    ProgressRange.year => '1-year average',
    ProgressRange.sinceStart => 'Average since the start',
    ProgressRange.all => 'Average of all readings',
  };

  /// The three weights a reader asks about, each named for what it is: the
  /// latest reading, the last 7 days, and the period chosen above (Build 95,
  /// Akshat's pick). Tape sites that moved across the period follow.
  Widget _bodySummary(
    BuildContext c,
    P p,
    ProgressData d,
    ProgressPeriod per,
    String today,
  ) {
    double u(double kg) => _unit == 'lb' ? kg * kLbPerKg : kg;
    String w(double kg) => '${_num(u(kg))} $_unit';
    String signed(double kg) =>
        '${kg >= 0 ? '+' : '−'}${_num(u(kg.abs()))} $_unit';
    String readings(int n) => '$n ${n == 1 ? 'reading' : 'readings'}';
    String span(String from, String to) => reviewWeekLabel(from, to);

    final ws = [
      for (final x in d.weights)
        if (x.date.compareTo(today) <= 0) x,
    ]..sort((a, b) => a.date.compareTo(b.date));
    final latest = d.latestWeightReading;
    final daily = ws.lastOrNull;
    final t = DateTime.parse(today);
    String back(int n) => dayLabelOf(DateTime(t.year, t.month, t.day - n));
    final now7 = BodyLogDb.sevenDayMean(d.weights, today);
    final oneDay =
        ws.length == 1 &&
        latest?.date == daily?.date &&
        latest?.kg == daily?.kg &&
        now7?.count == 1;
    final prev7 = BodyLogDb.sevenDayMean(d.weights, back(7));
    final week = span(back(6), today), weekBefore = span(back(13), back(7));

    Widget row(
      String label,
      String sub,
      String value, {
      bool selected = false,
    }) {
      final labelBlock = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: F.label.copyWith(color: selected ? p.on(C.body) : p.ink2),
          ),
          Text(sub, style: F.cap.copyWith(color: p.ink2, height: 1.4)),
        ],
      );
      final body = LayoutBuilder(
        builder: (c, box) {
          final painter = TextPainter(
            text: TextSpan(text: value, style: F.n24),
            textDirection: Directionality.of(c),
            textScaler: MediaQuery.textScalerOf(c),
          )..layout();
          final stacked = bigText(c) || box.maxWidth < painter.width + 160;
          painter.dispose();
          final number = SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(
              value,
              softWrap: false,
              style: F.n24.copyWith(color: p.ink),
            ),
          );
          if (stacked)
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                labelBlock,
                const SizedBox(height: S.x2),
                Align(alignment: Alignment.centerRight, child: number),
              ],
            );
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: labelBlock),
              const SizedBox(width: S.x2),
              number,
            ],
          );
        },
      );
      return Semantics(
        container: true,
        label: '$label${selected ? ', selected period' : ''}: $value. $sub',
        child: ExcludeSemantics(
          child: selected
              ? Container(
                  margin: const EdgeInsets.symmetric(vertical: S.x2),
                  padding: const EdgeInsets.all(S.x3),
                  decoration: BoxDecoration(
                    color: p.wash(C.body),
                    borderRadius: R.rMd,
                    border: Border.all(color: p.on(C.body), width: 1.5),
                  ),
                  child: body,
                )
              : Padding(
                  padding: const EdgeInsets.symmetric(vertical: S.x3),
                  child: body,
                ),
        ),
      );
    }

    final rows = <Widget>[];
    // A rule between plain rows; the selected row is its own box.
    void add(Widget r, {bool boxed = false}) {
      if (rows.isNotEmpty && !boxed) {
        rows.add(Divider(color: p.line, height: 1));
      }
      rows.add(r);
    }

    if (latest == null) {
      add(
        row(
          'Latest reading',
          d.readErrors.contains('Latest weight')
              ? 'Could not load. Pull to retry.'
              : daily == null
              ? 'No weigh-in yet'
              : 'Individual reading unavailable; daily weight shown below',
          '—',
        ),
      );
      if (daily != null)
        add(row('Latest daily weight', _md(daily.date), w(daily.kg)));
    } else {
      final at = latest.atTs > 0 ? DayClock.localAt(latest.atTs) : null;
      add(
        row(
          'Latest reading',
          at == null
              ? _md(latest.date)
              : '${_md(latest.date)}, '
                    '${MaterialLocalizations.of(c).formatTimeOfDay(TimeOfDay.fromDateTime(at))}',
          latest.entered != null && latest.unit == _unit
              ? '${_num(latest.entered!)} $_unit'
              : w(latest.kg),
        ),
      );
    }
    final weekSelected = _range == ProgressRange.week;
    if (oneDay) {
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: S.x2),
          child: Text(
            'One day of weight data. Its first reading is the 7-day average '
            'for now; a change needs another day.',
            style: F.cap.copyWith(color: p.ink2, height: 1.4),
          ),
        ),
      );
    } else {
      add(
        row(
          '7-day average',
          now7 == null
              ? 'No weigh-in in $week'
              : [
                  week,
                  readings(now7.count),
                  prev7 == null
                      ? 'none in $weekBefore to compare'
                      : '${signed(now7.kg - prev7.kg)} vs $weekBefore',
                ].join(' · '),
          now7 == null ? '—' : w(now7.kg),
          selected: weekSelected,
        ),
        boxed: weekSelected,
      );
    }
    if (!weekSelected && !oneDay) {
      final after =
          per.after ??
          (from: per.shownFrom, to: per.shownTo, days: 0, partial: false);
      final series = weightSeries(d.weights, unit: 'kg');
      final wa = weightWindow(series, after);
      final before = per.before;
      final wb = before == null ? null : weightWindow(series, before);
      add(
        row(
          '${_averageLabel(_range)} · selected',
          [
            span(after.from, after.to),
            if (wa.mean != null) readings(wa.count),
            if (wa.mean == null)
              'no weigh-in'
            else if (before == null)
              'no earlier stretch to compare'
            else if (wb?.mean == null)
              'none in ${span(before.from, before.to)} to compare'
            else
              '${signed(wa.mean! - wb!.mean!)} vs ${span(before.from, before.to)}',
          ].join(' · '),
          wa.mean == null ? '—' : w(wa.mean!),
          selected: true,
        ),
        boxed: true,
      );
    }

    // Tape sites that moved across the period, earlier → latest.
    final before = per.before, after = per.after;
    final sites = <Widget>[];
    if (before != null && after != null) {
      for (final site in BodySite.values) {
        final s = siteSeries(d.measures, site);
        final b = readingNear(s, before.from);
        final a = inRange(s, after.from, after.to).lastOrNull;
        if (a == null || b == null || a.date == b.date) continue;
        final places = bodyComparisonPlaces(b.value, a.value);
        final delta = a.value - b.value;
        sites.add(
          Padding(
            padding: const EdgeInsets.only(top: S.x2),
            // Wraps rather than squeezing: at large text the numbers drop
            // under the site and dates.
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: S.x2,
              children: [
                Text(
                  '${site.title} · ${_md(b.date)} → ${_md(a.date)}',
                  style: F.cap.copyWith(color: p.ink2),
                ),
                Text(
                  '${_num(b.value, places)} → ${_num(a.value, places)} in '
                  '(${delta >= 0 ? '+' : '−'}${_num(delta.abs(), places)})',
                  style: F.cap.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x4, S.x1, S.x4, S.x3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...rows,
          if (sites.isNotEmpty) ...[
            const SizedBox(height: S.x1),
            Text('TAPE', style: F.label.copyWith(color: p.ink2)),
            ...sites,
          ],
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
      Section(
        'Milestones',
        Surface(
          pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < notes.length; i++) ...[
                if (i > 0) Divider(color: p.line, height: 1),
                Semantics(
                  container: true,
                  label:
                      '${_md(notes[i].date)}: ${notes[i].title}. ${notes[i].sub}',
                  child: ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: S.x3),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 64,
                            child: Text(
                              _md(notes[i].date),
                              style: F.body.copyWith(
                                color: p.ink,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: S.x2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  notes[i].title,
                                  style: F.body.copyWith(
                                    color: p.ink,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  notes[i].sub,
                                  style: F.cap.copyWith(
                                    color: p.ink2,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
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
    // "Start" fits the four in one row; the line under the tabs says
    // "Since …" with the date.
    const ['7 days', '30 days', '3 months', 'Start'],
    _mainPeriods.indexOf(_range),
    (i) {
      setState(() {
        _range = _mainPeriods[i];
        _cursor = null;
      });
      if (widget.range == null) _save('progress.range', _mainPeriods[i].name);
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
        if (widget.range == null) _save('progress.range', r.name);
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
                semanticLabel: _metricKey == key
                    ? 'Chart $label, selected'
                    : 'Chart $label',
                onTap: () => _setMetric(key),
                child: Center(
                  child: Pill(label, _metricKey == key ? C.body : C.n400),
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
    final trend = m is WeightMetric && _trend;
    // The stats under the chart describe the line that is drawn: readings,
    // or the 7-day average when that is the line.
    final List<DatedValue> drawn = trend
        ? [
            for (final day in daysBetween(from, today))
              if (BodyLogDb.sevenDayMean(d.weights, day) case final mean?)
                (
                  date: day,
                  value: _unit == 'lb' ? mean.kg * kLbPerKg : mean.kg,
                ),
          ]
        : r;
    final summary = m is StepsMetric || drawn.isEmpty
        ? null
        : bodySummary(drawn);
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
              SubTabs(
                const ['Readings', '7-day average'],
                _trend ? 1 : 0,
                (i) => setState(() {
                  _trend = i == 1;
                  _cursor = null;
                }),
                color: C.body,
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
                title: trend
                    ? '7-day average'
                    : m is WeightMetric
                    ? 'Readings'
                    : m.label,
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
                      p.on(C.body),
                      axis: axis,
                      cursor: cursor,
                      fill: false,
                      dots: true,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: S.x2),
              if (summary != null && r.length > 1) ...[
                Text(
                  'ON THE CHART · ${trend ? '7-DAY AVERAGE' : 'READINGS'}',
                  style: F.label.copyWith(color: p.ink2),
                ),
                const SizedBox(height: S.x1),
              ],
              if (summary != null && r.length == 1 && m is! WeightMetric)
                _stat(
                  p,
                  'Latest reading',
                  '${_num(summary.latest.value)} ${m.unit}',
                  _md(summary.latest.date),
                ),
              if (summary != null && r.length == 1)
                Text(
                  'No earlier reading in this period to compare.',
                  style: F.cap.copyWith(color: p.ink2),
                ),
              if (summary != null && r.length > 1)
                _stats(c, [
                  _stat(
                    p,
                    trend ? 'First' : 'First reading',
                    '${_num(summary.start.value)} ${m.unit}',
                    _md(summary.start.date),
                  ),
                  _stat(
                    p,
                    trend ? 'Latest' : 'Latest reading',
                    '${_num(summary.latest.value)} ${m.unit}',
                    _md(summary.latest.date),
                  ),
                  _stat(
                    p,
                    'Change',
                    summary.count < 2
                        ? '—'
                        : '${summary.change >= 0 ? '+' : '−'}${_num(summary.change.abs())} ${m.unit}',
                    trend
                        ? 'over ${summary.count} days'
                        : '${summary.count} ${summary.count == 1 ? 'reading' : 'readings'}',
                  ),
                ]),
              if (steps != null)
                _stats(c, [
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
                ]),
              if (m is WeightMetric && d.weights.length > 1)
                if (_blockLine(d, today) case final line?)
                  Padding(
                    padding: const EdgeInsets.only(top: S.x2),
                    child: Text(line, style: F.cap.copyWith(color: p.ink3)),
                  ),
              // Body has no unit switch of its own any more (Build 95).
              if (m is WeightMetric)
                Text(
                  '$_unit · set in Settings → Units → Weight',
                  style: F.cap.copyWith(color: p.ink3),
                ),
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
        '${ch >= 0 ? '+' : '−'}${_num(u(ch.abs()))} vs the week from ${_md(previous.from)}',
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
    String setText(LiftComparison x, LiftSet s) => liftSetText(x.mode, s);
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

  /// The equal-length period before the one shown, or null where the page
  /// shows a span that has no equal "before" (Since start, All).
  DayWindow? _comparable(ProgressPeriod per) =>
      _range == ProgressRange.sinceStart || _range == ProgressRange.all
      ? null
      : per.before;

  PeriodInputs _inputsOf(ProgressData d, DayWindow w) => periodInputs(
    w,
    food: d.food,
    steps: d.steps,
    sleepMin: d.sleepMin,
    recovery: d.recovery,
    sessions: d.sessions,
  );

  List<Widget> _foodSection(
    BuildContext c,
    P p,
    ProgressData d,
    String from,
    String today,
    DayWindow? before,
  ) {
    final w = (
      from: from,
      to: today,
      days: daysBetween(from, today).length,
      partial: true,
    );
    final f = foodWindow(d.food, w);
    final b = before == null ? null : foodWindow(d.food, before);
    return [
      Section(
        'Food',
        Surface(
          framed: false,
          pad: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stats(c, [
                _stat(
                  p,
                  'Calories / day',
                  f.kcal == null ? '—' : thousands(f.kcal!),
                  '${f.kcalDays} of ${f.windowDays} days counted',
                  was: b == null
                      ? null
                      : b.kcal == null
                      ? 'no counted days'
                      : thousands(b.kcal!),
                ),
                _stat(
                  p,
                  'Protein / day',
                  f.protein == null ? '—' : '${f.protein!.round()} g',
                  '${f.proteinDays} complete days',
                  was: b == null
                      ? null
                      : b.protein == null
                      ? 'no complete days'
                      : '${b.protein!.round()} g',
                ),
              ]),
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
    DayWindow? before,
  ) {
    final now = _inputsOf(d, (
      from: from,
      to: today,
      days: daysBetween(from, today).length,
      partial: true,
    ));
    final was = before == null ? null : _inputsOf(d, before);
    String sleep(({double? minutes, int nights}) x) => x.minutes == null
        ? '—'
        : '${x.minutes! ~/ 60}h ${(x.minutes! % 60).round()}m';
    String rec(({double? pct, int days}) x) =>
        x.pct == null ? '—' : '${x.pct!.round()}';
    String steps(StepsSummary x) =>
        x.average == null ? '—' : thousands(x.average!);
    final w = now.workouts;
    return [
      Section(
        'Activity and recovery',
        Surface(
          framed: false,
          pad: const EdgeInsets.symmetric(vertical: S.x2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _stats(c, [
                _stat(
                  p,
                  'Workouts',
                  '${w.total}',
                  [
                    if (w.lift > 0) '${w.lift} lift',
                    if (w.run > 0) '${w.run} run',
                    if (w.walk > 0) '${w.walk} walk',
                    if (w.other > 0) '${w.other} other',
                  ].join(' · '),
                  was: was == null ? null : '${was.workouts.total}',
                ),
                _stat(
                  p,
                  'Steps / day',
                  steps(now.steps),
                  '${now.steps.days} days measured',
                  was: was == null ? null : steps(was.steps),
                ),
              ]),
              const SizedBox(height: S.x3),
              _stats(c, [
                _stat(
                  p,
                  'Sleep / night',
                  sleep(now.sleep),
                  '${now.sleep.nights} nights',
                  was: was == null ? null : sleep(was.sleep),
                ),
                _stat(
                  p,
                  'Recovery',
                  rec(now.recovery),
                  '${now.recovery.days} days',
                  was: was == null ? null : rec(was.recovery),
                ),
              ]),
            ],
          ),
        ),
      ),
    ];
  }
}

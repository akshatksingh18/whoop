// A rough night, and the one question the app cannot answer for itself.
//
// READ THE REFUSAL THIS WORKS INSIDE before changing anything here. It is
// written at the top of `analytics human/event_detection.dart` and it has three
// parts: the nocturnal signature is not specific (alcohol, a late meal, early
// illness, the luteal phase and a hot bedroom all look alike); there are no
// labels to train on; and a wrong "looks like a drinking night" is an
// accusation on a phone somebody else can see.
//
// The first two are answered by asking instead of guessing. The third is not,
// and a question that names alcohol is still the app raising alcohol. So the
// screen is split in half:
//
//   · THE STATE is a measurement and ships like any other. It says the night
//     was harder than this person's own nights and names WHICH measurements
//     moved. No cause, no score, no probability.
//   · THE ATTRIBUTION is opt-in, once, by a tap that names nothing. Until then
//     no tag vocabulary is rendered at all — and "alcohol" lives in that
//     vocabulary, so nobody meets it unasked.
//
// `alcoholNightFlag` IS NOT CALLED and must not be. What is called is
// [ana.roughNight], the one function that file says may ship — for its
// descriptor and nothing else. The four signs it counts are counted here from
// the four published nightly series, MDC-gated exactly the way the classifier
// gates them, because `roughNight` is a function of the sign COUNT and nothing
// else in `EventState` reaches this file.
//
// `NightSignature` is not used either. It may only exist as a REPLACEMENT for
// `multivariateAnomaly`, and that detector is live in the crossday rollup.
//
// One card per night, always: when this fires it REPLACES the "Sleeping heart
// rate ran high" card in `sleep_detail._unusual` rather than stacking on it.
// Two cards about one night are two observations as far as the reader can tell.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:provider/provider.dart';

import '../../ai/journal_ai.dart' show kJournalPresetTags;
import '../../data/db.dart';
import '../../data/journal_fields.dart' show formatMinuteOfDay;
import '../../data/local_repository.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../ui2.dart';
import 'journal_compose.dart';

/// Nights of the user's own record before any sign may fire. Matches
/// `alcoholNightFlag`'s own floor — below it the MAD of four nights is noise
/// with a scale attached.
const int kRoughNightMinNights = 7;

/// How far back the personal window reaches. Same 28 as the rest of Sleep.
const int kRoughNightWindow = 28;

/// A session ending at or after this local hour counts as late. Not a claim
/// about training — it is the hour past which the app can SAY something rather
/// than ask it.
///
/// ponytail: a flat 19:00 rather than "within N hours of sleep onset". Onset is
/// only trustworthy on a user-set window; swap it in if that changes.
const int kLateTrainingHour = 19;

/// Whether the attribution half has ever been asked for.
/// 'unset' (never asked) · 'on' (revealed, stays revealed) · 'never' (declined
/// for good — the reveal action stops being offered).
const String kRoughNightAsk = 'rough_night.ask';

/// The night the card was last dismissed on, so it does not come back.
const String kRoughNightDismissed = 'rough_night.dismissed';

/// The four nightly series the signature is built from, and the ONLY four.
/// Keys are `metric_series` keys, read as published — nothing is recomputed
/// here.
const _kRhr = 'rhr', _kRmssd = 'rmssd';
const _kDip = 'dip_pct', _kTempZ = 'skin_temp_z';

/// One night against the user's own window.
@immutable
class RoughNight {
  const RoughNight({
    required this.day,
    required this.signs,
    required this.descriptor,
    required this.moved,
    required this.knows,
  });

  final String day;

  /// How many of {RHR up, RMSSD down, HR dip blunted, skin temp up} cleared
  /// their minimal detectable change. Never rendered as a number — a count of
  /// signs printed on a card is a severity score with the word filed off.
  final int signs;

  /// [ana.roughNight]'s own words. Never retyped in this file.
  final String descriptor;

  /// Which measurements moved, in plain names, for the sentence under the
  /// headline. Order is the order they are counted in.
  final List<String> moved;

  /// What the app already knows about this night and therefore STATES rather
  /// than asks. Each is one finished sentence.
  final List<String> knows;

  bool get rough => signs >= 2;

  /// Tags worth offering, once attribution is opted into: the shared preset
  /// vocabulary minus anything already answered. `poor sleep` never appears —
  /// this card IS the sleep measurement, and asking the user to confirm it is
  /// asking them to grade the sensor.
  List<String> get ask => [
    for (final t in kJournalPresetTags)
      if (t != 'poor sleep' &&
          !(t == 'sick' && knows.any((k) => k.contains('illness'))))
        t,
  ];
}

/// Count the MDC-gated signs for [day] against the nights before it.
///
/// Pure, and the whole of the detection. [series] is keyed by `metric_series`
/// key then by date — exactly the shape [loadRoughNight] reads. Returns null
/// when the personal window is too short for the core pair to be gated at all,
/// which is an absence and never a zero.
///
/// The gates are `robustBaseline` (median + MAD) and `mdc` (1.96·√2·scale) from
/// the published foundations, the same two `alcoholNightFlag` uses. A sign that
/// cannot clear its own minimal detectable change does not count, and a
/// degenerate scale yields no MDC and therefore no sign — never a claim.
({int signs, List<String> moved})? roughNightSignCount(
  String day,
  Map<String, Map<String, double>> series, {
  int minNights = kRoughNightMinNights,
  int window = kRoughNightWindow,
}) {
  /// The [window] most recent values for [key] strictly BEFORE [day]. Strictly:
  /// a night compared against a window containing itself pulls its own baseline
  /// toward it and can never look unusual.
  List<double> history(String key) {
    final m = series[key];
    if (m == null) return const [];
    final days = m.keys.where((d) => d.compareTo(day) < 0).toList()..sort();
    final from = days.length > window ? days.length - window : 0;
    return [for (final d in days.sublist(from)) m[d]!];
  }

  double? tonight(String key) => series[key]?[day];

  final moved = <String>[];

  /// Did [v] sit [dir]·MDC away from the centre of [hist]? +1 = higher than
  /// usual is the sign, −1 = lower than usual is.
  bool fired(double? v, List<double> hist, int dir) {
    if (v == null || hist.length < minNights) return false;
    final b = ana.robustBaseline(hist, minValid: minNights);
    final m = ana.mdc(b);
    if (m == null || b.center == null) return false;
    return (v - b.center!) * dir > m;
  }

  final rhr = tonight(_kRhr), rmssd = tonight(_kRmssd);
  final rhrHist = history(_kRhr), rmssdHist = history(_kRmssd);
  // The core pair decides whether the night is decidable at all. Without both
  // series past the floor there is no state to report, only a shorter record.
  if (rhr == null ||
      rmssd == null ||
      rhrHist.length < minNights ||
      rmssdHist.length < minNights) {
    return null;
  }

  var signs = 0;
  if (fired(rhr, rhrHist, 1)) {
    signs++;
    moved.add('your resting heart rate ran higher');
  }
  if (fired(rmssd, rmssdHist, -1)) {
    signs++;
    moved.add('your HRV ran lower');
  }
  if (fired(tonight(_kDip), history(_kDip), -1)) {
    signs++;
    moved.add('your heart rate dropped less overnight than it usually does');
  }
  if (fired(tonight(_kTempZ), history(_kTempZ), 1)) {
    signs++;
    moved.add('your skin ran warmer');
  }
  return (signs: signs, moved: moved);
}

/// Read [day]'s state, plus everything the app can state about it instead of
/// asking. Null whenever there is no card to show — a short record, a night
/// that was ordinary, or a night this screen has no business commenting on.
///
/// FOUR indexed series reads and three read-seam calls, no compute. `getToday`
/// is not among them: [day] is passed in because the caller already knows which
/// night it is looking at.
Future<RoughNight?> loadRoughNight(LocalRepository repo, String day) async {
  // MEASURED ONLY. This is a detection, not a chart: the night is called
  // rough by comparing it against the spread of the days behind it, and a
  // day another vendor's algorithm derived is not the same measurement.
  // A picture may splice two algorithms; a statistic may not.
  //
  // Read ONCE for all four series rather than passing `measuredOnly: true`
  // four times: that flag inlines the mask as a subquery whose expensive half
  // is a LIKE over whole `day_result` bundles, so four series meant four full
  // scans of the user's history for one answer (see LocalDb.importedDates).
  final imported = await LocalDb.importedDates();
  final series = <String, Map<String, double>>{};
  for (final key in const [_kRhr, _kRmssd, _kDip, _kTempZ]) {
    series[key] = {
      for (final r in await LocalDb.metricSeries(key))
        if (r['date'] is String &&
            r['value'] is num &&
            !imported.contains(r['date']))
          r['date'] as String: (r['value'] as num).toDouble(),
    };
  }
  final counted = roughNightSignCount(day, series);
  if (counted == null || counted.signs < 2) return null;

  final knows = <String>[];

  // LATE TRAINING — the app has the end time, so it says it.
  try {
    final sessions = (await repo.getDayTimeline(day))['sessions'];
    if (sessions is List) {
      DateTime? latest;
      for (final s in sessions) {
        if (s is! Map) continue;
        final end = s['end_ts'];
        if (end is! num) continue;
        final t = DateTime.fromMillisecondsSinceEpoch(end.toInt() * 1000);
        if (t.hour >= kLateTrainingHour &&
            (latest == null || t.isAfter(latest))) {
          latest = t;
        }
      }
      if (latest != null) {
        final at = formatMinuteOfDay(latest.hour * 60 + latest.minute);
        knows.add('You trained until $at, which often does this on its own.');
      }
    }
  } catch (_) {/* a knowable that could not be read is simply not stated */}

  // ILLNESS — the same night's CUSUM state, from the rollup that already ran.
  try {
    final recent = (await repo.getInsights())['recent'];
    if (recent is List) {
      for (final r in recent) {
        if (r is Map && r['date'] == day && r['illness'] == true) {
          knows.add(
            'The illness watch flagged this night too — a sustained rise '
            'against your own baseline, not a diagnosis.',
          );
          break;
        }
      }
    }
  } catch (_) {/* the rollup fails closed; so does this */}

  // LUTEAL PHASE — `getCycle().phase` is TODAY'S phase and only today's, which
  // is one of the reasons the host offers this card for last night alone.
  try {
    final cycle = await repo.getCycle();
    if (cycle['enabled'] == true && cycle['phase'] == 'luteal') {
      knows.add(
        'You are in the luteal phase, which lifts resting heart rate and '
        'skin temperature by itself.',
      );
    }
  } catch (_) {/* cycle tracking off, or nothing logged */}

  // WARM ROOM — only when the temp sign is one of the ones that fired. The
  // channel is relative ADC, so this is "warmer than your usual", never a
  // temperature.
  if (counted.moved.any((m) => m.contains('skin'))) {
    knows.add(
      'Your skin ran warmer than your usual — a warm room does this too.',
    );
  }

  return RoughNight(
    day: day,
    signs: counted.signs,
    // The descriptor is [ana.roughNight]'s, reached through the struct it
    // takes. Every other field is inert: `roughNight` reads `signsPresent` and
    // nothing else, and the hypothesis band is fixed to 'none' because no
    // hypothesis was formed — the classifier never ran.
    descriptor:
        ana
            .roughNight(
              ana.EventState(
                state: '',
                alcoholHypothesisBand: 'none',
                rhrDelta: 0,
                rmssdDelta: 0,
                rhrZ: null,
                rmssdZ: null,
                signsPresent: counted.signs,
                ambiguous: false,
              ),
            )
            .value!
            .descriptor,
    moved: counted.moved,
    knows: knows,
  );
}

/// The card, and the tap that reveals the question.
///
/// Dismissible, and dismissal is remembered per night so it never comes back.
/// Nothing about the dismissal is written to the journal: a user who said
/// nothing has told us nothing, and a "declined" row is a label they did not
/// give.
class RoughNightCard extends StatefulWidget {
  const RoughNightCard({
    super.key,
    required this.night,
    this.onDismiss,
    this.ask,
  });

  final RoughNight night;

  /// Called after a dismissal or a save, so the host can drop the card.
  final VoidCallback? onDismiss;

  /// Force the opt-in state instead of reading the stored one — the gallery
  /// and the sweeps need every state on screen at once, the same way every
  /// other component here takes its state as a fixture.
  final String? ask;

  @override
  State<RoughNightCard> createState() => _RoughNightCardState();
}

class _RoughNightCardState extends State<RoughNightCard> {
  final _picked = <String>{};
  late String _ask = widget.ask ?? Prefs.getString(kRoughNightAsk, 'unset');
  bool _saving = false;

  void _setAsk(String v) {
    Prefs.setString(kRoughNightAsk, v);
    setState(() => _ask = v);
  }

  void _dismiss() {
    Prefs.setString(kRoughNightDismissed, widget.night.day);
    widget.onDismiss?.call();
  }

  /// Agreeing writes the tags the user picked onto that night, MERGED into
  /// whatever was already logged.
  ///
  /// `postJournal` replaces the row's whole tag set, so the stored day is read
  /// first — the same read-merge the compose screen does. Nothing numeric is
  /// written: the card asked whether, not how much, and a quantity nobody gave
  /// is a fabricated one. "Add how much" leads to the editor that does ask.
  Future<void> _save() async {
    if (_saving || _picked.isEmpty) return;
    setState(() => _saving = true);
    try {
      final repo = context.read<AppState>().repo;
      if (repo == null) return;
      Map<String, dynamic>? row;
      for (final e in await repo.getJournal(range: '30d')) {
        if (e['date'] == widget.night.day) row = e;
      }
      final tags = <String>{
        ...?(row?['tags'] as List?)?.map((t) => t.toString()),
        ..._picked,
      };
      await repo.postJournal(
        widget.night.day,
        tags.toList(),
        (row?['note'] as String?) ?? '',
      );
      _dismiss();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = widget.night;
    // "a rougher night than usual for you — your body worked harder overnight"
    // splits at the dash into a headline and its own explanation.
    final dash = n.descriptor.indexOf('—');
    final head =
        dash < 0 ? n.descriptor : n.descriptor.substring(0, dash).trim();

    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(LucideIcons.moonStar, size: 18, color: p.on(C.indigo)),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                  // Sentence case from the analytics wording, which is written
                  // lower-case for use mid-sentence.
                  head.isEmpty
                      ? 'A rougher night than usual'
                      : head[0].toUpperCase() + head.substring(1),
                  style: F.head.copyWith(
                    color: p.ink,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                ),
              ),
              const SizedBox(width: S.x2),
              Pressable(
                semanticLabel: 'Dismiss',
                onTap: _dismiss,
                child: Icon(LucideIcons.x, size: 16, color: p.ink3),
              ),
            ],
          ),
          const SizedBox(height: S.x3),
          Text(
            '${_sentence(n.moved)}, against your own nights. '
            'This is a measurement of the night, not a verdict on you.',
            style: F.cap.copyWith(color: p.ink2, height: 1.5),
          ),
          // WHAT THE APP ALREADY KNOWS. Stated, never asked — a screen that
          // asks about the session it recorded itself is a form, not an
          // observation.
          for (final k in n.knows) ...[
            const SizedBox(height: S.x3),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(LucideIcons.dot, size: 16, color: p.on(C.indigo)),
                const SizedBox(width: S.x2),
                Expanded(
                  child: Text(
                    k,
                    style: F.cap.copyWith(color: p.ink2, height: 1.5),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: S.x4),
          if (_ask == 'on') ..._question(c, p, n) else ..._invite(c, p),
        ],
      ),
    );
  }

  /// The half nobody sees until they ask for it. The action names nothing that
  /// is in the vocabulary behind it.
  List<Widget> _invite(BuildContext c, P p) => [
    if (_ask != 'never')
      BigButton(
        'Tell it what happened',
        icon: LucideIcons.messageSquarePlus,
        color: C.indigo,
        soft: true,
        onTap: () => _setAsk('on'),
      )
    else
      Text(
        'Nothing to answer — this card only reports the night.',
        style: F.over.copyWith(color: p.ink3, height: 1.5),
      ),
  ];

  List<Widget> _question(BuildContext c, P p, RoughNight n) => [
    Text(
      n.knows.isEmpty ? 'What else was going on?' : 'Anything else?',
      style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600),
    ),
    const SizedBox(height: S.x3),
    Wrap(
      spacing: S.x2,
      runSpacing: S.x2,
      children: [
        for (final t in n.ask)
          Pressable(
            onTap: () => setState(
              () => _picked.contains(t) ? _picked.remove(t) : _picked.add(t),
            ),
            child: Pill(
              t,
              _picked.contains(t) ? C.domMind : C.n400,
              icon: _picked.contains(t) ? LucideIcons.check : null,
            ),
          ),
      ],
    ),
    const SizedBox(height: S.x4),
    BigButton(
      _saving ? 'Saving' : 'Log it for that night',
      icon: LucideIcons.check,
      color: C.domMind,
      onTap: _saving || _picked.isEmpty ? null : _save,
    ),
    const SizedBox(height: S.x3),
    // The amounts live in the editor that already asks for them, and the
    // amount is what the correlation engine actually reads.
    Pressable(
      onTap: () => Navigator.of(c).push(
        MaterialPageRoute<void>(builder: (_) => JournalCompose(date: n.day)),
      ),
      child: Text(
        'Add how much',
        style: F.cap.copyWith(color: p.on(C.domMind)),
      ),
    ),
    const SizedBox(height: S.x2),
    Pressable(
      onTap: () => _setAsk('never'),
      child: Text(
        'Do not ask again',
        style: F.over.copyWith(color: p.ink3),
      ),
    ),
  ];

  /// "a, b and c" — the moved measurements as one clause.
  static String _sentence(List<String> parts) {
    if (parts.isEmpty) return 'Several overnight measurements moved together';
    final s = parts.length == 1
        ? parts.first
        : '${parts.sublist(0, parts.length - 1).join(', ')} and ${parts.last}';
    return s[0].toUpperCase() + s.substring(1);
  }
}

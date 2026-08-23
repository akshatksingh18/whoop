// The Oura ring as a [BandAdapter]: authenticate, drain its history by cursor,
// bank every byte, decode only what has been proven.
//
// NOTHING HERE HAS MET HARDWARE, and unlike `ble_hrs` there is not even a
// public specification to fall back on. It ships EXPERIMENTAL (ASSUMPTIONS R6),
// its rows carry a non-null `source` and `kDerivableSources` does not contain
// it, so nothing it writes can become a number until the owner has held a ring
// in his own hands. That is correct behaviour for an uncalibrated decoder, not
// a limitation to work around.
//
// WHY THIS IS THE OPPOSITE SHAPE TO gen4, and why the seam fits it. gen4's
// offload is TRIM-ON-ACK: the band deletes flash when the host says so, the
// handshake has three wire outcomes, and the decision to trim depends on
// whether the HOST's durable commit landed (ASSUMPTIONS G1-G4 — which is why
// gen4 is not behind this seam). Oura's is FETCH-BY-CURSOR: the ring never
// deletes anything on our say-so, there is no acknowledgement in the protocol
// at all, and the host's only state is a bookmark. Re-reading a range is
// idempotent — 48.5% of the reference capture is the same records delivered
// twice, and `decoded_onehz` is keyed `(device_id, ts_ms)` with REPLACE, so a
// re-read overwrites rather than duplicates.
//
// That is exactly the "fetch-by-range: `confirm()` advances the adapter's own
// cursor" row in [OffloadCheckpoint]'s own table, and this file is the first
// implementation of it. The ordering still holds and still means something: the
// cursor does not move until the host has committed, so an interrupted sync
// re-reads rather than skips.
//
// PAIRING EVICTS THE OURA APP, AND IT IS A PRECONDITION RATHER THAN A SIDE
// EFFECT. The ring holds exactly one 16-byte key and will only accept a new one
// while it is FACTORY RESET — so a ring that is currently onboarded to Oura's
// app cannot be paired here at all until the owner factory-resets it, which is
// what removes it from that app. There is no state in which both work. Any
// pairing UI must say that before the user commits, not after.
//
// THE KEY IS OURS AND IT NEVER LEAVES THE PHONE. It is generated locally, there
// is no vendor server anywhere in the handshake and no Oura account is needed —
// which is the whole reason this band is not declined the way a vendor-issued
// pairing token would be. Losing it costs another factory reset, nothing more.

import 'dart:async';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show AESEngine, ECBBlockCipher, KeyParameter;

import '_registry.dart';
import 'adapter.dart';
import 'oura_wire.dart';
import 'signals.dart';

/// Encrypt one authentication challenge.
///
/// The ring issues a 15-byte nonce; PKCS#7 pads it to exactly one 16-byte block
/// (a single 0x01), and the answer is that block under AES-128 in ECB mode with
/// the pairing key. One block, so ECB's usual objection — that identical
/// plaintext blocks repeat — has nothing to bite on, and the ring picks a fresh
/// nonce per connection.
///
/// Exposed rather than private so the test can pin it against a known vector
/// without a radio.
Uint8List ouraAuthResponse(List<int> key, List<int> nonce) {
  if (key.length != 16 || nonce.length != 15) {
    throw ArgumentError('Oura auth takes a 16-byte key and a 15-byte nonce');
  }
  final block = Uint8List(16)
    ..setRange(0, 15, nonce)
    ..[15] = 0x01;
  final out = Uint8List(16);
  ECBBlockCipher(AESEngine())
    ..init(true, KeyParameter(Uint8List.fromList(key)))
    ..processBlock(block, 0, out, 0);
  return out;
}

/// One Oura session.
///
/// NOT const and not a registry singleton, because it needs two things a const
/// adapter cannot hold: the pairing key, and the cursor to resume from. Both
/// belong to the HOST — the key is a secret it stores, the cursor is a bookmark
/// it persists — and handing them in at construction is what lets the seam stay
/// a one-way `Stream<BandEvent>` instead of growing an inbound command channel.
class OuraAdapter extends BandAdapter {
  /// The 16-byte pairing key this phone generated and wrote to this ring.
  final List<int> key;

  /// Where to resume the history drain, on the ring's decisecond clock. 0 asks
  /// for everything the ring still holds.
  final int startCursorDs;

  /// Wall-clock now, in Unix seconds. Injected so a fixture replay is
  /// deterministic — `DateTime.now()` does not appear in this file.
  final int Function() nowSeconds;

  /// How long to wait for a reply the ring owes us.
  final Duration replyTimeout;

  /// How long to wait for the host to commit a batch and call `confirm`.
  /// Expiring is SAFE: the cursor does not move, so the batch is re-read.
  /// Overridable only so a test does not have to sit through it.
  final Duration confirmTimeout;

  OuraAdapter({
    required this.key,
    this.startCursorDs = 0,
    int Function()? nowSeconds,
    this.replyTimeout = const Duration(seconds: 5),
    this.confirmTimeout = const Duration(seconds: 30),
  }) : nowSeconds = nowSeconds ??
            (() => DateTime.now().millisecondsSinceEpoch ~/ 1000);

  @override
  BandEntry get entry => kOura;

  /// NOTHING, and that is the honest answer today rather than a placeholder.
  ///
  /// The ring emits beat-to-beat intervals, SpO2 and a hypnogram, and this
  /// adapter decodes none of them: their layouts are bit-packed and there is
  /// not one captured byte of any of them to check a decoder against. A
  /// declared-but-absent signal is WORSE than a missing one (see
  /// [BandAdapter.signals]) — it turns a card that should delete itself into
  /// one that is permanently empty — so nothing is claimed until a decoder
  /// exists and a real capture has met it.
  ///
  /// Temperature is emitted below and still not declared here, deliberately:
  /// [InputSignal.skinTempRaw] means RELATIVE ADC COUNTS (I8), and this ring
  /// reports absolute degrees Celsius. They are not the same input and the
  /// per-family calibration that I8 exists to key does not apply. There is no
  /// member for absolute temperature and one should not be invented for a band
  /// nobody owns.
  @override
  Map<InputSignal, Duration> get signals => const {};

  /// How many events one history request may return. The wire field is a u8,
  /// so this is its ceiling, and it is also what tells a full batch from a
  /// short one when the cursor is advanced.
  static const int _kMaxEventsPerBatch = 255;

  /// The (ring decisecond, Unix second) pair this session is stamping against.
  ///
  /// Set once, from the first batch, and thereafter only IMPROVED — by a
  /// `time_sync` event, which is the one record that carries both clocks and so
  /// is the only measured bridge between them. It is not re-derived per batch:
  /// a re-anchored batch would write the same physiological second under a
  /// different `ts_ms` and duplicate rows that REPLACE cannot collapse.
  ///
  /// ponytail: session-scoped. It resets on every connect, so two sessions can
  /// still disagree by their arrival jitter about where a given record sits.
  /// The fix is to persist the pair beside the cursor and detect a ring reboot
  /// by the counter going backwards — do it when a host exists to persist it.
  (int ds, int unix)? _anchor;

  int _anchorUnixFor(int ds) {
    final a = _anchor!;
    // 10 deciseconds to the second. The subtraction is on the ring's own clock,
    // so the SPACING between records is exact however wrong the origin is.
    return a.$2 + (ds - a.$1) ~/ 10;
  }

  @override
  Stream<BandEvent> run(BandLink link) async* {
    final inbox = _Inbox();
    final sub = link.notify(kOuraNotifyChar).listen(
          (rec) {
            final f = parseFrame(rec.$2);
            if (f != null) inbox.add(rec.$1, f);
          },
          onDone: inbox.close,
          onError: (Object _) => inbox.close(),
        );
    try {
      if (!await _authenticate(link, inbox)) return;

      // Both writes are documented preconditions of a history drain rather than
      // housekeeping. The clock set is also what makes a later `time_sync`
      // event exist at all, and that event is the only anchor between the
      // ring's decisecond counter and a date.
      await link.write(kOuraCommandChar, ouraCmdSetNotifyFlags(0x3f));
      await link.write(kOuraCommandChar, ouraCmdSyncTime(nowSeconds()));

      var cursor = startCursorDs;
      // A misbehaving ring that answers every request with the same batch would
      // otherwise spin here forever on a live radio.
      for (var batch = 0; batch < 5000; batch++) {
        // Passed explicitly rather than left to the builder's default: the
        // cursor advance below compares the batch's own count against this
        // number, and two copies of it that could drift is a silent skip.
        final req = ouraCmdGetEvents(cursor, maxEvents: _kMaxEventsPerBatch);
        if (!await link.write(kOuraCommandChar, req)) {
          link.log('oura: history request refused; ending the drain.');
          return;
        }
        final got = await _collectBatch(inbox);
        if (got == null) {
          link.log('oura: no batch summary within the reply window.');
          return;
        }
        if (got.events.isEmpty) return;

        _anchor ??= (got.maxDs, got.arrivalSec);
        for (final e in got.events) {
          final unix = decodeTimeSync(e);
          // A better origin for this record and every one after it. Applied
          // BEFORE the batch is stamped so the batch carrying the sync is
          // itself correct.
          if (unix != null) _anchor = (e.tsDs, unix);
        }

        yield* _emit(link, got);

        // THE ORDERING IS THE POINT. The host commits durably, then calls
        // confirm, and only then does the cursor move. Nothing is deleted
        // either way — the ring has no trim — so a host that never confirms
        // costs a re-read, never a record.
        final done = Completer<bool>();
        yield OffloadCheckpoint(
          () async {
            if (!done.isCompleted) done.complete(true);
            return true;
          },
          remaining: got.summary.bytesLeft,
        );
        final confirmed = await done.future
            .timeout(confirmTimeout, onTimeout: () => false);
        if (!confirmed) {
          link.log('oura: batch was not confirmed; leaving the cursor put.');
          return;
        }
        // A FULL BATCH RE-READS ITS LAST DECISECOND; A SHORT ONE MOVES PAST IT.
        //
        // The cursor is a TIMESTAMP, not a record index, and the batch cap is a
        // record count — so a batch that came back full may have been cut in
        // the middle of a decisecond that holds more records than fitted.
        // Jumping to `maxDs + 1` there silently drops the remainder, and
        // nothing downstream can tell: the gap is in the ring's flash, not in
        // ours. Re-reading `maxDs` instead costs one duplicated decisecond,
        // which `decoded_onehz`'s REPLACE key absorbs for free.
        //
        // The `> cursor` guard is the escape: a ring with a whole batch inside
        // one decisecond would otherwise re-ask for the same thing forever, and
        // a bounded loss beats an unbounded stall.
        final full = got.summary.received >= _kMaxEventsPerBatch;
        cursor = (full && got.maxDs > cursor) ? got.maxDs : got.maxDs + 1;
        yield BandNote('oura_cursor_ds', cursor);
        if (got.summary.bytesLeft <= 0) return;
      }
    } finally {
      await sub.cancel();
    }
  }

  /// Nonce, encrypt, answer. False on any refusal — a session that carries on
  /// unauthenticated gets `auth required` to every command and looks identical
  /// to a dead link.
  Future<bool> _authenticate(BandLink link, _Inbox inbox) async {
    if (!await link.write(kOuraCommandChar, ouraCmdAuthNonce())) return false;
    final challenge =
        await inbox.firstWhere((f) => ouraAuthNonce(f) != null, replyTimeout);
    if (challenge == null) {
      link.log('oura: no authentication challenge.');
      return false;
    }
    final answer = ouraAuthResponse(key, ouraAuthNonce(challenge)!);
    if (!await link.write(kOuraCommandChar, ouraCmdAuthenticate(answer))) {
      return false;
    }
    final reply =
        await inbox.firstWhere((f) => ouraAuthResult(f) != null, replyTimeout);
    final result = reply == null ? null : ouraAuthResult(reply);
    if (result != 0) {
      // Worth naming, because the remedies differ: a wrong key needs re-pairing
      // and a ring in factory reset needs its key installed first.
      link.log('oura: authentication refused (result ${result ?? "none"}).');
      return false;
    }
    return true;
  }

  /// Read frames until the batch summary arrives.
  Future<_Batch?> _collectBatch(_Inbox inbox) async {
    final events = <OuraEvent>[];
    final raw = <Uint8List>[];
    var maxDs = 0;
    var arrival = 0;
    while (true) {
      final rec = await inbox.next(replyTimeout);
      if (rec == null) return null;
      final (at, f) = rec;
      final summary = parseBatchSummary(f);
      if (summary != null) return _Batch(events, raw, maxDs, arrival, summary);
      if (ouraIsAuthRequired(f)) return null;
      final e = parseEvent(f);
      if (e == null) continue;
      events.add(e);
      // The WHOLE frame, header included, so a re-decode later sees exactly
      // what the radio delivered rather than this file's idea of it.
      raw.add(Uint8List.fromList(<int>[f.tag, f.payload.length, ...f.payload]));
      if (e.tsDs > maxDs) maxDs = e.tsDs;
      arrival = at;
    }
  }

  /// Turn one collected batch into events for the host.
  Stream<BandEvent> _emit(BandLink link, _Batch got) async* {
    final samples = <NeutralSample>[];
    for (final e in got.events) {
      switch (e.tag) {
        case kOuraEvtTemp:
        case kOuraEvtTempPeriod:
          final t = decodeTemperatures(e);
          // The array's probes are not identified — one may be an ambient
          // reference — so the first is taken and the rest are left in the
          // archive rather than averaged into a number that means nothing.
          if (t != null && t.isNotEmpty) {
            samples.add(NeutralSample(
              anchor: TimeAnchor.arrival,
              tsEpoch: _anchorUnixFor(e.tsDs),
              skinTempC: t.first,
            ));
          }
        case kOuraEvtDebugData:
          final d = decodeDebugData(e.body);
          if (d == null) break;
          if (d.text != null) link.log('oura fw: ${d.text}');
          if (d.batteryPct != null) yield BandNote('battery', d.batteryPct);
          if (d.batteryMv != null) yield BandNote('battery_mv', d.batteryMv);
      }
    }
    // EVERY event frame is archived, including the ones just decoded and every
    // one that was not. Beat intervals, SpO2, the hypnogram and steps all live
    // in here undecoded, and that is the point: the bytes are banked now so a
    // decoder written when someone owns a ring can be run over them, instead of
    // a guess being run over them today (owner rulings R1-R3).
    yield SampleBatch(samples, raw: got.raw);
  }
}

/// One batch of history, as collected off the wire.
class _Batch {
  final List<OuraEvent> events;
  final List<Uint8List> raw;
  final int maxDs;

  /// When the last frame of this batch reached the phone. Only ever used as the
  /// fallback origin for the very first batch of a session.
  final int arrivalSec;
  final OuraBatchSummary summary;
  const _Batch(this.events, this.raw, this.maxDs, this.arrivalSec, this.summary);
}

/// Frames off the notify characteristic, buffered so that a reply landing
/// before anyone is waiting is not dropped.
///
/// Hand-rolled rather than `package:async`'s `StreamQueue` because that would
/// mean promoting a transitive dependency to a direct one for one class, and
/// the whole of what this session needs is "the next frame, or nothing".
class _Inbox {
  final List<(int, OuraFrame)> _buf = [];
  Completer<(int, OuraFrame)?>? _waiter;
  bool _closed = false;

  void add(int atSec, OuraFrame f) {
    final w = _waiter;
    if (w != null && !w.isCompleted) {
      _waiter = null;
      w.complete((atSec, f));
      return;
    }
    _buf.add((atSec, f));
  }

  void close() {
    _closed = true;
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete(null);
  }

  /// The next frame, or null on timeout or a closed link.
  Future<(int, OuraFrame)?> next(Duration timeout) {
    if (_buf.isNotEmpty) return Future.value(_buf.removeAt(0));
    if (_closed) return Future.value(null);
    final w = Completer<(int, OuraFrame)?>();
    _waiter = w;
    return w.future.timeout(timeout, onTimeout: () {
      if (identical(_waiter, w)) _waiter = null;
      return null;
    });
  }

  /// The next frame satisfying [test], discarding what comes before it.
  /// [timeout] bounds the whole search, not each frame.
  Future<OuraFrame?> firstWhere(
    bool Function(OuraFrame) test,
    Duration timeout,
  ) async {
    final deadline = Stopwatch()..start();
    while (deadline.elapsed < timeout) {
      final rec = await next(timeout - deadline.elapsed);
      if (rec == null) return null;
      if (test(rec.$2)) return rec.$2;
    }
    return null;
  }
}

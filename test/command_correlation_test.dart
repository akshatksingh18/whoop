// Command/response correlation — sequence allocation and response
// correlation", "Sequence-zero compatibility path", "Ordering", "`PENDING` is
// per-command" and "Timeouts and retries".
//
// What this stands in for: the engine used to await band replies with two
// ad-hoc one-shot completers (HELLO and GET_CLOCK) that fired on "a reply of
// roughly the right shape arrived". Any reply for that opcode — an earlier
// request's, a periodic poll's, a different command's answer landing on the
// same characteristic — released the gate, and the app then acted on it as if
// it were the answer to the question it had just asked. Correlation is what
// makes "the strap answered ME" a fact rather than an assumption.
//
// The pure half exercises the match rules; the wiring half drives the real
// engine over the debugWriteHook seam, where the ordering (observer installed
// BEFORE the write) is the thing that can only be checked end to end.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/ble/ble_state.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

const _fast = Duration(milliseconds: 40);

/// A synthetic revision-1 gen5 hello body,
/// parsed by the real protocol decoder so the identity fields under test are
/// the ones a strap would actually produce.
Uint8List _helloBody({String serial = 'W5AB12CD34', int tsSeconds = 0}) {
  final body = Uint8List(Gen5HelloInfo.semanticBodyLen);
  final v = ByteData.sublistView(body);
  body[0] = 1; // hello revision
  v.setUint32(1, 730, Endian.little); // 73.0% → 73
  v.setUint32(6, tsSeconds, Endian.little);
  for (var i = 0; i < serial.length && 14 + i < 25; i++) {
    body[14 + i] = serial.codeUnitAt(i);
  }
  v.setUint32(87, 82, Endian.little); // optical discriminator ⇒ WHOOP 5
  body[91] = 50;
  body[92] = 40;
  body[93] = 1; // firmware 50.40.1
  body[102] = 1; // on wrist
  return body;
}

Decoded _helloReply(
  int seq, {
  int status = CommandAwaiter.statusSuccess,
  String serial = 'W5AB12CD34',
  int tsSeconds = 0,
}) =>
    Decoded('cmd_response', {
      'opcode': Cmd.getHello,
      'req_seq': seq,
      'cmd_status': status,
      if (status == CommandAwaiter.statusSuccess)
        'gen5_hello':
            Gen5HelloInfo.parse(_helloBody(serial: serial, tsSeconds: tsSeconds))!,
    });

/// A gen5 link with no radio behind it, plus the seq of every command written.
class _Link {
  final logs = <String>[];
  final written = <({int seq, int opcode})>[];
  late final BleEngine engine;

  /// Mutable so a test can flip the link's behaviour mid-scenario (e.g. four
  /// failed writes, then a working link).
  bool writesSucceed;
  Decoded? Function(int seq, int opcode)? replyTo;

  _Link({
    this.writesSucceed = true,
    this.replyTo,
  }) {
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
    engine.debugInstallFakeLink(
      band: BandProfile.gen5,
      onWrite: (frame) async {
        final inner = parseFrame(frame, profile: BandProfile.gen5)!.inner;
        final seq = inner[1];
        final opcode = inner[2];
        written.add((seq: seq, opcode: opcode));
        if (!writesSucceed) return false;
        // The reply is injected from INSIDE the write, i.e. before the write
        // call has even returned to `_sendAwaited`. That is the ordering the
        // contract
        // demands: install the observer, then write. A registry built the other
        // way round loses every fast response.
        final reply = replyTo?.call(seq, opcode);
        if (reply != null) engine.debugAbsorbDecoded(reply);
        return true;
      },
    );
  }

  int seqOf(int opcode) =>
      written.lastWhere((w) => w.opcode == opcode).seq;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BleEngine.resetBandClaimForTest);
  tearDown(BleEngine.resetBandClaimForTest);

  group('CommandAwaiter — both fields must match', () {
    test('a reply echoing the sequence AND the opcode satisfies the await',
        () async {
      final a = CommandAwaiter();
      final p = a.register(0xA0, Cmd.getClock, timeout: _fast);
      expect(a.pendingCount, 1);

      expect(
        a.deliver(opcode: Cmd.getClock, reqSeq: 0xA0, status: 1, fields: const {
          'clock_epoch': 42,
        }),
        CommandDelivery.completed,
      );

      final r = await p.response;
      expect(r, isNotNull);
      expect(r!.opcode, Cmd.getClock);
      expect(r.seq, 0xA0);
      expect(r.success, isTrue);
      expect(r.fields['clock_epoch'], 42);
      expect(r.viaSeqZeroFallback, isFalse);
      expect(a.pendingCount, 0, reason: 'a satisfied command is forgotten');
    });

    test('a sequence match with the WRONG opcode is rejected and times out',
        () async {
      final a = CommandAwaiter();
      final p = a.register(0xA0, Cmd.getHello, timeout: _fast);

      expect(
        a.deliver(opcode: Cmd.getClock, reqSeq: 0xA0, status: 1),
        CommandDelivery.unmatched,
        reason: 'a sequence match by itself is insufficient',
      );
      expect(a.pendingCount, 1, reason: 'the await must stay open');
      expect(await p.response, isNull, reason: 'and then expire');
    });

    test('an opcode match with a sequence we never sent is rejected', () async {
      final a = CommandAwaiter();
      final p = a.register(0xA0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 0xA1, status: 1),
          CommandDelivery.unmatched);
      expect(await p.response, isNull);
    });

    test('a reply carrying no correlation fields satisfies nothing', () async {
      final a = CommandAwaiter();
      a.register(0xA0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: null, status: 1),
          CommandDelivery.unmatched);
      expect(a.deliver(opcode: null, reqSeq: 0xA0, status: 1),
          CommandDelivery.unmatched);
      expect(a.pendingCount, 1);
    });

    test('sequence zero is a valid sequence, matched exactly', () async {
      final a = CommandAwaiter();
      final p = a.register(0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 0, status: 1),
          CommandDelivery.completed);
      final r = await p.response;
      expect(r!.viaSeqZeroFallback, isFalse,
          reason: 'this is an exact match, not the compatibility path');
    });
  });

  group('CommandAwaiter — sequence-zero compatibility path', () {
    test('an originating seq of 0 matches a nonzero request by opcode',
        () async {
      final a = CommandAwaiter();
      final p = a.register(0xA0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 0, status: 1),
          CommandDelivery.completed);
      final r = await p.response;
      expect(r!.seq, 0xA0, reason: 'the request keeps its own sequence');
      expect(r.viaSeqZeroFallback, isTrue);
    });

    test('the opcode must still match', () async {
      final a = CommandAwaiter();
      final p = a.register(0xA0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getHello, reqSeq: 0, status: 1),
          CommandDelivery.unmatched);
      expect(await p.response, isNull);
    });

    test('two outstanding requests for one opcode make it AMBIGUOUS — refuse',
        () async {
      // The fallback's own caveat: "if you implement this fallback, serialize command
      // transactions, otherwise two outstanding requests with the same opcode
      // become ambiguous". Guessing which one a seq-0 reply belongs to is how
      // an old request's answer becomes the new request's result.
      final a = CommandAwaiter();
      final first = a.register(0xA0, Cmd.getClock, timeout: _fast);
      final second = a.register(0xA1, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 0, status: 1),
          CommandDelivery.unmatched);
      expect(a.pendingCount, 2);
      expect(await first.response, isNull);
      expect(await second.response, isNull);
    });

    test('the fallback can be switched off entirely', () async {
      final a = CommandAwaiter(seqZeroFallback: false);
      final p = a.register(0xA0, Cmd.getClock, timeout: _fast);

      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 0, status: 1),
          CommandDelivery.unmatched);
      expect(await p.response, isNull);
    });
  });

  group('CommandAwaiter — PENDING is per-command', () {
    test('GET_HELLO(145) waits past PENDING for a terminal result', () async {
      final a = CommandAwaiter();
      final p = a.register(7, Cmd.getHello, timeout: _fast);

      expect(
        a.deliver(
            opcode: Cmd.getHello,
            reqSeq: 7,
            status: CommandAwaiter.statusPending),
        CommandDelivery.pendingHeld,
      );
      expect(a.pendingCount, 1, reason: 'PENDING is not an answer here');

      expect(
        a.deliver(
            opcode: Cmd.getHello,
            reqSeq: 7,
            status: CommandAwaiter.statusSuccess),
        CommandDelivery.completed,
      );
      expect((await p.response)!.success, isTrue);
    });

    test('GET_DATA_RANGE(34) waits past PENDING too, and FAILURE is terminal',
        () async {
      final a = CommandAwaiter();
      final p = a.register(9, Cmd.getDataRange, timeout: _fast);

      expect(
        a.deliver(
            opcode: Cmd.getDataRange,
            reqSeq: 9,
            status: CommandAwaiter.statusPending),
        CommandDelivery.pendingHeld,
      );
      expect(
        a.deliver(
            opcode: Cmd.getDataRange,
            reqSeq: 9,
            status: CommandAwaiter.statusFailure),
        CommandDelivery.completed,
      );
      final r = await p.response;
      expect(r!.failed, isTrue);
      expect(r.success, isFalse);
    });

    test('every other command completes on the FIRST matching response',
        () async {
      // SET_CLOCK(10), GET_ADVERTISING_NAME(141), 22, 23 and 20 all take the
      // base policy. Only 145 and 34 are listed as waiting past PENDING.
      for (final opcode in [
        Cmd.setClock,
        Cmd.getCustomAdvertisingName,
        Cmd.sendHistoricalData,
        Cmd.historicalDataResult,
        Cmd.abortHistoricalTransmits,
      ]) {
        final a = CommandAwaiter();
        final p = a.register(11, opcode, timeout: _fast);
        expect(
          a.deliver(
              opcode: opcode,
              reqSeq: 11,
              status: CommandAwaiter.statusPending),
          CommandDelivery.completed,
          reason: 'opcode $opcode must not wait past PENDING',
        );
        expect((await p.response)!.status, CommandAwaiter.statusPending);
      }
      expect(CommandAwaiter.pendingIsNonTerminal, {145, 34});
    });

    test('UNSUPPORTED is terminal for everything', () async {
      final a = CommandAwaiter();
      final p = a.register(3, Cmd.getHello, timeout: _fast);
      expect(
        a.deliver(
            opcode: Cmd.getHello,
            reqSeq: 3,
            status: CommandAwaiter.statusUnsupported),
        CommandDelivery.completed,
      );
      expect((await p.response)!.unsupported, isTrue);
    });
  });

  group('CommandAwaiter — timeouts and lifetime', () {
    test('the timeout is 5,000 ms, applied once, with no resend', () async {
      expect(CommandAwaiter.defaultTimeout, const Duration(milliseconds: 5000));
      final a = CommandAwaiter();
      final p = a.register(1, Cmd.getClock, timeout: _fast);

      expect(await p.response, isNull);
      expect(a.pendingCount, 0, reason: 'an expired command is forgotten');
      // Nothing here resends: a late reply for an expired request finds no
      // waiter, which is the point — a duplicate write after a slow-but-
      // successful response is a real hazard for state-mutating commands.
      expect(a.deliver(opcode: Cmd.getClock, reqSeq: 1, status: 1),
          CommandDelivery.unmatched);
      expect(await p.response, isNull, reason: 'and it stays expired');
    });

    test('a reply that lands before anyone awaits it is still captured',
        () async {
      // The ordering rule in registry form: the observer exists from `register`
      // onwards, not from the first `await`.
      final a = CommandAwaiter();
      final p = a.register(2, Cmd.getClock, timeout: _fast);
      a.deliver(opcode: Cmd.getClock, reqSeq: 2, status: 1);
      expect(await p.response, isNotNull);
    });

    test('cancel releases a command without waiting out its timeout',
        () async {
      final a = CommandAwaiter();
      final p = a.register(4, Cmd.getClock, timeout: const Duration(hours: 1));
      p.cancel();
      expect(await p.response, isNull);
      expect(a.pendingCount, 0);
    });

    test('failAll drains the registry (the link went down)', () async {
      final a = CommandAwaiter();
      final p1 = a.register(5, Cmd.getClock, timeout: const Duration(hours: 1));
      final p2 = a.register(6, Cmd.getHello, timeout: const Duration(hours: 1));
      a.failAll();
      expect(a.pendingCount, 0);
      expect(await p1.response, isNull);
      expect(await p2.response, isNull);
    });
  });

  group('HelloIdentity — the READY identity gate, observed not enforced', () {
    test('alphanumeric serial and CPU pass', () {
      final id = HelloIdentity.evaluate(serial: 'W5AB12CD34', cpuHex: 'abc123');
      expect(id.ok, isTrue);
      expect(id.eepromFailureSignal, isFalse);
    });

    test('a serial with punctuation or spaces fails the gate', () {
      expect(HelloIdentity.evaluate(serial: 'W5-AB', cpuHex: 'ab').serialOk,
          isFalse);
      expect(HelloIdentity.evaluate(serial: 'W5 AB', cpuHex: 'ab').serialOk,
          isFalse);
      expect(
          HelloIdentity.evaluate(serial: '', cpuHex: 'ab').serialOk, isFalse,
          reason: 'the regex is +, not *');
    });

    test('an empty CPU string fails; hex is alphanumeric by construction', () {
      expect(HelloIdentity.evaluate(serial: 'W5', cpuHex: '').cpuOk, isFalse);
      expect(HelloIdentity.evaluate(serial: 'W5', cpuHex: '00ff').cpuOk, isTrue);
    });

    test('an all-zero serial is an EEPROM signal that still PASSES', () {
      final id = HelloIdentity.evaluate(
        serial: '00000000000',
        cpuHex: 'ab',
        eepromFailureSignal: true,
      );
      expect(id.ok, isTrue, reason: 'not a reject on its own');
      expect(id.eepromFailureSignal, isTrue);
    });
  });

  group('engine wiring — the hello await is correlated', () {
    test('a reply injected DURING the write still finds its observer',
        () async {
      final link = _Link(
        replyTo: (seq, opcode) =>
            opcode == Cmd.getHello ? _helloReply(seq) : null,
      );

      expect(await link.engine.debugReadGen5Hello(), isTrue);
      expect(link.engine.pendingCommandCount, 0);
      expect(link.engine.helloFailureCount, 0);
      expect(link.engine.helloIdentity!.ok, isTrue);
    });

    test('a WRONG-OPCODE reply on the hello sequence does not satisfy it',
        () async {
      // The exact failure correlation exists to prevent: the strap answers a
      // different command, the reply carries our sequence, and the old
      // completer fired on it.
      late final _Link link;
      link = _Link(
        replyTo: (seq, opcode) => opcode == Cmd.getHello
            ? Decoded('cmd_response', {
                'opcode': Cmd.getClock,
                'req_seq': seq,
                'cmd_status': CommandAwaiter.statusSuccess,
              })
            : null,
      );

      final hello = link.engine.debugReadGen5Hello();
      await pumpEventQueue();
      expect(link.engine.pendingCommandCount, 1,
          reason: 'the hello await must still be open');
      expect(link.logs.any((l) => l.contains('matched no pending command')),
          isTrue,
          reason: 'a near miss is the symptom worth surfacing');

      // The real answer, correlated, closes it.
      link.engine.debugAbsorbDecoded(_helloReply(link.seqOf(Cmd.getHello)));
      expect(await hello, isTrue);
      expect(link.engine.pendingCommandCount, 0);
    });

    test('a PENDING hello keeps waiting for the terminal result', () async {
      late final _Link link;
      link = _Link(
        replyTo: (seq, opcode) => opcode == Cmd.getHello
            ? _helloReply(seq, status: CommandAwaiter.statusPending)
            : null,
      );

      final hello = link.engine.debugReadGen5Hello();
      await pumpEventQueue();
      expect(link.engine.pendingCommandCount, 1,
          reason: 'GET_HELLO(145) waits past PENDING');

      link.engine.debugAbsorbDecoded(_helloReply(link.seqOf(Cmd.getHello)));
      expect(await hello, isTrue);
    });

    test('the hello carries the sequence it was allocated', () async {
      final link = _Link(
        replyTo: (seq, opcode) =>
            opcode == Cmd.getHello ? _helloReply(seq) : null,
      );
      await link.engine.debugReadGen5Hello();
      // Live commands come from the high range; the canonical hello frame's
      // hard-coded seq 1 would collide with the INIT range.
      expect(link.seqOf(Cmd.getHello), greaterThanOrEqualTo(SeqAllocator.liveFloor));
    });
  });

  group('engine wiring — hello failures and the bond reset', () {
    test('failures accumulate and the fifth resets the counter + the bond',
        () async {
      final link = _Link(writesSucceed: false);

      for (var i = 1; i <= 4; i++) {
        expect(await link.engine.debugReadGen5Hello(), isFalse);
        expect(link.engine.helloFailureCount, i,
            reason: 'the count survives attempts, it is not per-connection');
      }
      expect(await link.engine.debugReadGen5Hello(), isFalse);
      expect(link.engine.helloFailureCount, 0,
          reason: 'at five, reset the counter');
      expect(link.logs.any((l) => l.contains('bond')), isTrue,
          reason: 'and remove the platform bond before starting over');
      expect(BleEngine.kHelloFailuresBeforeBondReset, 5);
    });

    test('a non-success status counts as a failed hello', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == Cmd.getHello
            ? _helloReply(seq, status: CommandAwaiter.statusFailure)
            : null,
      );

      expect(await link.engine.debugReadGen5Hello(), isFalse);
      expect(link.engine.helloFailureCount, 1);
    });

    test('a successful hello does NOT clear the accumulated failures — only '
        'READY does', () async {
      // A hello object arriving is not a completed bootstrap. Clearing here
      // let a link that kept dying between hello and READY reset its own
      // counter and never reach the five-failure bond reset; the clear now
      // lives at the READY transition (pinned in gen5_bootstrap_official_test).
      final link = _Link(writesSucceed: false);
      await link.engine.debugReadGen5Hello();
      await link.engine.debugReadGen5Hello();
      expect(link.engine.helloFailureCount, 2);

      link.writesSucceed = true;
      link.replyTo = (seq, opcode) =>
          opcode == Cmd.getHello ? _helloReply(seq) : null;
      expect(await link.engine.debugReadGen5Hello(), isTrue);
      expect(link.engine.helloFailureCount, 2,
          reason: 'still 2 — the count clears only when the connection '
              'reaches READY');
    });
  });

  group('engine wiring — the hello records the identity verdict', () {
    // The EXCHANGE succeeding and the IDENTITY passing are different
    // questions: _readGen5Hello reports whether a terminal successful, parsed
    // hello landed, and records the verdict; the bootstrap
    // (_gen5PostHelloGates) then ENFORCES it — a failed verdict fails the
    // connection there, which gen5_bootstrap_official_test pins.
    test('a non-alphanumeric serial completes the exchange with a failed '
        'verdict for the bootstrap to enforce', () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == Cmd.getHello
            ? _helloReply(seq, serial: 'W5-AB12')
            : null,
      );

      expect(await link.engine.debugReadGen5Hello(), isTrue,
          reason: 'the exchange itself succeeded — enforcement is the '
              'bootstrap\'s, and this must NOT count as a hello-exchange '
              'failure');
      expect(link.engine.helloFailureCount, 0);
      expect(link.engine.helloIdentity!.ok, isFalse);
      expect(link.engine.offloadSnapshot['hello_identity_ok'], isFalse);
    });

    test('an all-zero serial is an EEPROM diagnostic with a PASSING verdict',
        () async {
      final link = _Link(
        replyTo: (seq, opcode) => opcode == Cmd.getHello
            ? _helloReply(seq, serial: '0000000000')
            : null,
      );

      expect(await link.engine.debugReadGen5Hello(), isTrue);
      expect(link.engine.helloIdentity!.ok, isTrue,
          reason: 'all-zero passes the alphanumeric gate — the official rule');
      expect(link.engine.helloIdentity!.eepromFailureSignal, isTrue);
      expect(
          link.engine.offloadSnapshot['hello_serial_eeprom_failure'], isTrue);
    });
  });

  group('engine wiring — the battery poll correlates without blocking', () {
    test('the poll returns on the WRITE and the reply is correlated after',
        () async {
      final link = _Link(); // writes succeed, nothing ever answers

      final sw = Stopwatch()..start();
      await link.engine.getBattery();
      sw.stop();
      expect(sw.elapsed, lessThan(const Duration(seconds: 1)),
          reason: 'a display value must never hold the session-open path for '
              'the full command timeout');
      expect(link.engine.pendingCommandCount, 1,
          reason: 'the observer is still there waiting for the reply');

      link.engine.debugAbsorbDecoded(Decoded('cmd_response', {
        'opcode': Cmd.getBatteryLevel,
        'req_seq': link.seqOf(Cmd.getBatteryLevel),
        'cmd_status': CommandAwaiter.statusSuccess,
        'battery_pct': 42.0,
      }));

      expect(link.engine.pendingCommandCount, 0);
      expect(link.engine.state.batteryPct, 42.0);
    });
  });
}

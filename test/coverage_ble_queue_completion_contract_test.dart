// Retained transport-free command/serialization contracts,not a radio claim.
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:whoop_companion/ble/ble_state.dart';

void main() {
  for (final status in [0, 1, 3]) {
    for (final zero in [false, true]) {
      test(
        'a held HELLO completes only on correlated terminal $status with sequence-zero=$zero',
        () async {
          final a = CommandAwaiter();
          final p = a.register(27, 0x91);
          final unrelated = a.register(28, 0x22);
          try {
            expect(p.isCompleted, false);
            expect(
              a.deliver(opcode: 0x91, reqSeq: 26, status: 1),
              CommandDelivery.unmatched,
            );
            expect(p.isCompleted, false);
            expect(
              a.deliver(opcode: 0x91, reqSeq: zero ? 0 : 27, status: 2),
              CommandDelivery.pendingHeld,
            );
            expect(p.isCompleted, false);
            expect(a.pendingCount, 2);
            const fields = {
              'authored_identity': 'synthetic',
              'clock_epoch': 1617712200,
            };
            expect(
              a.deliver(
                opcode: 0x91,
                reqSeq: zero ? 0 : 27,
                status: status,
                fields: fields,
              ),
              CommandDelivery.completed,
            );
            final reply = (await p.response)!;
            expect(reply.opcode, 0x91);
            expect(reply.seq, 27);
            expect(reply.status, status);
            expect(reply.fields, fields);
            expect(reply.viaSeqZeroFallback, zero);
            expect(p.isCompleted, true);
            expect(unrelated.isCompleted, false);
            expect(a.pendingKeys, ['28/34']);
            expect(
              a.deliver(opcode: 0x91, reqSeq: zero ? 0 : 27, status: 1),
              CommandDelivery.unmatched,
            );
          } finally {
            a.failAll();
          }
          expect(unrelated.isCompleted, true);
          expect(await unrelated.response, isNull);
          expect(a.pendingCount, 0);
        },
      );
    }
  }
  for (final finish in ['cancel', 'timeout']) {
    test(
      'a pending command $finish releases its observer and permits the next same-opcode request',
      () async {
        final a = CommandAwaiter();
        final p = a.register(
          31,
          0x22,
          timeout: const Duration(milliseconds: 25),
        );
        expect(p.isCompleted, false);
        if (finish == 'cancel') p.cancel();
        expect(await p.response, isNull);
        expect(p.isCompleted, true);
        expect(a.pendingCount, 0);
        final next = a.register(32, 0x22);
        expect(
          a.deliver(opcode: 0x22, reqSeq: 0, status: 1),
          CommandDelivery.completed,
        );
        expect((await next.response)!.seq, 32);
        expect(next.isCompleted, true);
        expect(a.pendingCount, 0);
      },
    );
  }
  for (final zero in [false, true]) {
    test(
      'a generic correlated response without status is explicitly unknown,sequence-zero=$zero',
      () async {
        final a = CommandAwaiter();
        final p = a.register(41, 0x91);
        expect(
          a.deliver(opcode: 0x91, reqSeq: zero ? 0 : 41),
          CommandDelivery.completed,
        );
        expect((await p.response)!.status, -1);
        expect(p.isCompleted, true);
        expect(a.pendingCount, 0);
      },
    );
  }
  for (final asynchronous in [false, true]) {
    for (final refusal in [false, true]) {
      test(
        'the write chain retains order after ${asynchronous ? 'deferred' : 'immediate'} refusal=$refusal',
        () async {
          final chain = WriteChain(), independent = WriteChain();
          final gate = Completer<void>(), entered = Completer<void>();
          final trace = <String>[];
          final error = StateError('authored characteristic write refusal');
          final first = chain.add<bool>(() {
            trace.add('first:start');
            entered.complete();
            if (asynchronous) {
              return gate.future.then((_) {
                trace.add('first:end');
                if (refusal) throw error;
                return false;
              });
            }
            trace.add('first:end');
            if (refusal) throw error;
            return Future.value(false);
          });
          final observed = expectLater(
            first,
            refusal ? throwsA(same(error)) : completion(false),
          );
          final second = chain.add<bool>(() async {
            trace.add('second');
            return true;
          });
          await entered.future;
          expect(await independent.add<int>(() async => 7), 7);
          if (asynchronous) {
            expect(trace, ['first:start']);
            gate.complete();
          }
          await observed;
          expect(await second, true);
          expect(
            await chain.add<String>(() async => 'fresh write'),
            'fresh write',
          );
          expect(trace, ['first:start', 'first:end', 'second']);
        },
      );
    }
  }
}

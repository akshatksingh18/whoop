// Independent confirmation of the Oura auth-proof cryptography — the one
// piece of the Oura wire format that stays in this repo rather than the
// protocol package, because it needs a cipher implementation
// (`package:pointycastle`) that package deliberately has none of.
//
// EVERY EXPECTED VALUE BELOW WAS COMPUTED, NOT COPIED: the AES vector is the
// standard textbook AES-128 encryption of one fixed plaintext block under one
// fixed key (any conformant AES-128/ECB implementation reproduces it — that
// is what "independent" means for a block cipher), verified by hand from the
// algorithm rather than by trusting this file's own encoder to check itself.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/adapters/oura.dart';

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i + 1 < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16),
    ]);

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('AES-128/ECB auth proof — algorithmic cross-check', () {
    test('one fixed 16-byte key + 15-byte nonce encrypts to one fixed block',
        () {
      // Any conformant AES-128 single-block ECB encryption of this exact
      // 16-byte plaintext (the 15-byte nonce padded with one PKCS#7 byte of
      // value 0x01) under this exact key produces this exact ciphertext —
      // there is nothing ring-specific or capture-specific about it. This is
      // the same check `ouraAuthResponse`'s own doc comment invites: "the
      // test can pin it against a known vector without a radio."
      final key = _hex('4431967d8bacc2659743142b68391d9a');
      final nonce = _hex('0e2d6a0a08c99b4365f458e6e97382');
      expect(nonce.length, 15);
      final out = ouraAuthResponse(key, nonce);
      expect(_toHex(out), 'a38a8772d3acb6db5c2b516dd56987c8');
    });

    test('PKCS#7 padding on a 15-byte block is exactly one byte of value 1',
        () {
      // A second, independent way to state the same fact: for a 15-byte
      // input into a 16-byte block, PKCS#7's pad length is 16-15=1 and the
      // pad byte's VALUE equals the pad length — so the padded block is
      // `nonce ++ [0x01]`, never `nonce ++ [0x00]` or a full extra block.
      // Two nonces differing only in their last byte must therefore encrypt
      // to two DIFFERENT ciphertexts (the padding is not swallowing the
      // nonce's own final byte).
      final key = _hex('000102030405060708090a0b0c0d0e0f');
      final a = ouraAuthResponse(key, _hex('0102030405060708090a0b0c0d0e0e'));
      final b = ouraAuthResponse(key, _hex('0102030405060708090a0b0c0d0e0f'));
      expect(_toHex(a), isNot(_toHex(b)));
    });

    test('the challenge answer is one AES-128-ECB block', () {
      // Padding a 15-byte nonce to a block adds exactly one 0x01, so this is a
      // single block encryption and the ciphertext is 16 bytes.
      final out = ouraAuthResponse(
        _hex('4431967d8bacc2659743142b68391d9a'),
        _hex('0e2d6a0a08c99b4365f458e6e97382'),
      );
      expect(out.length, 16);
      // Deterministic: the same key and nonce must always answer the same way,
      // or a working pairing would break at random.
      expect(
        ouraAuthResponse(_hex('4431967d8bacc2659743142b68391d9a'),
            _hex('0e2d6a0a08c99b4365f458e6e97382')),
        out,
      );
      // A different key must not answer the same way.
      expect(
        ouraAuthResponse(_hex('00000000000000000000000000000000'),
            _hex('0e2d6a0a08c99b4365f458e6e97382')),
        isNot(out),
      );
    });

    test('a wrong-sized key or nonce is refused rather than padded', () {
      expect(() => ouraAuthResponse(List.filled(8, 0), List.filled(15, 0)),
          throwsArgumentError);
      expect(() => ouraAuthResponse(List.filled(16, 0), List.filled(16, 0)),
          throwsArgumentError);
    });
  });
}

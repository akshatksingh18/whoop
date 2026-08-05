// Gen5 (WHOOP 5 / Maverick) live IMU decode.
//
// Hardware evidence (fw 50.40.1.0 HCI snoop, 2026-08-05): after toggleImuMode
// with [revision1, 0x01] the strap emits gen5-framed **0x2B** inners of
// **1232 bytes**, not top-level 0x33:
//   [0]=0x2B [1]=0x15 … [13]=0x04 [14..15]=100 LE (sample count)
//   [16..17]=100 LE (rate) [18..19]=3 LE (axes)
//   [20 .. 20+600)=100 planar XYZ int16 LE @ 100 Hz, scale 1/4096 g
//
// Gen4 `frameAccel` only accepts 0x33 (≥84 B / 10 samples) or R10 (rec 0x0A
// @685 B). Every gen5 live IMU frame abstained → step calibration stayed 0
// despite console `IMU data stream enabled`.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:openstrap_protocol/openstrap_protocol.dart';

/// Gen5 live 0x2B subtype byte[1] seen on every Maverick IMU frame.
const int kGen5LiveImuRec = 0x15;

/// Minimum inner length: header through 100×3×int16 accel planes.
const int kGen5LiveImuMinLen = 620;

/// Samples per gen5 live IMU accel block (matches u16 @ offset 14).
const int kGen5LiveImuSamples = 100;

/// Accel planar XYZ starts here (after 0x04 / count / rate / axes sub-header).
const int kGen5LiveImuAccelOffset = 20;

Uint8List? _bytes(String hex) {
  try {
    return hexToBytes(hex);
  } catch (_) {
    return null;
  }
}

/// Decode a gen5 Maverick live 0x2B IMU inner, or null if not that layout.
ImuFrame? frameAccelGen5Live(String hex) {
  final b = _bytes(hex);
  if (b == null || b.length < kGen5LiveImuMinLen) return null;
  if (b[0] != PacketType.realtimeRawData || b[1] != kGen5LiveImuRec) {
    return null;
  }
  // Sample-count u16 LE @14 must be 100 — rejects other 0x2B shapes.
  final count = b[14] | (b[15] << 8);
  if (count != kGen5LiveImuSamples) return null;

  final view = b.buffer.asByteData(b.offsetInBytes, b.lengthInBytes);
  const n = kGen5LiveImuSamples;
  const start = kGen5LiveImuAccelOffset;
  final xs = <double>[];
  final ys = <double>[];
  final zs = <double>[];
  final mags = <double>[];
  for (var i = 0; i < n; i++) {
    final x = view.getInt16(start + 2 * i, Endian.little).toDouble();
    final y = view.getInt16(start + 2 * (n + i), Endian.little).toDouble();
    final z = view.getInt16(start + 2 * (2 * n + i), Endian.little).toDouble();
    xs.add(x);
    ys.add(y);
    zs.add(z);
    mags.add(math.sqrt(x * x + y * y + z * z) / 4096.0);
  }
  // Already 100 Hz — no upsample. ts=1: gen5 header has no reliable unix@4;
  // live ingest uses wall time for coverage; callers reject ts<=0.
  return ImuFrame(1, 0, mags, xs, ys, zs);
}

/// Gen5 Maverick live 0x2B first; else gen4 `frameAccel` (0x33 / R10).
ImuFrame? frameAccelForBand(String hex) =>
    frameAccelGen5Live(hex) ?? frameAccel(hex);

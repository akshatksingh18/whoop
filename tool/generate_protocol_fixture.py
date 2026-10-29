"""Public, synthetic byte-contract examples; never reads captures or calls the decoder.

Expected semantic values are authored alongside input construction. This checks known
offsets, absence and representation, not the validity of a field map on real hardware.
"""
from __future__ import annotations

import argparse
import json
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "packages/protocol/test/fixtures/synthetic_protocol.json"
EPOCH = 946684800  # Arbitrary synthetic epoch, 2000-01-01 UTC.
NAMED_OUTPUT = OUTPUT.with_name("synthetic_packets.json")
PACKET_EPOCH = 1609459200  # Independent fictional session, 2021-01-01 UTC.


def frame(body: bytes, gen5: bool = False) -> bytes:
    """Independent bitwise header CRCs and stdlib payload CRC; no Dart encoder."""
    body = body + bytes(-len(body) % 4)
    length = struct.pack("<H", len(body) + 4)
    if gen5:
        header = b"\xaa\x01" + length + b"\x01\x00"
        crc = 0xFFFF
        for value in header:
            crc ^= value
            for _ in range(8):
                crc = (crc >> 1) ^ (0xA001 if crc & 1 else 0)
        header += struct.pack("<H", crc)
    else:
        crc = 0
        for value in length:
            crc ^= value
            for _ in range(8):
                crc = ((crc << 1) ^ (7 if crc & 0x80 else 0)) & 255
        header = b"\xaa" + length + bytes([crc])
    return header + body + struct.pack("<I", zlib.crc32(body))


def named_packets() -> dict[str, str]:
    result = {}

    def put(name, body, gen5=None):
        result[name] = (bytes(body) if gen5 is None else frame(bytes(body), gen5)).hex()

    # HELLO payload offsets include echoed sequence/status. All identity is fictional.
    hello = bytearray(96)
    hello[0:3] = bytes([7, 1, 4])
    struct.pack_into("<H", hello, 3, 650)  # 65.0%, earlier u16 candidate is invalid.
    hello[16:26] = b"TEST00001\0"
    hello[26:91] = b"a" * 64 + b"\0"  # Fictional firmware token, not a credential.
    put("hello-payload", hello)
    for seq in (1, 2, 4):
        put(f"hello-frame-{seq}", bytes([0x24, seq, 0x23]) + hello, False)
    name = b"Sample WHOOP"
    put("name-frame", bytes([0x24, 3, 0x4C, 7, 1, 1, len(name)]) + name, False)

    for index in range(3):
        body = bytearray([0xA5] * 80)
        body[0:3] = bytes([0x2F, 25, 0])
        struct.pack_into("<IIH", body, 3, 0x10000000 + index, PACKET_EPOCH + index, 8192)
        put(f"g4-v25-frame-{index}", body, False)
        put(f"g4-v25-inner-{index}", body)

    owned_v24 = bytearray.fromhex(fixtures()[0]["hex"])
    # Also valid at the separately established v18/v7 HR offsets when a test
    # changes only the layout byte. Neither location overlaps the two RR slots.
    owned_v24[14] = owned_v24[27] = 64
    put("g4-v24-inner", owned_v24)
    short_v12 = bytearray(owned_v24[:88])
    short_v12[1] = 12
    put("g4-v12-short", short_v12)

    def header(size, version, index, seconds, subsec):
        body = bytearray(size)
        body[:3] = bytes([0x2F, version, 0x80])
        struct.pack_into("<IIH", body, 3, index, seconds, subsec)
        return body

    body = header(112, 18, 0x10000001, PACKET_EPOCH + 100, 8192)
    body[14:16] = bytes([78, 2])
    struct.pack_into("<hh", body, 16, 700, 750)
    body[28:30] = bytes([0x81, 77])
    body[32] = 255
    struct.pack_into("<ffff", body, 33, 0.125, 1, 0, 0)
    struct.pack_into("<H", body, 49, 42)
    body[51] = 160
    struct.pack_into("<hhhH", body, 61, 250, 270, 3200, 0x1234)
    body[98:102] = bytes([32, 64, 10, 20])
    struct.pack_into("<f", body, 105, -2.5)
    put("g5-v18-frame", body, True)
    put("g5-v18-inner", body)
    for index in range(4):
        archived = bytearray(body)
        struct.pack_into("<II", archived, 3, 0x20000000 + index, PACKET_EPOCH + 400 + index)
        archived[14] = 80 + index
        struct.pack_into("<fff", archived, 37, 2.0, 0, 0)
        put(f"g5-archive-{index}", archived)

    body = header(76, 26, 0x10000002, PACKET_EPOCH + 101, 16384)
    struct.pack_into("<Hi", body, 13, 3, 262144)
    for index in range(24):
        struct.pack_into("<h", body, 19 + 2 * index, index - 12)
    struct.pack_into("<fH", body, 67, 0.25, 0x1234)
    body[73:76] = bytes([1, 1, 0])
    put("g5-v26-frame", body, True)
    for index in range(3):
        put(f"g5-header-{index}", header(13, 26, 0x10010001 + index, PACKET_EPOCH + index, 0))

    body = bytearray(20)
    body[0:2] = bytes([0x28, 7])
    struct.pack_into("<I", body, 2, PACKET_EPOCH + 200)
    body[8:10] = bytes([72, 2])
    struct.pack_into("<hh", body, 10, 700, 750)
    body[18] = 1
    put("g5-live-hr-frame", body, True)
    body = bytearray(24)
    body[:3] = bytes([0x31, 7, 2])
    struct.pack_into("<I", body, 3, PACKET_EPOCH + 201)
    struct.pack_into("<II", body, 13, 123456, 17)
    put("g5-history-end-frame", body, True)

    body = header(1232, 21, 100, PACKET_EPOCH + 300, 0)
    body[0] = 0x2B  # Same planar buffer in a realtime envelope.
    struct.pack_into("<H", body, 16, 100)
    struct.pack_into("<H", body, 622, 100)
    for index in range(100):
        struct.pack_into("<h", body, 420 + index * 2, 4096)
        struct.pack_into("<h", body, 632 + index * 2, index - 50)
    put("g5-live-imu", body)
    return result


def fixtures() -> list[dict]:
    cases = []

    def case(kind, body, expected):
        cases.append({"source": "synthetic", "kind": kind, "hex": body.hex(), "out": expected})

    def sample(ts, hr, record_type, activity=None, steps=None):
        return {"ts": ts, "hr": hr, "rec_type": record_type, "activity": activity,
                "steps_inc": steps, "wrist_on": hr > 0}

    # Exact binary fractions avoid approximating an independent float-rounding oracle.
    for index, version in enumerate([24, 12, 7, 9, 18, 99]):
        body = bytearray(96)
        body[0:2] = bytes([0x2F, version])
        ts, counter, subsec, hr = EPOCH + index, 1000 + index, index * 4096, 64 + index
        struct.pack_into("<IIH", body, 3, counter, ts, subsec)
        body[{7: 27, 18: 14}.get(version, 17)] = hr
        body[18] = 2
        struct.pack_into("<hh", body, 19, 600, 800)
        struct.pack_into("<H", body, 29, 257)
        body[31] = 11
        struct.pack_into("<f", body, 32, 0.5)
        struct.pack_into("<fff", body, 36, 0.25, 0, 1.25)
        struct.pack_into("<f", body, 48, 256)
        body[52:64] = body[36:48]
        struct.pack_into("<HHHH", body, 64, 400, 700, 1000, 2000)
        trusted = version in (24, 12)
        expected = {"ts_epoch": ts, "ts_subsec": subsec, "counter": counter, "hr": hr,
                    "rr_count": 2 if trusted else 0,
                    "rr_intervals_ms": [600, 800] if trusted else [],
                    "ppg_green": 257 if trusted else None,
                    "ppg_red_ir": 11 if trusted else None, "accel_g": [0.25, 0, 1.25],
                    "skin_contact": 67 if trusted else None,
                    "spo2_red_raw": 400 if trusted else None,
                    "spo2_ir_raw": 700 if trusted else None,
                    "skin_temp_raw": 1000 if trusted else None,
                    "ambient_raw": 2000 if trusted else None, "raw_tail": body[13:].hex()}
        case("r24", body, expected)
        case("record", body, None if version == 99 else sample(ts, hr, version))

    # Waveform version: timing exists, biometric/optical/acceleration quantities do not.
    body = bytearray(80)
    body[0:2] = bytes([0x2F, 25])
    struct.pack_into("<II", body, 3, 2020, EPOCH + 20)
    case("r24", body, {"ts_epoch": EPOCH + 20, "ts_subsec": 0, "counter": 2020,
                       "hr": 0, "rr_count": 0, "rr_intervals_ms": [], "ppg_green": None,
                       "ppg_red_ir": None, "accel_g": [], "skin_contact": None,
                       "spo2_red_raw": None, "spo2_ir_raw": None, "skin_temp_raw": None,
                       "ambient_raw": None, "raw_tail": body[13:].hex()})
    case("record", body, sample(EPOCH + 20, 0, 25))

    # Compact HR: explicit still/off-wrist and RR bounds, with no invented motion.
    for index, (hr, intervals) in enumerate([(0, []), (72, [800, 900]), (88, [199, 200, 2500, 2501])]):
        body = bytearray(20)
        body[0], body[8], body[9] = 0x28, hr, len(intervals)
        ts = EPOCH + 30 + index
        struct.pack_into("<I", body, 2, ts)
        for slot, value in enumerate(intervals):
            struct.pack_into("<h", body, 10 + slot * 2, value)
        body[18] = 1
        case("record", body, sample(ts, hr, 28))
        accepted = [x for x in intervals if 200 <= x <= 2500]
        case("rr", body, {"ts": ts, "rr_ms": accepted} if accepted else None)
    body[9] = 5
    case("rr", body, None)  # Would read wearing bytes as a fifth RR interval.

    # R10: known constant acceleration produces zero variance/gait, not missing motion.
    body = bytearray(685)
    body[0:2] = bytes([0x2B, 10])
    struct.pack_into("<I", body, 7, EPOCH + 40)
    body[17], body[18] = 76, 2
    struct.pack_into("<hh", body, 19, 700, 750)
    for index in range(100):
        struct.pack_into("<h", body, 485 + 2 * index, 4096)
    case("record", body, sample(EPOCH + 40, 76, 10, 0, 0))
    case("record", body[:84], sample(EPOCH + 40, 76, 10))
    case("rr", body, {"ts": EPOCH + 40, "rr_ms": [700, 750]})
    case("accel", body, {"ts": EPOCH + 40, "idx": 0, "mags": [1] * 100})

    # Live IMU: negative raw axes survive independently of their positive magnitude.
    body = bytearray(84)
    body[0] = 0x33
    struct.pack_into("<I", body, 4, EPOCH + 50)
    struct.pack_into("<H", body, 14, 7)
    for index in range(10):
        struct.pack_into("<h", body, 64 + 2 * index, -4096)
    case("accel", body, {"ts": EPOCH + 50, "idx": 7, "mags": [1] * 10})
    case("record", body, None)
    for kind in ("r24", "record", "rr", "accel"):
        case(kind, bytearray([0x2F, 24]), None)
    return cases


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    for output, data in [(OUTPUT, fixtures()), (NAMED_OUTPUT, named_packets())]:
        content = json.dumps(data, indent=2) + "\n"
        if args.check:
            if not output.exists() or output.read_text(encoding="utf-8") != content:
                raise SystemExit(f"Synthetic fixture drift in {output.name}: review and regenerate.")
        else:
            output.parent.mkdir(parents=True, exist_ok=True)
            output.write_text(content, encoding="utf-8")
    print(f"Synthetic protocol fixture: {len(fixtures())} independent byte-contract cases.")


if __name__ == "__main__":
    main()

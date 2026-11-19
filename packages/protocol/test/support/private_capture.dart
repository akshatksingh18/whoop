import 'dart:io';

// Optional local regression evidence. Never fetch or publish a real recording.
File? privateCapture(String name) {
  final dir = Platform.environment['WHOOP_PROTOCOL_CAPTURE_DIR'] ??
      '../../build/ownership-checkpoint/private-protocol-corpus';
  final file = File('$dir/$name');
  return file.existsSync() ? file : null;
}

final privateParityCapture = privateCapture('decode_parity_cases.json');
final privateCaptureSkip = privateParityCapture == null
    ? 'Private capture corpus absent; synthetic checks cannot replace hardware evidence'
    : null;

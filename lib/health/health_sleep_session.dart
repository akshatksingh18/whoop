import 'dart:async';

import 'package:flutter/services.dart';

enum HealthSleepStage { awake, rem, light, deep }

class HealthSleepStageInterval {
  const HealthSleepStageInterval({
    required this.start,
    required this.end,
    required this.stage,
  });

  final DateTime start;
  final DateTime end;
  final HealthSleepStage stage;

  Duration get duration => end.difference(start);

  Map<String, Object> toMap() => {
    'startTime': start.millisecondsSinceEpoch,
    'endTime': end.millisecondsSinceEpoch,
    'stage': stage.name,
  };
}

class HealthSleepSession {
  const HealthSleepSession({
    required this.start,
    required this.end,
    required this.stages,
  });

  final DateTime start;
  final DateTime end;
  final List<HealthSleepStageInterval> stages;

  Map<String, Object> toMap() => {
    'startTime': start.millisecondsSinceEpoch,
    'endTime': end.millisecondsSinceEpoch,
    'stages': stages.map((stage) => stage.toMap()).toList(),
  };
}

HealthSleepSession? normalizeHealthSleepSession(Map<String, dynamic> bundle) {
  final sleep = bundle['sleep'];
  final window = sleep is Map ? sleep['window'] : null;
  final value = window is Map ? window['value'] : null;
  final onsetMs = value is Map ? (value['onset_ms'] as num?)?.toInt() : null;
  final offsetMs = value is Map ? (value['offset_ms'] as num?)?.toInt() : null;
  if (onsetMs == null || offsetMs == null || offsetMs <= onsetMs) return null;

  final start = DateTime.fromMillisecondsSinceEpoch(onsetMs);
  final end = DateTime.fromMillisecondsSinceEpoch(offsetMs);
  final series = bundle['series'];
  final rawStages = series is Map ? series['hypnogram'] : null;
  final candidates = <HealthSleepStageInterval>[];
  if (rawStages is List) {
    for (final raw in rawStages) {
      if (raw is! Map) continue;
      final startSeconds = (raw['start'] as num?)?.toInt();
      final endSeconds = (raw['end'] as num?)?.toInt();
      final stage = healthSleepStageOf(raw['stage']?.toString());
      if (startSeconds == null || endSeconds == null || stage == null) continue;

      final rawStart = DateTime.fromMillisecondsSinceEpoch(startSeconds * 1000);
      final rawEnd = DateTime.fromMillisecondsSinceEpoch(endSeconds * 1000);
      final clippedStart = rawStart.isBefore(start) ? start : rawStart;
      final clippedEnd = rawEnd.isAfter(end) ? end : rawEnd;
      if (!clippedStart.isBefore(clippedEnd)) continue;
      candidates.add(
        HealthSleepStageInterval(
          start: clippedStart,
          end: clippedEnd,
          stage: stage,
        ),
      );
    }
  }

  candidates.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : a.end.compareTo(b.end);
  });

  final normalized = <HealthSleepStageInterval>[];
  var cursor = start;
  for (final candidate in candidates) {
    final normalizedStart = candidate.start.isBefore(cursor)
        ? cursor
        : candidate.start;
    if (!normalizedStart.isBefore(candidate.end)) continue;
    normalized.add(
      HealthSleepStageInterval(
        start: normalizedStart,
        end: candidate.end,
        stage: candidate.stage,
      ),
    );
    cursor = candidate.end;
  }

  return HealthSleepSession(start: start, end: end, stages: normalized);
}

HealthSleepStage? healthSleepStageOf(String? stage) {
  switch (stage) {
    case 'wake':
    case 'awake':
      return HealthSleepStage.awake;
    case 'rem':
      return HealthSleepStage.rem;
    case 'light':
    case 'nrem':
      return HealthSleepStage.light;
    case 'deep':
      return HealthSleepStage.deep;
    default:
      return null;
  }
}

abstract interface class HealthConnectSleepSessionWriter {
  Future<bool> replace(HealthSleepSession session);
}

class MethodChannelHealthConnectSleepSessionWriter
    implements HealthConnectSleepSessionWriter {
  MethodChannelHealthConnectSleepSessionWriter({
    this.channel = const MethodChannel('openstrap/health_connect_sleep'),
  });

  final MethodChannel channel;
  Future<void> _pending = Future<void>.value();

  @override
  Future<bool> replace(HealthSleepSession session) {
    final result = Completer<bool>();
    _pending = _pending.then((_) async {
      try {
        result.complete(
          await channel.invokeMethod<bool>(
                'replaceSleepSession',
                session.toMap(),
              ) ==
              true,
        );
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }
}

class HealthConnectSleepSessionExporter {
  const HealthConnectSleepSessionExporter({required this.writer});

  final HealthConnectSleepSessionWriter writer;

  Future<bool> replace(Map<String, dynamic> bundle) async {
    final session = normalizeHealthSleepSession(bundle);
    if (session == null) return true;
    if (session.stages.isEmpty) return false;
    return writer.replace(session);
  }
}

// Test-only partial readers preserve the existing fail-fast defaults and helpers.
// Production readers must implement the entire LocalRepository contract.
import 'package:whoop_companion/data/local_repository.dart';
import 'package:whoop_companion/compute/manual_session.dart' show SessionSpan;
import 'package:whoop_companion/gps/route_models.dart';
import 'package:whoop_companion/data/journal_fields.dart';
export 'package:whoop_companion/data/local_repository.dart';

abstract class TestLocalRepository extends LocalRepository {
  @override
  Future<Map<String, dynamic>> getProfile() =>
      throw UnimplementedError('re-layer: getProfile');

  @override
  Future<Map<String, dynamic>> getToday() =>
      throw UnimplementedError('re-layer: getToday');

  @override
  Future<List<Map<String, dynamic>>> sleepWindows({
    int days = 60,
    String? before,
  }) => throw UnimplementedError('re-layer: sleepWindows');

  @override
  Future<Map<String, dynamic>> getInsights() =>
      throw UnimplementedError('re-layer: getInsights');

  @override
  Future<Map<String, dynamic>> getDaySleepV2(String date) =>
      throw UnimplementedError('re-layer: getDaySleepV2');
  @override
  Future<Map<String, dynamic>> getDayStrain(String date) =>
      throw UnimplementedError('re-layer: getDayStrain');

  @override
  Future<Map<String, dynamic>> getZones() =>
      throw UnimplementedError('re-layer: getZones');
  @override
  Future<Map<String, dynamic>> getDaySleep(String date) =>
      throw UnimplementedError('re-layer: getDaySleep');
  @override
  Future<Map<String, dynamic>> getDayTimeline(String date) =>
      throw UnimplementedError('re-layer: getDayTimeline');

  @override
  Future<List<Map<String, num>>> getRecordedHr(int fromSec, int toSec) =>
      throw UnimplementedError('re-layer: getRecordedHr');

  @override
  Future<Map<String, dynamic>> getNightSignals(int onsetTs, int wakeTs) async =>
      const {};
  @override
  Future<Map<String, dynamic>> getDayLungs(String date) =>
      throw UnimplementedError('re-layer: getDayLungs');
  @override
  Future<Map<String, dynamic>> getDayWear(String date) =>
      throw UnimplementedError('re-layer: getDayWear');

  @override
  Future<Map<String, dynamic>> getDayNaps(String date) =>
      throw UnimplementedError('re-layer: getDayNaps');
  @override
  Future<Map<String, dynamic>> getDayHrv(String date) =>
      throw UnimplementedError('re-layer: getDayHrv');

  @override
  Future<num?> getMeasuredDaySteps(String date) async {
    final day = await getDaySteps(date);
    return (day['day_total'] ?? day['total']) as num?;
  }

  @override
  Future<Map<String, dynamic>> getDaySteps(String date) =>
      throw UnimplementedError('re-layer: getDaySteps');

  @override
  Future<List<String>> availableDays() =>
      throw UnimplementedError('re-layer: availableDays');

  @override
  Future<Map<String, dynamic>> getRecords() =>
      throw UnimplementedError('re-layer: getRecords');
  @override
  Future<Map<String, dynamic>> getChart(String metric, {int? from, int? to}) =>
      throw UnimplementedError('re-layer: getChart');

  @override
  Future<Map<String, dynamic>> getWorkouts({String range = 'month'}) =>
      throw UnimplementedError('re-layer: getWorkouts');
  @override
  Future<Map<String, dynamic>> getWorkout(String id) =>
      throw UnimplementedError('re-layer: getWorkout');
  @override
  Future<void> deleteWorkout(String id) =>
      throw UnimplementedError('re-layer: deleteWorkout');

  @override
  Future<void> setWorkoutPrivate(String id, bool private) =>
      throw UnimplementedError('re-layer: setWorkoutPrivate');

  @override
  Future<int> rescoreRecentSessions({int sinceDays = 3}) =>
      throw UnimplementedError('re-layer: rescoreRecentSessions');

  @override
  Future<int> repairSessionCalorieBasis() =>
      throw UnimplementedError('re-layer: repairSessionCalorieBasis');

  @override
  Future<Map<String, dynamic>> logManualWorkout({
    required int startTs,
    required int endTs,
    required String type,
  }) => throw UnimplementedError('re-layer: logManualWorkout');

  @override
  Future<Map<String, dynamic>> setWorkoutWindow(
    String id, {
    required int startTs,
    required int endTs,
  }) => throw UnimplementedError('re-layer: setWorkoutWindow');

  @override
  Future<List<SessionSpan>> savedSessionSpans() =>
      throw UnimplementedError('re-layer: savedSessionSpans');
  @override
  Future<WorkoutRoute?> getWorkoutRoute(String id) =>
      throw UnimplementedError('re-layer: getWorkoutRoute');

  @override
  Future<Map<String, dynamic>?> getJournalDay(String date) =>
      throw UnimplementedError('re-layer: getJournalDay');

  @override
  Future<void> mergeJournalTags(String date, List<String> tags) =>
      throw UnimplementedError('re-layer: mergeJournalTags');

  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(String date) =>
      throw UnimplementedError('re-layer: getJournalMetrics');

  @override
  Future<List<String>> saveJournalEdit(
    String date, {
    required Map<String, JournalMetricValue?> changes,
    required Map<String, JournalMetricValue> base,
    List<String>? tags,
    List<String>? baseTags,
    String? note,
    String? baseNote,
  }) => throw UnimplementedError('re-layer: saveJournalEdit');

  @override
  Future<List<JournalFieldSpec>> getJournalFields() =>
      throw UnimplementedError('re-layer: getJournalFields');

  @override
  Future<void> postCustomJournalField(JournalFieldSpec spec) =>
      throw UnimplementedError('re-layer: postCustomJournalField');

  @override
  Future<Map<String, dynamic>> getCycle() =>
      throw UnimplementedError('re-layer: getCycle');
}

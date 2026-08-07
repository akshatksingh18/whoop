# Health Connect Sleep Priority and Heart-Rate Batch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure the newest Android sleep session is always attempted before bulk health data and reduce continuous-heart-rate export from roughly 1,440 Health Connect calls per day to one typed replacement.

**Architecture:** Add a small testable priority-sleep coordinator in Dart, then add a typed Dart/MethodChannel/Android writer for one daily `HeartRateRecord` containing all minute samples. `HealthExporter` will call the priority coordinator before its existing oldest-to-newest loop, reuse that result to avoid a duplicate sleep write, and route Android heart rate through the new batch writer while preserving Apple Health's current generic writes.

**Tech Stack:** Flutter/Dart, `flutter_test`, Android Kotlin, `androidx.health.connect:connect-client:1.1.0-alpha07`, Flutter `MethodChannel`.

## Global Constraints

- The newest detected Android sleep session is the highest-priority Health Connect write.
- If the priority sleep write returns `false` or throws, stop before bulk metrics consume quota.
- Preserve minute-average heart-rate samples on Android.
- Preserve the existing Apple Health export path.
- Check every Boolean write result; `false` keeps the export unsuccessful.
- Do not change derivation, sleep staging, database contents, or UI behavior.
- Keep changes limited to health export code, Android channel registration, tests, and these design/plan documents.

---

## File Structure

- Create `lib/health/health_heart_rate_batch.dart`: typed sample model, normalization, platform-neutral export routing, and MethodChannel writer.
- Create `android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/HealthConnectHeartRateWriter.kt`: validate and replace one daily `HeartRateRecord` on `Dispatchers.IO`.
- Modify `android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/NativeChannels.kt`: register the new writer.
- Modify `lib/health/health_export.dart`: prioritize newest Android sleep and route continuous HR through the batch API.
- Modify `test/health_sleep_export_test.dart`: cover sleep-first/abort/no-duplicate behavior.
- Create `test/health_heart_rate_export_test.dart`: cover normalization, batching, Apple preservation, empty data, and `false` propagation.

---

### Task 1: Prioritize the newest Android sleep session

**Files:**
- Modify: `lib/health/health_export.dart`
- Modify: `test/health_sleep_export_test.dart`

**Interfaces:**
- Produces: `PrioritySleepExportResult` with `String? date` and `bool succeeded`.
- Produces: `exportNewestPrioritySleep({required Iterable<MapEntry<String, Map<String, dynamic>>> newestFirstDays, required Future<bool> Function(Map<String, dynamic>) write})`.
- Changes: `_exportDay(..., {bool androidSleepAlreadyWritten = false})`.

- [ ] **Step 1: Write failing coordinator tests**

Add tests that call the wished-for coordinator with three newest-first bundles. The first bundle has no valid sleep, the second has `_overnightBundle()`, and the third has an older valid sleep. Assert that only the second bundle is written and its date is returned. Add a second test whose writer returns `false` and assert `succeeded == false` and that a supplied bulk callback is never reached. Add a third assertion that `_exportDay` has a skip flag so the same date is not written twice in one export pass.

```dart
test('newest detected sleep is written before bulk and only once', () async {
  final writes = <Map<String, dynamic>>[];
  final result = await exportNewestPrioritySleep(
    newestFirstDays: [
      MapEntry('2026-08-06', <String, dynamic>{}),
      MapEntry('2026-08-05', _overnightBundle()),
      MapEntry('2026-08-04', _overnightBundle()),
    ],
    write: (bundle) async {
      writes.add(bundle);
      return true;
    },
  );

  expect(result.date, '2026-08-05');
  expect(result.succeeded, isTrue);
  expect(writes, hasLength(1));
});
```

- [ ] **Step 2: Run the focused test and verify RED**

Run: `flutter test test/health_sleep_export_test.dart --reporter expanded`

Expected: compilation fails because `PrioritySleepExportResult` and `exportNewestPrioritySleep` do not exist.

- [ ] **Step 3: Implement the minimal priority coordinator**

In `health_export.dart`, add the result type and function. Iterate newest-first, use `normalizeHealthSleepSession` only to identify the first bundle containing a valid detected sleep, call `write` exactly once, and return its date and Boolean result. Return `{date: null, succeeded: true}` when no pending bundle contains sleep.

```dart
class PrioritySleepExportResult {
  const PrioritySleepExportResult({required this.date, required this.succeeded});
  final String? date;
  final bool succeeded;
}

Future<PrioritySleepExportResult> exportNewestPrioritySleep({
  required Iterable<MapEntry<String, Map<String, dynamic>>> newestFirstDays,
  required Future<bool> Function(Map<String, dynamic>) write,
}) async {
  for (final day in newestFirstDays) {
    if (normalizeHealthSleepSession(day.value) == null) continue;
    return PrioritySleepExportResult(
      date: day.key,
      succeeded: await write(day.value),
    );
  }
  return const PrioritySleepExportResult(date: null, succeeded: true);
}
```

- [ ] **Step 4: Integrate priority sleep into `exportAll`**

Decode pending rows once into date/bundle entries. On Android, call `exportNewestPrioritySleep` before the normal loop using newest-first order and `_androidSleep.replace`. If it fails or throws, record the affected date in the existing retry-state shape (`attempts`, `last_ms`, `finalized`), persist it, and return `0` before any generic health write. Pass `androidSleepAlreadyWritten: date == priorityResult.date` into `_exportDay`; guard its native sleep block with `if (Platform.isAndroid && !androidSleepAlreadyWritten)`.

- [ ] **Step 5: Run focused tests and verify GREEN**

Run: `flutter test test/health_sleep_export_test.dart --reporter expanded`

Expected: all sleep-export tests pass and the coordinator tests prove newest-first, abort-on-false, and one-write behavior.

- [ ] **Step 6: Commit Task 1**

```powershell
git add lib/health/health_export.dart test/health_sleep_export_test.dart
git commit -m "fix(health): prioritize current Android sleep export"
```

---

### Task 2: Batch Android minute heart-rate samples

**Files:**
- Create: `lib/health/health_heart_rate_batch.dart`
- Create: `android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/HealthConnectHeartRateWriter.kt`
- Modify: `android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/NativeChannels.kt`
- Modify: `lib/health/health_export.dart`
- Create: `test/health_heart_rate_export_test.dart`

**Interfaces:**
- Produces: `HealthHeartRateSample(DateTime time, int beatsPerMinute)` and `toMap()`.
- Produces: `normalizeHealthHeartRateSamples(List<Map<String, Object?>> rows, DateTime start, DateTime end)`.
- Produces: `HealthConnectHeartRateWriter.replaceDay(DateTime start, DateTime end, List<HealthHeartRateSample> samples) -> Future<bool>`.
- Produces: `MethodChannelHealthConnectHeartRateWriter` on channel `openstrap/health_connect_heart_rate`, method `replaceHeartRateDay`.
- Produces: `exportContinuousHeartRateDay(...) -> Future<bool>` that selects one Android batch call or preserved generic per-minute calls.

- [ ] **Step 1: Write failing Dart tests for the wished-for API**

Create `test/health_heart_rate_export_test.dart`. Build rows containing out-of-order timestamps, a duplicate minute, values below 1 and above 300, and timestamps outside the day. Assert normalization returns ordered unique in-range samples. Mock a MethodChannel and assert Android makes exactly one `replaceHeartRateDay` call containing every normalized sample. Return `false` from the handler and assert the export returns `false`. Pass `useAndroidBatch: false` with a generic callback and assert one generic call per valid sample, preserving Apple behavior. Assert empty normalized input returns `true` without invoking either writer.

- [ ] **Step 2: Run the new test and verify RED**

Run: `flutter test test/health_heart_rate_export_test.dart --reporter expanded`

Expected: compilation fails because `health_heart_rate_batch.dart` and its types do not exist.

- [ ] **Step 3: Implement Dart normalization and routing**

Create the file with an injected interface and MethodChannel implementation. Convert SQL `minute_ts` seconds to `DateTime`, truncate `avg_hr` with `toInt()` to match `health 11.1.1`, reject values outside `1..300`, clip by dropping samples outside `[start, end)`, sort by timestamp, and keep one sample per timestamp. For Android, call `replaceDay` once. For Apple, call the injected generic writer for each sample with end time `sample.time + 1 minute`, aggregating every Boolean result without stopping after a failure.

- [ ] **Step 4: Run the Dart test and verify GREEN**

Run: `flutter test test/health_heart_rate_export_test.dart --reporter expanded`

Expected: all heart-rate batch tests pass.

- [ ] **Step 5: Write the native Android batch writer**

Create `HealthConnectHeartRateWriter.kt` following the existing sleep writer's channel/coroutine pattern. Parse `startTime`, `endTime`, and `samples` defensively through `Number.toLong()`. Reject invalid parents, invalid BPM values, duplicate/out-of-order samples, and samples outside `[start, end)`. Treat an empty sample list as `true` without deletion. Under a mutex on `Dispatchers.IO`, delete `HeartRateRecord` data for the exact day and insert one record:

```kotlin
HeartRateRecord(
    startTime = start,
    endTime = end,
    startZoneOffset = ZoneId.systemDefault().rules.getOffset(start),
    endZoneOffset = ZoneId.systemDefault().rules.getOffset(end),
    samples = samples,
    metadata = Metadata(
        recordingMethod = Metadata.RECORDING_METHOD_AUTOMATICALLY_RECORDED,
    ),
)
```

Return `insertRecords(listOf(record)).recordIdsList.size == 1`; rethrow `CancellationException`; log and return `false` for other Health Connect exceptions. Register it from `NativeChannels.register`.

- [ ] **Step 6: Route `HealthExporter` through the batch API**

Add a constructor-injected `_androidHeartRate` with a default `MethodChannelHealthConnectHeartRateWriter`. Replace the existing continuous-HR loop with `exportContinuousHeartRateDay`, passing `useAndroidBatch: Platform.isAndroid`, the queried rows, and an Apple generic callback that calls `_health.writeHealthData` with `HealthDataType.HEART_RATE`. If the helper returns `false`, set the day-level `success = false`.

- [ ] **Step 7: Run formatting and focused tests**

Run:

```powershell
dart format lib/health/health_heart_rate_batch.dart lib/health/health_export.dart test/health_heart_rate_export_test.dart test/health_sleep_export_test.dart
flutter test test/health_heart_rate_export_test.dart test/health_sleep_export_test.dart --reporter expanded
```

Expected: formatting completes and all focused tests pass.

- [ ] **Step 8: Compile the Android writer and commit Task 2**

Run: `flutter build apk --debug`

Expected: Kotlin compiles against pinned `connect-client:1.1.0-alpha07` and the debug APK succeeds.

```powershell
git add android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/HealthConnectHeartRateWriter.kt android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/NativeChannels.kt lib/health/health_heart_rate_batch.dart lib/health/health_export.dart test/health_heart_rate_export_test.dart
git commit -m "fix(health): batch Android heart-rate export"
```

---

### Task 3: Verify, publish, and test on the Pixel

**Files:**
- No new production files.
- Verify only the files changed in Tasks 1 and 2 plus the approved design/plan documents.

**Interfaces:**
- Consumes: all Task 1 and Task 2 interfaces.
- Produces: release APK at `build/app/outputs/flutter-apk/app-release.apk` and desktop copy `C:\Users\felix\Desktop\OpenStrap-Edge-fix-193.apk`.

- [ ] **Step 1: Run static analysis and focused tests**

```powershell
flutter analyze
flutter test test/health_heart_rate_export_test.dart test/health_sleep_export_test.dart --reporter expanded
```

Expected: analyzer reports `No issues found!`; all focused tests pass.

- [ ] **Step 2: Run the full test suite**

Run: `flutter test --reporter expanded`

Expected: no new failure relative to the known Windows DST and timing-sensitive DeriveScheduler failures. Record exact pass/skip/fail totals.

- [ ] **Step 3: Build the release APK**

Run: `flutter build apk --release`

Expected: `build/app/outputs/flutter-apk/app-release.apk` is produced successfully.

- [ ] **Step 4: Copy, hash, install, and open the APK**

Copy the release APK to `C:\Users\felix\Desktop\OpenStrap-Edge-fix-193.apk`, calculate SHA-256, run `adb install -r` against the connected device, and open `wtf.openstrap.openstrap_edge/.MainActivity`. Do not uninstall the app or clear its database.

- [ ] **Step 5: Verify the real export boundary**

Clear only logcat, tap `Sync now`, and confirm in logs that the newest sleep write occurs before heart-rate/workout writes, there is no burst of per-minute `HEART_RATE` calls, and the current sleep replacement succeeds. Open Health Connect and verify one OpenStrap sleep parent for `01:36–08:20` with all stages. Google/Fitbit refresh may remain asynchronous; distinguish its cache from the Health Connect source of truth.

- [ ] **Step 6: Commit any verification-only test adjustment, push, and update PR**

If verification required no code change, do not create an empty commit. Push `fix/health-connect-sleep-session` to `origin`, then update PR #196 with the confirmed quota root cause, batching fix, commands/results, and APK hash.


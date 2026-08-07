# Health Connect Legacy Sleep Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove legacy OpenStrap sleep fragments that begin before a recomputed parent session, then write exactly one Android `SleepSessionRecord` for the night.

**Architecture:** Keep the typed Dart sleep-session API and normalized parent payload unchanged. Add a pure Kotlin helper that derives a DST-safe local noon-to-noon cleanup interval containing the parent; the Android writer uses that broader interval only for deletion and still inserts the exact normalized parent.

**Tech Stack:** Flutter/Dart, Kotlin/JVM 17, AndroidX Health Connect `1.1.0-alpha07`, JUnit 4, Gradle.

## Global Constraints

- Only OpenStrap-owned `SleepSessionRecord` values may be deleted; Health Connect enforces calling-package ownership.
- Preserve the exact parent boundaries and every normalized awake, REM, light, and deep stage.
- Preserve Apple Health behavior unchanged.
- Use local calendar noon boundaries through `ZoneId`, never a fixed 24-hour duration, so DST transitions remain correct.
- A native delete or insert failure must return `false` to the Dart retry policy.
- Do not modify database, analytics, BLE, Google Health, or unrelated export behavior.

---

### Task 1: DST-safe legacy sleep cleanup window

**Files:**
- Modify: `android/app/build.gradle.kts`
- Modify: `android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/HealthConnectSleepWriter.kt`
- Create: `android/app/src/test/kotlin/wtf/openstrap/openstrap_edge/HealthConnectSleepWriterTest.kt`

**Interfaces:**
- Consumes: `SleepSessionRecord.startTime`, `SleepSessionRecord.endTime`, and `ZoneId.systemDefault()`.
- Produces: `internal data class SleepCleanupRange(val start: Instant, val end: Instant)` and `internal fun sleepCleanupRange(start: Instant, end: Instant, zoneId: ZoneId): SleepCleanupRange`.

- [ ] **Step 1: Add the JUnit test dependency and write the failing legacy-fragment test**

Add this dependency to `android/app/build.gradle.kts`:

```kotlin
testImplementation("junit:junit:4.13.2")
```

Create `HealthConnectSleepWriterTest.kt` with a test that constructs:

```kotlin
private val berlin = ZoneId.of("Europe/Berlin")

private fun localInstant(year: Int, month: Int, day: Int, hour: Int, minute: Int): Instant =
    ZonedDateTime.of(year, month, day, hour, minute, 0, 0, berlin).toInstant()

@Test
fun cleanupRangeIncludesLegacyFragmentThatStartsBeforeRecomputedSession() {
    val sessionStart = localInstant(2026, 8, 6, 1, 36)
    val sessionEnd = localInstant(2026, 8, 6, 8, 20)
    val staleFragmentStart = localInstant(2026, 8, 5, 23, 34)

    val range = sleepCleanupRange(sessionStart, sessionEnd, berlin)

    assertEquals(localInstant(2026, 8, 5, 12, 0), range.start)
    assertEquals(localInstant(2026, 8, 6, 12, 0), range.end)
    assertTrue(!staleFragmentStart.isBefore(range.start))
    assertTrue(staleFragmentStart.isBefore(range.end))
}
```

- [ ] **Step 2: Run the Android unit test and verify RED**

Run:

```powershell
Set-Location android
.\gradlew.bat :app:testDebugUnitTest --tests "wtf.openstrap.openstrap_edge.HealthConnectSleepWriterTest.cleanupRangeIncludesLegacyFragmentThatStartsBeforeRecomputedSession"
```

Expected: compilation fails because `sleepCleanupRange` and `SleepCleanupRange` do not exist.

- [ ] **Step 3: Add a failing DST-boundary test**

Add:

```kotlin
@Test
fun cleanupRangeUsesLocalNoonAcrossDstTransition() {
    val sessionStart = localInstant(2026, 10, 25, 1, 30)
    val sessionEnd = localInstant(2026, 10, 25, 9, 0)

    val range = sleepCleanupRange(sessionStart, sessionEnd, berlin)

    assertEquals(localInstant(2026, 10, 24, 12, 0), range.start)
    assertEquals(localInstant(2026, 10, 25, 12, 0), range.end)
    assertEquals(25, Duration.between(range.start, range.end).toHours())
}
```

Run:

```powershell
Set-Location android
.\gradlew.bat :app:testDebugUnitTest --tests "wtf.openstrap.openstrap_edge.HealthConnectSleepWriterTest.cleanupRangeUsesLocalNoonAcrossDstTransition"
```

Expected: compilation fails because the cleanup helper does not exist.

- [ ] **Step 4: Implement the minimal pure cleanup helper**

In `HealthConnectSleepWriter.kt`, add imports for `LocalTime` and `ZonedDateTime`, then add:

```kotlin
internal data class SleepCleanupRange(val start: Instant, val end: Instant)

internal fun sleepCleanupRange(start: Instant, end: Instant, zoneId: ZoneId): SleepCleanupRange {
    require(start.isBefore(end))
    val localEnd = end.atZone(zoneId)
    val endDate = if (localEnd.toLocalTime().isBefore(LocalTime.NOON)) {
        localEnd.toLocalDate()
    } else {
        localEnd.toLocalDate().plusDays(1)
    }
    val cleanupEnd = endDate.atTime(LocalTime.NOON).atZone(zoneId).toInstant()
    val calculatedStart = endDate.minusDays(1).atTime(LocalTime.NOON).atZone(zoneId).toInstant()
    val cleanupStart = if (start.isBefore(calculatedStart)) start else calculatedStart
    return SleepCleanupRange(cleanupStart, cleanupEnd)
}
```

- [ ] **Step 5: Use the cleanup range for native deletion only**

Immediately before `client.deleteRecords`, calculate:

```kotlin
val cleanupRange = sleepCleanupRange(
    session.startTime,
    session.endTime,
    ZoneId.systemDefault(),
)
```

Replace the current exact-session filter with:

```kotlin
TimeRangeFilter.between(cleanupRange.start, cleanupRange.end)
```

Do not change the inserted `session` or its stages.

- [ ] **Step 6: Run native and existing sleep tests and verify GREEN**

Run:

```powershell
Set-Location android
.\gradlew.bat :app:testDebugUnitTest --tests "wtf.openstrap.openstrap_edge.HealthConnectSleepWriterTest"
Set-Location ..
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\flutter.bat' test test/health_sleep_export_test.dart
```

Expected: both commands exit 0 and all tests pass.

- [ ] **Step 7: Format and commit the focused fix**

Run:

```powershell
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\dart.bat' format lib test
git diff --check
git add android/app/build.gradle.kts android/app/src/main/kotlin/wtf/openstrap/openstrap_edge/HealthConnectSleepWriter.kt android/app/src/test/kotlin/wtf/openstrap/openstrap_edge/HealthConnectSleepWriterTest.kt
git commit -m "fix(health): remove legacy sleep fragments"
```

Expected: formatting and `git diff --check` succeed; the commit contains only the three listed files.

### Task 2: Full verification and device proof

**Files:**
- No production changes expected.
- Verify: `build/app/outputs/flutter-apk/app-release.apk`

**Interfaces:**
- Consumes: the completed Task 1 commit.
- Produces: analyzer/test/build/device evidence and an installable APK.

- [ ] **Step 1: Run static analysis and focused health tests**

```powershell
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\flutter.bat' analyze
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\flutter.bat' test test/health_sleep_export_test.dart test/health_heart_rate_export_test.dart
```

Expected: analyzer reports no issues and focused tests pass.

- [ ] **Step 2: Run the full Flutter suite**

```powershell
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\flutter.bat' test
```

Expected: no new health failures. Record any pre-existing Windows DST or timing-sensitive failures exactly rather than hiding them.

- [ ] **Step 3: Build and copy the release APK**

```powershell
& 'C:\Users\felix\.cache\flutter-sdk-3.41.6\flutter\bin\flutter.bat' build apk --release
Copy-Item -Force 'build\app\outputs\flutter-apk\app-release.apk' 'C:\Users\felix\Desktop\OpenStrap-Edge-fix-193.apk'
Get-FileHash 'C:\Users\felix\Desktop\OpenStrap-Edge-fix-193.apk' -Algorithm SHA256
```

Expected: build exits 0, the desktop APK exists, and a SHA-256 hash is recorded.

- [ ] **Step 4: Install without deleting app data and trigger export**

```powershell
adb install -r 'C:\Users\felix\Desktop\OpenStrap-Edge-fix-193.apk'
adb shell am start -n wtf.openstrap.openstrap_edge/.MainActivity
```

Expected: installation reports `Success`; the existing package, database, and WHOOP pairing remain in place.

- [ ] **Step 5: Verify Health Connect and Google Health**

Use the existing OpenStrap profile `Sync now` action. Confirm:

- OpenStrap reports at least one synchronized day.
- Logcat has no `OpenStrapSleepExport` error or `API call quota exceeded` message.
- Health Connect has one OpenStrap parent for `01:36–08:20` with all stages.
- The stale `23:34–02:55` OpenStrap fragments are absent.
- Google Health no longer reports the stale `2 h 19 min` night after its Health Connect sync completes.

- [ ] **Step 6: Push and update PR #196**

Fast-forward `fix/health-connect-sleep-session` to the verified worktree branch, push it to `origin`, and update PR #196 with the legacy-fragment cleanup evidence. Preserve `Fixes #193` in the PR description.

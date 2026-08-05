package wtf.openstrap.openstrap_edge

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/** Writes one Health Connect sleep parent containing all normalized stages. */
object HealthConnectSleepWriter {
    private const val CHANNEL = "openstrap/health_connect_sleep"
    private const val REPLACE_SLEEP_SESSION = "replaceSleepSession"
    private const val RECORDING_METHOD_AUTOMATIC = 2
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private val replaceMutex = Mutex()

    fun register(engine: FlutterEngine, context: Context) {
        val app = context.applicationContext
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method != REPLACE_SLEEP_SESSION) {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                scope.launch {
                    result.success(replace(app, call))
                }
            }
    }

    private suspend fun replace(context: Context, call: MethodCall): Boolean {
        return replaceMutex.withLock {
            try {
                if (HealthConnectClient.getSdkStatus(context) != HealthConnectClient.SDK_AVAILABLE) {
                    false
                } else {
                    val session = buildSession(call)
                    if (session == null) {
                        false
                    } else {
                        val client = HealthConnectClient.getOrCreate(context)

                        // This removes both records created by this writer and legacy
                        // one-stage fragments whose intervals fall inside the real
                        // overnight window, including the portion before midnight.
                        client.deleteRecords(
                            SleepSessionRecord::class,
                            TimeRangeFilter.between(session.startTime, session.endTime),
                        )
                        client.insertRecords(listOf(session)).recordIdsList.size == 1
                    }
                }
            } catch (_: Exception) {
                false
            }
        }
    }

    private fun buildSession(call: MethodCall): SleepSessionRecord? {
        val start = call.argument<Long>("startTime")?.let(Instant::ofEpochMilli) ?: return null
        val end = call.argument<Long>("endTime")?.let(Instant::ofEpochMilli) ?: return null
        if (!start.isBefore(end)) return null

        val rawStages = call.argument<List<Map<String, Any?>>>("stages").orEmpty()
        val stages = rawStages.mapNotNull(::buildStage).sortedBy { it.startTime }
        var previousEnd = start
        for (stage in stages) {
            if (stage.startTime.isBefore(start) || stage.endTime.isAfter(end)) return null
            if (!stage.startTime.isBefore(stage.endTime)) return null
            if (stage.startTime.isBefore(previousEnd)) return null
            previousEnd = stage.endTime
        }

        val zoneRules = ZoneId.systemDefault().rules
        return SleepSessionRecord(
            startTime = start,
            startZoneOffset = zoneRules.getOffset(start),
            endTime = end,
            endZoneOffset = zoneRules.getOffset(end),
            title = "OpenStrap sleep",
            stages = stages,
            metadata = Metadata(recordingMethod = RECORDING_METHOD_AUTOMATIC),
        )
    }

    private fun buildStage(raw: Map<String, Any?>): SleepSessionRecord.Stage? {
        val start = (raw["startTime"] as? Number)?.toLong()?.let(Instant::ofEpochMilli)
            ?: return null
        val end = (raw["endTime"] as? Number)?.toLong()?.let(Instant::ofEpochMilli)
            ?: return null
        val type = when (raw["stage"] as? String) {
            "awake" -> SleepSessionRecord.STAGE_TYPE_AWAKE
            "rem" -> SleepSessionRecord.STAGE_TYPE_REM
            "light" -> SleepSessionRecord.STAGE_TYPE_LIGHT
            "deep" -> SleepSessionRecord.STAGE_TYPE_DEEP
            else -> return null
        }
        return SleepSessionRecord.Stage(start, end, type)
    }
}

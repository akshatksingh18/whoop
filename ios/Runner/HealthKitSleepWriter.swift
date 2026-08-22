import Flutter
import HealthKit

// HealthKit sleep replace. Mirrors Android `HealthConnectSleepWriter`: one
// channel call deletes OUR overlapping `sleepAnalysis` samples, then writes
// one `inBed` envelope plus stages.
//
// The Flutter `health` plugin is not used here. Unknown type keys (SLEEP_SESSION)
// map to bodyMass and hang `delete()`. SLEEP_LIGHT / inBed writes have been
// failing on recent iOS as Core-less ~2 h nights with leftover 11pm fragments
// (#225/#239/#249). Dart already computed the noon-to-noon cleanup window;
// this file does not re-derive local noon.

enum HealthKitSleepWriter {
  private static let channelName = "openstrap/healthkit_sleep"
  private static let store = HKHealthStore()
  private static let queue = DispatchQueue(label: "wtf.openstrap.healthkit.sleep")

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "replaceSleepSession" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      queue.async {
        replace(args) { ok in
          DispatchQueue.main.async { result(ok) }
        }
      }
    }
  }

  private static func replace(_ args: [String: Any], completion: @escaping (Bool) -> Void) {
    guard HKHealthStore.isHealthDataAvailable() else {
      completion(true) // iPad / simulator: no store, not an export failure
      return
    }
    guard let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
      completion(false)
      return
    }
    guard let cleanupStart = dateMs(args["cleanupStartTime"]),
          let cleanupEnd = dateMs(args["cleanupEndTime"]),
          cleanupStart < cleanupEnd else {
      completion(false)
      return
    }

    let samples: [HKCategorySample]
    do {
      samples = try buildSamples(args, type: sleepType)
    } catch {
      completion(false)
      return
    }

    let datePred = HKQuery.predicateForSamples(
      withStart: cleanupStart, end: cleanupEnd, options: []
    )
    let sourcePred = HKQuery.predicateForObjects(from: HKSource.default())
    let pred = NSCompoundPredicate(andPredicateWithSubpredicates: [datePred, sourcePred])

    store.deleteObjects(of: sleepType, predicate: pred) { _, _, error in
      if error != nil {
        completion(false)
        return
      }
      guard !samples.isEmpty else {
        completion(true)
        return
      }
      store.save(samples) { success, error in
        completion(success && error == nil)
      }
    }
  }

  private static func buildSamples(
    _ args: [String: Any],
    type: HKCategoryType
  ) throws -> [HKCategorySample] {
    guard let start = dateMs(args["startTime"]),
          let end = dateMs(args["endTime"]) else {
      return []
    }
    guard start < end else {
      throw SleepWriteError.invalidWindow
    }

    var samples: [HKCategorySample] = [
      HKCategorySample(
        type: type,
        value: HKCategoryValueSleepAnalysis.inBed.rawValue,
        start: start,
        end: end
      ),
    ]

    let rawStages = args["stages"] as? [Any] ?? []
    var previousEnd = start
    for raw in rawStages {
      guard let map = raw as? [String: Any],
            let stageStart = dateMs(map["startTime"]),
            let stageEnd = dateMs(map["endTime"]),
            let value = sleepValue(map["stage"] as? String) else {
        throw SleepWriteError.invalidStage
      }
      guard stageStart < stageEnd,
            stageStart >= start,
            stageEnd <= end,
            stageStart >= previousEnd else {
        throw SleepWriteError.invalidStage
      }
      samples.append(
        HKCategorySample(type: type, value: value.rawValue, start: stageStart, end: stageEnd)
      )
      previousEnd = stageEnd
    }
    return samples
  }

  private static func sleepValue(_ stage: String?) -> HKCategoryValueSleepAnalysis? {
    switch stage {
    case "awake": return .awake
    case "rem":
      if #available(iOS 16.0, *) { return .asleepREM }
      return .asleep
    case "light":
      // .asleepCore is the iOS 16+ name for light sleep; on iOS 15 HealthKit
      // only has the binary .asleep. The runner target is 15.0 — without the
      // guard this file does not compile at all.
      if #available(iOS 16.0, *) { return .asleepCore }
      return .asleep
    case "deep":
      if #available(iOS 16.0, *) { return .asleepDeep }
      return .asleep
    default: return nil
    }
  }

  private static func dateMs(_ raw: Any?) -> Date? {
    guard let n = raw as? NSNumber else { return nil }
    return Date(timeIntervalSince1970: n.doubleValue / 1000.0)
  }

  private enum SleepWriteError: Error {
    case invalidWindow
    case invalidStage
  }
}

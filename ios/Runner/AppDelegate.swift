import Flutter
import UIKit
import AudioToolbox
import AVFoundation
import BackgroundTasks
import CoreLocation
import CoreMotion
import MapKit
import UserNotifications
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // CoreBluetooth state restoration — must be created here (early) so iOS can relaunch
    // us with willRestoreState when the band reappears. Wakes the app → headless sync.
    NativeLog.launch(launchOptions: launchOptions)
    BleRestoreManager.shared.start(launchOptions: launchOptions)

    // Pushups (build 86): a Done/Pause tapped on a locked-screen reminder runs
    // Dart in a background engine, which needs the plugins registered there
    // too; and this delegate lets the plugin receive those responses.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
    // Home auto-pause: the location manager must exist at launch so a region
    // event that relaunched the app is delivered to it.
    HomeRegionBridge.shared.start()

    // BGTaskScheduler registration MUST happen before didFinishLaunching returns.
    // Build 86 enables both tasks in the personal build too (bounded work,
    // supplementary to BLE wakes and foreground catch-up).
    // The channel wiring (messenger) happens in didInitializeImplicitFlutterEngine below;
    // here we only register the identifier with the OS so it survives to that point.
    // schedule() is called after the channel is wired so Dart is ready to handle the task.
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: BackgroundTaskManager.taskIdentifier,
      using: nil
    ) { task in
      guard let processingTask = task as? BGProcessingTask else {
        task.setTaskCompleted(success: false)
        return
      }
      BackgroundTaskManager.handleTask(processingTask)
    }
    // Light sync-only BGAppRefreshTask — separate identifier + budget from the
    // processing task above; also registered BEFORE didFinishLaunching returns.
    BGTaskScheduler.shared.register(
      forTaskWithIdentifier: BackgroundTaskManager.refreshTaskIdentifier,
      using: nil
    ) { task in
      guard let refreshTask = task as? BGAppRefreshTask else {
        task.setTaskCompleted(success: false)
        return
      }
      BackgroundTaskManager.handleRefreshTask(refreshTask)
    }

    #if !PERSONAL_SIDELOAD
    // Apple Watch companion: activate the WCSession so the watch can receive
    // today's metrics (mirrored from the App Group snapshot). No-op without a
    // paired watch. See WatchBridge.swift.
    WatchBridge.shared.activate()
    #endif

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Whenever the phone app comes to the foreground, mirror the App Group
  // snapshot to the watch, so the wrist is not waiting on the next derive.
  //
  // It mirrors whatever is already there — nothing rewrites the group on a mere
  // foreground, only a completed derive does (AppState → WidgetService.refresh).
  // So this can ship yesterday's snapshot, and that is survivable only because
  // the watch ages `updated_at` itself (WatchMetrics.fresh) and shows its
  // no-recent-data state rather than yesterday's numbers.
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    #if !PERSONAL_SIDELOAD
    WatchBridge.shared.pushCurrentState()
    #endif
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    // Live Activity MethodChannel (start/update/end the workout activity).
    // LiveActivityBridge lives in LiveActivityBridge.swift (Runner target).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(messenger: registrar.messenger())
    }
    #if !PERSONAL_SIDELOAD
    // Breathing-session Live Activity — separate channel/attributes type from
    // the workout one (BreathingLiveActivityBridge.swift, Runner target).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BreathingLiveActivityBridge") {
      BreathingLiveActivityBridge.register(messenger: registrar.messenger())
    }
    #endif
    // BLE-restore channel: native wake (band reconnected) → Dart headless sync.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BleRestoreManager") {
      BleRestoreManager.shared.attach(messenger: registrar.messenger())
    }
    // Band-gesture actions channel (double-tap → play/pause, skip, ring phone).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ActionBridge") {
      ActionBridge.register(messenger: registrar.messenger())
    }
    // AccessorySetupKit pairing bridge (iOS 18+). The ASK picker provisions the WHOOP so
    // iOS 26 keeps the app eligible for background relaunch (TN3115). No-op pre-iOS 18.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AccessorySetup") {
      AccessorySetup.register(messenger: registrar.messenger())
    }
    // Home-screen icon switching (setAlternateIconName). iOS only — see the
    // bridge below for the system-alert cost it carries.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppIconBridge") {
      AppIconBridge.register(messenger: registrar.messenger())
    }
    // Build-time iOS configuration exposed to Dart without requiring --dart-define.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "ConfigBridge") {
      ConfigBridge.register(messenger: registrar.messenger())
    }
    // The phone's OWN step count (CMPedometer), not HealthKit's multi-writer
    // aggregate. See lib/health/phone_pedometer.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "PedometerBridge") {
      PedometerBridge.register(messenger: registrar.messenger())
      PhoneCadenceBridge.register(messenger: registrar.messenger())
    }
    // Pushups Home auto-pause (build 86). See HomeRegionBridge.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HomeRegionBridge") {
      HomeRegionBridge.shared.attach(messenger: registrar.messenger())
    }
    // Body progress photos taken with the camera (build 86). See CameraBridge.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CameraBridge") {
      CameraBridge.register(messenger: registrar.messenger())
    }
    // A dark Apple Maps picture under a recorded route. See lib/gps/map_snapshot.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MapSnapshotBridge") {
      MapSnapshotBridge.register(messenger: registrar.messenger())
    }
    // Spoken pace every kilometre during a run. See lib/gps/run_voice.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "SpeechBridge") {
      SpeechBridge.register(messenger: registrar.messenger())
    }
    #if !PERSONAL_SIDELOAD
    // HKWorkoutRoute → Dart. Coordinates only; the `health` plugin still reads
    // the workouts themselves. See lib/health/health_workout_import.dart.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthRouteBridge") {
      HealthRouteBridge.register(messenger: registrar.messenger())
    }
    // HealthKit sleep replace (inBed + Core/Deep/REM). See HealthKitSleepWriter.swift.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HealthKitSleepWriter") {
      HealthKitSleepWriter.register(messenger: registrar.messenger())
    }
    #endif
    // BGTask channel: Dart handler for opportunistic headless sync and bounded
    // calculation (personal build included from build 86).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskManager") {
      BackgroundTaskManager.wireChannel(messenger: registrar.messenger())
      // Now that the channel is wired, submit the first task requests
      // (processing + light refresh).
      BackgroundTaskManager.schedule()
      BackgroundTaskManager.scheduleRefresh()
    }
  }
}

/// Pushups Home auto-pause (build 86): one system-monitored circular region
/// around Home. Region monitoring, never continuous location, and no trail of
/// places. Boundary events are kept in a small inbox in UserDefaults until
/// Dart drains them, because an event can relaunch the app before Dart runs.
/// The Home point itself is kept by Dart (preferences), not here.
final class HomeRegionBridge: NSObject, CLLocationManagerDelegate {
  static let shared = HomeRegionBridge()
  static let regionId = "whoop.pushups.home"
  private static let inboxKey = "whoop.pushups.home.inbox"

  private let manager = CLLocationManager()
  private var channel: FlutterMethodChannel?
  private var locationResults: [FlutterResult] = []
  private var authResults: [FlutterResult] = []

  func start() {
    manager.delegate = self
  }

  func attach(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "openstrap/home_region", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(nil)
        return
      }
      self.handle(call, result)
    }
  }

  private func authName() -> String {
    switch manager.authorizationStatus {
    case .notDetermined: return "notDetermined"
    case .authorizedWhenInUse: return "whenInUse"
    case .authorizedAlways: return "always"
    case .denied: return "denied"
    case .restricted: return "restricted"
    @unknown default: return "denied"
    }
  }

  private func handle(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
    switch call.method {
    case "status":
      let refresh: String
      switch UIApplication.shared.backgroundRefreshStatus {
      case .available: refresh = "available"
      case .denied: refresh = "denied"
      case .restricted: refresh = "restricted"
      @unknown default: refresh = "denied"
      }
      result([
        "authorization": authName(),
        "monitoring": CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self),
        "backgroundRefresh": refresh,
        "monitored": manager.monitoredRegions.contains { $0.identifier == HomeRegionBridge.regionId },
      ])
    case "currentLocation":
      locationResults.append(result)
      if manager.authorizationStatus == .notDetermined {
        manager.requestWhenInUseAuthorization()
      } else if manager.authorizationStatus == .denied || manager.authorizationStatus == .restricted {
        failLocation()
      } else {
        manager.requestLocation()
      }
    case "requestAlways":
      if manager.authorizationStatus == .authorizedAlways {
        result("always")
        return
      }
      authResults.append(result)
      manager.requestAlwaysAuthorization()
      // iOS shows nothing when it has already decided; answer anyway.
      DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
        self?.finishAuth()
      }
    case "monitor":
      guard let a = call.arguments as? [String: Any],
            let lat = a["lat"] as? Double,
            let lon = a["lon"] as? Double,
            let radius = a["radius"] as? Double else {
        result(FlutterError(code: "args", message: "Home needs a place and a radius.", details: nil))
        return
      }
      guard CLLocationManager.isMonitoringAvailable(for: CLCircularRegion.self) else {
        result(FlutterError(code: "unavailable", message: "This phone cannot watch a Home area.", details: nil))
        return
      }
      stopAll()
      let region = CLCircularRegion(
        center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        radius: min(radius, manager.maximumRegionMonitoringDistance),
        identifier: HomeRegionBridge.regionId)
      region.notifyOnEntry = true
      region.notifyOnExit = true
      manager.startMonitoring(for: region)
      manager.requestState(for: region)
      result(nil)
    case "stop":
      stopAll()
      UserDefaults.standard.removeObject(forKey: HomeRegionBridge.inboxKey)
      result(nil)
    case "drain":
      let list = UserDefaults.standard.array(forKey: HomeRegionBridge.inboxKey) ?? []
      UserDefaults.standard.removeObject(forKey: HomeRegionBridge.inboxKey)
      result(list)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func stopAll() {
    for r in manager.monitoredRegions where r.identifier == HomeRegionBridge.regionId {
      manager.stopMonitoring(for: r)
    }
  }

  private func record(_ kind: String) {
    var list = UserDefaults.standard.array(forKey: HomeRegionBridge.inboxKey) ?? []
    list.append(["kind": kind, "at": Date().timeIntervalSince1970])
    if list.count > 50 { list.removeFirst(list.count - 50) }
    UserDefaults.standard.set(list, forKey: HomeRegionBridge.inboxKey)
    NativeLog.note("home region \(kind)")
    channel?.invokeMethod("event", arguments: nil)
  }

  func locationManager(_ m: CLLocationManager, didEnterRegion region: CLRegion) {
    if region.identifier == HomeRegionBridge.regionId { record("enter") }
  }

  func locationManager(_ m: CLLocationManager, didExitRegion region: CLRegion) {
    if region.identifier == HomeRegionBridge.regionId { record("exit") }
  }

  func locationManager(_ m: CLLocationManager, didDetermineState state: CLRegionState, for region: CLRegion) {
    guard region.identifier == HomeRegionBridge.regionId else { return }
    switch state {
    case .inside: record("inside")
    case .outside: record("outside")
    default: break
    }
  }

  func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
    if !locationResults.isEmpty && m.authorizationStatus != .notDetermined {
      if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
        m.requestLocation()
      } else {
        failLocation()
      }
    }
    if m.authorizationStatus != .notDetermined { finishAuth() }
  }

  private func finishAuth() {
    let rs = authResults
    authResults = []
    for r in rs { r(authName()) }
  }

  func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    guard let l = locations.last else { return }
    let rs = locationResults
    locationResults = []
    for r in rs {
      r(["lat": l.coordinate.latitude, "lon": l.coordinate.longitude, "accuracy": l.horizontalAccuracy])
    }
  }

  func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
    failLocation()
  }

  func locationManager(_ m: CLLocationManager, monitoringDidFailFor region: CLRegion?, withError error: Error) {
    NativeLog.note("home region monitoring failed: \(error.localizedDescription)")
  }

  private func failLocation() {
    let rs = locationResults
    locationResults = []
    for r in rs { r(nil) }
  }
}

/// A progress photo from the camera (build 86, Body). The system camera UI,
/// scaled to at most 2048 px and re-drawn upright, returned as JPEG bytes
/// with no metadata; Dart re-encodes it once more before keeping it. Nothing
/// is saved to the photo library. Cancel returns nil.
enum CameraBridge {
  private static let channelName = "openstrap/camera"
  private static var delegate: CameraDelegate?

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "capture" else {
        result(FlutterMethodNotImplemented)
        return
      }
      DispatchQueue.main.async {
        guard UIImagePickerController.isSourceTypeAvailable(.camera),
              let top = topViewController() else {
          result(FlutterError(code: "unavailable", message: "The camera is not available.", details: nil))
          return
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.allowsEditing = false
        let d = CameraDelegate(result: result)
        delegate = d
        picker.delegate = d
        top.present(picker, animated: true)
      }
    }
  }

  static func finished() { delegate = nil }

  static func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let windows = scenes.flatMap { $0.windows }
    var top = (windows.first { $0.isKeyWindow } ?? windows.first)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}

final class CameraDelegate: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
  private var result: FlutterResult?

  init(result: @escaping FlutterResult) {
    self.result = result
  }

  func imagePickerController(
    _ picker: UIImagePickerController,
    didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
  ) {
    let image = info[.originalImage] as? UIImage
    picker.dismiss(animated: true) {
      var data: Data?
      if let image = image, image.size.width > 0, image.size.height > 0 {
        let scale = min(1, 2048 / max(image.size.width, image.size.height))
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let upright = UIGraphicsImageRenderer(size: size, format: format).image { _ in
          image.draw(in: CGRect(origin: .zero, size: size))
        }
        data = upright.jpegData(compressionQuality: 0.9)
      }
      self.result?(data.map { FlutterStandardTypedData(bytes: $0) })
      self.result = nil
      CameraBridge.finished()
    }
  }

  func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
    picker.dismiss(animated: true) {
      self.result?(nil)
      self.result = nil
      CameraBridge.finished()
    }
  }
}

enum ConfigBridge {
  private static let channelName = "openstrap/ios_config"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "appGroupIdentifier":
        #if PERSONAL_SIDELOAD
        result("")
        #else
        result(Bundle.main.object(forInfoDictionaryKey: "OpenStrapAppGroupIdentifier") as? String ?? "")
        #endif
      case "syncWatch":
        // Dart calls this right after writing the widget snapshot; mirror it to
        // the paired Apple Watch. Best-effort, never fails the Dart caller.
        #if PERSONAL_SIDELOAD
        result(false)
        #else
        WatchBridge.shared.pushCurrentState()
        result(true)
        #endif
      case "keepAwake":
        // Hold the display awake for a live workout, the way every run/ride app
        // does. Scoped strictly to the session: Dart clears it on finish, and
        // iOS drops it anyway if the app is terminated, so it cannot leak into
        // a permanently-awake screen.
        let args = call.arguments as? [String: Any] ?? [:]
        let on = args["on"] as? Bool ?? false
        UIApplication.shared.isIdleTimerDisabled = on
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// The iPhone's own pedometer. This is the motion coprocessor's count — the same one
// HealthKit republishes as the iPhone's contribution to step count, minus every OTHER
// writer in the store. Requires NSMotionUsageDescription in Info.plist: without it the
// first call CRASHES the app (Apple's words), which is why the plist edit ships with
// this file, not after it.
// Independent from historical queries: currentCadence only exists in live updates.
enum PhoneCadenceBridge {
  private static let pedometer = CMPedometer()
  private static var generation = 0
  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "openstrap/phone_cadence", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      generation += 1
      pedometer.stopUpdates()
      if call.method == "stop" { result(nil); return }
      guard call.method == "start" else { result(FlutterMethodNotImplemented); return }
      guard CMPedometer.isCadenceAvailable(), CMPedometer.authorizationStatus() == .authorized,
            let args = call.arguments as? [String: Any], let token = args["generation"] as? Int
      else { result(false); return }
      let nativeToken = generation
      pedometer.startUpdates(from: Date()) { data, error in
        DispatchQueue.main.async {
          guard nativeToken == generation else { return }
          var reading: [String: Any] = ["generation": token]
          if error == nil, let data = data, let cadence = data.currentCadence {
            reading["stepsPerSecond"] = cadence.doubleValue
            reading["atMs"] = Int(data.endDate.timeIntervalSince1970 * 1000)
          }
          channel.invokeMethod("cadence", arguments: reading)
        }
      }
      result(true)
    }
  }
}

enum PedometerBridge {
  private static let channelName = "openstrap/phone_steps"
  private static let pedometer = CMPedometer()

  /// Apple: "Only the past seven days worth of data is stored and available for you to
  /// retrieve. Specifying a start date that is more than seven days in the past returns
  /// only the available data." A too-old range therefore UNDER-REPORTS SILENTLY rather
  /// than erroring — the one failure this whole file exists to refuse. An hour taken
  /// from the last (safety) hour of the window is answered "not covered", never short.
  private static let cacheWindow: TimeInterval = 7 * 24 * 60 * 60 - 60 * 60

  /// Mirrors PhonePedometer.intervalNotCovered on the Dart side: we hold no record of
  /// this interval. NOT a failure, NOT a zero.
  private static let notCovered = -1

  /// `notDetermined` is not a no — the first query is what raises the prompt.
  private static var denied: Bool {
    switch CMPedometer.authorizationStatus() {
    case .denied, .restricted: return true
    default: return false
    }
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "available":
        result(CMPedometer.isStepCountingAvailable())

      case "authorized":
        result(CMPedometer.isStepCountingAvailable() && !denied)

      case "stop":
        // Nothing to stop and nothing to forget: CMPedometer is query-only, so iOS
        // keeps no store of ours to accumulate into. Android's does — see
        // PhoneStepCounter.stopAndForget. Handled rather than left unimplemented so
        // the Dart caller does not have to know which platform it is on.
        result(nil)

      case "requestPermission":
        // CoreMotion has NO explicit request API — the system prompt is raised by the
        // first query, and until one is issued the app does not appear under Settings ›
        // Privacy & Security › Motion & Fitness at all. So arming IS a query.
        guard CMPedometer.isStepCountingAvailable() else {
          result(false)
          return
        }
        let now = Date()
        pedometer.queryPedometerData(from: now.addingTimeInterval(-60), to: now) { _, error in
          DispatchQueue.main.async {
            result(error == nil && !denied)
          }
        }

      case "stepsInInterval", "movementInInterval":
        let movement = call.method == "movementInInterval"
        let args = call.arguments as? [String: Any] ?? [:]
        guard let fromMs = args["fromMs"] as? Int, let toMs = args["toMs"] as? Int else {
          result(nil)
          return
        }
        guard CMPedometer.isStepCountingAvailable(), !denied else {
          result(nil) // unavailable or refused — unknown, and the day is abandoned
          return
        }
        let from = Date(timeIntervalSince1970: Double(fromMs) / 1000)
        let to = Date(timeIntervalSince1970: Double(toMs) / 1000)
        guard to > from else {
          if movement { result(["steps": 0, "distance_m": 0]) } else { result(0) }
          return
        }
        guard from >= Date().addingTimeInterval(-cacheWindow) else {
          if movement { result(["steps": notCovered]) } else { result(notCovered) }
          return
        }
        pedometer.queryPedometerData(from: from, to: to) { data, error in
          DispatchQueue.main.async {
            guard let data = data, error == nil else {
              result(nil)
              return
            }
            if movement {
              var reading: [String: Any] = ["steps": data.numberOfSteps.intValue]
              if let metres = data.distance?.doubleValue, metres.isFinite, metres >= 0 {
                reading["distance_m"] = metres
              }
              result(reading)
            } else {
              result(data.numberOfSteps.intValue)
            }
          }
        }

      case "motionWindow":
        // Steps and distance for one session window in fixed chunks (a minute by
        // default, at most 720 chunks), for a run's distance, cadence and splits
        // when it was not recorded with GPS, and for the exact steps a run took.
        // Same contract as stepsInInterval: nil = failed or refused, notCovered =
        // older than the phone keeps. A chunk with no distance answers -1.
        let args = call.arguments as? [String: Any] ?? [:]
        guard let fromMs = args["fromMs"] as? Int, let toMs = args["toMs"] as? Int else {
          result(nil)
          return
        }
        guard CMPedometer.isStepCountingAvailable(), !denied else {
          result(nil)
          return
        }
        let from = Date(timeIntervalSince1970: Double(fromMs) / 1000)
        let to = Date(timeIntervalSince1970: Double(toMs) / 1000)
        guard to > from else {
          result(nil)
          return
        }
        guard from >= Date().addingTimeInterval(-cacheWindow) else {
          result(notCovered)
          return
        }
        var chunk = Double(max(args["chunkSec"] as? Int ?? 60, 60))
        let span = to.timeIntervalSince(from)
        if span / chunk > 720 { chunk = (span / 720).rounded(.up) }
        DispatchQueue.global(qos: .userInitiated).async {
          var steps = [Int]()
          var meters = [Double]()
          var failed = false
          var t = from
          while t < to && !failed {
            let e = min(t.addingTimeInterval(chunk), to)
            let done = DispatchSemaphore(value: 0)
            pedometer.queryPedometerData(from: t, to: e) { data, error in
              if let data = data, error == nil {
                steps.append(data.numberOfSteps.intValue)
                meters.append(data.distance?.doubleValue ?? -1)
              } else {
                failed = true
              }
              done.signal()
            }
            done.wait()
            t = e
          }
          DispatchQueue.main.async {
            result(failed ? nil : ["chunkSec": Int(chunk), "steps": steps, "meters": meters])
          }
        }

      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

// Band-gesture actions on iOS. Media control is deliberately NOT offered: iOS has no
// public API to control a third-party player (Spotify et al.) — only Apple Music via
// systemMusicPlayer — so advertising it would be misleading. The only sanctioned
// no-risk action here today is "ring my phone" (system alert sound + vibrate). System
// volume and call control aren't possible from a sandboxed iOS app and are omitted.
enum ActionBridge {
  private static let channelName = "openstrap/device_actions"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "capabilities":
        result(["ring_phone", "torch"])
      case "perform":
        let args = call.arguments as? [String: Any] ?? [:]
        result(perform(args["action"] as? String ?? ""))
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func perform(_ action: String) -> Bool {
    switch action {
    case "ring_phone":
      AudioServicesPlaySystemSound(SystemSoundID(1005)) // loud alert tone
      AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
      return true
    case "torch":
      // Torch via AVCaptureDevice — toggling it does NOT start a capture session, so
      // it needs no camera authorization / NSCameraUsageDescription. (Verifeid on device.)
      guard let device = AVCaptureDevice.default(for: .video), device.hasTorch else {
        return false
      }
      do {
        try device.lockForConfiguration()
        device.torchMode = device.isTorchActive ? .off : .on
        device.unlockForConfiguration()
        return true
      } catch {
        return false
      }
    default:
      return false
    }
  }
}

/// Switching the home-screen icon.
///
/// `setAlternateIconName` is the only public way to do this, and it comes with
/// a cost the UI has to be honest about: iOS puts up its own "You have changed
/// the icon for OpenStrap" alert on every change, and there is no way to
/// suppress it. The icons themselves are compiled into the asset catalog
/// (AppIcon / AppIconBW) and named by ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES
/// in the Runner target — nothing here can invent one that was not built in.
///
/// `available` is asked rather than assumed: alternate icons are refused on some
/// managed/enterprise configurations, and a settings row that cannot work should
/// not be drawn.
enum AppIconBridge {
  private static let channelName = "openstrap/app_icon"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "available":
        result(UIApplication.shared.supportsAlternateIcons)
      case "current":
        // nil means the primary icon. iOS owns this state — nothing is mirrored
        // into prefs, so the app can never disagree with the home screen.
        result(UIApplication.shared.alternateIconName)
      case "set":
        guard UIApplication.shared.supportsAlternateIcons else {
          result(false)
          return
        }
        let name = (call.arguments as? [String: Any])?["name"] as? String
        UIApplication.shared.setAlternateIconName(name) { error in
          if let error = error {
            NSLog("[app_icon] setAlternateIconName(\(name ?? "nil")) failed: \(error)")
          }
          result(error == nil)
        }
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// Renders a static, dark Apple Maps image around a route and reports where each
/// route point lands on it, so Flutter can draw the line on top. MapKit fetches
/// the map tiles from Apple; nothing about the run is sent beyond the area shown.
/// Speaks one short line with the system voice, ducking music rather than
/// stopping it, and hands the audio back when done. No dependency: this is
/// AVSpeechSynthesizer, built into iOS.
final class SpeechBridge: NSObject, AVSpeechSynthesizerDelegate {
  private static let shared = SpeechBridge()
  private let synth = AVSpeechSynthesizer()
  private var interrupted = false

  override init() {
    super.init()
    synth.delegate = self
    NotificationCenter.default.addObserver(self, selector: #selector(audioInterrupted(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
  }

  @objc private func audioInterrupted(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    interrupted = type == .began
    if interrupted { synth.stopSpeaking(at: .immediate) }
  }

  @objc private func routeChanged(_ notification: Notification) {
    guard let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          raw == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
    // Do not suddenly play a private cue on the speaker after headphones disconnect.
    synth.stopSpeaking(at: .immediate)
  }

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "openstrap/speech", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "say",
            let text = (call.arguments as? [String: Any])?["text"] as? String,
            !text.isEmpty else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard !shared.interrupted else {
        result(FlutterError(code: "audio_interrupted", message: "Audio is in use by a call.", details: nil))
        return
      }
      do {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .voicePrompt,
          options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        try session.setActive(true)
        let u = AVSpeechUtterance(string: text)
        u.rate = AVSpeechUtteranceDefaultSpeechRate
        shared.synth.speak(u)
        result(true)
      } catch {
        result(FlutterError(code: "audio_unavailable", message: error.localizedDescription, details: nil))
      }
    }
  }

  private func releaseAudio(_ s: AVSpeechSynthesizer) {
    if !s.isSpeaking {
      try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
  }
  func speechSynthesizer(_ s: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    releaseAudio(s)
  }
  func speechSynthesizer(_ s: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
    releaseAudio(s)
  }
}

enum MapSnapshotBridge {
  private static let channelName = "openstrap/map_snapshot"

  static func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "snapshot",
            let args = call.arguments as? [String: Any],
            let lat = args["lat"] as? [Double],
            let lng = args["lng"] as? [Double],
            let width = args["width"] as? Double,
            let height = args["height"] as? Double,
            lat.count == lng.count, lat.count >= 2, width > 0, height > 0 else {
        result(FlutterMethodNotImplemented)
        return
      }
      var minLat = lat[0], maxLat = lat[0], minLng = lng[0], maxLng = lng[0]
      for i in 0..<lat.count {
        minLat = min(minLat, lat[i]); maxLat = max(maxLat, lat[i])
        minLng = min(minLng, lng[i]); maxLng = max(maxLng, lng[i])
      }
      let pad = 1.35
      let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                          longitude: (minLng + maxLng) / 2)
      let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * pad, 0.002),
                                  longitudeDelta: max((maxLng - minLng) * pad, 0.002))
      let options = MKMapSnapshotter.Options()
      options.region = MKCoordinateRegion(center: center, span: span)
      options.size = CGSize(width: width, height: height)
      options.scale = UIScreen.main.scale
      options.mapType = .mutedStandard
      options.pointOfInterestFilter = .excludingAll
      options.traitCollection = UITraitCollection(userInterfaceStyle: .dark)
      MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { snap, error in
        guard let snap = snap, let png = snap.image.pngData() else {
          DispatchQueue.main.async {
            result(FlutterError(code: "snapshot_failed",
                                message: error?.localizedDescription, details: nil))
          }
          return
        }
        var xs = [Double](), ys = [Double]()
        xs.reserveCapacity(lat.count); ys.reserveCapacity(lat.count)
        for i in 0..<lat.count {
          let pt = snap.point(for: CLLocationCoordinate2D(latitude: lat[i], longitude: lng[i]))
          xs.append(Double(pt.x) / width); ys.append(Double(pt.y) / height)
        }
        DispatchQueue.main.async {
          result(["png": FlutterStandardTypedData(bytes: png), "x": xs, "y": ys])
        }
      }
    }
  }
}

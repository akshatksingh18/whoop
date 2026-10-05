import Flutter
import UIKit
import AudioToolbox
import AVFoundation
#if !PERSONAL_SIDELOAD
import BackgroundTasks
#endif
import CoreMotion
import MapKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // CoreBluetooth state restoration — must be created here (early) so iOS can relaunch
    // us with willRestoreState when the band reappears. Wakes the app → headless sync.
    BleRestoreManager.shared.start(launchOptions: launchOptions)

    #if !PERSONAL_SIDELOAD
    // BGTaskScheduler registration MUST happen before didFinishLaunching returns.
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
    #if !PERSONAL_SIDELOAD
    // Live Activity MethodChannel (start/update/end the workout activity).
    // LiveActivityBridge lives in LiveActivityBridge.swift (Runner target).
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LiveActivityBridge") {
      LiveActivityBridge.register(messenger: registrar.messenger())
    }
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
    // BGTask channel: Dart handler for opportunistic headless sync + heavy derivation.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "BackgroundTaskManager") {
      BackgroundTaskManager.wireChannel(messenger: registrar.messenger())
      // Now that the channel is wired, submit the first task requests
      // (heavy processing + light sync-only refresh).
      BackgroundTaskManager.schedule()
      BackgroundTaskManager.scheduleRefresh()
    }
    #endif
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

      case "stepsInInterval":
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
          result(0)
          return
        }
        guard from >= Date().addingTimeInterval(-cacheWindow) else {
          result(notCovered)
          return
        }
        pedometer.queryPedometerData(from: from, to: to) { data, error in
          DispatchQueue.main.async {
            guard let data = data, error == nil else {
              result(nil)
              return
            }
            result(data.numberOfSteps.intValue)
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

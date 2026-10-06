import Foundation
import Flutter
import ActivityKit
import UIKit

// Codable shape must match the extension copy; checked by the contract tests.
@available(iOS 16.1, *)
struct OpenStrapWidgetAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var elapsed: Int
    var distanceKm: Double?
    var paceSeconds: Double?
    var hr: Int?
    var zone: Int?
    var lastKmSeconds: Int?
    var paused: Bool
    var updatedAt: Date
    var timerAnchor: Date
  }
  var sessionId: String
  var sessionName: String
}

@MainActor
enum LiveActivityBridge {
  private static var channel: FlutterMethodChannel?
  private static var pendingSession: String?
  private static var ready = false
  /// The outcome of the last start/update, so a phone that shows nothing can
  /// say why (Settings → Status). Never contains health data.
  private static var last: [String: Any] = ["reason": "not requested yet"]
  static func open(_ url: URL) -> Bool {
    guard url.scheme == "whoop", url.host == "session",
      let id = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?
        .first(where: { $0.name == "id" })?.value, !id.isEmpty else { return false }
    if ready { channel?.invokeMethod("openSession", arguments: id) }
    else { pendingSession = id }
    return true
  }
  static func register(messenger: FlutterBinaryMessenger) {
    let ch = FlutterMethodChannel(name: "openstrap/live_activity", binaryMessenger: messenger)
    channel = ch
    ch.setMethodCallHandler { call, result in
      if call.method == "pendingSession" {
        ready = true
        let id = pendingSession
        pendingSession = nil
        result(id)
        return
      }
      guard #available(iOS 16.2, *) else {
        result(["ok": false, "reason": "needs iOS 16.2"])
        return
      }
      let args = call.arguments as? [String: Any] ?? [:]
      Task { @MainActor in
        switch call.method {
        case "start", "update": result(await publish(args))
        case "status": result(status())
        case "test": result(await test())
        case "end":
          for activity in Activity<OpenStrapWidgetAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
          }
          result(true)
        default: result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  /// What iOS reports, plus the installed extension's identity. A missing or
  /// misnamed extension is the one failure that makes `request` succeed while
  /// the lock screen stays empty.
  @available(iOS 16.2, *)
  private static func status() -> [String: Any] {
    let main = Bundle.main.bundleIdentifier ?? ""
    var plugins: [String] = []
    if let dir = Bundle.main.builtInPlugInsURL,
      let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
      for url in items where url.pathExtension == "appex" {
        plugins.append(Bundle(url: url)?.bundleIdentifier ?? url.lastPathComponent)
      }
    }
    var out = last
    out["enabled"] = ActivityAuthorizationInfo().areActivitiesEnabled
    out["ios"] = UIDevice.current.systemVersion
    out["app"] = main
    out["extensions"] = plugins
    out["extensionOk"] = plugins.contains { $0.hasPrefix(main + ".") }
    out["active"] = Activity<OpenStrapWidgetAttributes>.activities.map { "\($0.activityState)" }
    return out
  }

  /// A one-minute sample on the lock screen, started by the user from Status.
  @available(iOS 16.2, *)
  private static func test() async -> [String: Any] {
    if Activity<OpenStrapWidgetAttributes>.activities.contains(where: { $0.attributes.sessionId != "test" }) {
      return ["ok": false, "reason": "a workout activity is already running"]
    }
    let r = await publish(["id": "test", "name": "Walking", "elapsed": 0, "paused": false])
    if r["ok"] as? Bool == true {
      Task { @MainActor in
        try? await Task.sleep(nanoseconds: 60_000_000_000)
        for a in Activity<OpenStrapWidgetAttributes>.activities where a.attributes.sessionId == "test" {
          await a.end(nil, dismissalPolicy: .immediate)
        }
      }
    }
    var out = status()
    out["ok"] = r["ok"]
    return out
  }

  @available(iOS 16.2, *)
  private static func publish(_ a: [String: Any]) async -> [String: Any] {
    func done(_ ok: Bool, _ reason: String) -> [String: Any] {
      last = ["ok": ok, "reason": reason, "at": Date().timeIntervalSince1970]
      if !ok { NSLog("[LiveActivity] %@", reason) }
      return last
    }
    guard let id = a["id"] as? String, !id.isEmpty else { return done(false, "no session id") }
    guard ActivityAuthorizationInfo().areActivitiesEnabled else {
      return done(false, "Live Activities are off for WHOOP in iOS Settings")
    }
    let now = Date()
    let elapsed = max(0, (a["elapsed"] as? NSNumber)?.intValue ?? 0)
    let state = OpenStrapWidgetAttributes.ContentState(
      elapsed: elapsed,
      distanceKm: (a["distanceKm"] as? NSNumber)?.doubleValue,
      paceSeconds: (a["paceSeconds"] as? NSNumber)?.doubleValue,
      hr: (a["hr"] as? NSNumber)?.intValue,
      zone: (a["zone"] as? NSNumber)?.intValue,
      lastKmSeconds: (a["lastKmSeconds"] as? NSNumber)?.intValue,
      paused: a["paused"] as? Bool ?? false,
      updatedAt: now, timerAnchor: now.addingTimeInterval(-Double(elapsed)))
    let content = ActivityContent(state: state, staleDate: now.addingTimeInterval(45))
    for activity in Activity<OpenStrapWidgetAttributes>.activities {
      if activity.attributes.sessionId == id, activity.activityState == .active || activity.activityState == .stale {
        await activity.update(content)
        return done(true, "updated")
      }
      // An ended, dismissed or foreign activity is replaced, never updated:
      // updating a dismissed one succeeds silently and shows nothing.
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    // Creating a replacement is foreground-only; never use a Live Activity as
    // a keepalive. The app retries on its next foreground.
    guard UIApplication.shared.applicationState != .background else {
      return done(false, "waiting for the app to be open")
    }
    do {
      _ = try Activity.request(attributes: OpenStrapWidgetAttributes(
        sessionId: id, sessionName: a["name"] as? String ?? "Walking"), content: content)
      return done(true, "started")
    } catch {
      return done(false, "iOS refused: \(error.localizedDescription)")
    }
  }
}

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
      guard #available(iOS 16.2, *) else { result(false); return }
      let args = call.arguments as? [String: Any] ?? [:]
      Task { @MainActor in
        switch call.method {
        case "start", "update": result(await publish(args))
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
  @available(iOS 16.2, *)
  private static func publish(_ a: [String: Any]) async -> Bool {
    guard let id = a["id"] as? String, !id.isEmpty,
      ActivityAuthorizationInfo().areActivitiesEnabled else { return false }
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
      if activity.attributes.sessionId == id { await activity.update(content); return true }
      await activity.end(nil, dismissalPolicy: .immediate)
    }
    // Updating may refresh an existing activity in the background. Creating a
    // replacement is foreground-only; never use a Live Activity as a keepalive.
    guard UIApplication.shared.applicationState == .active else { return false }
    do {
      _ = try Activity.request(attributes: OpenStrapWidgetAttributes(
        sessionId: id, sessionName: a["name"] as? String ?? "Walking"), content: content)
      return true
    } catch { return false }
  }
}

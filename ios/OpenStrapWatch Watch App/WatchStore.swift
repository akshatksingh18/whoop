// WatchStore — receives today's metrics from the iPhone and caches them.
//
// Add to the Watch App target only. On activation it pulls the latest snapshot;
// thereafter it receives coalesced `applicationContext` pushes (and complication
// user-info) from WatchBridge on the phone. Every ingest writes the watch-side
// App Group and reloads complication timelines so the face stays in sync.

import Combine
import Foundation
import WatchConnectivity
import WidgetKit

final class WatchStore: NSObject, ObservableObject, WCSessionDelegate {
  static let shared = WatchStore()

  @Published private(set) var metrics: WatchMetrics = .load()
  @Published private(set) var reachable: Bool = false

  func activate() {
    guard WCSession.isSupported() else { return }
    let s = WCSession.default
    s.delegate = self
    s.activate()
  }

  /// Ask the phone for the freshest snapshot (used right after activation and on
  /// manual refresh). Falls back silently if the phone is unreachable.
  func requestRefresh() {
    let s = WCSession.default
    guard s.activationState == .activated, s.isReachable else { return }
    s.sendMessage([:], replyHandler: { [weak self] reply in
      self?.ingest(reply)
    }, errorHandler: nil)
  }

  private func ingest(_ payload: [String: Any]) {
    NSLog("[WatchStore] ingest keys=%@ suiteNil=%d", payload.keys.sorted().joined(separator: ","),
          (UserDefaults(suiteName: WatchConfig.appGroup) == nil) ? 1 : 0)
    guard !payload.isEmpty, let d = UserDefaults(suiteName: WatchConfig.appGroup) else { return }
    for (k, v) in payload { d.set(v, forKey: k) }
    DispatchQueue.main.async {
      self.metrics = .load()
      WidgetCenter.shared.reloadAllTimelines()
    }
  }

  // MARK: - WCSessionDelegate

  func session(
    _ session: WCSession,
    activationDidCompleteWith activationState: WCSessionActivationState,
    error: Error?
  ) {
    DispatchQueue.main.async { self.reachable = session.isReachable }
    if activationState == .activated { requestRefresh() }
  }

  func sessionReachabilityDidChange(_ session: WCSession) {
    DispatchQueue.main.async { self.reachable = session.isReachable }
    if session.isReachable { requestRefresh() }
  }

  func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    ingest(applicationContext)
  }

  func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
    ingest(userInfo)
  }
}

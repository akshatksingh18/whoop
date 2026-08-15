// WatchStore — receives today's metrics from the iPhone and caches them.
//
// Add to the Watch App target only. On activation it pulls the latest snapshot;
// thereafter it receives coalesced `applicationContext` pushes from WatchBridge
// on the phone. Every ingest caches the payload so the glance stays in sync.
//
// There are no complications: the OpenStrapWatchWidget sources were never in
// the Xcode project, so nothing compiled them and there was no timeline to
// reload. Re-adding them means an Xcode-created watchOS widget extension target
// embedded in this app (plus its own bundle id and a watch App Group), not a
// loose folder.

import Combine
import Foundation
import WatchConnectivity

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
    guard !payload.isEmpty else { return }
    let d = UserDefaults.standard
    for (k, v) in payload { d.set(v, forKey: k) }
    DispatchQueue.main.async { self.metrics = .load() }
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

import Foundation
import BackgroundTasks
import Flutter

/// BGTaskScheduler bridge for OpenStrap Edge.
///
/// Registers a BGProcessingTask (identifier: "wtf.openstrap.edge.bgsync") that
/// iOS runs opportunistically when the device is idle. On task launch it calls
/// the Dart `openstrap/bg_task` channel → `run`, which runs runHeadlessSync() +
/// a heavy DerivationEngine pass, then signals completion.
///
/// Task identifier scoped to wtf.openstrap.edge.
///
/// Design notes:
///   - Expiration is a STOP: the handler tells Dart to cancel calculation
///     ("expire"), then completes the task exactly once. A late Dart reply
///     after expiration is ignored rather than completing the task again.
///   - Uses BGProcessingTaskRequest (not BGAppRefreshTaskRequest): allows a
///     longer wall-clock budget and does not require user-granted Background App
///     Refresh — more reliable for compute-heavy sync+derive.
///
/// Call order from AppDelegate:
///   1. BGTaskScheduler.shared.register(forTaskIdentifier:...) in didFinishLaunching
///      (BEFORE super returns) — the OS needs this call before launch completes.
///   2. handleTask(_:) wired as the task handler in that same register block.
///   3. wireChannel(messenger:) called from didInitializeImplicitFlutterEngine so
///      the Flutter binary messenger is available for Dart callout.
///   4. schedule() called after wireChannel so the first request is queued once
///      Dart is ready, and again on every applicationDidEnterBackground.
enum BackgroundTaskManager {
    static let taskIdentifier = "wtf.openstrap.edge.bgsync"
    /// LIGHT companion task: a BGAppRefreshTask (short ~30 s budget, separate
    /// app-refresh budget from processing tasks) that runs a SYNC-ONLY pass —
    /// no heavy derivation — so the band's flash backlog gets pulled more often
    /// than the processing task alone allows. Requires the user's Background
    /// App Refresh setting to be on (the "fetch" UIBackgroundMode was already
    /// declared; this finally registers a task for it).
    static let refreshTaskIdentifier = "wtf.openstrap.edge.refresh"
    private static let channelName = "openstrap/bg_task"
    private static let retryInterval: TimeInterval = 10 * 60   // 10-min earliest

    // Retained so the channel survives between task invocations.
    private static var channel: FlutterMethodChannel?

    /// Completes a BGTask exactly once, whichever of expiration or the Dart
    /// reply arrives first. Main-queue only (both callers hop there).
    private final class Once {
        private var done = false
        func run(_ body: () -> Void) {
            if done { return }
            done = true
            body()
        }
    }

    /// Ask Dart to stop calculation now: iOS is ending the time it granted.
    private static func expire(_ label: String) {
        NativeLog.note("\(label) expired")
        channel?.invokeMethod("expire", arguments: nil)
    }

    // MARK: - AppDelegate hooks

    /// Wire the Dart method channel. Called from didInitializeImplicitFlutterEngine
    /// once the binary messenger is live. Also called from schedule() guard so we
    /// never schedule without a channel.
    static func wireChannel(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
        NSLog("[bg-task] channel wired")
    }

    /// Handle an OS-delivered BGProcessingTask. Pass this as the handler block in
    /// BGTaskScheduler.shared.register(...) inside AppDelegate.didFinishLaunching.
    static func handleTask(_ task: BGProcessingTask) {
        NSLog("[bg-task] task launched")
        NativeLog.note("bg-processing launched")

        // Re-schedule immediately so there is always a next request queued.
        schedule()

        let once = Once()
        // Expiration: stop Dart's calculation, then complete once. Committed
        // work stays; the non-destructive cursor and durable job queue let
        // the next wake or foreground open continue.
        task.expirationHandler = {
            DispatchQueue.main.async {
                expire("bg-processing")
                once.run { task.setTaskCompleted(success: false) }
            }
        }

        guard let ch = channel else {
            NSLog("[bg-task] channel not yet wired — marking complete")
            once.run { task.setTaskCompleted(success: true) }
            return
        }

        ch.invokeMethod("run", arguments: nil) { reply in
            let success = (reply as? Bool) ?? true
            NSLog("[bg-task] Dart returned success=\(success)")
            DispatchQueue.main.async {
                once.run {
                    NativeLog.note("bg-processing completed success=\(success)")
                    task.setTaskCompleted(success: success)
                }
            }
        }
    }

    /// Submit (or renew) the next BGProcessingTaskRequest. Safe to call multiple
    /// times — if a request is already pending, the OS silently replaces it.
    ///
    /// `earliestBeginDate` is documented as a floor, never a promise: "the system
    /// doesn't guarantee launching the task at the specified date, but only that
    /// it won't begin sooner" (BGTaskRequest.earliestBeginDate). Apple's own
    /// sample code uses the identical `Date(timeIntervalSinceNow: 15 * 60)`
    /// pattern — confirmed this matches, not an assumption.
    static func schedule() {
        let req = BGProcessingTaskRequest(identifier: taskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: retryInterval)
        req.requiresNetworkConnectivity = false
        req.requiresExternalPower = false
        do {
            try BGTaskScheduler.shared.submit(req)
            NSLog("[bg-task] scheduled (earliest +\(Int(retryInterval))s)")
        } catch {
            // .notPermitted fires in the Simulator (expected).
            // .tooManyPendingTaskRequests is harmless — prior request still queued.
            NSLog("[bg-task] schedule failed (ignored): \(error)")
        }
    }

    // MARK: - BGAppRefreshTask (light, sync-only)

    /// Handle an OS-delivered BGAppRefreshTask. Registered in AppDelegate under
    /// [refreshTaskIdentifier]. Invokes the same Dart channel as the processing
    /// task but with mode="sync": headless BLE drain only, NO heavy derivation —
    /// a refresh task's ~30 s budget can't fit the heavy pass, and the Dart side
    /// enforces the light profile.
    static func handleRefreshTask(_ task: BGAppRefreshTask) {
        NSLog("[bg-refresh] task launched")
        NativeLog.note("bg-refresh launched")

        // Re-schedule immediately so there is always a next request queued.
        scheduleRefresh()

        let once = Once()
        task.expirationHandler = {
            DispatchQueue.main.async {
                expire("bg-refresh")
                once.run { task.setTaskCompleted(success: false) }
            }
        }

        guard let ch = channel else {
            NSLog("[bg-refresh] channel not yet wired — marking complete")
            once.run { task.setTaskCompleted(success: true) }
            return
        }

        ch.invokeMethod("run", arguments: ["mode": "sync"]) { reply in
            let success = (reply as? Bool) ?? true
            NSLog("[bg-refresh] Dart returned success=\(success)")
            DispatchQueue.main.async {
                once.run {
                    NativeLog.note("bg-refresh completed success=\(success)")
                    task.setTaskCompleted(success: success)
                }
            }
        }
    }

    /// Submit (or renew) the next BGAppRefreshTaskRequest. Same renewal points
    /// as the processing request (post-wire + every sceneDidEnterBackground).
    static func scheduleRefresh() {
        let req = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        req.earliestBeginDate = Date(timeIntervalSinceNow: retryInterval)
        do {
            try BGTaskScheduler.shared.submit(req)
            NSLog("[bg-refresh] scheduled (earliest +\(Int(retryInterval))s)")
        } catch {
            NSLog("[bg-refresh] schedule failed (ignored): \(error)")
        }
    }
}

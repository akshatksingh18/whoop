import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
                      options connectionOptions: UIScene.ConnectionOptions) {
    for context in connectionOptions.urlContexts { _ = LiveActivityBridge.open(context.url) }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    let remaining = Set(URLContexts.filter { !LiveActivityBridge.open($0.url) })
    if !remaining.isEmpty { super.scene(scene, openURLContexts: remaining) }
  }

  /// Re-submit the BGProcessingTask + BGAppRefreshTask requests every time a
  /// scene enters the background so iOS always has pending requests to fire
  /// opportunistically. This is the correct hook in a UISceneDelegate-based app
  /// (scene lifecycle fires reliably; AppDelegate.applicationDidEnterBackground
  /// fires less consistently when UISceneDelegate is in use).
  override func sceneDidEnterBackground(_ scene: UIScene) {
    super.sceneDidEnterBackground(scene)
    #if !PERSONAL_SIDELOAD
    BackgroundTaskManager.schedule()
    BackgroundTaskManager.scheduleRefresh()
    #endif
  }
}

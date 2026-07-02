// OpenStrap App Intents — Siri / Shortcuts / Spotlight / Ultra Action Button.
//
// Add to the Runner (iOS app) target. These read the phone's App Group snapshot
// (the same keys WidgetService writes) and answer spoken/dialog queries. Because
// they're AppShortcuts, they work with zero user setup: "Hey Siri, OpenStrap
// recovery". The Apple Watch Ultra's Action Button can be bound to any of these
// via Settings ▸ Action Button ▸ Shortcut.

import AppIntents
import Foundation

// MARK: - Shared reader

enum OpenStrapShared {
  static var appGroup: String {
    Bundle.main.object(forInfoDictionaryKey: "OpenStrapAppGroupIdentifier") as? String
      ?? "group.wtf.openstrap"
  }

  static func defaults() -> UserDefaults? { UserDefaults(suiteName: appGroup) }

  static var hasData: Bool { defaults()?.bool(forKey: "has_data") ?? false }
  static var readiness: Int { defaults()?.object(forKey: "readiness") as? Int ?? -1 }
  static var strain: Double { defaults()?.object(forKey: "strain") as? Double ?? -1 }
  static var hrv: Int { defaults()?.object(forKey: "hrv") as? Int ?? -1 }
  static var rhr: Int { defaults()?.object(forKey: "rhr") as? Int ?? -1 }
  static var sleepMin: Int { defaults()?.object(forKey: "sleep_min") as? Int ?? -1 }

  static var sleepText: String {
    guard sleepMin >= 0 else { return "no sleep data yet" }
    return "\(sleepMin / 60) hours \(sleepMin % 60) minutes"
  }
  static var noData: String { "I don't have today's numbers yet. Open OpenStrap and sync your strap." }
}

// MARK: - Intents

@available(iOS 16.0, *)
struct RecoveryIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Recovery"
  static var description = IntentDescription("Ask OpenStrap for today's recovery.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.readiness >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.noData))
    }
    let r = OpenStrapShared.readiness
    let tier = r < 34 ? "Take it easy today." : (r < 67 ? "A moderate day looks good." : "You're primed to push.")
    return .result(dialog: "Your recovery is \(r) percent. \(tier)")
  }
}

@available(iOS 16.0, *)
struct StrainIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Strain"
  static var description = IntentDescription("Ask OpenStrap for today's strain.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.strain >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.noData))
    }
    let s = String(format: "%.1f", OpenStrapShared.strain)
    return .result(dialog: "Today's strain so far is \(s) out of twenty-one.")
  }
}

@available(iOS 16.0, *)
struct SleepIntent: AppIntent {
  static var title: LocalizedStringResource = "Check Sleep"
  static var description = IntentDescription("Ask OpenStrap how you slept.")
  static var openAppWhenRun = false

  func perform() async throws -> some IntentResult & ProvidesDialog {
    guard OpenStrapShared.hasData, OpenStrapShared.sleepMin >= 0 else {
      return .result(dialog: IntentDialog(stringLiteral: OpenStrapShared.noData))
    }
    return .result(dialog: "You slept \(OpenStrapShared.sleepText) last night.")
  }
}

// MARK: - Shortcuts provider (zero-setup Siri phrases)

@available(iOS 16.0, *)
struct OpenStrapShortcuts: AppShortcutsProvider {
  static var appShortcuts: [AppShortcut] {
    AppShortcut(
      intent: RecoveryIntent(),
      phrases: [
        "\(.applicationName) recovery",
        "What's my recovery in \(.applicationName)",
        "How recovered am I in \(.applicationName)",
      ],
      shortTitle: "Recovery",
      systemImageName: "bolt.heart")

    AppShortcut(
      intent: StrainIntent(),
      phrases: [
        "\(.applicationName) strain",
        "What's my strain in \(.applicationName)",
      ],
      shortTitle: "Strain",
      systemImageName: "flame")

    AppShortcut(
      intent: SleepIntent(),
      phrases: [
        "\(.applicationName) sleep",
        "How did I sleep in \(.applicationName)",
      ],
      shortTitle: "Sleep",
      systemImageName: "moon.zzz")
  }
}

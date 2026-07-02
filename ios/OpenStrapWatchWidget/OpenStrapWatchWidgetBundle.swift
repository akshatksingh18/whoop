// OpenStrap Watch complications — WidgetKit widgets for the Apple Watch face.
//
// Add these to a "Watch Widget Extension" target embedded in the Watch App.
// They read the watch-side App Group (written by WatchStore when the phone
// pushes fresh metrics) and render as accessory-family complications. Add
// WatchMetrics.swift to this target too (shared model + WatchConfig.appGroup).

import SwiftUI
import WidgetKit

// MARK: - Timeline

struct RecoveryEntry: TimelineEntry {
  let date: Date
  let metrics: WatchMetrics
}

struct RecoveryProvider: TimelineProvider {
  func placeholder(in context: Context) -> RecoveryEntry {
    RecoveryEntry(date: Date(), metrics: .empty)
  }

  func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
    completion(RecoveryEntry(date: Date(), metrics: .load()))
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
    // Data is push-driven (WatchStore reloads timelines on new WCSession data),
    // so a single current entry with a periodic safety refresh is enough.
    let entry = RecoveryEntry(date: Date(), metrics: .load())
    let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
    completion(Timeline(entries: [entry], policy: .after(next)))
  }
}

private func recoveryColor(_ tier: Int) -> Color {
  // Matches lib/theme/tokens.dart good/warn/bad (Char variant, for the dark face).
  switch tier {
  case 2: return Color(red: 0x34 / 255, green: 0xC9 / 255, blue: 0x88 / 255) // good
  case 1: return Color(red: 0xF7 / 255, green: 0xB5 / 255, blue: 0x3A / 255) // warn
  case 0: return Color(red: 0xF2 / 255, green: 0x61 / 255, blue: 0x68 / 255) // bad
  default: return .gray
  }
}

// MARK: - Recovery complication (circular / corner / inline)

struct RecoveryComplication: Widget {
  let kind = "OpenStrapRecovery"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RecoveryProvider()) { entry in
      RecoveryComplicationView(m: entry.metrics)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Recovery")
    .description("Today's recovery from OpenStrap.")
    .supportedFamilies([.accessoryCircular, .accessoryCorner, .accessoryInline])
  }
}

struct RecoveryComplicationView: View {
  @Environment(\.widgetFamily) private var family
  let m: WatchMetrics

  var body: some View {
    switch family {
    case .accessoryInline:
      Label("Recovery \(m.readinessText)", systemImage: "bolt.heart")
    case .accessoryCorner:
      Text(m.readinessText)
        .font(.system(size: 18, weight: .bold, design: .rounded))
        .widgetLabel {
          Gauge(value: m.readinessFraction) { EmptyView() }
            .tint(recoveryColor(m.recoveryTier))
        }
    default: // accessoryCircular
      Gauge(value: m.readinessFraction) {
        Image(systemName: "bolt.heart")
      } currentValueLabel: {
        Text(m.readiness >= 0 ? "\(m.readiness)" : "—")
          .font(.system(size: 15, weight: .bold, design: .rounded))
      }
      .gaugeStyle(.accessoryCircular)
      .tint(recoveryColor(m.recoveryTier))
    }
  }
}

// MARK: - Combined rectangular (recovery · strain · sleep)

struct TodayComplication: Widget {
  let kind = "OpenStrapToday"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: RecoveryProvider()) { entry in
      TodayComplicationView(m: entry.metrics)
        .containerBackground(.clear, for: .widget)
    }
    .configurationDisplayName("Today")
    .description("Recovery, strain and sleep at a glance.")
    .supportedFamilies([.accessoryRectangular])
  }
}

struct TodayComplicationView: View {
  let m: WatchMetrics

  var body: some View {
    HStack(spacing: 8) {
      Gauge(value: m.readinessFraction) {
        EmptyView()
      } currentValueLabel: {
        Text(m.readiness >= 0 ? "\(m.readiness)" : "—")
          .font(.system(size: 13, weight: .bold, design: .rounded))
      }
      .gaugeStyle(.accessoryCircular)
      .tint(recoveryColor(m.recoveryTier))

      VStack(alignment: .leading, spacing: 1) {
        Text("Recovery")
          .font(.system(size: 12, weight: .semibold))
        Text("Strain \(m.strainText)  ·  \(m.sleepText)")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
        if !m.coachLine.isEmpty {
          Text(m.coachLine)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
      }
      Spacer(minLength: 0)
    }
  }
}

// MARK: - Bundle

@main
struct OpenStrapWatchWidgetBundle: WidgetBundle {
  var body: some Widget {
    RecoveryComplication()
    TodayComplication()
  }
}

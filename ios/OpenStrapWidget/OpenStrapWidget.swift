//
//  OpenStrapWidget.swift
//  OpenStrapWidget
//
//  Home/lock-screen widget — renders the snapshot the app writes into the shared
//  App Group. Nothing else: this is a local-first app with no backend and no
//  account, so there is nothing for the widget to fetch. (It used to carry a
//  "self-refreshes hourly by fetching /today" path guarded on a JWT that no code
//  ever wrote — dead on every install, and its parser hard-wrote has_data = true,
//  which would have clobbered the app's staleness gate the moment anyone wired it
//  up.) The app calls WidgetService.refresh() after every derive; that is the
//  only refresh there is.
//
//  Shows three rings: Strain · Sleep · HRV. (Recovery was retired — the app no
//  longer surfaces a recovery score; HRV is the real measured autonomic signal.)
//
//  HONESTY: `has_data` is the Dart side saying "this snapshot is empty or more
//  than a day old" — every view here gates on it, and an absent metric is drawn
//  as an empty slot, never as a dash over a ring pinned at zero. The readiness
//  BANDING is not computed here: Dart publishes `readiness_tier` so the phone,
//  the widget, the watch and Siri cannot disagree about what 65 means.

import WidgetKit
import SwiftUI

private let kAppGroup = AppGroup.identifier

// MARK: - Theme (Ember on Paper / Char)
// The app writes "theme_dark" into the App Group to mirror its in-app appearance
// (which already resolves "System" to the actual OS brightness). Surfaces + ink
// flip between paper and char; the ember coral + ring accents stay constant.

private extension Color {
  init(_ r: Int, _ g: Int, _ b: Int) {
    self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
  }
}

private struct Pal {
  let bg: Color, ink: Color, inkMuted: Color, track: Color
  let good: Color, warn: Color, bad: Color
  static let light = Pal(bg: Color(244, 241, 236), ink: Color(26, 23, 20),
                         inkMuted: Color(165, 156, 144), track: Color(236, 231, 223),
                         good: Color(43, 182, 115), warn: Color(245, 166, 35),
                         bad: Color(229, 72, 77))
  static let dark  = Pal(bg: Color(30, 26, 21), ink: Color(241, 236, 227),
                         inkMuted: Color(126, 116, 102), track: Color(42, 37, 31),
                         good: Color(52, 201, 136), warn: Color(247, 181, 58),
                         bad: Color(242, 97, 104))
  static var isDark: Bool {
    UserDefaults(suiteName: kAppGroup)?.object(forKey: "theme_dark") as? Bool ?? false
  }
  static var current: Pal { isDark ? .dark : .light }
}

private extension Color {
  static var paper: Color { Pal.current.bg }
  static var ink: Color { Pal.current.ink }
  static var inkMuted: Color { Pal.current.inkMuted }
  static var surfaceAlt: Color { Pal.current.track }
  static var good: Color { Pal.current.good }
  static var warn: Color { Pal.current.warn }
  static var bad: Color { Pal.current.bad }
  static let coral      = Color(255, 90, 54)
  static let coralDeep  = Color(232, 67, 31)
  static let sleepBlue  = Color(124, 168, 240)
}

// MARK: - Model

struct OpenStrapEntry: TimelineEntry {
  let date: Date
  let hasData: Bool
  let readiness: Int      // -1 = none (composite 0..100) — the headline
  let tier: Int           // -1 = not scored · 0 rest · 1 easy · 2 steady · 3 good
  let band: String        // the phone's own label for `tier` ("Steady", …)
  let strain: Double      // -1 = none
  let sleepMin: Int       // -1 = none
  let needMin: Int    // -1 = none (sleep need, min) — never fabricate 8h
  let hrv: Int            // -1 = none (RMSSD, ms)
  let hrvBaseline: Int    // -1 = none (personal RMSSD baseline, ms)
  let rhr: Int            // -1 = none
  let coachLine: String

  static let placeholder = OpenStrapEntry(
    date: Date(), hasData: true, readiness: 72, tier: 2, band: "Steady",
    strain: 12.4, sleepMin: 437, needMin: 480, hrv: 62, hrvBaseline: 58, rhr: 54,
    coachLine: "Room to push today")

  // Ring fractions (0…1). A negative fraction means "no measurement" — Ring
  // draws the track only, and no view fills an arc against a value we don't have.
  var readinessT: Double { readiness >= 0 ? Double(readiness) / 100.0 : -1 }
  /// Tier → colour. The THRESHOLDS live in Dart (`readinessBand` in
  /// lib/ui2/screens/home_screen.dart) and arrive as `readiness_tier`; this maps
  /// the tier onto the widget's own surface palette and nothing more. Do not
  /// re-derive a band from `readiness` here — that is how the phone, the widget
  /// and the watch ended up disagreeing about the same score.
  var readinessColor: Color {
    switch tier {
    case 3, 2: return .good
    case 1: return .warn
    case 0: return .bad
    default: return .inkMuted
    }
  }
  var strainT: Double { strain >= 0 ? min(strain / 21.0, 1) : -1 }
  var sleepT: Double { (sleepMin >= 0 && needMin > 0) ? min(Double(sleepMin) / Double(needMin), 1) : -1 }
  var hrvT: Double {
    guard hrv >= 0 else { return -1 }
    if hrvBaseline > 0 { return min(Double(hrv) / (1.5 * Double(hrvBaseline)), 1) }
    return min(Double(hrv) / 100.0, 1)
  }
  // HRV reads green at/above your baseline, warmer as it drops below it.
  var hrvColor: Color {
    guard hrv >= 0, hrvBaseline > 0 else { return .inkMuted }
    if hrv >= hrvBaseline { return .good }
    if hrv >= Int(0.8 * Double(hrvBaseline)) { return .warn }
    return .bad
  }
}

// MARK: - Shared store (App Group, read-only)

private enum Store {
  static var defaults: UserDefaults? { UserDefaults(suiteName: kAppGroup) }

  static func read() -> OpenStrapEntry {
    let d = defaults
    return OpenStrapEntry(
      date: Date(),
      hasData: d?.bool(forKey: "has_data") ?? false,
      readiness: d?.object(forKey: "readiness") as? Int ?? -1,
      tier: d?.object(forKey: "readiness_tier") as? Int ?? -1,
      band: d?.string(forKey: "readiness_band") ?? "",
      strain: d?.object(forKey: "strain") as? Double ?? -1,
      sleepMin: d?.object(forKey: "sleep_min") as? Int ?? -1,
      needMin: (d?.object(forKey: "sleep_need_min") as? Int) ?? -1,
      hrv: d?.object(forKey: "hrv") as? Int ?? -1,
      hrvBaseline: d?.object(forKey: "hrv_baseline") as? Int ?? -1,
      rhr: d?.object(forKey: "rhr") as? Int ?? -1,
      coachLine: d?.string(forKey: "coach_line") ?? "")
  }
}

// MARK: - Provider

struct Provider: TimelineProvider {
  func placeholder(in context: Context) -> OpenStrapEntry { .placeholder }

  func getSnapshot(in context: Context, completion: @escaping (OpenStrapEntry) -> Void) {
    completion(context.isPreview ? .placeholder : Store.read())
  }

  func getTimeline(in context: Context, completion: @escaping (Timeline<OpenStrapEntry>) -> Void) {
    // Push-driven: the app reloads timelines after every derive. The hourly
    // re-render exists so `has_data` can go stale on its own if it doesn't.
    let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date())
      ?? Date().addingTimeInterval(3600)
    completion(Timeline(entries: [Store.read()], policy: .after(next)))
  }
}

// MARK: - Reusable views

private struct Ring: View {
  let t: Double
  let color: Color
  let lineWidth: CGFloat
  var body: some View {
    ZStack {
      Circle().stroke(Color.surfaceAlt, lineWidth: lineWidth)
      if t > 0 {
        Circle()
          .trim(from: 0, to: min(max(t, 0), 1))
          .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(-90))
      }
    }
  }
}

/// Minutes → "45m" / "7h 05m". Byte-for-byte the phone's `hm()`
/// (lib/ui2/screens/home_screen.dart) so the same night reads the same on both.
private func hm(_ min: Int) -> String {
  if min < 0 { return "" }
  if min < 60 { return "\(min)m" }
  return String(format: "%dh %02dm", min / 60, min % 60)
}

private func numFont(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .rounded) }

/// One labelled metric ring (used for all three: Strain / Sleep / HRV).
///
/// An absent metric is an EMPTY slot: no number, no arc, the whole cell dimmed.
/// The phone's contract (grammar.dart) is what/why/fix, which does not fit in a
/// 44pt circle — but a bare "—" over a ring drawn at zero reads as "your HRV is
/// zero", which is worse than saying nothing. The reason is one tap away.
private struct MetricRing: View {
  let label: String
  let value: String
  let t: Double
  let color: Color
  var size: CGFloat = 58
  var line: CGFloat = 7
  var valueSize: CGFloat = 16
  private var absent: Bool { value.isEmpty }
  var body: some View {
    VStack(spacing: 5) {
      ZStack {
        Ring(t: t, color: color, lineWidth: line)
        Text(value).font(numFont(valueSize)).foregroundColor(.ink).minimumScaleFactor(0.6).lineLimit(1)
      }
      .frame(width: size, height: size)
      Text(label).font(.system(size: 9, weight: .semibold)).tracking(0.8).foregroundColor(.inkMuted)
    }
    .opacity(absent ? 0.4 : 1)
  }
}

/// The three rings in a row, each taking an equal share of the width so they're
/// evenly distributed regardless of value width.
private struct TripleRings: View {
  let e: OpenStrapEntry
  var size: CGFloat = 58
  var line: CGFloat = 7
  var valueSize: CGFloat = 16
  var body: some View {
    HStack(spacing: 0) {
      MetricRing(label: "STRAIN",
                 value: e.strain >= 0 ? String(format: "%.1f", e.strain) : "",
                 t: e.strainT, color: .coral, size: size, line: line, valueSize: valueSize)
        .frame(maxWidth: .infinity)
      MetricRing(label: "SLEEP", value: hm(e.sleepMin),
                 t: e.sleepT, color: .sleepBlue, size: size, line: line, valueSize: valueSize - 1)
        .frame(maxWidth: .infinity)
      MetricRing(label: "HRV", value: e.hrv >= 0 ? "\(e.hrv)" : "",
                 t: e.hrvT, color: e.hrvColor, size: size, line: line, valueSize: valueSize)
        .frame(maxWidth: .infinity)
    }
    .frame(maxWidth: .infinity)
  }
}

/// Readiness headline row — big ring + score + the phone's own band label.
private struct ReadinessRow: View {
  let e: OpenStrapEntry
  var ring: CGFloat = 64
  var body: some View {
    HStack(spacing: 12) {
      ZStack {
        Ring(t: e.readinessT, color: e.readinessColor, lineWidth: 9)
        if e.readiness >= 0 {
          Text("\(e.readiness)").font(numFont(22)).foregroundColor(e.readinessColor)
        }
      }
      .frame(width: ring, height: ring)
      VStack(alignment: .leading, spacing: 2) {
        Text("READINESS").font(.system(size: 10, weight: .semibold)).tracking(1.1).foregroundColor(.inkMuted)
        Text(e.readiness >= 0
             ? (e.band.isEmpty ? "HRV recovery + sleep" : e.band)
             : "Still building your baseline")
          .font(.system(size: 12)).foregroundColor(.ink)
      }
      Spacer(minLength: 0)
    }
    .opacity(e.readiness >= 0 ? 1 : 0.55)
  }
}

private struct SmallView: View {
  let e: OpenStrapEntry
  var body: some View {
    // 2×2: Readiness · Strain / Sleep · HRV.
    VStack(spacing: 10) {
      HStack(spacing: 0) {
        MetricRing(label: "READY", value: e.readiness >= 0 ? "\(e.readiness)" : "",
                   t: e.readinessT, color: e.readinessColor, size: 44, line: 6, valueSize: 13).frame(maxWidth: .infinity)
        MetricRing(label: "STRAIN", value: e.strain >= 0 ? String(format: "%.1f", e.strain) : "",
                   t: e.strainT, color: .coral, size: 44, line: 6, valueSize: 13).frame(maxWidth: .infinity)
      }
      HStack(spacing: 0) {
        MetricRing(label: "SLEEP", value: hm(e.sleepMin), t: e.sleepT, color: .sleepBlue, size: 44, line: 6, valueSize: 12).frame(maxWidth: .infinity)
        MetricRing(label: "HRV", value: e.hrv >= 0 ? "\(e.hrv)" : "", t: e.hrvT, color: e.hrvColor, size: 44, line: 6, valueSize: 13).frame(maxWidth: .infinity)
      }
    }
    .padding(12)
  }
}

private struct MediumView: View {
  let e: OpenStrapEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      ReadinessRow(e: e)
      TripleRings(e: e, size: 56, line: 7, valueSize: 15)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
  }
}

/// `has_data == false` — the app is telling us the snapshot is empty or is
/// describing a day more than one behind. Say that; do not render last week's
/// readiness at full confidence.
private struct NoDataView: View {
  @Environment(\.widgetFamily) var family
  var body: some View {
    switch family {
    case .accessoryCircular:
      Image(systemName: "bolt.heart").font(.system(size: 18)).widgetAccentable()
    case .accessoryRectangular:
      VStack(alignment: .leading, spacing: 2) {
        Text("No recent data").font(.system(size: 13, weight: .bold)).widgetAccentable()
        Text("Open OpenStrap and sync your strap.")
          .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
      }
    case .accessoryInline:
      Text("OpenStrap · no recent data")
    default:
      VStack(spacing: 6) {
        Image(systemName: "bolt.heart").font(.system(size: 22)).foregroundColor(.inkMuted)
        Text("No recent data")
          .font(.system(size: 14, weight: .semibold, design: .rounded)).foregroundColor(.ink)
        Text("Open OpenStrap and sync your strap.")
          .font(.system(size: 11)).multilineTextAlignment(.center).foregroundColor(.inkMuted)
      }
      .padding(12)
    }
  }
}

private struct AccessoryCircularView: View {
  let e: OpenStrapEntry
  var body: some View {
    // No Gauge when there is no score: `Gauge(value: 0)` draws a ring pinned at
    // empty, which is indistinguishable from "your readiness is 0".
    if e.readiness >= 0 {
      Gauge(value: e.readinessT) {
        Text("RDY")
      } currentValueLabel: {
        Text("\(e.readiness)")
      }
      .gaugeStyle(.accessoryCircular)
      .widgetAccentable()
    } else {
      VStack(spacing: 0) {
        Image(systemName: "bolt.heart").font(.system(size: 15)).widgetAccentable()
        Text("RDY").font(.system(size: 9, weight: .semibold))
      }
    }
  }
}

private struct AccessoryRectangularView: View {
  let e: OpenStrapEntry
  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(e.readiness >= 0 ? "Readiness \(e.readiness)" : "Readiness not scored")
        .font(.system(size: 13, weight: .bold)).widgetAccentable()
      Text(pair("Strain", e.strain >= 0 ? String(format: "%.1f", e.strain) : nil,
                "HRV", e.hrv >= 0 ? "\(e.hrv)" : nil))
        .font(.system(size: 13, weight: .semibold))
      Text(pair("Sleep", hm(e.sleepMin).isEmpty ? nil : hm(e.sleepMin),
                "RHR", e.rhr >= 0 ? "\(e.rhr)" : nil))
        .font(.system(size: 12)).foregroundStyle(.secondary)
    }
  }

  /// Two "Label value" pairs, dropping whichever side has no measurement — an
  /// absent metric is left out of the line rather than printed as a dash.
  private func pair(_ aLabel: String, _ a: String?, _ bLabel: String, _ b: String?) -> String {
    [a.map { "\(aLabel) \($0)" }, b.map { "\(bLabel) \($0)" }]
      .compactMap { $0 }.joined(separator: "   ")
  }
}

private extension View {
  @ViewBuilder func widgetBackground(_ color: Color) -> some View {
    containerBackground(color, for: .widget)
  }
}

struct OpenStrapWidgetEntryView: View {
  @Environment(\.widgetFamily) var family
  var entry: OpenStrapEntry

  var body: some View {
    content.widgetBackground(isSystem ? Color.paper : Color.clear)
  }

  private var isSystem: Bool { family == .systemSmall || family == .systemMedium }

  @ViewBuilder private var content: some View {
    if !entry.hasData {
      NoDataView()
    } else {
      switch family {
      case .systemSmall:  SmallView(e: entry)
      case .systemMedium: MediumView(e: entry)
      case .accessoryCircular:    AccessoryCircularView(e: entry)
      case .accessoryRectangular: AccessoryRectangularView(e: entry)
      case .accessoryInline:
        Text(entry.readiness >= 0 ? "Ready \(entry.readiness)" : "Readiness not scored")
      default: SmallView(e: entry)
      }
    }
  }
}

struct OpenStrapWidget: Widget {
  let kind: String = "OpenStrapWidget"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: Provider()) { entry in
      OpenStrapWidgetEntryView(entry: entry)
    }
    .configurationDisplayName("OpenStrap")
    .description("Readiness, strain, sleep and HRV at a glance.")
    .supportedFamilies([.systemSmall, .systemMedium,
                        .accessoryCircular, .accessoryRectangular, .accessoryInline])
  }
}

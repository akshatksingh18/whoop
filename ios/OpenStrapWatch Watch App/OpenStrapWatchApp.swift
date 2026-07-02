// Edge Watch App — the on-wrist glance for today's recovery, strain and sleep.
//
// Read-only mirror of the phone's derived metrics (received over WCSession by
// WatchStore). Styled to match the phone app: "Ember on Paper" (light) / "Char"
// (dark), tracking the app's own theme via the `theme_dark` flag it syncs. No
// compute, no BLE — the WHOOP band is the sensor and the phone does the analytics.

import SwiftUI

@main
struct OpenStrapWatchApp: App {
  @StateObject private var store = WatchStore.shared

  init() { WatchStore.shared.activate() }

  var body: some Scene {
    WindowGroup {
      WatchGlanceView()
        .environmentObject(store)
    }
  }
}

// MARK: - Palette (mirrors lib/theme/tokens.dart — Ember on Paper / Char)

extension Color {
  init(hex: UInt32) {
    self.init(
      .sRGB,
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255,
      opacity: 1)
  }
}

struct Palette {
  let bg, surface, surfaceAlt, divider: Color
  let ink, inkSoft, inkMuted: Color
  let coral, coralSoft, coralInk: Color
  let good, warn, bad, cool: Color

  static let ember = Palette(
    bg: Color(hex: 0xF4F1EC), surface: Color(hex: 0xFFFFFF),
    surfaceAlt: Color(hex: 0xECE7DF), divider: Color(hex: 0xE6E0D6),
    ink: Color(hex: 0x16130F), inkSoft: Color(hex: 0x6B6157), inkMuted: Color(hex: 0xA59C90),
    coral: Color(hex: 0xFF5A36), coralSoft: Color(hex: 0xFFE7DF), coralInk: Color(hex: 0x7A2A16),
    good: Color(hex: 0x2BB673), warn: Color(hex: 0xF5A623), bad: Color(hex: 0xE5484D),
    cool: Color(hex: 0x7CA8F0))

  static let char = Palette(
    bg: Color(hex: 0x14110D), surface: Color(hex: 0x1E1A15),
    surfaceAlt: Color(hex: 0x2A251F), divider: Color(hex: 0x302A22),
    ink: Color(hex: 0xF1ECE3), inkSoft: Color(hex: 0xB6AB9C), inkMuted: Color(hex: 0x7E7466),
    coral: Color(hex: 0xFF6B47), coralSoft: Color(hex: 0x3A2018), coralInk: Color(hex: 0xFFB59E),
    good: Color(hex: 0x34C988), warn: Color(hex: 0xF7B53A), bad: Color(hex: 0xF26168),
    cool: Color(hex: 0x8FB4F2))

  func recovery(_ tier: Int) -> Color {
    switch tier {
    case 2: return good
    case 1: return warn
    case 0: return bad
    default: return inkMuted
    }
  }
}

// MARK: - Glance

struct WatchGlanceView: View {
  @EnvironmentObject var store: WatchStore
  private var m: WatchMetrics { store.metrics }
  private var p: Palette { m.themeDark ? .char : .ember }

  var body: some View {
    ZStack {
      p.bg.ignoresSafeArea()
      // Signature coral ember glow, top-trailing (matches the app's GlowCard/recap).
      RadialGradient(
        colors: [p.coral.opacity(m.themeDark ? 0.20 : 0.16), .clear],
        center: .topTrailing, startRadius: 2, endRadius: 130)
        .ignoresSafeArea()

      ScrollView {
        VStack(spacing: 12) {
          if !m.hasData { empty } else {
            recoveryHero
            HStack(spacing: 10) {
              MetricCard(p: p, title: "STRAIN", value: m.strainText,
                         fraction: m.strainFraction, accent: p.coral)
              MetricCard(p: p, title: "SLEEP", value: m.sleepText,
                         fraction: m.sleepFraction, accent: p.cool)
            }
            HStack(spacing: 8) {
              StatCell(p: p, label: "HRV", value: m.hrvText, unit: "ms")
              StatCell(p: p, label: "RHR", value: m.rhrText, unit: "bpm")
            }
            if !m.coachLine.isEmpty { coach }
          }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
      }
    }
    .onAppear { store.requestRefresh() }
  }

  private var empty: some View {
    VStack(spacing: 8) {
      Image(systemName: "heart.text.square")
        .font(.system(size: 32))
        .foregroundStyle(p.inkMuted)
      Text("No data yet")
        .font(.system(size: 16, weight: .semibold, design: .rounded))
        .foregroundStyle(p.ink)
      Text("Open Edge on your iPhone and sync your strap.")
        .font(.system(size: 12))
        .multilineTextAlignment(.center)
        .foregroundStyle(p.inkSoft)
    }
    .padding(.top, 20)
  }

  private var recoveryHero: some View {
    let tint = p.recovery(m.recoveryTier)
    return ZStack {
      Circle().stroke(tint.opacity(0.18), lineWidth: 11)
      Circle()
        .trim(from: 0, to: m.readinessFraction)
        .stroke(tint, style: StrokeStyle(lineWidth: 11, lineCap: .round))
        .rotationEffect(.degrees(-90))
      VStack(spacing: -2) {
        Text(m.readiness >= 0 ? "\(m.readiness)" : "—")
          .font(.system(size: 40, weight: .bold, design: .rounded))
          .foregroundStyle(p.ink)
        Text("RECOVERY")
          .font(.system(size: 9, weight: .semibold, design: .rounded))
          .tracking(1.2)
          .foregroundStyle(p.inkMuted)
      }
    }
    .frame(width: 118, height: 118)
    .padding(.vertical, 2)
  }

  private var coach: some View {
    HStack(alignment: .top, spacing: 6) {
      Image(systemName: "sparkles")
        .font(.system(size: 11))
        .foregroundStyle(p.coralInk)
      Text(m.coachLine)
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(p.coralInk)
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 8)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(p.coralSoft, in: RoundedRectangle(cornerRadius: 12))
  }
}

// MARK: - Components

private struct MetricCard: View {
  let p: Palette
  let title: String
  let value: String
  let fraction: Double
  let accent: Color

  var body: some View {
    VStack(spacing: 6) {
      ZStack {
        Circle().stroke(accent.opacity(0.18), lineWidth: 6)
        Circle()
          .trim(from: 0, to: fraction)
          .stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(-90))
        Text(value)
          .font(.system(size: 15, weight: .bold, design: .rounded))
          .foregroundStyle(p.ink)
          .minimumScaleFactor(0.6)
          .lineLimit(1)
          .padding(3)
      }
      .frame(width: 54, height: 54)
      Text(title)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(p.inkMuted)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 10)
    .background(p.surface, in: RoundedRectangle(cornerRadius: 14))
    .overlay(RoundedRectangle(cornerRadius: 14).stroke(p.divider, lineWidth: 1))
  }
}

private struct StatCell: View {
  let p: Palette
  let label: String
  let value: String
  let unit: String

  var body: some View {
    VStack(spacing: 1) {
      Text(label)
        .font(.system(size: 9, weight: .semibold, design: .rounded))
        .tracking(0.8)
        .foregroundStyle(p.inkMuted)
      HStack(alignment: .firstTextBaseline, spacing: 2) {
        Text(value)
          .font(.system(size: 18, weight: .bold, design: .rounded))
          .foregroundStyle(p.ink)
        Text(unit)
          .font(.system(size: 9))
          .foregroundStyle(p.inkSoft)
      }
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .background(p.surface, in: RoundedRectangle(cornerRadius: 12))
    .overlay(RoundedRectangle(cornerRadius: 12).stroke(p.divider, lineWidth: 1))
  }
}

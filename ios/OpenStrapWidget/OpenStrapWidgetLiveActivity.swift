import ActivityKit
import WidgetKit
import SwiftUI

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

@available(iOSApplicationExtension 16.2, *)
struct OpenStrapWidgetLiveActivity: Widget {
  private func url(_ id: String) -> URL? {
    var u = URLComponents()
    u.scheme = "whoop"; u.host = "session"
    u.queryItems = [URLQueryItem(name: "id", value: id)]
    return u.url
  }
  private func duration(_ seconds: Int) -> String {
    String(format: "%02d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
  }
  private func pace(_ seconds: Double?) -> String {
    guard let s = seconds, s.isFinite, s > 0, s < 3600 else { return "—" }
    return String(format: "%d:%02d", Int(s) / 60, Int(s) % 60)
  }
  @ViewBuilder private func timer(_ s: OpenStrapWidgetAttributes.ContentState, stale: Bool = false) -> some View {
    if s.paused || stale { Text(duration(s.elapsed)) }
    else { Text(s.timerAnchor, style: .timer).monospacedDigit() }
  }
  private func metric(_ value: String, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
      Text(label).font(.caption).foregroundStyle(.secondary)
    }.frame(maxWidth: .infinity, alignment: .leading)
  }
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: OpenStrapWidgetAttributes.self) { c in
      VStack(alignment: .leading, spacing: 12) {
        HStack {
          Label(c.attributes.sessionName, systemImage: c.attributes.sessionName == "Running" ? "figure.run" : "figure.walk")
            .foregroundStyle(.mint).font(.subheadline.weight(.semibold))
          Spacer()
          Text(c.state.paused ? "PAUSED" : c.isStale ? "LAST UPDATE" : "RECORDING")
            .font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            timer(c.state, stale: c.isStale).font(.system(size: 25, weight: .semibold, design: .rounded))
            Text("Active time").font(.caption).foregroundStyle(.secondary)
          }.frame(maxWidth: .infinity, alignment: .leading)
          metric(c.state.distanceKm.map { String(format: "%.2f", $0) } ?? "—", "Distance · km")
          metric(c.isStale || c.state.paused ? "—" : pace(c.state.paceSeconds), "Pace · /km")
        }
        HStack {
          if !c.isStale, !c.state.paused, let hr = c.state.hr {
            Label("\(hr) bpm", systemImage: "heart.fill").foregroundStyle(.pink)
            if let zone = c.state.zone { Text("Z\(zone)").foregroundStyle(.secondary) }
          }
          if c.isStale { Text(c.state.updatedAt, style: .time).foregroundStyle(.secondary) }
          Spacer()
          Text("Tap for controls ›").foregroundStyle(.secondary)
        }.font(.caption)
        if let split = c.state.lastKmSeconds, split > 0 {
          Text("Last km · \(pace(Double(split))) /km").font(.caption).foregroundStyle(.secondary)
        }
      }.padding(16).activityBackgroundTint(Color(red: 0.06, green: 0.07, blue: 0.08))
        .activitySystemActionForegroundColor(.white).foregroundStyle(.white)
        .widgetURL(url(c.attributes.sessionId))
    } dynamicIsland: { c in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(c.attributes.sessionName, systemImage: c.attributes.sessionName == "Running" ? "figure.run" : "figure.walk").font(.caption).foregroundStyle(.mint)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(c.state.paused ? "Paused" : c.state.distanceKm.map { String(format: "%.2f km", $0) } ?? "— km")
            .font(.headline).monospacedDigit()
        }
        DynamicIslandExpandedRegion(.bottom) {
          HStack { timer(c.state, stale: c.isStale); Spacer(); Text(c.isStale || c.state.paused ? "— /km" : "\(pace(c.state.paceSeconds)) /km") }
            .font(.headline).monospacedDigit()
        }
      } compactLeading: {
        Image(systemName: c.state.paused ? "pause.fill" : c.attributes.sessionName == "Running" ? "figure.run" : "figure.walk").foregroundStyle(.mint)
      } compactTrailing: {
        Text(c.state.distanceKm.map { String(format: "%.1f", $0) } ?? "—").monospacedDigit()
      } minimal: {
        Image(systemName: c.state.paused ? "pause.fill" : c.attributes.sessionName == "Running" ? "figure.run" : "figure.walk").foregroundStyle(.mint)
      }.widgetURL(url(c.attributes.sessionId)).keylineTint(.mint)
    }
  }
}

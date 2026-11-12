import SwiftUI

struct StatusBadge: View {
  let text: String
  let color: Color

  init(_ status: Assistant.Status) {
    self.init(text: status.label, color: status.color)
  }

  init(_ status: Link.Status) {
    switch status {
    case .online: self.init(Assistant.Status.online)
    case .idle: self.init(Assistant.Status.idle)
    case .offline: self.init(Assistant.Status.offline)
    case .notPaired: self.init(text: "Not paired", color: .orange)
    }
  }

  private init(text: String, color: Color) {
    self.text = text
    self.color = color
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text)
    }
    .accessibilityElement(children: .combine)
  }
}

extension Assistant.Status {
  var label: String {
    switch self {
    case .online: "Online"
    case .idle: "Idle"
    case .offline: "Offline"
    }
  }

  var color: Color {
    switch self {
    case .online: .green
    case .idle: .yellow
    case .offline: .gray
    }
  }
}

struct LastActiveText: View {
  let lastActive: LastActive

  var body: some View {
    switch lastActive {
    case .now:
      Text("Active now")
    case .never:
      Text("Never active")
    case .at(let date):
      TimelineView(.everyMinute) { context in
        Text(
          "Last active \(date.formatted(.relative(presentation: .named, unitsStyle: .abbreviated).locale(.current)))"
        )
      }
    }
  }
}

#Preview {
  List {
    StatusBadge(Assistant.Status.online)
    StatusBadge(Assistant.Status.idle)
    StatusBadge(Assistant.Status.offline)
    StatusBadge(Link.Status.notPaired)
    LastActiveText(lastActive: .now)
    LastActiveText(lastActive: .at(.now.addingTimeInterval(-7200)))
    LastActiveText(lastActive: .never)
  }
}

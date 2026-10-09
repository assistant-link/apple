import SwiftUI

struct StatusBadge: View {
  let text: String
  let color: Color

  init(_ status: Assistant.Status) {
    switch status {
    case .online: (text, color) = ("Online", .green)
    case .offline: (text, color) = ("Offline", .secondary)
    }
  }

  init(_ status: Link.Status) {
    switch status {
    case .online: (text, color) = ("Online", .green)
    case .offline: (text, color) = ("Offline", .secondary)
    case .notPaired: (text, color) = ("Not paired", .orange)
    }
  }

  var body: some View {
    HStack(spacing: 6) {
      Circle().fill(color).frame(width: 8, height: 8)
      Text(text)
    }
    .accessibilityElement(children: .combine)
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
    StatusBadge(Assistant.Status.offline)
    StatusBadge(Link.Status.notPaired)
    LastActiveText(lastActive: .now)
    LastActiveText(lastActive: .at(.now.addingTimeInterval(-7200)))
    LastActiveText(lastActive: .never)
  }
}

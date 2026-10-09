import SwiftUI

/// A preset avatar. The service stores only the id; until final assets exist each preset is
/// a filled circle in a system color, which adapts to light and dark mode.
struct Avatar: Equatable, Identifiable, Sendable {
  let id: String
  let name: String
  let color: Color

  static let presets: [Avatar] = [
    ("Red", Color.red), ("Orange", .orange), ("Yellow", .yellow), ("Green", .green),
    ("Teal", .teal), ("Blue", .blue), ("Indigo", .indigo), ("Purple", .purple),
    ("Gray", .gray), ("Brown", .brown),
  ].enumerated().map { index, preset in
    Avatar(id: "avatar-\(index + 1)", name: preset.0, color: preset.1)
  }

  static let `default` = presets[0]

  static let unknown = Avatar(id: "unknown", name: "Unknown", color: Color(.systemFill))

  init(id: String) {
    self = Self.presets.first { $0.id == id } ?? Self.unknown
  }

  private init(id: String, name: String, color: Color) {
    self.id = id
    self.name = name
    self.color = color
  }
}

struct AvatarView: View {
  let avatar: Avatar
  var size: CGFloat = 40
  var isOnline = false

  var body: some View {
    Circle()
      .fill(avatar.color)
      .frame(width: size, height: size)
      .overlay(alignment: .bottomTrailing) {
        if isOnline {
          Circle()
            .fill(.green)
            .frame(width: size * 0.3, height: size * 0.3)
            .overlay { Circle().strokeBorder(Color(.systemBackground), lineWidth: size * 0.05) }
            .offset(x: size * 0.02, y: size * 0.02)
        }
      }
      .accessibilityElement()
      .accessibilityLabel(isOnline ? "\(avatar.name) avatar, online" : "\(avatar.name) avatar")
  }
}

#Preview("All presets") {
  VStack(spacing: 32) {
    ForEach([ColorScheme.light, .dark], id: \.self) { scheme in
      LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
        ForEach(Avatar.presets) { avatar in
          VStack {
            AvatarView(avatar: avatar, size: 48)
            Text(avatar.id).font(.caption2)
          }
        }
      }
      .padding()
      .background(Color(.systemBackground))
      .environment(\.colorScheme, scheme)
    }
  }
}

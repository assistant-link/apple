import SwiftUI

/// An icon button drawn as a disc that takes taps on its whole area and dims while pressed.
struct CircleButtonStyle: ButtonStyle {
  var foreground: Color = .primary
  var background: Color = Color(.tertiarySystemFill)
  var diameter: CGFloat = 36

  @ScaledMetric private var scale = 1.0
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    let size = diameter * min(scale, 1.5)
    configuration.label
      .labelStyle(.iconOnly)
      .font(.body.weight(.semibold))
      // Keeps the glyph inside the disc, which stops scaling at 1.5.
      .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
      .foregroundStyle(foreground)
      .frame(width: size, height: size)
      .background(background, in: Circle())
      .contentShape(Circle())
      .opacity(isEnabled ? (configuration.isPressed ? 0.6 : 1) : 0.4)
  }
}

extension ButtonStyle where Self == CircleButtonStyle {
  static func circle(
    foreground: Color = .primary, background: Color = Color(.tertiarySystemFill),
    diameter: CGFloat = 36
  ) -> CircleButtonStyle {
    CircleButtonStyle(foreground: foreground, background: background, diameter: diameter)
  }
}

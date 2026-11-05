import SwiftUI

/// An icon button drawn as a disc that dims while pressed. Taps land on a square of at least 44 pt around
/// the disc, the HIG minimum, so a small disc does not need to grow.
struct CircleButtonStyle: ButtonStyle {
  var foreground: Color = .primary
  var background: Color = Color(.tertiarySystemFill)
  var diameter: CGFloat = 36

  private static let minimumHitSide: CGFloat = 44

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
      .frame(minWidth: Self.minimumHitSide, minHeight: Self.minimumHitSide)
      .contentShape(Rectangle())
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

import SwiftUI

extension View {
  /// Liquid Glass where the system has it, a material before iOS 26.
  @ViewBuilder
  func glassBackground<S: Shape>(in shape: S, tint: Color? = nil) -> some View {
    if #available(iOS 26.0, *) {
      glassEffect(.regular.tint(tint), in: shape)
    } else {
      background(.regularMaterial, in: shape).background(tint ?? .clear, in: shape)
    }
  }
}

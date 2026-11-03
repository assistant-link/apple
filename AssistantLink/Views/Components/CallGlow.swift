import SwiftUI

/// The red glow behind the status bar and navigation bar while a voice chat is on.
struct CallGlow: View {
  var body: some View {
    ZStack(alignment: .top) {
      RadialGradient(
        colors: [.red.opacity(0.35), .clear], center: .top, startRadius: 0, endRadius: 240)
      Capsule()
        .fill(.red.opacity(0.3))
        .frame(height: 56)
        .padding(.horizontal, 48)
        .padding(.top, 60)
        .blur(radius: 24)
    }
    .frame(height: 150)
    .frame(maxWidth: .infinity)
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }
}

#Preview("Call glow") {
  CallGlow().frame(maxHeight: .infinity, alignment: .top)
}

#Preview("Call glow, dark") {
  CallGlow().frame(maxHeight: .infinity, alignment: .top).preferredColorScheme(.dark)
}

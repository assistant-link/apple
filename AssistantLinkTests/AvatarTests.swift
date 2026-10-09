import SwiftUI
import Testing

@testable import AssistantLink

struct AvatarTests {
  @Test func thereAreTenPresets() {
    #expect(Avatar.presets.map(\.id) == (1...10).map { "avatar-\($0)" })
  }

  @Test(arguments: [ColorScheme.light, .dark])
  func presetColorsAreDistinct(scheme: ColorScheme) {
    var environment = EnvironmentValues()
    environment.colorScheme = scheme
    let colors = Avatar.presets.map { $0.color.resolve(in: environment) }
    for (index, color) in colors.enumerated() {
      for other in colors[(index + 1)...] {
        #expect(color.distance(to: other) > 0.2, "two presets look alike in \(scheme)")
      }
    }
  }

  @Test func oneOfThePresetsIsTheDefault() {
    #expect(Avatar.presets.contains(Avatar.default))
  }

  @Test func unknownIdsGetAFallback() {
    #expect(Avatar(id: "avatar-11") == Avatar.unknown)
    #expect(Avatar(id: "avatar-3") == Avatar.presets[2])
  }
}

extension Color.Resolved {
  fileprivate func distance(to other: Color.Resolved) -> Float {
    let dr = red - other.red
    let dg = green - other.green
    let db = blue - other.blue
    return (dr * dr + dg * dg + db * db).squareRoot()
  }
}

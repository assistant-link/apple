// swift-tools-version: 6.0
import PackageDescription

// Compiles the app's own model and service sources (symlinked into Sources/App) on Linux.
let package = Package(
  name: "VoiceE2E",
  targets: [
    .target(name: "OSLog", path: "Shims/OSLog"),
    .executableTarget(
      name: "VoiceE2E", dependencies: ["OSLog"], path: "Sources",
      // Swift 6.2's libswiftObservation.so on Linux references a libswiftCore symbol that
      // libswiftCore doesn't export, which the linker rejects. Only an error path uses it.
      linkerSettings: [.unsafeFlags(["-Xlinker", "--allow-shlib-undefined"])]),
  ])

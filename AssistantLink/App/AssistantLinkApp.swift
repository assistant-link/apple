import SwiftUI

@main
struct AssistantLinkApp: App {
  /// Unit tests run inside this app; without this check every test run would register an
  /// account with the production service.
  nonisolated static let isRunningUnitTests =
    ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

  @State private var model = AppModel.live()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup {
      if Self.isRunningUnitTests {
        Text("Running unit tests")
      } else {
        AssistantListView()
          .environment(model)
          .task { await model.start() }
          .task(
            id: LiveUpdatesTrigger(isForeground: scenePhase != .background, session: model.session)
          ) {
            if scenePhase != .background {
              await model.runLiveUpdates()
            }
          }
      }
    }
  }
}

/// The live connection stays open while the app is in the foreground, for the current account.
private struct LiveUpdatesTrigger: Equatable {
  let isForeground: Bool
  let session: Int
}

import Foundation
import Testing

@testable import AssistantLink

struct AssistantLinkTests {
  @Test func hostAppIsAssistantLink() {
    let displayName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
    #expect(displayName == "Assistant Link")
  }

  @Test func theHostAppKnowsItIsRunningUnitTests() {
    #expect(AssistantLinkApp.isRunningUnitTests)
  }
}

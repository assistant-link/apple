import Foundation
import Testing

@testable import AssistantLink

struct ServiceConfigurationTests {
  private func emptyDefaults() -> UserDefaults {
    UserDefaults(suiteName: "ServiceConfigurationTests.\(UUID().uuidString)")!
  }

  @Test func defaultsToProduction() {
    #expect(
      ServiceConfiguration.baseURL(defaults: emptyDefaults())
        == URL(string: "https://assistant-link.fly.dev")!)
  }

  @Test func debugBuildsAcceptAnOverride() {
    let defaults = emptyDefaults()
    defaults.set("http://localhost:4000", forKey: ServiceConfiguration.overrideKey)
    #expect(
      ServiceConfiguration.baseURL(defaults: defaults) == URL(string: "http://localhost:4000")!)
  }

  @Test func ignoresAnOverrideThatIsNotAnHTTPURL() {
    let defaults = emptyDefaults()
    defaults.set("localhost", forKey: ServiceConfiguration.overrideKey)
    #expect(ServiceConfiguration.baseURL(defaults: defaults) == ServiceConfiguration.production)
  }
}

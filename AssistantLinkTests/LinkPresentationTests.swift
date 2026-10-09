import Foundation
import Testing

@testable import AssistantLink

struct LinkPresentationTests {
  private let disconnected = Date(timeIntervalSince1970: 1_791_462_615)

  @Test func onlineLinksAreActiveNow() {
    let link = Link(id: "l-1", label: nil, status: .online, lastActiveAt: disconnected)
    #expect(LastActive(link) == .now)
  }

  @Test func offlineLinksShowWhenTheyWereLastActive() {
    let link = Link(id: "l-1", label: nil, status: .offline, lastActiveAt: disconnected)
    #expect(LastActive(link) == .at(disconnected))
  }

  @Test func linksNoAgentConnectedToWereNeverActive() {
    #expect(
      LastActive(Link(id: "l-1", label: nil, status: .notPaired, lastActiveAt: nil)) == .never)
    #expect(LastActive(Link(id: "l-1", label: nil, status: .offline, lastActiveAt: nil)) == .never)
  }

  @Test func unlabeledLinksAreNamedByPosition() {
    let links = [
      Link(id: "l-1", label: "laptop", status: .online, lastActiveAt: nil),
      Link(id: "l-2", label: nil, status: .notPaired, lastActiveAt: nil),
    ]
    #expect(links[0].displayName(position: 0) == "laptop")
    #expect(links[1].displayName(position: 1) == "Link 2")
  }
}

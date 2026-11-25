import Foundation
import Testing

@testable import AssistantLink

/// How each paired Link is woken, on Assistant Details. The app ships before the service sends
/// the wake fields, so a service without them shows no caption at all.
struct WakeRouteTests {
  private let address = "hermes@example.com"

  /// A paired Link with `fields` added to its JSON.
  private func decodeLink(_ fields: String = "", status: String = "online") throws -> Link {
    let json = [#""id": "l-1", "label": "laptop", "status": "\#(status)""#, fields]
      .filter { !$0.isEmpty }
      .joined(separator: ", ")
    return try APIClient.decoder.decode(Link.self, from: Data(json: "{\(json)}"))
  }

  private func caption(_ fields: String, status: String = "online") throws -> WakeCaption? {
    WakeCaption(try decodeLink(fields, status: status))
  }

  // MARK: Decoding

  @Test func aLinkFromAServiceWithoutWakeRoutesHasNoCaption() throws {
    let link = try decodeLink()

    #expect(link == Link(id: "l-1", label: "laptop", status: .online, lastActiveAt: nil))
    #expect(link.wake == nil)
    #expect(WakeCaption(link) == nil)
  }

  @Test func allWakeFieldsDecode() throws {
    let link = try decodeLink(
      #"""
      "webhook_installed": true,
      "wake_email": {"address": "hermes@example.com", "confirmed": true},
      "wake_route": "webhook"
      """#)

    #expect(
      link.wake
        == Wake(
          webhookInstalled: true, email: Wake.Email(address: address, confirmed: true),
          route: .webhook))
  }

  @Test func webhookInstalledDecodes() throws {
    #expect(try decodeLink(#""webhook_installed": true"#).wake?.webhookInstalled == true)
    #expect(try decodeLink(#""webhook_installed": false"#).wake?.webhookInstalled == false)
    #expect(try decodeLink(#""webhook_installed": null"#).wake?.webhookInstalled == false)
    #expect(try decodeLink(#""webhook_installed": "yes""#).wake?.webhookInstalled == false)
  }

  @Test func wakeEmailDecodesAsNoEmailWhenNullMissingOrMalformed() throws {
    let pending = try decodeLink(
      #""wake_email": {"address": "hermes@example.com", "confirmed": false}"#)
    #expect(pending.wake?.email == Wake.Email(address: address, confirmed: false))

    for fields in [
      #""wake_email": null"#,
      #""wake_route": null"#,
      #""wake_email": "hermes@example.com""#,
      #""wake_email": {"address": "hermes@example.com"}"#,
      #""wake_email": {"address": 7, "confirmed": true}"#,
      #""wake_email": {"address": "", "confirmed": true}"#,
      #""wake_email": []"#,
    ] {
      let link = try decodeLink(fields)
      #expect(link.wake != nil, "\(fields)")
      #expect(link.wake?.email == nil, "\(fields)")
      #expect(link.label == "laptop", "\(fields)")
    }
  }

  @Test func wakeRouteTellsMissingFromNull() throws {
    #expect(try decodeLink(#""wake_route": "webhook""#).wake?.route == .webhook)
    #expect(try decodeLink(#""wake_route": "email""#).wake?.route == .email)
    #expect(try decodeLink(#""wake_route": null"#).wake?.route == .noRoute)
    #expect(try decodeLink(#""webhook_installed": true"#).wake?.route == nil)
  }

  @Test func anUnknownOrMalformedWakeRouteIsNoRoute() throws {
    #expect(try decodeLink(#""wake_route": "carrier_pigeon""#).wake?.route == .noRoute)
    #expect(try decodeLink(#""wake_route": 1"#).wake?.route == .noRoute)
  }

  @Test func assistantsDecodeWithWakeFieldsOnSomeLinks() throws {
    let assistant = try APIClient.decoder.decode(
      Assistant.self,
      from: Data(
        json: #"""
          {"id": "as-1", "name": "Hermes", "avatar": "avatar-3", "status": "online",
           "links": [
             {"id": "l-1", "label": "laptop", "status": "online", "webhook_installed": true,
              "wake_email": {"confirmed": "maybe"}, "wake_route": "webhook"},
             {"id": "l-2", "label": "cloud", "status": "offline"}
           ]}
          """#))

    #expect(assistant.links.map(\.id) == ["l-1", "l-2"])
    #expect(assistant.links[0].wake == Wake(webhookInstalled: true, route: .webhook))
    #expect(assistant.links[1].wake == nil)
  }

  // MARK: Captions

  @Test func webhookOnly() throws {
    let caption = try caption(
      #""webhook_installed": true, "wake_email": null, "wake_route": "webhook""#)

    #expect(caption == .webhook(alsoEmail: nil))
    #expect(caption?.text == "Woken by webhook")
    #expect(caption?.note == nil)
    #expect(caption?.isMuted == false)
  }

  @Test func confirmedEmailOnly() throws {
    let caption = try caption(
      #"""
      "webhook_installed": false,
      "wake_email": {"address": "hermes@example.com", "confirmed": true},
      "wake_route": "email"
      """#)

    #expect(caption == .email(address))
    #expect(caption?.text == "Woken by email · hermes@example.com")
    #expect(caption?.note == nil)
    #expect(caption?.isMuted == false)
  }

  @Test func theWebhookWinsOverAnEmail() throws {
    for confirmed in [true, false] {
      let caption = try caption(
        #"""
        "webhook_installed": true,
        "wake_email": {"address": "hermes@example.com", "confirmed": \#(confirmed)},
        "wake_route": "webhook"
        """#)

      #expect(caption == .webhook(alsoEmail: address))
      #expect(caption?.text == "Woken by webhook")
      #expect(caption?.note == "Email also set · hermes@example.com")
      #expect(caption?.isMuted == false)
    }
  }

  @Test func aPendingEmailIsNotARoute() throws {
    let caption = try caption(
      #"""
      "webhook_installed": false,
      "wake_email": {
        "address": "hermes.assistant.wake@long-subdomain.example.com", "confirmed": false
      },
      "wake_route": null
      """#)

    #expect(caption == .pendingEmail("hermes.assistant.wake@long-subdomain.example.com"))
    // In full, however long: the row wraps it.
    #expect(
      caption?.text
        == "Wake email pending confirmation · hermes.assistant.wake@long-subdomain.example.com")
    #expect(caption?.note == nil)
    #expect(caption?.isMuted == false)
  }

  @Test func noWakeRoute() throws {
    let caption = try caption(
      #""webhook_installed": false, "wake_email": null, "wake_route": null"#)

    #expect(caption == .noRoute)
    #expect(caption?.text == "No wake route")
    #expect(caption?.note == nil)
    #expect(caption?.isMuted == true)
  }

  @Test func anUnknownRouteShowsWhatIsKnown() throws {
    #expect(try caption(#""wake_route": "carrier_pigeon""#) == .noRoute)
    #expect(
      try caption(
        #"""
        "wake_email": {"address": "hermes@example.com", "confirmed": false},
        "wake_route": "carrier_pigeon"
        """#) == .pendingEmail(address))
  }

  @Test func withoutARouteTheServiceRulesApply() throws {
    #expect(try caption(#""webhook_installed": true"#) == .webhook(alsoEmail: nil))
    #expect(
      try caption(
        #"""
        "webhook_installed": true,
        "wake_email": {"address": "hermes@example.com", "confirmed": true}
        """#) == .webhook(alsoEmail: address))
    #expect(
      try caption(#""wake_email": {"address": "hermes@example.com", "confirmed": true}"#)
        == .email(address))
    #expect(
      try caption(#""wake_email": {"address": "hermes@example.com", "confirmed": false}"#)
        == .pendingEmail(address))
    #expect(try caption(#""webhook_installed": false"#) == .noRoute)
  }

  @Test func anEmailRouteWithoutAnEmailIsNoRoute() throws {
    #expect(try caption(#""webhook_installed": false, "wake_route": "email""#) == .noRoute)
  }

  @Test func linksNotPairedHaveNoCaption() throws {
    #expect(
      try caption(
        #""webhook_installed": true, "wake_route": "webhook""#, status: "not_paired") == nil)
    #expect(try caption(#""wake_route": null"#, status: "not_paired") == nil)
  }

  @Test func otherStatusesHaveACaption() throws {
    for status in ["online", "idle", "offline", "hibernating"] {
      #expect(try caption(#""wake_route": null"#, status: status) == .noRoute, "\(status)")
    }
  }

  @Test func theWebhookItselfIsNeverShown() throws {
    let link = try decodeLink(
      #"""
      "webhook_installed": true, "webhook_url": "https://hooks.example.net/wake/T0KEN",
      "webhook_secret": "whsec_S3CRET",
      "wake_email": {"address": "hermes@example.com", "confirmed": true,
                     "url": "https://hooks.example.net/wake/T0KEN"},
      "wake_route": "webhook"
      """#)
    let caption = try #require(WakeCaption(link))
    let shown = [caption.text, caption.note ?? ""].joined(separator: "\n")

    for secret in ["hooks.example.net", "T0KEN", "whsec", "S3CRET", "https"] {
      #expect(!shown.contains(secret), "\(secret)")
      #expect(!String(describing: link).contains(secret), "\(secret)")
    }
  }

  @Test func theSamplesAreTheFiveStates() {
    let captions = Wake.samples.map {
      WakeCaption(Link(id: "l-1", label: "laptop", status: .online, lastActiveAt: nil, wake: $0))
    }

    #expect(
      captions == [
        .webhook(alsoEmail: nil), .email(address), .webhook(alsoEmail: address),
        .pendingEmail(address), .noRoute,
      ])
  }
}

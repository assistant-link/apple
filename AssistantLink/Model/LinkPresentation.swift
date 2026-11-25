import Foundation

enum LastActive: Equatable {
  case now
  case at(Date)
  case never

  init(_ link: Link) {
    if link.status == .online {
      self = .now
    } else if let date = link.lastActiveAt {
      self = .at(date)
    } else {
      self = .never
    }
  }
}

extension Link {
  /// `position` is the Link's index among its Assistant's Links, oldest first.
  func displayName(position: Int) -> String {
    label ?? "Link \(position + 1)"
  }
}

/// How a paired Link is woken, on Assistant Details. It names a webhook only as the route.
enum WakeCaption: Equatable {
  case webhook(alsoEmail: String?)
  case email(String)
  case pendingEmail(String)
  case noRoute

  /// `nil` for a Link not paired yet, and when the service doesn't say how its Links are woken.
  init?(_ link: Link) {
    guard link.status != .notPaired, let wake = link.wake else { return nil }
    // When the service doesn't send the route, its rules decide it: the webhook wins, and an
    // email wakes only once confirmed.
    let route: Wake.Route =
      wake.route
      ?? (wake.webhookInstalled ? .webhook : wake.email?.confirmed == true ? .email : .noRoute)
    switch (route, wake.email) {
    case (.webhook, let email): self = .webhook(alsoEmail: email?.address)
    case (.email, let email?): self = .email(email.address)
    case (_, let email?) where !email.confirmed: self = .pendingEmail(email.address)
    default: self = .noRoute
    }
  }

  var text: String {
    switch self {
    case .webhook: "Woken by webhook"
    case .email(let address): "Woken by email · \(address)"
    case .pendingEmail(let address): "Wake email pending confirmation · \(address)"
    case .noRoute: "No wake route"
    }
  }

  /// The email the webhook wins over, as a quieter second line.
  var note: String? {
    guard case .webhook(let address?) = self else { return nil }
    return "Email also set · \(address)"
  }

  /// Whether `text` is quiet like `note`, as it says nothing wakes the agent.
  var isMuted: Bool { self == .noRoute }
}

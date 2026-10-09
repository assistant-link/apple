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

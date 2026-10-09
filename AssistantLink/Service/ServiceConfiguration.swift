import Foundation

enum ServiceConfiguration {
  static let production = URL(string: "https://assistant-link.fly.dev")!

  /// Debug builds read this user default, so a launch argument such as
  /// `-serviceURL http://localhost:4000` points the app at a local service.
  static let overrideKey = "serviceURL"

  static func baseURL(defaults: UserDefaults = .standard) -> URL {
    #if DEBUG
      if let value = defaults.string(forKey: overrideKey),
        let url = URL(string: value),
        url.scheme == "http" || url.scheme == "https",
        url.host() != nil
      {
        return url
      }
    #endif
    return production
  }
}

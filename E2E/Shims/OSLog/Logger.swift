public enum OSLogPrivacy { case `public` }

public struct OSLogMessage: ExpressibleByStringInterpolation {
  public struct StringInterpolation: StringInterpolationProtocol {
    public init(literalCapacity: Int, interpolationCount: Int) {}
    public mutating func appendLiteral(_ literal: String) {}
    public mutating func appendInterpolation(_ value: some Any, privacy: OSLogPrivacy) {}
  }

  public init(stringLiteral value: String) {}
  public init(stringInterpolation: StringInterpolation) {}
}

public struct Logger: Sendable {
  public init(subsystem: String, category: String) {}
  public func notice(_ message: OSLogMessage) {}
}

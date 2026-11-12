import Foundation

// The service adds enum values, fields and items before installed apps know them, so the API
// models decode what they can instead of failing a whole screen.

/// An API enum that decodes a value this app doesn't know as `fallback`.
protocol ForwardCompatibleEnum: RawRepresentable<String>, Decodable {
  static var fallback: Self { get }
}

extension ForwardCompatibleEnum {
  init(from decoder: any Decoder) throws {
    self = try Self(rawValue: decoder.singleValueContainer().decode(String.self)) ?? .fallback
  }
}

/// A list that skips the elements this app can't decode and keeps the rest.
@propertyWrapper
struct LossyArray<Element: Decodable>: Decodable {
  var wrappedValue: [Element]

  init(wrappedValue: [Element]) {
    self.wrappedValue = wrappedValue
  }

  init(from decoder: any Decoder) throws {
    var container = try decoder.unkeyedContainer()
    var elements: [Element] = []
    while !container.isAtEnd {
      if let element = try? container.decode(Element.self) {
        elements.append(element)
      } else {
        // A failed decode stays on the same element.
        _ = try container.decode(Skipped.self)
      }
    }
    wrappedValue = elements
  }
}

extension LossyArray: Equatable where Element: Equatable {}
extension LossyArray: Sendable where Element: Sendable {}

/// An optional value that is `nil` when it is missing or this app can't decode it.
@propertyWrapper
struct LossyOptional<Value: Decodable>: Decodable {
  var wrappedValue: Value?

  init(wrappedValue: Value?) {
    self.wrappedValue = wrappedValue
  }

  init(from decoder: any Decoder) throws {
    wrappedValue = try? decoder.singleValueContainer().decode(Value.self)
  }
}

extension LossyOptional: Equatable where Value: Equatable {}
extension LossyOptional: Sendable where Value: Sendable {}

extension KeyedDecodingContainer {
  /// Synthesized decoding would otherwise require the key.
  func decode<Value>(_ type: LossyOptional<Value>.Type, forKey key: Key) -> LossyOptional<Value> {
    LossyOptional(wrappedValue: try? decodeIfPresent(Value.self, forKey: key))
  }
}

private struct Skipped: Decodable {
  init(from decoder: any Decoder) {}
}

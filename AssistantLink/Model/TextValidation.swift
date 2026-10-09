import Foundation

/// The service's rules for Assistant names, checked before sending.
enum TextValidation {
  enum Problem: Error, Equatable {
    case empty
    case tooLong
    case multiline

    var message: String {
      switch self {
      case .empty: "Enter a name."
      case .tooLong: "Use at most \(TextValidation.maxLength) characters."
      case .multiline: "Use a single line, without tabs or line breaks."
      }
    }
  }

  static let maxLength = 50

  static func name(_ raw: String) -> Result<String, Problem> {
    let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.isEmpty { return .failure(.empty) }
    if text.count > maxLength { return .failure(.tooLong) }
    let breaksLine = text.unicodeScalars.contains {
      switch $0.properties.generalCategory {
      case .control, .lineSeparator, .paragraphSeparator: true
      default: false
      }
    }
    return breaksLine ? .failure(.multiline) : .success(text)
  }
}

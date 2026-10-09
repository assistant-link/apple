import Testing

@testable import AssistantLink

struct TextValidationTests {
  @Test func namesAreTrimmed() {
    #expect(TextValidation.name("  Hermes \n") == .success("Hermes"))
  }

  @Test(arguments: ["", "   ", "\n\t "])
  func blankNamesAreRejected(name: String) {
    #expect(TextValidation.name(name) == .failure(.empty))
  }

  @Test func namesUpToFiftyCharactersAreAccepted() {
    let name = String(repeating: "a", count: 50)
    #expect(TextValidation.name(name) == .success(name))
  }

  @Test func namesOverFiftyCharactersAreRejected() {
    #expect(TextValidation.name(String(repeating: "a", count: 51)) == .failure(.tooLong))
  }

  @Test func emojiCountAsOneCharacter() {
    let name = String(repeating: "👩‍💻", count: 50)
    #expect(TextValidation.name(name) == .success(name))
  }

  @Test(arguments: ["Her\nmes", "Her\tmes", "Her\u{2028}mes", "Her\u{2029}mes", "Her\u{7}mes"])
  func namesMustBeASingleLine(name: String) {
    #expect(TextValidation.name(name) == .failure(.multiline))
  }
}

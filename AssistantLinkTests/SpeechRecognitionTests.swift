import Speech
import Testing

@testable import AssistantLink

struct SpeechLocaleTests {
  private static func anyEnglish(_ identifier: String) -> Bool { identifier.hasPrefix("en-") }

  @Test func aHebrewPhoneTranscribesUSEnglish() {
    #expect(
      SpeechLocale.english(preferredLanguages: ["he-IL"], isSupported: Self.anyEnglish) == "en-US")
  }

  @Test func thePreferredEnglishWins() {
    let languages = ["he-IL", "en-GB", "en-US"]
    #expect(
      SpeechLocale.english(preferredLanguages: languages, isSupported: Self.anyEnglish) == "en-GB")
  }

  @Test func anUnsupportedEnglishFallsBackToTheNextOne() {
    let languages = ["en-IL", "en-AU"]
    let supported: (String) -> Bool = { $0 == "en-AU" || $0 == "en-US" }
    #expect(SpeechLocale.english(preferredLanguages: languages, isSupported: supported) == "en-AU")
  }

  @Test func englishWithoutARegionIsUSEnglish() {
    #expect(
      SpeechLocale.english(preferredLanguages: ["en"], isSupported: Self.anyEnglish) == "en-US")
  }

  @Test func underscoresAreRead() {
    #expect(
      SpeechLocale.english(preferredLanguages: ["en_GB"], isSupported: Self.anyEnglish) == "en-GB")
  }
}

struct RecognizerSessionTests {
  @Test func theRecognizerMayUseTheServer() {
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.requiresOnDeviceRecognition = true
    RecognizerSession.configure(request, vocabulary: ["Grok"])
    #expect(!request.requiresOnDeviceRecognition)
    #expect(request.shouldReportPartialResults)
    #expect(request.addsPunctuation)
    #expect(request.contextualStrings == ["Grok"])
  }
}

struct TranscriptionTextTests {
  @Test func aVolatileResultFollowsTheFinalizedOnes() {
    var text = TranscriptionText()
    text.add("hello", isFinal: false)
    #expect(text.text == "hello")
    text.add("Hello there.", isFinal: true)
    #expect(text.text == "Hello there.")
    text.add(" how", isFinal: false)
    #expect(text.text == "Hello there. how")
  }

  @Test func theNextResultReplacesTheVolatileOne() {
    var text = TranscriptionText()
    text.add("Hello there.", isFinal: true)
    text.add("how", isFinal: false)
    text.add("how are", isFinal: false)
    text.add(" How are you?", isFinal: true)
    #expect(text.text == "Hello there. How are you?")
  }

  @Test func aVolatileResultThatIsNeverFinalizedIsKept() {
    var text = TranscriptionText()
    text.add("Hello there.", isFinal: true)
    text.add("how are you", isFinal: false)
    #expect(text.text == "Hello there. how are you")
  }
}

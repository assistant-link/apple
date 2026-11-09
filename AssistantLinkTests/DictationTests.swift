import Testing

@testable import AssistantLink

@MainActor
private final class FakeListener: SpeechListener {
  var vocabulary: [String] = []
  var startError: (any Error)?
  private(set) var starts = 0
  private(set) var stops = 0
  private var handler: (@MainActor (SpeechEvent) -> Void)?

  func start(_ handler: @escaping @MainActor (SpeechEvent) -> Void) throws {
    if let startError { throw startError }
    starts += 1
    self.handler = handler
  }

  func stop() {
    stops += 1
    handler = nil
  }

  func hear(_ event: SpeechEvent) { handler?(event) }
}

@MainActor
private final class FakeAudio: VoiceAudio {
  var isAllowed = true
  private(set) var isActive = false

  func requestPermission() async -> Bool { isAllowed }
  func activate() throws { isActive = true }
  func observeRouteChanges(_ handler: @escaping @MainActor () -> Void) {}
  func deactivate() { isActive = false }
}

@MainActor
private func makeDictation() -> (Dictation, FakeListener, FakeAudio) {
  let listener = FakeListener()
  let audio = FakeAudio()
  return (Dictation(listener: listener, audio: audio), listener, audio)
}

@MainActor
struct DictationTests {
  @Test func startsIdle() {
    let (dictation, _, _) = makeDictation()
    #expect(dictation.phase == .idle)
    #expect(dictation.text.isEmpty)
  }

  @Test func recordsAfterPermissionAndHintsTheAssistantsName() async {
    let (dictation, listener, audio) = makeDictation()
    await dictation.start(assistantName: "Hermes")
    #expect(dictation.phase == .recording)
    #expect(audio.isActive)
    #expect(listener.vocabulary.first == "Hermes")
  }

  @Test func permissionDeniedFailsWithoutRecording() async {
    let (dictation, listener, audio) = makeDictation()
    audio.isAllowed = false
    await dictation.start()
    #expect(dictation.phase == .idle)
    #expect(dictation.failure == .permissionDenied)
    #expect(listener.starts == 0)
  }

  @Test func recognizerFailingToStartIsUnavailable() async {
    let (dictation, listener, audio) = makeDictation()
    listener.startError = SpeechListenerError.recognizerUnavailable
    await dictation.start()
    #expect(dictation.phase == .idle)
    #expect(dictation.failure == .unavailable)
    #expect(!audio.isActive)
  }

  @Test func aNewStartClearsTheFailure() async {
    let (dictation, _, audio) = makeDictation()
    audio.isAllowed = false
    await dictation.start()
    audio.isAllowed = true
    await dictation.start()
    #expect(dictation.failure == nil)
    #expect(dictation.phase == .recording)
  }

  @Test func partialWordsAreProvisionalUntilFinal() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("Call David"))
    #expect(dictation.confirmed.isEmpty)
    #expect(dictation.provisional == "Call David")
    listener.hear(.final("Call David at nine"))
    #expect(dictation.confirmed == "Call David at nine")
    #expect(dictation.provisional.isEmpty)
    listener.hear(.partial("and"))
    #expect(dictation.text == "Call David at nine and")
  }

  @Test func dictationContinuesAfterTheTextAlreadyInTheField() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start(after: "Hello ")
    listener.hear(.final("there"))
    #expect(dictation.text == "Hello there")
  }

  @Test func levelsKeepTheNewest() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    for index in 0..<(Dictation.maxLevels + 5) {
      listener.hear(.level(Float(index)))
    }
    #expect(dictation.levels.count == Dictation.maxLevels)
    #expect(dictation.levels.last == Float(Dictation.maxLevels + 4))
  }

  @Test func stopKeepsTheWordsIncludingProvisionalOnes() async {
    let (dictation, listener, audio) = makeDictation()
    await dictation.start()
    listener.hear(.final("Call David"))
    listener.hear(.partial("at nine"))
    dictation.stop()
    #expect(dictation.phase == .editing)
    #expect(dictation.confirmed == "Call David at nine")
    #expect(listener.stops == 1)
    #expect(!audio.isActive)
    #expect(dictation.take() == "Call David at nine")
    #expect(dictation.phase == .idle)
    #expect(dictation.text.isEmpty)
  }

  @Test func sendWhileRecordingStopsAndReturnsEverything() async {
    let (dictation, listener, audio) = makeDictation()
    await dictation.start()
    listener.hear(.final("Call David"))
    listener.hear(.partial("at nine"))
    #expect(dictation.send() == "Call David at nine")
    #expect(dictation.phase == .idle)
    #expect(listener.stops == 1)
    #expect(!audio.isActive)
  }

  @Test func wordsHeardAfterStopAreIgnored() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.final("Hello"))
    dictation.stop()
    listener.hear(.final("late"))
    #expect(dictation.text == "Hello")
  }

  @Test func silenceRestartsTheRecognizerAndKeepsTheWords() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("Hello"))
    listener.hear(.stopped)
    #expect(dictation.phase == .recording)
    #expect(listener.starts == 2)
    #expect(dictation.confirmed == "Hello")
  }

  @Test func aRecognizerFailureStopsAndKeepsTheWords() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.final("Hello"))
    listener.hear(.failed)
    #expect(dictation.phase == .editing)
    #expect(dictation.take() == "Hello")
  }

  @Test func cancelDropsTheWords() async {
    let (dictation, listener, audio) = makeDictation()
    await dictation.start()
    listener.hear(.final("Hello"))
    dictation.cancel()
    #expect(dictation.phase == .idle)
    #expect(dictation.text.isEmpty)
    #expect(!audio.isActive)
  }
}

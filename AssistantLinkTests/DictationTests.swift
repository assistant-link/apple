import Testing

@testable import AssistantLink

@MainActor
private func makeDictation() -> (Dictation, FakeDictationListener, FakeDictationAudio) {
  let listener = FakeDictationListener()
  let audio = FakeDictationAudio()
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

  @Test func aNewSegmentWithoutAFinalResultKeepsTheEarlierWords() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("So I"))
    listener.hear(.partial("So I recorded the first word"))
    listener.hear(.partial("Or"))
    #expect(dictation.confirmed == "So I recorded the first word")
    listener.hear(.partial("Or a sentence"))
    listener.hear(.partial("In the first goes away"))
    #expect(dictation.confirmed == "So I recorded the first word Or a sentence")
    #expect(dictation.provisional == "In the first goes away")
    #expect(dictation.send() == "So I recorded the first word Or a sentence In the first goes away")
  }

  @Test func aRevisionOfTheSameSegmentIsNotKept() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("call David at"))
    listener.hear(.partial("Call David at nine"))
    #expect(dictation.confirmed.isEmpty)
    #expect(dictation.text == "Call David at nine")
  }

  @Test func punctuationAddedToTheFirstWordIsARevision() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("hello there"))
    listener.hear(.partial("Hello, there friend"))
    #expect(dictation.confirmed.isEmpty)
    #expect(dictation.text == "Hello, there friend")
  }

  @Test func aNewSegmentKeepsAOneWordFirstUtterance() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("Hello"))
    listener.hear(.partial("there everyone"))
    #expect(dictation.confirmed == "Hello")
    #expect(dictation.send() == "Hello there everyone")
  }

  @Test func aOneWordRevisionIsNotANewSegment() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("two"))
    listener.hear(.partial("to"))
    #expect(dictation.confirmed.isEmpty)
    #expect(dictation.text == "to")
  }

  @Test func aRewrittenFirstWordIsARevisionNotANewSegment() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.final("Call David"))
    listener.hear(.partial("two friends"))
    listener.hear(.partial("to friends later"))
    #expect(dictation.confirmed == "Call David")
    #expect(dictation.send() == "Call David to friends later")
  }

  @Test func aFinalResultThenNewPartialsAccumulate() async {
    let (dictation, listener, _) = makeDictation()
    await dictation.start()
    listener.hear(.partial("Hello there"))
    listener.hear(.final("Hello there"))
    listener.hear(.partial("General Kenobi"))
    #expect(dictation.confirmed == "Hello there")
    #expect(dictation.text == "Hello there General Kenobi")
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

  @Test func cancelWhileIdleLeavesTheAudioSessionAlone() {
    let (dictation, listener, audio) = makeDictation()
    try? audio.activate()
    dictation.cancel()
    #expect(audio.isActive)
    #expect(listener.stops == 0)
  }

  @Test func stopWhilePreparingCancelsTheStartAndKeepsTheText() async {
    let (dictation, listener, audio) = makeDictation()
    audio.holdsPermission = true
    let starting = Task { await dictation.start(after: "Call David") }
    while dictation.phase != .preparing { await Task.yield() }
    dictation.stop()
    #expect(dictation.phase == .editing)
    audio.answer(true)
    await starting.value
    #expect(dictation.phase == .editing)
    #expect(dictation.failure == nil)
    #expect(listener.starts == 0)
    #expect(!audio.isActive)
    #expect(dictation.take() == "Call David")
    #expect(dictation.phase == .idle)
  }

  @Test func stopWhilePreparingIgnoresADeniedPermission() async {
    let (dictation, _, audio) = makeDictation()
    audio.holdsPermission = true
    let starting = Task { await dictation.start() }
    while dictation.phase != .preparing { await Task.yield() }
    dictation.stop()
    audio.answer(false)
    await starting.value
    #expect(dictation.failure == nil)
  }

  @Test func anAnswerToAStoppedStartDoesNotTakeOverTheNextStart() async {
    let (dictation, listener, audio) = makeDictation()
    audio.holdsPermission = true
    let first = Task { await dictation.start() }
    while dictation.phase != .preparing { await Task.yield() }
    dictation.stop()
    _ = dictation.take()
    let second = Task { await dictation.start() }
    while dictation.phase != .preparing { await Task.yield() }
    audio.answer(true)
    await first.value
    #expect(dictation.phase == .preparing)
    #expect(listener.starts == 0)
    audio.answer(true)
    await second.value
    #expect(dictation.phase == .recording)
    #expect(listener.starts == 1)
  }
}

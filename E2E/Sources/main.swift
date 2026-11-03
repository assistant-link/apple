import Foundation

// Plays the app on a call with an Assistant that the environment has already set up.
// Exits non-zero unless every check passes.

let env = ProcessInfo.processInfo.environment
let assistantID = env["E2E_ASSISTANT_ID"]!
let api = APIClient(baseURL: URL(string: env["SERVER"]!)!, credential: env["E2E_CREDENTIAL"]!)
let script = [
  "Hello, this is a test of the voice call.",
  "What is the weather like today?",
  "Thank you, goodbye.",
]

func transcribe(_ lines: [String]) throws -> [String] {
  let process = Process()
  process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  process.arguments = ["python3", env["E2E_DIR"]! + "/speech.py"] + lines
  let output = Pipe()
  process.standardOutput = output
  try process.run()
  let data = output.fileHandleForReading.readDataToEndOfFile()
  process.waitUntilExit()
  return try JSONDecoder().decode([String].self, from: data)
}

func until(_ seconds: Int, _ condition: () -> Bool) async -> Bool {
  let deadline = ContinuousClock.now + .seconds(seconds)
  while !condition() {
    if ContinuousClock.now > deadline { return false }
    try? await Task.sleep(for: .milliseconds(10))
  }
  return true
}

func ms(_ duration: Duration) -> Int {
  Int(duration.components.seconds * 1000 + duration.components.attoseconds / 1_000_000_000_000_000)
}

var failures: [String] = []

@MainActor func check(_ condition: Bool, _ what: String) {
  if !condition { failures.append(what) }
}

let heard = try transcribe(script)
let listener = FakeListener()
let speaker = FakeSpeaker()
let model = AppModel(
  connect: { api },
  voiceCall: VoiceCall(listener: listener, speaker: speaker, audio: FakeAudio()))
await model.start()
try await model.openConversation(assistantID: assistantID)
let live = Task { await model.runLiveUpdates() }
let call = model.voiceCall

@MainActor func timeline() -> Timeline { model.timelines[assistantID] ?? Timeline() }

let callStart = ContinuousClock.now
check(await model.startVoiceCall(assistantID: assistantID), "the call started")
check(call.state == .connecting, "the call waits for the Assistant")
check(await until(60) { call.state == .listening }, "the Assistant came online")
print("Online \(ms(.now - callStart)) ms after the call started")

var rows: [(received: Int, spoken: Int)] = []
for (index, text) in heard.enumerated() {
  check(await until(10) { listener.isListening }, "listening for line \(index + 1)")
  await listener.hear(text)
  let isSent = {
    timeline().outgoing.contains { $0.text == text }
      || timeline().events.contains { $0.sender == .user && $0.text == text }
  }
  check(await until(10, isSent), "utterance \(index + 1) was sent after the silence")
  let sentAt = ContinuousClock.now
  func replies() -> [Event] {
    timeline().events.filter { $0.sender == .assistant && $0.type == .textMessage }
  }
  let replied = await until(30) { replies().count > index && speaker.spoken.count > index }
  check(replied, "reply \(index + 1) arrived and was spoken")
  guard replied else { break }
  rows.append((ms(.now - sentAt), ms(speaker.spoken[index].at - sentAt)))
}

model.endVoiceCall()
await model.callEvents?.value
live.cancel()

let events = try await api.events(assistantID: assistantID, limit: 50).events
let mine = events.filter { $0.sender == .user && $0.type == .textMessage }
let replies = events.filter { $0.sender == .assistant && $0.type == .textMessage }
let order = events.map(\.type)
check(order.first(where: { $0 != .linkCreated }) == .callStarted, "call_started comes first")
check(order.last == .callEnded, "call_ended is the last event")
check(order.filter { $0 == .callStarted }.count == 1, "one call_started")
check(order.filter { $0 == .callEnded }.count == 1, "one call_ended")
check(mine.map(\.text) == heard, "the utterances were stored as heard")
check(mine.allSatisfy { $0.via == .voice }, "every utterance was stored with via voice")
check(speaker.spoken.map(\.text) == replies.map(\.text), "the replies were spoken in order")
check(replies.count == script.count, "one reply per utterance")

for (index, row) in rows.enumerated() {
  print("Line \(index + 1)")
  print("  said:        \(script[index])")
  print("  transcribed: \(heard[index])")
  print("  reply:       \(speaker.spoken[index].text)")
  print("  latency:     reply received \(row.received) ms, speech started \(row.spoken) ms")
}
for failure in failures { print("FAIL: \(failure)") }
exit(failures.isEmpty ? 0 : 1)

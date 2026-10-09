import Foundation
import Synchronization
import Testing

@testable import AssistantLink

struct BackoffTests {
  @Test func doublesFromTheBaseUpToTheCap() {
    var backoff = Backoff(jitter: { 1 })

    let delays = (0..<7).map { _ in backoff.next() }

    #expect(delays == [1, 2, 4, 8, 16, 30, 30].map { Duration.seconds($0) })
  }

  @Test func jitterTakesUpToHalfOff() {
    var low = Backoff(jitter: { 0.5 })
    var high = Backoff(jitter: { 1 })

    _ = (low.next(), high.next())

    #expect(low.next() == .seconds(1))
    #expect(high.next() == .seconds(2))
  }

  @Test func resetStartsFromTheBaseAgain() {
    var backoff = Backoff(jitter: { 1 })
    _ = (backoff.next(), backoff.next(), backoff.next())

    backoff.reset()

    #expect(backoff.next() == .seconds(1))
  }
}

/// Plays one scripted connection per attempt and records the delays between attempts. The
/// clock moves only when a script says so, or by each delay.
private final class Script: Sendable {
  enum Step: Sendable {
    case open
    case message(String)
    case wait(Duration)
  }

  enum End: Sendable {
    case closed
    case failed(LiveConnectionError)
  }

  struct Attempt: Sendable {
    var steps: [Step]
    var end: End
  }

  private let attempts: Mutex<[Attempt]>
  private let clock = Mutex(Duration.zero)
  private let recordedDelays = Mutex<[Duration]>([])

  init(_ attempts: [Attempt]) { self.attempts = Mutex(attempts) }

  var delays: [Duration] { recordedDelays.withLock { $0 } }
  var remainingAttempts: Int { attempts.withLock { $0.count } }

  func liveUpdates() -> LiveUpdates {
    LiveUpdates(
      connect: { self.connect() },
      sleep: { delay in
        self.recordedDelays.withLock { $0.append(delay) }
        self.clock.withLock { $0 += delay }
      },
      uptime: { self.clock.withLock { $0 } },
      backoff: Backoff(jitter: { 1 }))
  }

  /// Steps run as the stream is read, so a `.wait` moves the clock after the events before it.
  private func connect() -> AsyncThrowingStream<LiveEvent, any Error> {
    guard let attempt = attempts.withLock({ $0.isEmpty ? nil : $0.removeFirst() }) else {
      Issue.record("connected more often than scripted")
      return AsyncThrowingStream { $0.finish(throwing: LiveConnectionError.rejected(status: 400)) }
    }
    let steps = Steps(attempt.steps)
    return AsyncThrowingStream {
      while let step = steps.next() {
        switch step {
        case .open: return .opened
        case .message(let text): return .message(text)
        case .wait(let duration): self.clock.withLock { $0 += duration }
        }
      }
      switch attempt.end {
      case .closed: return nil
      case .failed(let error): throw error
      }
    }
  }

  private final class Steps: Sendable {
    private let remaining: Mutex<[Step]>

    init(_ steps: [Step]) { remaining = Mutex(steps) }

    func next() -> Step? { remaining.withLock { $0.isEmpty ? nil : $0.removeFirst() } }
  }
}

private func linkStatus(_ linkID: String, _ status: String) -> String {
  #"{"jsonrpc": "2.0", "method": "link.status", "params": {"link_id": "\#(linkID)", "status": "\#(status)", "last_active_at": null}}"#
}

private let accountDeleted =
  #"{"jsonrpc": "2.0", "method": "connection.closing", "params": {"reason": "account_deleted"}}"#

@MainActor
struct LiveUpdatesTests {
  @Test func appliesLinkStatusAfterEachOpen() async {
    let script = Script([
      .init(steps: [.open, .message(linkStatus("l-1", "online"))], end: .closed),
      .init(
        steps: [.open, .message(linkStatus("l-1", "offline")), .message(accountDeleted)],
        end: .closed),
    ])
    var log: [String] = []

    let stop = await script.liveUpdates().run(
      onOpen: { log.append("open") },
      onLinkStatus: { log.append("\($0.linkID) \($0.status)") })

    #expect(stop == .accountDeleted)
    #expect(log == ["open", "l-1 online", "open", "l-1 offline"])
  }

  @Test func reconnectsWithBackoffAfterFailuresAndDrops() async {
    let script = Script([
      .init(steps: [], end: .failed(.lost)),
      .init(steps: [], end: .failed(.rejected(status: 503))),
      .init(steps: [.open], end: .failed(.lost)),
      .init(steps: [.open], end: .closed),
      .init(steps: [.open, .message(accountDeleted)], end: .closed),
    ])

    let stop = await script.liveUpdates().run(onOpen: {}, onLinkStatus: { _ in })

    #expect(stop == .accountDeleted)
    #expect(script.delays == [1, 2, 4, 8].map { Duration.seconds($0) })
  }

  @Test func resetsTheBackoffAfterAConnectionStaysUpForAMinute() async {
    let script = Script([
      .init(steps: [], end: .failed(.lost)),
      .init(steps: [], end: .failed(.lost)),
      .init(steps: [.open, .wait(.seconds(60))], end: .failed(.lost)),
      .init(steps: [.open, .wait(.seconds(59))], end: .failed(.lost)),
      .init(steps: [.open, .message(accountDeleted)], end: .closed),
    ])

    _ = await script.liveUpdates().run(onOpen: {}, onLinkStatus: { _ in })

    #expect(script.delays == [1, 2, 1, 2].map { Duration.seconds($0) })
  }

  @Test func stopsWhenTheCredentialIsRejected() async {
    let script = Script([
      .init(steps: [], end: .failed(.rejected(status: 401))),
      .init(steps: [.open], end: .closed),
    ])

    let stop = await script.liveUpdates().run(onOpen: {}, onLinkStatus: { _ in })

    #expect(stop == .rejected(status: 401))
    #expect(script.delays.isEmpty)
    #expect(script.remainingAttempts == 1)
  }

  @Test func stopsOnOtherClientErrors() async {
    let script = Script([.init(steps: [], end: .failed(.rejected(status: 404)))])

    let stop = await script.liveUpdates().run(onOpen: {}, onLinkStatus: { _ in })

    #expect(stop == .rejected(status: 404))
  }

  @Test func reconnectsAfterClosingForAnotherReason() async {
    let shutdown =
      #"{"jsonrpc": "2.0", "method": "connection.closing", "params": {"reason": "shutdown"}}"#
    let script = Script([
      .init(steps: [.open, .message(shutdown)], end: .closed),
      .init(steps: [.open, .message(accountDeleted)], end: .closed),
    ])

    let stop = await script.liveUpdates().run(onOpen: {}, onLinkStatus: { _ in })

    #expect(stop == .accountDeleted)
    #expect(script.delays == [.seconds(1)])
  }

  @Test func returnsNilWhenCancelled() async {
    let updates = LiveUpdates(
      connect: { AsyncThrowingStream { $0.finish(throwing: LiveConnectionError.lost) } },
      sleep: { try await Task.sleep(for: $0) },
      uptime: { .zero },
      backoff: Backoff(jitter: { 1 }))

    let task = Task { await updates.run(onOpen: {}, onLinkStatus: { _ in }) }
    task.cancel()

    #expect(await task.value == nil)
  }
}

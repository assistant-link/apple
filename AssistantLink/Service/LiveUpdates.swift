import Foundation

enum LiveEvent: Equatable, Sendable {
  /// The service is answering on the connection, so it sends every later status change.
  case opened
  case message(String)
}

enum LiveConnectionError: Error, Equatable {
  /// The service refused the WebSocket upgrade with this HTTP status.
  case rejected(status: Int)
  case lost
}

/// Reconnect delays like `al wait`'s: doubling from 1 s up to 30 s, each with up to half
/// taken off at random.
struct Backoff {
  private static let base = Duration.seconds(1)
  private static let cap = Duration.seconds(30)

  private let jitter: @Sendable () -> Double
  private var failures = 0

  init(jitter: @escaping @Sendable () -> Double = { .random(in: 0.5...1) }) {
    self.jitter = jitter
  }

  mutating func next() -> Duration {
    let ceiling = min(Self.base * (1 << min(failures, 5)), Self.cap)
    failures += 1
    return ceiling * jitter()
  }

  mutating func reset() {
    failures = 0
  }
}

/// Keeps the app's live connection open, reconnecting with backoff whenever it drops.
@MainActor
struct LiveUpdates {
  enum Stop: Equatable {
    case accountDeleted
    case rejected(status: Int)
  }

  private static let stableUptime = Duration.seconds(60)

  let connect: @Sendable () -> AsyncThrowingStream<LiveEvent, any Error>
  let sleep: @Sendable (Duration) async throws -> Void
  let uptime: @Sendable () -> Duration
  let backoff: Backoff

  /// Returns why it stopped reconnecting, or `nil` when cancelled. A rejected upgrade (4xx)
  /// stops it, because retrying with the same credential can't succeed.
  func run(onOpen: () async -> Void, onLinkStatus: (LinkStatusChange) -> Void) async -> Stop? {
    var backoff = backoff
    while !Task.isCancelled {
      var openedAt: Duration?
      do {
        for try await event in connect() {
          switch event {
          case .opened:
            openedAt = uptime()
            await onOpen()
          case .message(let text):
            switch LiveMessage(text: text) {
            case .linkStatus(let change): onLinkStatus(change)
            case .closing(reason: "account_deleted"): return .accountDeleted
            case .closing, .ignored: break
            }
          }
        }
      } catch LiveConnectionError.rejected(let status) where (400..<500).contains(status) {
        return .rejected(status: status)
      } catch {}

      if let openedAt, uptime() - openedAt >= Self.stableUptime {
        backoff.reset()
      }
      do {
        try await sleep(backoff.next())
      } catch {
        return nil
      }
    }
    return nil
  }
}

extension LiveUpdates {
  static func live(_ api: APIClient) -> LiveUpdates? {
    guard let request = api.liveConnectionRequest() else { return nil }
    let origin = ContinuousClock.now
    return LiveUpdates(
      connect: { WebSocketConnection.open(request) },
      sleep: { try await Task.sleep(for: $0) },
      uptime: { ContinuousClock.now - origin },
      backoff: Backoff())
  }
}

import Foundation
import Synchronization

/// One WebSocket to the live connection. The stream ends when the connection does; cancelling
/// the iteration closes it.
enum WebSocketConnection {
  /// Matches the service's ping interval. A ping still unanswered after one interval means the
  /// connection is gone even though no error arrived, as on a half-open TCP connection after a
  /// network change.
  static let pingInterval = Duration.seconds(25)

  static func open(_ request: URLRequest) -> AsyncThrowingStream<LiveEvent, any Error> {
    AsyncThrowingStream { continuation in
      let session = URLSession(configuration: .default)
      let task = session.webSocketTask(with: request)
      let receiving = Task {
        do {
          while true {
            if case .string(let text) = try await task.receive() {
              continuation.yield(.message(text))
            }
          }
        } catch {
          continuation.finish(throwing: failure(of: task))
        }
      }
      let pinging = Task { await keepAlive(task, continuation: continuation) }
      continuation.onTermination = { _ in
        receiving.cancel()
        pinging.cancel()
        task.cancel(with: .goingAway, reason: nil)
        session.finishTasksAndInvalidate()
      }
      task.resume()
    }
  }

  /// The first pong reports `.opened`: the service answers pings only after it has set up the
  /// connection and subscribed it to the account's status changes.
  private static func keepAlive(
    _ task: URLSessionWebSocketTask,
    continuation: AsyncThrowingStream<LiveEvent, any Error>.Continuation
  ) async {
    let pongs = Pongs()
    while !Task.isCancelled {
      guard pongs.sendPing() else {
        task.cancel(with: .goingAway, reason: nil)
        return
      }
      task.sendPing { error in
        if error == nil, pongs.receivePong() {
          continuation.yield(.opened)
        }
      }
      try? await Task.sleep(for: pingInterval)
    }
  }

  private static func failure(of task: URLSessionWebSocketTask) -> LiveConnectionError {
    if let response = task.response as? HTTPURLResponse, response.statusCode != 101 {
      return .rejected(status: response.statusCode)
    }
    return .lost
  }
}

private final class Pongs: Sendable {
  private let state = Mutex((awaiting: false, received: 0))

  /// Returns `false` while the previous ping is still unanswered.
  func sendPing() -> Bool {
    state.withLock { state in
      guard !state.awaiting else { return false }
      state.awaiting = true
      return true
    }
  }

  /// Returns `true` for the first pong only.
  func receivePong() -> Bool {
    state.withLock { state in
      state.awaiting = false
      state.received += 1
      return state.received == 1
    }
  }
}

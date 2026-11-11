import Foundation
import Synchronization
import Testing

@testable import AssistantLink

@MainActor
struct KokoroSelectionTests {
  @Test func englishUsesTheNeuralVoiceOnEveryIOSVersion() {
    #expect(LiveSpeechSpeaker.usesKokoro(language: .english))
  }

  @Test func otherLanguagesKeepTheSystemVoice() {
    #expect(!LiveSpeechSpeaker.usesKokoro(language: .french))
    #expect(!LiveSpeechSpeaker.usesKokoro(language: nil))
  }

  @Test func theModelRunsOnTheCPUOnly() {
    #expect(KokoroSynthesizer.provider == "cpu")
  }
}

struct KokoroModelStoreTests {
  private static let files = [
    KokoroModelStore.File(name: "model.onnx", size: 5),
    KokoroModelStore.File(name: "tokens.txt", size: 3),
  ]

  private final class Requests: Sendable {
    private let names = Mutex<[String]>([])

    var sorted: [String] { names.withLock { $0.sorted() } }

    func add(_ name: String) { names.withLock { $0.append(name) } }
  }

  private func store(
    root: URL, requests: Requests = Requests(), status: Int = 200
  ) -> KokoroModelStore {
    let session = StubURLProtocol.session { request, _ in
      let name = request.url!.lastPathComponent
      requests.add(name)
      let size = Self.files.first { $0.name == name }?.size ?? 0
      return (status, Data(repeating: 1, count: size))
    }
    return KokoroModelStore(root: root, session: session, files: Self.files)
  }

  private func temporaryRoot() -> URL {
    FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
  }

  @Test func theFilesAreDownloadedIntoOneFolder() async throws {
    let root = temporaryRoot()
    let requests = Requests()

    let folder = try await store(root: root, requests: requests).prepare()

    #expect(requests.sorted == ["model.onnx", "tokens.txt"])
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "model.onnx").path))
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: "tokens.txt").path))
  }

  @Test func aDownloadedModelIsNotDownloadedAgain() async throws {
    let root = temporaryRoot()
    _ = try await store(root: root).prepare()
    let requests = Requests()

    _ = try await store(root: root, requests: requests).prepare()

    #expect(requests.sorted.isEmpty)
  }

  @Test func aFailedDownloadLeavesNoModelBehind() async throws {
    let root = temporaryRoot()

    await #expect(throws: (any Error).self) {
      try await store(root: root, status: 500).prepare()
    }

    let retried = try await store(root: root).prepare()
    #expect(FileManager.default.fileExists(atPath: retried.appending(path: "tokens.txt").path))
  }

  @Test func aFileOfTheWrongSizeIsRejected() async {
    let session = StubURLProtocol.session { _, _ in (200, Data(count: 1)) }
    let store = KokoroModelStore(root: temporaryRoot(), session: session, files: Self.files)

    await #expect(throws: (any Error).self) { try await store.prepare() }
  }
}

import AVFoundation
import WebRTC

enum WebRTCRelayError: Error {
  case noConnection
  case noOffer
}

/// The call's audio over WebRTC to the service, over UDP only and without TURN: the service is
/// reachable directly. The service has the vendor's connection; the device never contacts it.
@MainActor
final class WebRTCRelay: NSObject, VoiceRelay {
  /// How long to wait for the ICE candidates before offering those gathered so far. Without
  /// STUN or TURN servers there are only host candidates, which take a moment.
  static let gatheringWait = Duration.seconds(3)

  private static let factory: RTCPeerConnectionFactory = {
    RTCInitializeSSL()
    // `LiveVoiceAudio` owns the call's audio session; WebRTC starts its audio only in `start`,
    // once the device stopped listening.
    let session = RTCAudioSession.sharedInstance()
    session.useManualAudio = true
    session.isAudioEnabled = false
    // As `LiveVoiceAudio`, so WebRTC configuring the session keeps the sound on the speaker.
    let configuration = RTCAudioSessionConfiguration.webRTC()
    configuration.category = AVAudioSession.Category.playAndRecord.rawValue
    configuration.mode = AVAudioSession.Mode.voiceChat.rawValue
    configuration.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP, .allowBluetoothA2DP]
    RTCAudioSessionConfiguration.setWebRTC(configuration)
    return RTCPeerConnectionFactory()
  }()

  private var connection: RTCPeerConnection?
  private var microphone: RTCAudioTrack?
  private var isGathered = false
  private var gathered: CheckedContinuation<Void, Never>?
  private var state: VoiceRelayState?
  private var onChange: (@MainActor (VoiceRelayState) -> Void)?
  private var isAudioStarted = false

  func offer() async throws -> String {
    let configuration = RTCConfiguration()
    configuration.tcpCandidatePolicy = .disabled
    configuration.bundlePolicy = .maxBundle
    configuration.rtcpMuxPolicy = .require
    configuration.continualGatheringPolicy = .gatherOnce
    let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
    let made: RTCPeerConnection? = Self.factory.peerConnection(
      with: configuration, constraints: constraints, delegate: self)
    guard let connection = made else { throw WebRTCRelayError.noConnection }
    self.connection = connection
    let source = Self.factory.audioSource(with: constraints)
    let microphone = Self.factory.audioTrack(with: source, trackId: "microphone")
    self.microphone = microphone
    connection.add(microphone, streamIds: ["call"])

    let sdp = try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, any Error>) in
      connection.offer(for: constraints) { @Sendable local, error in
        if let local {
          continuation.resume(returning: local.sdp)
        } else {
          continuation.resume(throwing: error ?? WebRTCRelayError.noOffer)
        }
      }
    }
    try await complete {
      connection.setLocalDescription(
        RTCSessionDescription(type: .offer, sdp: sdp), completionHandler: $0)
    }
    await waitForCandidates()
    guard let offer = connection.localDescription?.sdp else { throw WebRTCRelayError.noOffer }
    return offer
  }

  func accept(answer: String) async throws {
    guard let connection else { throw WebRTCRelayError.noConnection }
    try await complete {
      connection.setRemoteDescription(
        RTCSessionDescription(type: .answer, sdp: answer), completionHandler: $0)
    }
  }

  func start(_ onChange: @escaping @MainActor (VoiceRelayState) -> Void) {
    self.onChange = onChange
    if !isAudioStarted {
      isAudioStarted = true
      let session = RTCAudioSession.sharedInstance()
      session.audioSessionDidActivate(AVAudioSession.sharedInstance())
      session.isAudioEnabled = true
    }
    if let state { onChange(state) }
  }

  func setMuted(_ muted: Bool) {
    microphone?.isEnabled = !muted
  }

  func close() {
    onChange = nil
    if isAudioStarted {
      isAudioStarted = false
      let session = RTCAudioSession.sharedInstance()
      session.isAudioEnabled = false
      session.audioSessionDidDeactivate(AVAudioSession.sharedInstance())
    }
    connection?.close()
    connection = nil
    microphone = nil
    finishGathering()
  }

  /// Runs a WebRTC operation that reports its end on another thread, so the handler must not be
  /// isolated to the main actor.
  private func complete(
    _ operation: (@escaping @Sendable ((any Error)?) -> Void) -> Void
  ) async throws {
    try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<Void, any Error>) in
      operation { error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private func waitForCandidates() async {
    guard !isGathered else { return }
    await withCheckedContinuation { continuation in
      gathered = continuation
      Task { [weak self] in
        try? await Task.sleep(for: Self.gatheringWait)
        self?.finishGathering()
      }
    }
  }

  private func finishGathering() {
    isGathered = true
    gathered?.resume()
    gathered = nil
  }

  private func changed(_ state: VoiceRelayState) {
    guard self.state != state else { return }
    self.state = state
    onChange?(state)
  }
}

// WebRTC calls these on its signaling thread.
extension WebRTCRelay: RTCPeerConnectionDelegate {
  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState
  ) {
    let state: VoiceRelayState? =
      switch newState {
      case .connected, .completed: .connected
      case .failed: .failed
      default: nil
      }
    guard let state else { return }
    Task { @MainActor [weak self] in self?.changed(state) }
  }

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState
  ) {
    guard newState == .complete else { return }
    Task { @MainActor [weak self] in self?.finishGathering() }
  }

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState
  ) {}

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream
  ) {}

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream
  ) {}

  nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate
  ) {}

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]
  ) {}

  nonisolated func peerConnection(
    _ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel
  ) {}
}

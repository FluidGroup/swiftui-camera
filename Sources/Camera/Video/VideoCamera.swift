@preconcurrency import AVFoundation
import AVKit
import SwiftUI

public struct Video: Sendable {
  /// Retain the token for as long as a save, editor or export reads the movie.
  public let file: CapturedFile
  public let profile: VideoRecordingProfile
}

public enum RecordingState: Equatable, Sendable {
  case idle
  case recording(startedAt: Date)
  case finishing
}

/// A headless movie camera. Microphone use is opt-in. Each hold records one
/// HEVC movie, preferring Apple Log on supported iPhones.
public struct VideoCamera<Content: View>: View {
  @Environment(\.cameraSource) private var source
  private let microphoneEnabled: Bool
  private let minimumDuration: TimeInterval
  private let content: (VideoCameraProxy) -> Content
  private var deliver: (@MainActor (Video) async -> Void)?
  private var failure: (@MainActor (String) -> Void)?
  private var audioDidEnd: @Sendable () -> Void = {}

  public init(
    microphoneEnabled: Bool = false, minimumDuration: TimeInterval = 0,
    @ViewBuilder content: @escaping (VideoCameraProxy) -> Content
  ) {
    self.microphoneEnabled = microphoneEnabled
    self.minimumDuration = minimumDuration
    self.content = content
  }

  public func onVideoCapture(perform action: @escaping @MainActor (Video) async -> Void) -> Self {
    var copy = self
    copy.deliver = action
    return copy
  }

  public func onFailure(perform action: @escaping @MainActor (String) -> Void) -> Self {
    var copy = self
    copy.failure = action
    return copy
  }

  /// Restore the host's playback policy after a microphone configuration has
  /// stopped and before the next camera starts. Runs on the capture executor.
  public func onMicrophoneRelease(perform action: @escaping @Sendable () -> Void) -> Self {
    var copy = self
    copy.audioDidEnd = action
    return copy
  }

  public var body: some View {
    VideoSession(
      source: source, microphoneEnabled: microphoneEnabled, minimumDuration: minimumDuration,
      deliver: deliver, failure: failure, audioDidEnd: audioDidEnd, content: content
    )
    .id(source)
  }
}

private struct VideoSession<Content: View>: View {
  let source: CameraSource
  let microphoneEnabled: Bool
  let minimumDuration: TimeInterval
  let deliver: (@MainActor (Video) async -> Void)?
  let failure: (@MainActor (String) -> Void)?
  let audioDidEnd: @Sendable () -> Void
  let content: (VideoCameraProxy) -> Content
  @State private var appliedMicrophone: Bool?
  @State private var camera = VideoCameraProxy()

  var body: some View {
    let enabled = appliedMicrophone ?? microphoneEnabled
    ZStack { content(camera) }
      .task(id: enabled) {
        await camera.run(
          source: source, microphoneEnabled: enabled, minimumDuration: minimumDuration,
          deliver: deliver, failure: failure, audioDidEnd: audioDidEnd)
      }
      .onChange(of: microphoneEnabled, initial: true) { updateMicrophone() }
      .onChange(of: camera.recordingState) { updateMicrophone() }
      #if os(iOS)
        .onCameraCaptureEvent(isEnabled: camera.status == .available(.running) && deliver != nil) {
          event in
          switch event.phase {
          case .began: camera.begin(.hardware)
          case .ended, .cancelled: camera.end(.hardware)
          @unknown default: camera.end(.hardware)
          }
        }
      #endif
  }

  private func updateMicrophone() {
    if camera.recordingState == .idle { appliedMicrophone = microphoneEnabled }
  }
}

@Observable @MainActor
public final class VideoCameraProxy {
  public private(set) var status = CameraStatus.available(.starting)
  public private(set) var profile: VideoRecordingProfile = .standard
  public private(set) var recordingState: RecordingState = .idle
  /// Whether this configuration connected a microphone (permission may be denied).
  public private(set) var microphoneEnabled = false
  private(set) var preview: VideoPreviewSource?
  let frames = PreviewFrames()

  enum Press { case control, touch, hardware }
  private var press: Press?
  private var commands: AsyncStream<VideoCommand>.Continuation?
  private var currentRun: UUID?
  private var canRecord = false

  init() {}

  public func startRecording() { begin(.control) }
  public func stopRecording() { end(.control) }

  func begin(_ source: Press) {
    guard canRecord, status == .available(.running), recordingState == .idle, let commands else {
      return
    }
    press = source
    recordingState = .recording(startedAt: .now)
    commands.yield(.begin)
  }

  func end(_ source: Press) {
    guard press == source else { return }
    press = nil
    recordingState = .finishing
    commands?.yield(.end)
  }

  func run(
    source: CameraSource, simulationHardware: CameraHardware = .simulated,
    microphoneEnabled requested: Bool, minimumDuration: TimeInterval,
    deliver: (@MainActor (Video) async -> Void)?, failure: (@MainActor (String) -> Void)?,
    audioDidEnd: @escaping @Sendable () -> Void
  ) async {
    let request = CameraRequest()
    let id = UUID()
    currentRun = id
    status = .available(.starting)
    recordingState = .idle
    microphoneEnabled = false
    press = nil
    preview = nil
    canRecord = deliver != nil
    let simulated = !BackendKind.select(source).needsAuthorization
    var includesAudio = false
    if !simulated {
      let access = await CameraAuthorization.request()
      guard !Task.isCancelled, currentRun == id else { return }
      guard access == .authorized else {
        status = .accessDenied
        return
      }
      if requested { includesAudio = await AVCaptureDevice.requestAccess(for: .audio) }
    }
    guard !Task.isCancelled, currentRun == id else { return }
    let (stream, input) = AsyncStream<VideoCommand>.makeStream()
    let (events, sink) = AsyncStream<VideoEvent>.makeStream()
    commands = input
    let engine = Task { @CaptureActor [frames, includesAudio] in
      let engine = VideoEngine(
        hardware: simulated ? simulationHardware : .shared, simulated: simulated,
        includesAudio: includesAudio, minimumDuration: minimumDuration, frames: frames,
        events: sink, commands: input, audioDidEnd: audioDidEnd)
      await engine.drain(stream, request: request)
    }
    // Delivery survives view cancellation. A replaced run still delivers its
    // final clip, but cannot publish state into the new configuration.
    let delivery = Task {
      for await event in events {
        switch event {
        case .finished(let video):
          if let video { await deliver?(video) }
          if currentRun == id {
            recordingState = .idle
            press = nil
          }
        case .failure(let message): failure?(message)
        case .status(let value) where currentRun == id:
          status = value
          if value != .available(.running) { preview = nil }
        case .ready(let value, let enabled, let source) where currentRun == id:
          profile = value
          microphoneEnabled = enabled
          preview = source
          status = .available(.running)
        case .finishing where currentRun == id:
          recordingState = .finishing
          press = nil
        default: break
        }
      }
    }
    await withTaskCancellationHandler {
      await engine.value
      await delivery.value
    } onCancel: {
      request.cancel()
      input.finish()
    }
  }
}

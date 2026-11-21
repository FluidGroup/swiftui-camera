@preconcurrency import AVFoundation
import Foundation

/// The preview layer only attaches the session on the main actor. All capture
/// configuration and lifetime operations stay on CaptureActor.
struct VideoPreviewSource: @unchecked Sendable {
  let session: AVCaptureSession
  let device: AVCaptureDevice
}

enum VideoCommand: Sendable {
  case begin, end
  case interrupted(UUID, CameraStatus.Interruption)
  case resumed(UUID)
  case runtimeError(UUID, String)
}

enum VideoEvent: Sendable {
  case status(CameraStatus)
  case ready(VideoRecordingProfile, microphoneEnabled: Bool, VideoPreviewSource?)
  case finishing
  case finished(Video?)
  case failure(String)
}

@CaptureActor
final class VideoEngine: CameraHardwareClient {
  private let hardware: CameraHardware
  private let simulated: Bool
  private let includesAudio: Bool
  private let minimumDuration: TimeInterval
  private let frames: PreviewFrames
  private let events: AsyncStream<VideoEvent>.Continuation
  private let commands: AsyncStream<VideoCommand>.Continuation
  private let audioDidEnd: @Sendable () -> Void
  private var recorder: CameraRecorder?
  private var profile: VideoRecordingProfile = .standard
  private var generation = UUID()
  private var interrupted = false
  private var observers: [any NSObjectProtocol] = []
  private(set) var hasCaptureInFlight = false

  init(
    hardware: CameraHardware, simulated: Bool, includesAudio: Bool, minimumDuration: TimeInterval,
    frames: PreviewFrames, events: AsyncStream<VideoEvent>.Continuation,
    commands: AsyncStream<VideoCommand>.Continuation, audioDidEnd: @escaping @Sendable () -> Void
  ) {
    self.hardware = hardware
    self.simulated = simulated
    self.includesAudio = includesAudio
    self.minimumDuration = minimumDuration
    self.frames = frames
    self.events = events
    self.commands = commands
    self.audioDidEnd = audioDidEnd
  }

  func drain(_ stream: AsyncStream<VideoCommand>, request: CameraRequest) async {
    hardware.request(self, request)
    for await command in stream {
      switch command {
      case .begin:
        do {
          guard hardware.canCapture(self), !interrupted, let recorder else {
            events.yield(.finished(nil))
            continue
          }
          try recorder.startRecording()
          hasCaptureInFlight = true
        } catch {
          events.yield(.failure(error.localizedDescription))
          events.yield(.finished(nil))
        }
      case .end:
        await finishRecording()
      case .interrupted(let id, let reason) where id == generation:
        interrupted = true
        events.yield(.status(.available(.interrupted(reason))))
        await finishRecording()
      case .resumed(let id) where id == generation:
        if let recorder, recorder.session.isRunning {
          interrupted = false
          publishReady(recorder)
        }
      case .runtimeError(let id, let message) where id == generation:
        hardware.withdraw(self)
        await finishRecording()
        events.yield(.status(.unavailable(.configurationFailed(message))))
      default: break  // Notification from a configuration that has been released.
      }
    }
    hardware.withdraw(self)
    await finishRecording()
    events.finish()
  }

  func startHardware() -> Bool {
    let recorder = CameraRecorder(simulated: simulated, frames: frames)
    do {
      CapturedFileStore.sweepOrphans()
      profile = try recorder.configure(includesAudio: includesAudio)
      self.recorder = recorder
      interrupted = false
      if !simulated { observe(recorder.session) }
      try recorder.startRunning()
      publishReady(recorder)
      return true
    } catch {
      self.recorder = recorder
      stopHardware(waiting: false)
      events.yield(.status(.unavailable(.configurationFailed(error.localizedDescription))))
      return false
    }
  }

  private func publishReady(_ recorder: CameraRecorder) {
    let preview = recorder.videoDevice.map {
      VideoPreviewSource(session: recorder.session, device: $0)
    }
    events.yield(.ready(profile, microphoneEnabled: recorder.hasAudio, preview))
  }

  func stopHardware(waiting: Bool) {
    for observer in observers { NotificationCenter.default.removeObserver(observer) }
    observers.removeAll()
    generation = UUID()
    recorder?.stopRunning()
    recorder = nil
    if includesAudio && !simulated { audioDidEnd() }
    if waiting { waitingForHardware() } else { events.yield(.status(.available(.stopped))) }
  }

  func waitingForHardware() {
    events.yield(.status(.available(.interrupted(.inUseByAnotherCamera))))
  }

  private func finishRecording() async {
    guard hasCaptureInFlight, let recorder else { return }
    events.yield(.finishing)
    do {
      let file = try await recorder.stopRecording(minimumDuration: minimumDuration)
      events.yield(.finished(file.map { Video(file: $0, profile: profile) }))
    } catch {
      events.yield(.failure(error.localizedDescription))
      events.yield(.finished(nil))
    }
    hasCaptureInFlight = false
    hardware.reconcile()
  }

  private func observe(_ session: AVCaptureSession) {
    let center = NotificationCenter.default
    observers = [
      center.addObserver(
        forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil
      ) { [commands, generation] note in
        var raw: Int?
        #if os(iOS)
          raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        #endif
        commands.yield(.interrupted(generation, .init(reasonRawValue: raw)))
      },
      center.addObserver(
        forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil
      ) { [commands, generation] _ in
        commands.yield(.resumed(generation))
      },
      center.addObserver(
        forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil
      ) { [commands, generation] note in
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        commands.yield(
          .runtimeError(generation, error?.localizedDescription ?? "The capture session stopped."))
      },
    ]
  }
}

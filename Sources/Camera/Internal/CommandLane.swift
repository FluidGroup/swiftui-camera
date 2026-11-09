import AVFoundation
import Synchronization

struct DeviceIntent: Sendable, Hashable {
  enum Focus: Sendable, Hashable {
    case continuous
    case point(DevicePoint)
    case locked(LensPosition)
  }

  enum WhiteBalance: Sendable, Hashable {
    case automatic
    case locked(Kelvin, Tint)
  }

  var position: CameraPosition
  var lensID: CameraLens.ID?
  var zoom: ZoomFactor?
  var exposure: ExposureProgram
  var bias: ExposureBias
  var focus: Focus
  var focusTap: Int
  var whiteBalance: WhiteBalance

  init(position: CameraPosition) {
    self.position = position
    self.lensID = nil
    self.zoom = nil
    self.exposure = .automatic
    self.bias = ExposureBias(0)
    self.focus = .continuous
    self.focusTap = 0
    self.whiteBalance = .automatic
  }
}

enum LaneCommand: Sendable {
  case start
  case stop
  case reconcile
  case capturePhoto(PhotoRequest)
}

struct PhotoShot: Sendable, Hashable {
  var format: PhotoFormat
  var flash: FlashMode
  var resolution: ResolutionPreference
  var dimensions: PhotoResolution?
  var isMirrored: Bool
  var exposure: ExposureProgram
}

/// One press's settings, made and tracked on the main actor, then handed to the session queue.
///
/// `@unchecked Sendable` is this type's one invariant: the main actor never touches `settings`
/// after `startTrackingCaptureRequest(using:)` returns, and the session queue only reads it, to
/// clone the settings it hands the photo output.
final class PhotoRequest: @unchecked Sendable {
  let settings: AVCapturePhotoSettings
  let shot: PhotoShot
  let snapshot: CameraFailure.Snapshot

  init(settings: AVCapturePhotoSettings, shot: PhotoShot, snapshot: CameraFailure.Snapshot) {
    self.settings = settings
    self.shot = shot
    self.snapshot = snapshot
  }

  var trackedID: Int64 {
    settings.uniqueID
  }
}

@MainActor
final class CommandLane {
  let commands: AsyncStream<LaneCommand>
  let intentBox: IntentBox
  private let continuation: AsyncStream<LaneCommand>.Continuation

  init(intent: DeviceIntent) {
    let (commands, continuation) = AsyncStream<LaneCommand>.makeStream(bufferingPolicy: .unbounded)
    self.commands = commands
    self.continuation = continuation
    self.intentBox = IntentBox(intent)
  }

  deinit {
    continuation.finish()
  }

  func send(_ command: LaneCommand) {
    continuation.yield(command)
  }

  func updateIntent(_ update: (inout DeviceIntent) -> Void) {
    intentBox.update(update)
    send(.reconcile)
  }

  func adoptIntent(_ update: (inout DeviceIntent) -> Void) {
    intentBox.update(update)
  }
}

final class IntentBox: Sendable {
  private let storage: Mutex<DeviceIntent>

  init(_ intent: DeviceIntent) {
    storage = Mutex(intent)
  }

  var value: DeviceIntent {
    storage.withLock { $0 }
  }

  func update(_ update: (inout DeviceIntent) -> Void) {
    storage.withLock { update(&$0) }
  }
}

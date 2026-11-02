import AVFoundation
import ImageIO

final class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
  private let shot: PhotoShot
  private let uniqueID: Int64
  private let camera: CameraModel
  private let progress: @Sendable (Int64, CaptureProgress) -> Void
  private var fileURL: URL?
  private var preview: CGImage?
  private var pixelSize: CGSize = .zero
  private var processingError: (any Error)?

  init(shot: PhotoShot, uniqueID: Int64, camera: CameraModel, progress: @escaping @Sendable (Int64, CaptureProgress) -> Void) {
    self.shot = shot
    self.uniqueID = uniqueID
    self.camera = camera
    self.progress = progress
  }

  func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    Task { @MainActor [camera] in camera.photoWillCapture() }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
    progress(uniqueID, .captured)
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: (any Error)?) {
    if let error {
      processingError = error
      return
    }
    guard let data = photo.fileDataRepresentation() else {
      processingError = CaptureFailure.missingPhotoData
      return
    }
    #if os(iOS)
    let fileExtension = photo.isRawPhoto ? "dng" : shot.format.fileExtension
    let dimensions = photo.isRawPhoto ? photo.resolvedSettings.rawPhotoDimensions : photo.resolvedSettings.photoDimensions
    let orientation = photo.displayOrientation
    let sensorPreview = photo.previewCGImageRepresentation()
    #else
    // No RAW on a Mac, and AVCapturePhoto carries no orientation metadata there: Mac cameras
    // deliver upright.
    let fileExtension = shot.format.fileExtension
    let dimensions = photo.resolvedSettings.photoDimensions
    let orientation = CGImagePropertyOrientation.up
    let sensorPreview = photo.cgImageRepresentation()
    #endif
    do {
      let url = try CapturedFileStore.makeURL(fileExtension: fileExtension)
      try data.write(to: url)
      fileURL = url
    } catch {
      processingError = error
      return
    }

    let display = UprightImage.displaySize(width: Int(dimensions.width), height: Int(dimensions.height), orientation: orientation)
    pixelSize = CGSize(width: display.width, height: display.height)
    preview = sensorPreview.flatMap { UprightImage.make($0, orientation: orientation, maxLongSide: PhotoSettingsBuilder.previewLongSide) }
  }

  func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: (any Error)?) {
    let result: Result<Photo, CameraFailure>
    if let error = error ?? processingError {
      if let fileURL {
        try? FileManager.default.removeItem(at: fileURL)
      }
      result = .failure(CameraFailure(kind: .photoCapture, message: error.localizedDescription))
    } else if let fileURL {
      result = .success(
        Photo(
          file: CapturedFile(url: fileURL),
          format: shot.format,
          pixelSize: pixelSize,
          preview: preview
        ))
    } else {
      result = .failure(CameraFailure(kind: .photoCapture, message: CaptureFailure.missingPhotoData.localizedDescription))
    }
    Task { @MainActor [camera] in camera.photoDidFinish(result) }
    progress(uniqueID, .finished)
  }

  private enum CaptureFailure: LocalizedError {
    case missingPhotoData

    var errorDescription: String? {
      "The captured photo contained no image data."
    }
  }
}

enum CaptureProgress: Sendable {
  /// `didCapturePhotoFor`: the exposure is done, so a session change no longer fails the request.
  case captured
  /// `didFinishCaptureFor`, the guaranteed last callback, with or without `captured` before it.
  case finished
}

extension PhotoFormat {
  var fileExtension: String {
    switch self {
    case .jpeg: "jpg"
    case .heif: "heic"
    case .appleProRAW: "dng"
    }
  }
}

#if os(iOS)
extension AVCapturePhoto {
  /// RAW and preview buffers stay in sensor orientation; the photo's metadata records how to
  /// rotate them for display.
  fileprivate var displayOrientation: CGImagePropertyOrientation {
    guard
      let value = metadata[kCGImagePropertyOrientation as String] as? NSNumber,
      let orientation = CGImagePropertyOrientation(rawValue: value.uint32Value)
    else { return .up }
    return orientation
  }
}
#endif

/// Readiness for hardware: the coordinator, used from the main actor the way its API expects.
///
/// `@unchecked Sendable`: the coordinator is created on the session queue, where the photo output
/// lives, and touched only on the main actor afterwards; its delegate runs on the main queue.
final class HardwareReadinessTracker: ReadinessTracking, @unchecked Sendable {
  private let coordinator: AVCapturePhotoOutputReadinessCoordinator
  private let delegate: ReadinessDelegate

  init(photoOutput: AVCapturePhotoOutput, camera: CameraModel) {
    coordinator = AVCapturePhotoOutputReadinessCoordinator(photoOutput: photoOutput)
    delegate = ReadinessDelegate(camera: camera)
    coordinator.delegate = delegate
  }

  @MainActor
  func startTracking(_ request: PhotoRequest) {
    coordinator.startTrackingCaptureRequest(using: request.settings)
  }

  @MainActor
  func stopTracking(uniqueID: Int64) {
    coordinator.stopTrackingCaptureRequest(using: uniqueID)
  }
}

@MainActor
private final class ReadinessDelegate: NSObject, AVCapturePhotoOutputReadinessCoordinatorDelegate {
  private weak var camera: CameraModel?

  nonisolated init(camera: CameraModel) {
    self.camera = camera
  }

  nonisolated func readinessCoordinator(
    _ coordinator: AVCapturePhotoOutputReadinessCoordinator,
    captureReadinessDidChange captureReadiness: AVCapturePhotoOutput.CaptureReadiness
  ) {
    MainActor.assumeIsolated {
      camera?.apply(readiness: ShutterState.Phase(captureReadiness))
    }
  }
}

extension ShutterState.Phase {
  init(_ readiness: AVCapturePhotoOutput.CaptureReadiness) {
    switch readiness {
    case .sessionNotRunning: self = .unavailable
    case .ready: self = .ready
    case .notReadyMomentarily: self = .busy(.momentarily)
    case .notReadyWaitingForCapture: self = .busy(.waitingForCapture)
    case .notReadyWaitingForProcessing: self = .busy(.processing)
    @unknown default: self = .busy(.momentarily)
    }
  }
}

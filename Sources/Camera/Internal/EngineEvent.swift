import AVFoundation

enum EngineEvent: Sendable {
  case status(CameraStatus)
  case facts(DeviceFacts)
  case readings(DeviceReadings)
  case readiness(ShutterState.Phase)
  case readinessTracker(any ReadinessTracking)
  case preview(PreviewSource)
  case cameraControlAppearance(CameraControlAppearance)
  case failure(CameraFailure)
  case subjectAreaChanged
  case adopt(IntentAdoption)
}

enum IntentAdoption: Sendable, Hashable {
  case lens(CameraLens.ID)
  case lensSwitchFailed(requested: CameraLens.ID, connected: CameraLens.ID)
  case exposure(ExposureProgram)
  case whiteBalance(DeviceIntent.WhiteBalance)
  case focus(DeviceIntent.Focus)
  case zoom(ZoomFactor)
  case bias(ExposureBias)
}

/// Where the preview's frames come from, which tells the preview how to stand them upright: a
/// device's frames turn with its rotation coordinator, and the simulated camera's are upright.
///
/// `@unchecked Sendable`: the main actor only hands the device to
/// `AVCaptureDevice.RotationCoordinator`, AVCam's own pattern, and never mutates it; every
/// mutation stays on the session queue.
enum PreviewSource: @unchecked Sendable, Equatable {
  case device(AVCaptureDevice)
  case simulated

  static func == (lhs: PreviewSource, rhs: PreviewSource) -> Bool {
    switch (lhs, rhs) {
    case (.device(let device), .device(let other)): device === other
    case (.simulated, .simulated): true
    case (.device, .simulated), (.simulated, .device): false
    }
  }
}

protocol ReadinessTracking: Sendable {
  @MainActor func startTracking(_ request: PhotoRequest)
  @MainActor func stopTracking(uniqueID: Int64)
}

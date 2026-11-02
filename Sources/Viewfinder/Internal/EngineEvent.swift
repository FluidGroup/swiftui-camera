import AVFoundation

enum EngineEvent: Sendable {
  case status(CameraStatus)
  case facts(DeviceFacts)
  case readings(DeviceReadings)
  case readiness(ShutterState.Phase)
  case readinessTracker(any ReadinessTracking)
  case preview(PreviewContent?)
  case hardwareControls(HardwareControlsAppearance)
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

/// What the preview shows: the session's video for a connected device, or the test pattern.
///
/// `@unchecked Sendable`: the main actor only hands the session and device to
/// `AVCaptureVideoPreviewLayer` and `AVCaptureDevice.RotationCoordinator`, AVCam's own pattern,
/// and never mutates either; every mutation stays on the session queue.
enum PreviewContent: @unchecked Sendable, Equatable {
  case video(session: AVCaptureSession, device: AVCaptureDevice)
  case testPattern

  static func == (lhs: PreviewContent, rhs: PreviewContent) -> Bool {
    switch (lhs, rhs) {
    case (.video(let session, let device), .video(let otherSession, let otherDevice)):
      session === otherSession && device === otherDevice
    case (.testPattern, .testPattern):
      true
    case (.video, .testPattern), (.testPattern, .video):
      false
    }
  }
}

protocol ReadinessTracking: Sendable {
  @MainActor func startTracking(_ request: PhotoRequest)
  @MainActor func stopTracking(uniqueID: Int64)
}

extension CameraStatus.Interruption {
  /// From `AVCaptureSession.InterruptionReason.rawValue`. An audio-only reason and a missing one
  /// (macOS sends none) are `.other`.
  init(reasonRawValue: Int?) {
    switch reasonRawValue.flatMap(Reason.init(rawValue:)) {
    case .videoDeviceNotAvailableInBackground: self = .backgrounded
    case .videoDeviceInUseByAnotherClient: self = .inUseByAnotherApp
    case .videoDeviceNotAvailableWithMultipleForegroundApps: self = .multitasking
    case .videoDeviceNotAvailableDueToSystemPressure: self = .systemPressure
    case .sensitiveContentMitigationActivated: self = .sensitiveContent
    case .audioDeviceInUseByAnotherClient, nil: self = .other
    }
  }

  /// `AVCaptureSession.InterruptionReason`, which the macOS SDK doesn't declare.
  private enum Reason: Int {
    case videoDeviceNotAvailableInBackground = 1
    case audioDeviceInUseByAnotherClient = 2
    case videoDeviceInUseByAnotherClient = 3
    case videoDeviceNotAvailableWithMultipleForegroundApps = 4
    case videoDeviceNotAvailableDueToSystemPressure = 5
    case sensitiveContentMitigationActivated = 6
  }
}

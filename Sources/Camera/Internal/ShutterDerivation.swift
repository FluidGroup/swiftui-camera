enum ShutterDerivation {
  static func state(
    status: CameraStatus,
    allowsCapture: Bool,
    readiness: ShutterState.Phase,
    owner: PressSource?,
    photosInFlight: Int,
    captureCount: Int
  ) -> ShutterState {
    ShutterState(
      phase: phase(status: status, allowsCapture: allowsCapture, readiness: readiness),
      isPressed: owner != nil,
      photosInFlight: photosInFlight,
      captureCount: captureCount
    )
  }

  static func phase(status: CameraStatus, allowsCapture: Bool, readiness: ShutterState.Phase) -> ShutterState.Phase {
    guard allowsCapture, case .available(.running) = status else { return .unavailable }
    return readiness
  }
}

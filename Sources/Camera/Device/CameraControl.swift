/// What Camera Control, the capture button on the side of iPhone 16 and later, can offer. Each item
/// stays in sync with `CameraSettings` in both directions.
public enum CameraControlItem: Sendable, Hashable {
  case lensPicker
  case zoom
  case exposureBias
  case iso
  case shutterSpeed
  case whiteBalance
  case focus
}

/// What Camera Control is doing, so the app can hide the chrome it covers.
public enum CameraControlAppearance: Sendable, Hashable {
  case inactive
  case active
  /// `sessionControlsWillEnterFullscreenAppearance`: hide on-screen sliders. Fade the shutter
  /// instead of removing it if you like; hardware presses reach the camera either way.
  case fullscreen
}

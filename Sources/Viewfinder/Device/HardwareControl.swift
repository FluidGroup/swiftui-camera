/// Camera Control (the hardware slider) entries, in dial order. Each one mirrors the on-screen
/// control of the same name in both directions.
public enum HardwareControl: Sendable, Hashable {
  case lensPicker
  case zoom
  case exposureBias
  case iso
  case shutterSpeed
  case whiteBalance
  case focus
}

/// What Camera Control is doing, so the app can hide the chrome it covers.
public enum HardwareControlsAppearance: Sendable, Hashable {
  case inactive
  case active
  /// `sessionControlsWillEnterFullscreenAppearance`: hide on-screen sliders. Fade the shutter
  /// instead of removing it if you like; hardware presses reach the camera either way.
  case fullscreen
}

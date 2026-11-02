public enum CameraSource: Sendable, Hashable {
  /// Hardware on a device. A simulated camera in the Simulator and in Xcode previews, so every
  /// screen runs there without a code change.
  case automatic
  case hardware
  case simulated(CameraSimulation)
}

/// A camera with no hardware. The preview shows a moving test pattern, readiness advances on
/// timers, and each press delivers a `Photo` rendered from the pattern.
public struct CameraSimulation: Sendable, Hashable {
  public var lenses: [CameraLens]
  public var processingDelay: Duration

  public init(lenses: [CameraLens] = [], processingDelay: Duration = .milliseconds(300)) {
    self.lenses = lenses
    self.processingDelay = processingDelay
  }
}

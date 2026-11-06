/// Everything a shutter look needs, as one value. Build it with literals in `#Preview`.
///
/// A photo is taken when the press ends, from the screen, Camera Control, or the volume buttons.
public struct ShutterState: Sendable, Hashable {
  public enum Phase: Sendable, Hashable {
    /// Not running, not authorized, or capture is off: no `onPhotoCapture`, or its `isEnabled`
    /// is false.
    case unavailable
    case ready
    case busy(Busy)
  }

  /// `AVCapturePhotoOutput.CaptureReadiness` without `.ready` and `.sessionNotRunning`.
  public enum Busy: Sendable, Hashable {
    /// Between rapid presses. Looks ready but ignores presses, per Apple's guidance against
    /// flicker.
    case momentarily
    case waitingForCapture
    case processing
  }

  public var phase: Phase
  /// A press is down from any source: touch, Camera Control, a volume button, AirPods. The
  /// on-screen shutter therefore animates when a hardware button is pressed.
  public var isPressed: Bool
  /// Photos captured but not delivered yet. Responsive capture overlaps them.
  public var photosInFlight: Int
  /// Increments at each exposure (`willCapturePhotoFor`). Use it as an animation or haptic
  /// trigger.
  public var captureCount: Int

  public init(phase: Phase, isPressed: Bool = false, photosInFlight: Int = 0, captureCount: Int = 0) {
    self.phase = phase
    self.isPressed = isPressed
    self.photosInFlight = photosInFlight
    self.captureCount = captureCount
  }

  /// Accepts a new press. False while momentarily busy even though nothing looks different.
  public var isEnabled: Bool {
    switch phase {
    case .ready: true
    case .unavailable, .busy: false
    }
  }

  /// Apple's readiness guidance: dim while waiting for capture, processing, or unavailable.
  /// Never dim for `.momentarily`.
  public var isDimmed: Bool {
    switch phase {
    case .ready, .busy(.momentarily): false
    case .unavailable, .busy(.waitingForCapture), .busy(.processing): true
    }
  }

  /// Show a spinner: `.busy(.processing)`.
  public var showsProgress: Bool {
    switch phase {
    case .busy(.processing): true
    case .unavailable, .ready, .busy(.momentarily), .busy(.waitingForCapture): false
    }
  }

  /// Nothing pressed and nothing in flight. Safe to close the screen.
  public var isIdle: Bool {
    isPressed == false && photosInFlight == 0
  }
}

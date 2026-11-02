import Foundation

public enum CameraStatus: Sendable, Hashable {
  /// The camera can run. The associated value says what the session is doing now.
  case available(Session)
  /// Camera access is denied or restricted. Offer a path to Settings.
  case accessDenied
  /// No usable camera, or configuration failed. Terminal for this session.
  case unavailable(UnavailableReason)

  public enum Session: Sendable, Hashable {
    /// The `Camera` isn't on screen, or hasn't started.
    case stopped
    /// Authorizing, discovering devices, and configuring.
    case starting
    case running
    /// The system paused the session. It resumes on its own, and the camera then re-applies its
    /// whole device intent (lens, exposure, focus, white balance).
    case interrupted(Interruption)
  }

  public enum Interruption: Sendable, Hashable {
    case backgrounded
    case inUseByAnotherApp
    case multitasking
    case systemPressure
    case sensitiveContent
    case other
  }

  public enum UnavailableReason: Sendable, Hashable {
    case noCamera
    case configurationFailed(String)
  }
}

/// A failure that doesn't end the session, delivered to `Camera.onFailure(perform:)`. Keep it in
/// state to show an alert.
public struct CameraFailure: Error, Sendable, Hashable, Identifiable {
  public enum Kind: Sendable, Hashable {
    case photoCapture
    case lensSwitch
    case deviceConfiguration
  }

  public let id: UUID
  public let kind: Kind
  public let message: String

  public init(kind: Kind, message: String) {
    self.id = UUID()
    self.kind = kind
    self.message = message
  }
}

import AVFoundation

/// Camera authorization, callable with no session.
///
/// A `Camera` calls the same `request` when it starts, so a capture screen never has to.
public enum CameraAuthorization {
  public enum Status: Sendable, Hashable {
    case notDetermined
    case authorized
    case denied
    case restricted
  }

  public static var status: Status {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined: .notDetermined
    case .authorized: .authorized
    case .denied: .denied
    case .restricted: .restricted
    @unknown default: .denied
    }
  }

  /// Prompts only while the status is `.notDetermined`. Otherwise returns the current status
  /// without showing UI.
  public static func request() async -> Status {
    switch status {
    case .notDetermined:
      _ = await AVCaptureDevice.requestAccess(for: .video)
      return status
    case .authorized, .denied, .restricted:
      return status
    }
  }
}

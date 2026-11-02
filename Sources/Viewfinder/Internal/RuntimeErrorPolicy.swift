enum RuntimeErrorPolicy {
  enum Response: Sendable, Hashable {
    /// Media services came back: the session is whole and only needs to run again, with the
    /// whole intent applied once more. The one error AVCam restarts from.
    case restart
    /// Report it and wait for the next start or the end of an interruption. A session restarted
    /// here can fail the same way at once and loop.
    case report
  }

  /// `AVError.mediaServicesWereReset`, which AVFoundation declares only for iOS.
  static let mediaServicesWereResetCode = -11819

  static func response(toErrorCode code: Int?) -> Response {
    code == mediaServicesWereResetCode ? .restart : .report
  }
}

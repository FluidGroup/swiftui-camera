import Dispatch

/// Control actions run on this same queue, which `AVCaptureSlider` requires ("the same exclusive
/// execution context").
@globalActor
actor CaptureActor {
  static let shared = CaptureActor()

  nonisolated let queue = DispatchSerialQueue(label: "viewfinder.capture-session")

  nonisolated var unownedExecutor: UnownedSerialExecutor {
    queue.asUnownedSerialExecutor()
  }
}

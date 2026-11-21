import Synchronization

/// Created when the view appears, before authorization can suspend. The capture
/// queue can see cancellation even while it is draining another client's writer.
final class CameraRequest: Sendable {
  let time = ContinuousClock.now
  private let cancelled = Mutex(false)

  var isCancelled: Bool { cancelled.withLock { $0 } }

  func cancel() { cancelled.withLock { $0 = true } }
}

/// The latest visible client may configure the hardware once the previous client
/// has finished capturing. All three operations run on the session executor.
@CaptureActor
protocol CameraHardwareClient: AnyObject {
  var hasCaptureInFlight: Bool { get }
  func startHardware() -> Bool
  func stopHardware(waiting: Bool)
  func waitingForHardware()
}

@CaptureActor
final class CameraHardware {
  nonisolated static let shared = CameraHardware()
  nonisolated static let simulated = CameraHardware()

  nonisolated init() {}

  private var requests: [(client: any CameraHardwareClient, request: CameraRequest)] = []
  private var owner: (any CameraHardwareClient)?

  func request(_ client: any CameraHardwareClient, _ request: CameraRequest = CameraRequest()) {
    guard !request.isCancelled, !requests.contains(where: { $0.client === client }) else { return }
    requests.append((client, request))
    requests.sort { $0.request.time < $1.request.time }
    if requests.last?.client !== client || owner?.hasCaptureInFlight == true {
      client.waitingForHardware()
    }
    reconcile()
  }

  func withdraw(_ client: any CameraHardwareClient) {
    requests.removeAll { $0.client === client }
    reconcile()
  }

  func canCapture(_ client: any CameraHardwareClient) -> Bool {
    owner === client && requests.last?.client === client
      && requests.last?.request.isCancelled == false
  }

  /// Start/stop do not suspend. Clients call back here after the last photo or
  /// movie writer finishes, including cancellation and failure paths.
  func reconcile() {
    requests.removeAll { $0.request.isCancelled }
    guard owner !== requests.last?.client, owner?.hasCaptureInFlight != true else { return }
    if let owner {
      owner.stopHardware(waiting: requests.contains { $0.client === owner })
      self.owner = nil
    }
    while let next = requests.last {
      if !next.request.isCancelled, next.client.startHardware() {
        owner = next.client
        return
      }
      requests.removeLast()
    }
  }
}

import Synchronization

/// Created when the view appears, before authorization can suspend. The capture
/// queue can see cancellation even while it is draining another client's writer.
final class CameraRequest: Sendable {
  let time = ContinuousClock.now
  private struct State {
    var isCancelled = false
    var accepting = false
    var queued = 0
  }
  private let state = Mutex(State())

  var isCancelled: Bool { state.withLock { $0.isCancelled } }
  func cancel() { state.withLock { $0.isCancelled = true } }

  /// A press and a handoff can race on different executors. Once accepted, a
  /// command keeps its session through submission, even if the view disappears.
  func reserveCapture() -> Bool {
    state.withLock {
      guard $0.accepting && !$0.isCancelled else { return false }
      $0.queued += 1
      return true
    }
  }

  @CaptureActor func didSubmitCapture() { state.withLock { $0.queued -= 1 } }

  @CaptureActor @discardableResult
  func setAccepting(_ accepting: Bool) -> Bool {
    state.withLock {
      $0.accepting = accepting
      return $0.queued == 0
    }
  }
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

  private typealias Entry = (client: any CameraHardwareClient, request: CameraRequest)
  private var requests: [Entry] = []
  private var owner: Entry?

  func request(_ client: any CameraHardwareClient, _ request: CameraRequest = CameraRequest()) {
    guard !request.isCancelled, !requests.contains(where: { $0.client === client }) else { return }
    requests.append((client, request))
    requests.sort { $0.request.time < $1.request.time }
    reconcile()
    if owner?.request !== request, requests.contains(where: { $0.request === request }) {
      client.waitingForHardware()
    }
  }

  func withdraw(_ client: any CameraHardwareClient) {
    requests.removeAll { $0.client === client }
    reconcile()
  }

  /// Start/stop do not suspend. Clients call back here after the last photo or
  /// movie writer finishes, including cancellation and failure paths.
  func reconcile() {
    requests.removeAll { $0.request.isCancelled }
    if let owner {
      if owner.request === requests.last?.request {
        owner.request.setAccepting(true)
        return
      }
      guard owner.request.setAccepting(false), !owner.client.hasCaptureInFlight else { return }
      owner.client.stopHardware(waiting: requests.contains { $0.client === owner.client })
      self.owner = nil
    }
    while let next = requests.last {
      next.request.setAccepting(true)
      if !next.request.isCancelled, next.client.startHardware() {
        owner = next
        return
      }
      next.request.setAccepting(false)
      requests.removeLast()
    }
  }
}

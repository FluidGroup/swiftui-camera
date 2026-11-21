import Testing

@testable import Camera

@CaptureActor
struct CameraHardwareTests {
  private final class Client: CameraHardwareClient {
    var hasCaptureInFlight = false
    var canStart = true
    var running = false
    var starts = 0
    var waiting = false

    func startHardware() -> Bool {
      starts += 1
      running = canStart
      waiting = false
      return canStart
    }
    func stopHardware(waiting: Bool) {
      running = false
      self.waiting = waiting
    }
    func waitingForHardware() { waiting = true }
  }

  @Test func slowAuthorizationDoesNotDisplaceANewerView() {
    let hardware = CameraHardware()
    let earlier = Client()
    let later = Client()
    let pendingPermission = CameraRequest()

    hardware.request(later)
    hardware.request(earlier, pendingPermission)
    #expect(earlier.waiting && later.running)
    pendingPermission.cancel()
    hardware.withdraw(later)
    #expect(earlier.starts == 0)
  }

  @Test func handoffWaitsForCaptureAndSkipsWithdrawnClients() {
    let hardware = CameraHardware()
    let first = Client()
    let removed = Client()
    let latest = Client()
    hardware.request(first)
    first.hasCaptureInFlight = true
    hardware.request(removed)
    hardware.request(latest)
    hardware.withdraw(removed)
    #expect(first.running && latest.waiting && latest.starts == 0)
    #expect(latest.waiting)
    first.hasCaptureInFlight = false
    hardware.reconcile()
    #expect(!first.running && first.waiting && latest.running)
    hardware.withdraw(latest)
    #expect(first.running && removed.starts == 0)
  }

  @Test func anAcceptedPressOutlivesDismissalUntilSubmitted() {
    let hardware = CameraHardware()
    let photo = Client()
    let video = Client()
    let request = CameraRequest()
    hardware.request(photo, request)
    #expect(request.reserveCapture())
    request.cancel()
    hardware.request(video)
    #expect(photo.running && video.waiting)
    #expect(!request.reserveCapture())
    photo.hasCaptureInFlight = true
    request.didSubmitCapture()
    hardware.reconcile()
    #expect(photo.running)
    photo.hasCaptureInFlight = false
    hardware.reconcile()
    #expect(video.running && !photo.running)
  }

  @Test func failureRestoresThePreviousOwner() {
    let hardware = CameraHardware()
    let first = Client()
    let failed = Client()
    failed.canStart = false
    hardware.request(first)
    hardware.request(failed)
    #expect(first.starts == 2 && first.running)
  }
}

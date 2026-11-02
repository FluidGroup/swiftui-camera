import Testing

@testable import Viewfinder

struct ShutterDerivationTests {
  private func state(
    status: CameraStatus = .available(.running),
    allowsCapture: Bool = true,
    readiness: ShutterState.Phase = .ready,
    owner: PressSource? = nil,
    inFlight: Int = 0,
    count: Int = 0
  ) -> ShutterState {
    ShutterDerivation.state(
      status: status,
      allowsCapture: allowsCapture,
      readiness: readiness,
      owner: owner,
      photosInFlight: inFlight,
      captureCount: count
    )
  }

  @Test func readinessShowsThroughWhileRunningAndAllowed() {
    #expect(state(readiness: .ready).phase == .ready)
    #expect(state(readiness: .busy(.momentarily)).phase == .busy(.momentarily))
    #expect(state(readiness: .busy(.processing)).phase == .busy(.processing))
  }

  @Test func anythingButRunningIsUnavailable() {
    #expect(state(status: .available(.starting)).phase == .unavailable)
    #expect(state(status: .available(.stopped)).phase == .unavailable)
    #expect(state(status: .available(.interrupted(.backgrounded))).phase == .unavailable)
    #expect(state(status: .accessDenied).phase == .unavailable)
    #expect(state(status: .unavailable(.noCamera)).phase == .unavailable)
  }

  @Test func theScopeGateWinsOverReadiness() {
    #expect(state(allowsCapture: false, readiness: .ready).phase == .unavailable)
  }

  @Test func pressAndCountersComeFromTheirOwners() {
    let pressed = state(owner: .hardware, inFlight: 2, count: 7)
    #expect(pressed.isPressed)
    #expect(pressed.photosInFlight == 2)
    #expect(pressed.captureCount == 7)
    #expect(!pressed.isIdle)
    #expect(state().isIdle)
  }
}

import Testing

@testable import Viewfinder

struct InterruptionMappingTests {
  @Test func everySessionReasonHasItsOwnCase() {
    #expect(CameraStatus.Interruption(reasonRawValue: 1) == .backgrounded)
    #expect(CameraStatus.Interruption(reasonRawValue: 3) == .inUseByAnotherApp)
    #expect(CameraStatus.Interruption(reasonRawValue: 4) == .multitasking)
    #expect(CameraStatus.Interruption(reasonRawValue: 5) == .systemPressure)
    #expect(CameraStatus.Interruption(reasonRawValue: 6) == .sensitiveContent)
  }

  @Test func audioMissingAndUnknownReasonsAreOther() {
    #expect(CameraStatus.Interruption(reasonRawValue: 2) == .other)
    #expect(CameraStatus.Interruption(reasonRawValue: nil) == .other)
    #expect(CameraStatus.Interruption(reasonRawValue: 99) == .other)
  }
}

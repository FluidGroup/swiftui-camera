import AVFoundation
import Testing

@testable import Camera

struct RuntimeErrorPolicyTests {
  @Test func onlyAMediaServicesResetRestartsTheSession() {
    #expect(RuntimeErrorPolicy.response(toErrorCode: RuntimeErrorPolicy.mediaServicesWereResetCode) == .restart)
    #expect(RuntimeErrorPolicy.response(toErrorCode: AVError.Code.deviceNotConnected.rawValue) == .report)
    #expect(RuntimeErrorPolicy.response(toErrorCode: AVError.Code.unknown.rawValue) == .report)
    #expect(RuntimeErrorPolicy.response(toErrorCode: nil) == .report)
  }

  #if os(iOS)
  @Test func theResetCodeIsAVFoundations() {
    #expect(RuntimeErrorPolicy.mediaServicesWereResetCode == AVError.Code.mediaServicesWereReset.rawValue)
  }
  #endif
}

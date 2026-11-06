import Testing

@testable import Camera

struct ShutterMachineTests {
  @Test func releaseFromTheOwnerCaptures() {
    var state = ShutterMachine.State()
    #expect(ShutterMachine.reduce(&state, .press(.touch), canPress: true) == nil)
    #expect(ShutterMachine.reduce(&state, .release(.touch), canPress: true) == .capturePhoto)
    #expect(state.owner == nil)
  }

  @Test func anotherSourceCannotTakeOrEndAHeldPress() {
    var state = ShutterMachine.State()
    _ = ShutterMachine.reduce(&state, .press(.touch), canPress: true)
    #expect(ShutterMachine.reduce(&state, .press(.hardware), canPress: true) == nil)
    #expect(ShutterMachine.reduce(&state, .release(.hardware), canPress: true) == nil)
    #expect(ShutterMachine.reduce(&state, .activate, canPress: true) == nil)
    #expect(state.owner == .touch)
  }

  @Test func cancelEndsThePressWithoutCapturing() {
    var state = ShutterMachine.State()
    _ = ShutterMachine.reduce(&state, .press(.hardware), canPress: true)
    #expect(ShutterMachine.reduce(&state, .cancel(.hardware), canPress: true) == nil)
    #expect(state.owner == nil)
  }

  @Test func aCancelAfterTheReleaseIsIgnored() {
    var state = ShutterMachine.State()
    _ = ShutterMachine.reduce(&state, .press(.touch), canPress: true)
    _ = ShutterMachine.reduce(&state, .release(.touch), canPress: true)
    #expect(ShutterMachine.reduce(&state, .cancel(.touch), canPress: true) == nil)
    #expect(state.owner == nil)
  }

  @Test func readinessIsCheckedAtPressNotRelease() {
    var state = ShutterMachine.State()
    #expect(ShutterMachine.reduce(&state, .press(.touch), canPress: false) == nil)
    #expect(state.owner == nil)

    _ = ShutterMachine.reduce(&state, .press(.touch), canPress: true)
    #expect(ShutterMachine.reduce(&state, .release(.touch), canPress: false) == .capturePhoto)
  }

  @Test func activateCapturesOnlyWhenIdleAndReady() {
    var state = ShutterMachine.State()
    #expect(ShutterMachine.reduce(&state, .activate, canPress: false) == nil)
    #expect(ShutterMachine.reduce(&state, .activate, canPress: true) == .capturePhoto)
  }
}

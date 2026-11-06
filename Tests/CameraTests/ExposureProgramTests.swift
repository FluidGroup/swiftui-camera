import Testing

@testable import Camera

struct ExposureProgramTests {
  private func controls(isoAutomatic: Bool, shutterAutomatic: Bool) -> ExposureControls {
    ExposureControls(
      iso: ManualControl(value: ISO(100), range: ISO(25)...ISO(6400), isAutomatic: isoAutomatic),
      shutterSpeed: ManualControl(
        value: ShutterSpeed(1.0 / 100), range: ShutterSpeed(1.0 / 8000)...ShutterSpeed(1), isAutomatic: shutterAutomatic),
      bias: ManualControl(value: ExposureBias(0.7), range: ExposureBias(-8)...ExposureBias(8))
    )
  }

  @Test func theProgramFollowsTheToggles() {
    #expect(controls(isoAutomatic: true, shutterAutomatic: true).program == .automatic)
    #expect(controls(isoAutomatic: true, shutterAutomatic: false).program == .shutterPriority(ShutterSpeed(1.0 / 100)))
    #expect(controls(isoAutomatic: false, shutterAutomatic: true).program == .isoPriority(ISO(100)))
    #expect(controls(isoAutomatic: false, shutterAutomatic: false).program == .manual(ShutterSpeed(1.0 / 100), ISO(100)))
  }

  @Test func automaticTurnsBothTogglesOnAndKeepsTheTargets() {
    var exposure = controls(isoAutomatic: false, shutterAutomatic: false)
    exposure.program = .automatic
    #expect(exposure.iso.isAutomatic && exposure.shutterSpeed.isAutomatic)
    #expect(exposure.iso.value == ISO(100))
    #expect(exposure.shutterSpeed.value == ShutterSpeed(1.0 / 100))
  }

  @Test func shutterPriorityFixesTheShutterSpeedAndFreesISO() {
    var exposure = controls(isoAutomatic: false, shutterAutomatic: true)
    exposure.program = .shutterPriority(ShutterSpeed(1.0 / 500))
    #expect(exposure.shutterSpeed.value == ShutterSpeed(1.0 / 500))
    #expect(!exposure.shutterSpeed.isAutomatic)
    #expect(exposure.iso.isAutomatic)
    #expect(exposure.program == .shutterPriority(ShutterSpeed(1.0 / 500)))
  }

  @Test func isoPriorityFixesISOAndFreesTheShutterSpeed() {
    var exposure = controls(isoAutomatic: true, shutterAutomatic: false)
    exposure.program = .isoPriority(ISO(800))
    #expect(exposure.iso.value == ISO(800))
    #expect(!exposure.iso.isAutomatic)
    #expect(exposure.shutterSpeed.isAutomatic)
    #expect(exposure.program == .isoPriority(ISO(800)))
  }

  @Test func manualFixesBothTargets() {
    var exposure = controls(isoAutomatic: true, shutterAutomatic: true)
    exposure.program = .manual(ShutterSpeed(0.5), ISO(3200))
    #expect(exposure.shutterSpeed.value == ShutterSpeed(0.5))
    #expect(exposure.iso.value == ISO(3200))
    #expect(!exposure.shutterSpeed.isAutomatic && !exposure.iso.isAutomatic)
    #expect(exposure.program == .manual(ShutterSpeed(0.5), ISO(3200)))
  }

  @Test func targetsAreStoredAsGivenEvenOutsideTheRange() {
    var exposure = controls(isoAutomatic: true, shutterAutomatic: true)
    exposure.program = .manual(ShutterSpeed(10), ISO(100_000))
    #expect(exposure.shutterSpeed.value == ShutterSpeed(10))
    #expect(exposure.iso.value == ISO(100_000))
  }

  @Test func theProgramLeavesBiasAlone() {
    var exposure = controls(isoAutomatic: true, shutterAutomatic: true)
    for program in [ExposureProgram.manual(ShutterSpeed(0.5), ISO(3200)), .shutterPriority(ShutterSpeed(0.01)), .automatic] {
      exposure.program = program
      #expect(exposure.bias.value == ExposureBias(0.7))
    }
  }

  @Test func programsRoundTripWhenTheControlsCannotGoAutomatic() {
    var exposure = controls(isoAutomatic: false, shutterAutomatic: false)
    exposure.iso.supportsAutomatic = false
    exposure.program = .shutterPriority(ShutterSpeed(0.25))
    #expect(exposure.program == .shutterPriority(ShutterSpeed(0.25)))
  }
}

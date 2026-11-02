import Testing

@testable import Viewfinder

struct ExposureSteeringTests {
  private let isoRange = ISO(50)...ISO(3200)
  private let speedRange = ShutterSpeed(1 / 8000)...ShutterSpeed(1)

  @Test func aBrightFrameLowersTheFreeParameterByTheOffsetInStops() {
    #expect(ExposureSteering.iso(holding: ISO(800), offset: 1, range: isoRange) == ISO(400))
    #expect(ExposureSteering.shutterSpeed(holding: ShutterSpeed(1 / 60), offset: 2, range: speedRange) == ShutterSpeed(1 / 240))
  }

  @Test func aDarkFrameRaisesIt() {
    #expect(ExposureSteering.iso(holding: ISO(100), offset: -1, range: isoRange) == ISO(200))
  }

  @Test func theMeterNoiseInsideTheDeadBandIsIgnored() {
    #expect(ExposureSteering.iso(holding: ISO(800), offset: 0.1, range: isoRange) == nil)
    #expect(ExposureSteering.iso(holding: ISO(800), offset: -0.16, range: isoRange) == nil)
  }

  @Test func theRangeLimitsTheMoveAndEndsItAtTheLimit() {
    #expect(ExposureSteering.iso(holding: ISO(100), offset: 3, range: isoRange) == ISO(50))
    #expect(ExposureSteering.iso(holding: ISO(50), offset: 3, range: isoRange) == nil)
    #expect(ExposureSteering.shutterSpeed(holding: ShutterSpeed(1), offset: -1, range: speedRange) == nil)
  }
}

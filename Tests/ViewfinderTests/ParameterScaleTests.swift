import Testing

@testable import Viewfinder

private func approximately(_ a: Double, _ b: Double, tolerance: Double = 1e-9) -> Bool {
  abs(a - b) <= tolerance
}

struct ParameterScaleTests {
  @Test func linearPositionIsTheFractionOfTheRange() {
    let range = Tint(-150)...Tint(150)
    #expect(Tint.position(of: Tint(-150), in: range) == 0)
    #expect(approximately(Tint.position(of: Tint(0), in: range), 0.5))
    #expect(approximately(Tint.position(of: Tint(75), in: range), 0.75))
    #expect(Tint.position(of: Tint(150), in: range) == 1)
  }

  @Test func logarithmicPositionMakesEqualStopsEqualSteps() {
    let range = ISO(50)...ISO(800)
    #expect(approximately(Self.position(ISO(100), range), 0.25))
    #expect(approximately(Self.position(ISO(200), range), 0.5))
    #expect(approximately(Self.position(ISO(400), range), 0.75))
  }

  @Test func reciprocalPositionIncreasesWithKelvinAndEvensOutMireds() {
    let range = Kelvin(2000)...Kelvin(10000)
    #expect(approximately(Self.position(Kelvin(4000), range), 0.625))
    #expect(approximately(Self.position(Kelvin(2500), range), 0.25))
    #expect(Self.position(Kelvin(5000), range) > Self.position(Kelvin(4000), range))
  }

  @Test func positionIsClampedToTheUnitInterval() {
    let range = ISO(100)...ISO(1600)
    #expect(Self.position(ISO(25), range) == 0)
    #expect(Self.position(ISO(6400), range) == 1)
    #expect(Self.position(ISO(-5), range) == 0)
  }

  @Test func valueAtPositionIsClampedIntoTheRange() {
    let range = Tint(-50)...Tint(50)
    #expect(Tint.value(at: -3, in: range) == Tint(-50))
    #expect(Tint.value(at: 7, in: range) == Tint(50))
    #expect(Tint.value(at: .nan, in: range) == Tint(-50))
  }

  @Test func valueAtPositionInvertsTheScales() {
    #expect(approximately(ISO.value(at: 0.25, in: ISO(50)...ISO(800)).rawValue, 100, tolerance: 1e-9))
    #expect(approximately(Kelvin.value(at: 0.625, in: Kelvin(2000)...Kelvin(10000)).rawValue, 4000, tolerance: 1e-6))
    #expect(approximately(ExposureBias.value(at: 0.5, in: ExposureBias(-2)...ExposureBias(2)).rawValue, 0))
  }

  @Test(arguments: [0.0, 0.1, 0.25, 0.5, 0.77, 0.999, 1.0])
  func positionRoundTripsThroughValue(position: Double) {
    #expect(Self.roundTrip(position, ISO(25)...ISO(25600)))
    #expect(Self.roundTrip(position, ShutterSpeed(1.0 / 8000)...ShutterSpeed(1.0 / 3)))
    #expect(Self.roundTrip(position, Kelvin(2000)...Kelvin(10000)))
    #expect(Self.roundTrip(position, ExposureBias(-8)...ExposureBias(8)))
    #expect(Self.roundTrip(position, ZoomFactor(0.5)...ZoomFactor(25)))
  }

  @Test func aDegenerateRangeHasPositionZeroAndValueLow() {
    let range = ISO(100)...ISO(100)
    #expect(Self.position(ISO(100), range) == 0)
    #expect(ISO.value(at: 0.7, in: range) == ISO(100))
  }

  @Test func nonPositiveLogarithmicAndReciprocalRangesFallBackToLinear() {
    #expect(approximately(Self.position(ISO(50), ISO(0)...ISO(100)), 0.5))
    #expect(approximately(ISO.value(at: 0.25, in: ISO(0)...ISO(100)).rawValue, 25))
    #expect(approximately(Self.position(Kelvin(5000), Kelvin(0)...Kelvin(10000)), 0.5))
  }

  @Test func neverProducesNonFiniteNumbers() {
    let ranges = [ISO(0)...ISO(0), ISO(-5)...ISO(5), ISO(100)...ISO(100), ISO(1)...ISO(1e308)]
    for range in ranges {
      for value in [-1.0, 0, 1, 1e-300, 1e300, .nan, .infinity, -.infinity] {
        let position = Self.position(ISO(value), range)
        #expect(position.isFinite && (0...1).contains(position))
      }
      for position in [-1.0, 0, 0.5, 1, 2, .nan, .infinity] {
        let value = ISO.value(at: position, in: range)
        #expect(value.rawValue.isFinite && range.contains(value))
      }
    }
  }

  @Test func manualControlPositionDrivesTheValue() {
    var control = ManualControl(value: ISO(100), range: ISO(50)...ISO(800))
    #expect(approximately(control.position, 0.25))
    control.position = 0.75
    #expect(approximately(control.value.rawValue, 400, tolerance: 1e-9))
  }

  private static func position<P: CameraParameter>(_ value: P, _ range: ClosedRange<P>) -> Double {
    P.position(of: value, in: range)
  }

  private static func roundTrip<P: CameraParameter>(_ position: Double, _ range: ClosedRange<P>) -> Bool {
    let value = P.value(at: position, in: range)
    return range.contains(value) && approximately(P.position(of: value, in: range), position, tolerance: 1e-9)
  }
}

import Testing

@testable import Viewfinder

private func raw<P: CameraParameter>(_ stops: [P]) -> [Double] { stops.map(\.rawValue) }

private func expectValues(_ actual: [Double], _ expected: [Double], sourceLocation: SourceLocation = #_sourceLocation) {
  #expect(actual == expected, sourceLocation: sourceLocation)
}

private func assertWellFormed<P: CameraParameter>(_ stops: [P], in range: ClosedRange<P>) -> Bool {
  zip(stops, stops.dropFirst()).allSatisfy { $0 < $1 } && stops.allSatisfy(range.contains)
}

struct ISOStopTests {
  @Test func nominalThirdStopsInsideTheRange() {
    let stops = ISO.stops(in: ISO(100)...ISO(800))
    expectValues(raw(stops), [100, 125, 160, 200, 250, 320, 400, 500, 640, 800])
  }

  @Test func theRangeLimitsAreAddedWhenFarFromTheNearestStop() {
    let stops = ISO.stops(in: ISO(21)...ISO(2900))
    #expect(stops.first == ISO(21))
    #expect(stops.dropFirst().first == ISO(25))
    #expect(stops.last == ISO(2900))
    #expect(stops.dropLast().last == ISO(2500))
  }

  @Test func aLimitWithinASixthOfAStopIsNotAdded() {
    expectValues(raw(ISO.stops(in: ISO(95)...ISO(103))), [100])
    #expect(ISO.stops(in: ISO(28)...ISO(64)).first == ISO(28))
  }

  @Test func aRangeBetweenStopsYieldsItsLimits() {
    expectValues(raw(ISO.stops(in: ISO(101)...ISO(118))), [101, 118])
    expectValues(raw(ISO.stops(in: ISO(100)...ISO(100))), [100])
  }
}

struct ShutterSpeedStopTests {
  @Test func nominalStopsInsideTheRange() {
    let range = ShutterSpeed(1.0 / 8000)...ShutterSpeed(1.0 / 4000)
    expectValues(raw(ShutterSpeed.stops(in: range)), [1.0 / 8000, 1.0 / 6400, 1.0 / 5000, 1.0 / 4000])
  }

  @Test func theSeriesContinuesBelowAnEighthThousandthInThirdStops() {
    let range = ShutterSpeed(1.0 / 128_000)...ShutterSpeed(1.0 / 8000)
    let denominators = ShutterSpeed.stops(in: range).map { (1 / $0.rawValue).rounded() }
    expectValues(
      denominators,
      [128_000, 100_000, 80_000, 64_000, 50_000, 40_000, 32_000, 25_600, 20_000, 16_000, 12_800, 10_000, 8000])
  }

  @Test func theSeriesReachesThirtySeconds() {
    let range = ShutterSpeed(0.3)...ShutterSpeed(30)
    expectValues(raw(ShutterSpeed.stops(in: range)), [
        1.0 / 3, 0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30,
      ])
  }

  @Test func stopsAroundOneSecondRoundTripThroughNotation() {
    let range = ShutterSpeed(1.0 / 30)...ShutterSpeed(2)
    #expect(
      ShutterSpeed.stops(in: range).map { $0.formatted() } == [
        "1/30", "1/25", "1/20", "1/15", "1/13", "1/10", "1/8", "1/6", "1/5", "1/4", "0.3\"", "0.4\"", "0.5\"", "0.6\"",
        "0.8\"", "1\"", "1.3\"", "1.6\"", "2\"",
      ])
  }

  @Test func aDeviceLimitBetweenNominalStopsIsAdded() {
    let range = ShutterSpeed(1.0 / 45_000)...ShutterSpeed(0.4)
    let stops = ShutterSpeed.stops(in: range)
    #expect(stops.first == ShutterSpeed(1.0 / 45_000))
    #expect(stops.dropFirst().first == ShutterSpeed(1.0 / 40_000))
    #expect(stops.last == ShutterSpeed(0.4))
    #expect(assertWellFormed(stops, in: range))
  }
}

struct ExposureBiasStopTests {
  @Test func multiplesOfAThirdEV() {
    let stops = ExposureBias.stops(in: ExposureBias(-1)...ExposureBias(1))
    expectValues(raw(stops), [-1, -2.0 / 3, -1.0 / 3, 0, 1.0 / 3, 2.0 / 3, 1])
  }

  @Test func theRangeLimitIsAddedBeyondASixthOfAnEV() {
    let stops = ExposureBias.stops(in: ExposureBias(-0.52)...ExposureBias(0.45))
    expectValues(raw(stops), [-0.52, -1.0 / 3, 0, 1.0 / 3])
  }

  @Test func exactlyHalfAStepAwayIsNotAdded() {
    let stops = ExposureBias.stops(in: ExposureBias(-0.5)...ExposureBias(0.5))
    expectValues(raw(stops), [-1.0 / 3, 0, 1.0 / 3])
  }

  @Test func theDeviceRangeMinusEightToEightHasFortyNineStops() {
    let range = ExposureBias(-8)...ExposureBias(8)
    let stops = ExposureBias.stops(in: range)
    #expect(stops.count == 49)
    #expect(assertWellFormed(stops, in: range))
  }
}

struct KelvinStopTests {
  @Test func tenMiredStepsRoundedToFiftyMergedWithThePresets() {
    let stops = Kelvin.stops(in: Kelvin(3000)...Kelvin(7600))
    expectValues(raw(stops), [
        3000, 3050, 3150, 3200, 3350, 3450, 3550, 3700, 3850, 4000, 4150, 4350, 4550, 4750, 5000, 5250, 5500, 5900,
        6250, 6500, 7150, 7500,
      ])
  }

  @Test func presetsInsideTheRangeAreAlwaysPresent() {
    let stops = raw(Kelvin.stops(in: Kelvin(2500)...Kelvin(8000)))
    for preset in [3200.0, 4000, 5500, 6500, 7500] { #expect(stops.contains(preset)) }
  }

  @Test func aPresetOutsideTheRangeIsNotIncluded() {
    let stops = raw(Kelvin.stops(in: Kelvin(4500)...Kelvin(6000)))
    #expect(!stops.contains(4000) && !stops.contains(6500))
    #expect(stops.contains(5500))
  }

  @Test func stepsNearAPresetAreDropped() {
    let stops = raw(Kelvin.stops(in: Kelvin(3000)...Kelvin(7600)))
    #expect(!stops.contains(5550))
    #expect(stops.filter { (3900...4100).contains($0) } == [4000])
  }

  @Test func theRangeLimitsAreReachable() {
    let range = Kelvin(2735)...Kelvin(9876)
    let stops = Kelvin.stops(in: range)
    #expect(stops.first == range.lowerBound)
    #expect(stops.last == range.upperBound)
    #expect(assertWellFormed(stops, in: range))
  }
}

struct TintStopTests {
  @Test func multiplesOfTen() {
    expectValues(raw(Tint.stops(in: Tint(-30)...Tint(30))), [-30, -20, -10, 0, 10, 20, 30])
  }

  @Test func theLimitIsAddedBeyondFiveFromTheNearestMultiple() {
    expectValues(raw(Tint.stops(in: Tint(-36)...Tint(27))), [-36, -30, -20, -10, 0, 10, 20, 27])
    expectValues(raw(Tint.stops(in: Tint(-34)...Tint(24))), [-30, -20, -10, 0, 10, 20])
  }
}

struct LensPositionStopTests {
  @Test func multiplesOfFiveHundredths() {
    let stops = LensPosition.stops(in: LensPosition(0)...LensPosition(1))
    #expect(stops.count == 21)
    #expect(stops.map { $0.formatted() }.prefix(4) == ["0.00", "0.05", "0.10", "0.15"])
    #expect(stops.last == LensPosition(1))
    #expect(assertWellFormed(stops, in: LensPosition(0)...LensPosition(1)))
  }
}

struct ZoomFactorStopTests {
  @Test func anchorsWithSixthStopStepsBetweenThem() {
    let stops = ZoomFactor.stops(in: ZoomFactor(0.5)...ZoomFactor(25))
    expectValues(raw(stops), [
        0.5, 0.6, 0.7, 0.8, 0.9, 1, 1.1, 1.3, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8, 3, 3.4, 3.8, 4.2, 5, 5.6, 6.3, 7.1, 7.9, 8.9,
        10, 11.2, 12.6, 14.1, 15, 16.8, 18.9, 21.2, 25,
      ])
  }

  @Test func stepsNextToAnAnchorAreDropped() {
    let stops = raw(ZoomFactor.stops(in: ZoomFactor(0.5)...ZoomFactor(25)))
    #expect(!stops.contains(4.8) && !stops.contains(23.8))
  }

  @Test func aTelephotoRangeStartsAtItsOwnLimit() {
    let range = ZoomFactor(4.4)...ZoomFactor(30)
    let stops = ZoomFactor.stops(in: range)
    #expect(stops.first == ZoomFactor(4.4))
    #expect(stops.last == ZoomFactor(30))
    #expect(assertWellFormed(stops, in: range))
  }

  @Test func theFrontCameraRangeStartsAtOne() {
    let stops = ZoomFactor.stops(in: ZoomFactor(1)...ZoomFactor(2.9))
    expectValues(raw(stops), [1, 1.1, 1.3, 1.4, 1.6, 1.8, 2, 2.2, 2.5, 2.8])
  }
}

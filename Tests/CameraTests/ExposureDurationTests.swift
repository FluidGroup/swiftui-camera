import CoreMedia
import Testing

@testable import Camera

struct ExposureDurationTests {
  private let min = CMTime(value: 1, timescale: 128_000)
  private let max = CMTime(value: 1, timescale: 3)

  @Test func aLimitReadBackInSecondsNeverLeavesTheRange() {
    #expect(ExposureDuration.clamped(seconds: min.seconds, min: min, max: max) == min)
    let slowest = ExposureDuration.clamped(seconds: max.seconds, min: min, max: max)
    #expect(slowest <= max && slowest >= min)
    let fifteenth = CMTime(value: 1, timescale: 15)
    let limit = ExposureDuration.clamped(seconds: 1.0 / 15, min: min, max: fifteenth)
    #expect(limit <= fifteenth && limit >= min)
  }

  @Test func aDurationInsideTheRangeKeepsNanosecondPrecision() {
    let time = ExposureDuration.clamped(seconds: 1.0 / 250, min: min, max: max)
    #expect(time.timescale == 1_000_000_000)
    #expect(time.value == 4_000_000)
  }

  @Test func outsideTheRangeTheNearestLimitIsReturned() {
    #expect(ExposureDuration.clamped(seconds: 1.0 / 1_000_000, min: min, max: max) == min)
    #expect(ExposureDuration.clamped(seconds: 2, min: min, max: max) == max)
    #expect(ExposureDuration.clamped(seconds: .nan, min: min, max: max) == min)
    #expect(ExposureDuration.clamped(seconds: -1, min: min, max: max) == min)
  }

  @Test func aRangeWithItsLimitsReversedReturnsTheMinimum() {
    #expect(ExposureDuration.clamped(seconds: 0.1, min: max, max: min) == max)
  }
}

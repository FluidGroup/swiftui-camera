import Foundation

/// Priority exposure on a device without native priority modes: one parameter stays fixed and the
/// other moves by the metered offset. `offset` is `exposureTargetOffset`, EV above the target, so
/// a positive offset means the frame is too bright and the free parameter comes down.
enum ExposureSteering {
  static let deadBand = 1.0 / 6.0

  static func iso(holding current: ISO, offset: Double, range: ClosedRange<ISO>) -> ISO? {
    steered(current.rawValue, offset: offset, range: range.lowerBound.rawValue...range.upperBound.rawValue).map(ISO.init)
  }

  static func shutterSpeed(holding current: ShutterSpeed, offset: Double, range: ClosedRange<ShutterSpeed>) -> ShutterSpeed? {
    steered(current.rawValue, offset: offset, range: range.lowerBound.rawValue...range.upperBound.rawValue).map(ShutterSpeed.init)
  }

  private static func steered(_ current: Double, offset: Double, range: ClosedRange<Double>) -> Double? {
    guard offset.isFinite, abs(offset) > deadBand, current > 0 else { return nil }
    let next = (current / pow(2, offset)).clamped(to: range)
    guard abs(next - current) / current > 0.01 else { return nil }
    return next
  }
}

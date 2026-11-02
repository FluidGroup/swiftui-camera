import CoreMedia

enum ExposureDuration {
  /// `seconds` as a `CMTime` inside `min...max`, clamped in `CMTime` space. The limits are exact
  /// rationals (1/128000 s), and converting them through seconds lands a nanosecond outside the
  /// range, which `setExposureModeCustom` rejects with `NSRangeException`; the format's own
  /// `CMTime` is always accepted.
  static func clamped(seconds: Double, min: CMTime, max: CMTime) -> CMTime {
    guard min <= max else { return min }
    let time = CMTime(seconds: seconds, preferredTimescale: 1_000_000_000)
    guard time.isNumeric else { return min }
    if time <= min { return min }
    if time >= max { return max }
    return time
  }
}

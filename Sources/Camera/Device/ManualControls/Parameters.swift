import Foundation

public struct ISO: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.logarithmic
  private static let nominal: [Double] = [
    25, 32, 40, 50, 64, 80, 100, 125, 160, 200, 250, 320, 400, 500, 640, 800, 1000, 1250, 1600,
    2000, 2500, 3200, 4000, 5000, 6400, 8000, 10000, 12800, 16000, 20000, 25600,
  ]

  /// Third stops: 25, 32, 40, 50, 64, 80, 100, 125, 160, 200, ... 25600, plus the range's own
  /// limits when a limit is more than 1/6 stop from the nearest of them.
  public static func stops(in range: ClosedRange<ISO>) -> [ISO] {
    StopSeries.logarithmic(nominal, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(ISO.init)
  }

  public func formatted() -> String { "ISO " + Notation.fixed(rawValue, decimals: 0) }
}

/// Exposure duration in seconds.
public struct ShutterSpeed: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.logarithmic
  private static let nominal: [Double] =
    [
      128000, 100000, 80000, 64000, 50000, 40000, 32000, 25600, 20000, 16000, 12800, 10000,
      8000, 6400, 5000, 4000, 3200, 2500, 2000, 1600, 1250, 1000, 800, 640, 500, 400, 320, 250,
      200, 160, 125, 100, 80, 60, 50, 40, 30, 25, 20, 15, 13, 10, 8, 6, 5, 4, 3,
    ].map { 1 / $0 }
    + [0.4, 0.5, 0.6, 0.8, 1, 1.3, 1.6, 2, 2.5, 3.2, 4, 5, 6, 8, 10, 13, 15, 20, 25, 30]

  /// The third-stop series photographers know: 1/8000 ... 1/250, 1/200, 1/160 ... 30", continued
  /// below 1/8000 for devices with faster exposure durations, plus the range's own limits when a
  /// limit is more than 1/6 stop from the nearest of them.
  public static func stops(in range: ClosedRange<ShutterSpeed>) -> [ShutterSpeed] {
    StopSeries.logarithmic(nominal, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(ShutterSpeed.init)
  }

  /// "1/250" below 0.3 s, then seconds with at most one decimal: `0.3"`, `1"`, `1.3"`.
  public func formatted() -> String {
    guard rawValue > 0 else { return "0\"" }
    if rawValue < 0.3 { return "1/" + Notation.fixed(1 / rawValue, decimals: 0) }
    return Notation.compact(rawValue) + "\""
  }
}

/// Exposure compensation in EV.
public struct ExposureBias: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.linear
  /// Multiples of 1/3 EV, plus the range's own limits when a limit is more than 1/6 EV from the
  /// nearest of them.
  public static func stops(in range: ClosedRange<ExposureBias>) -> [ExposureBias] {
    StopSeries.multiples(numerator: 1, denominator: 3, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(ExposureBias.init)
  }

  public func formatted() -> String { Notation.signed(rawValue, decimals: 1) }
}

/// White-balance color temperature.
public struct Kelvin: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.reciprocal
  static let presets: [Double] = [3200, 4000, 5500, 6500, 7500]

  /// 10-mired steps across the range, rounded to the nearest 50 K and merged with the presets.
  /// A step within 5 mireds of a preset is dropped in the preset's favor. The range's own limits
  /// are added when a limit is more than 5 mireds from the nearest stop.
  public static func stops(in range: ClosedRange<Kelvin>) -> [Kelvin] {
    let lo = range.lowerBound.rawValue
    let hi = range.upperBound.rawValue
    guard lo > 0, lo <= hi else {
      return StopSeries.spanning([], lo: lo, hi: hi, halfStep: 5) { $0 - $1 }.map(Kelvin.init)
    }
    let mired = { (kelvin: Double) in 1e6 / kelvin }
    let inRange = presets.filter { $0 >= lo && $0 <= hi }
    let epsilon = StopSeries.epsilon
    let first = max(1, Int((mired(hi) / 10 - epsilon).rounded(.up)))
    let last = Int((mired(lo) / 10 + epsilon).rounded(.down))
    var stops = Set(inRange)
    if first <= last {
      for step in first...last {
        let m = Double(step) * 10
        if inRange.contains(where: { abs(mired($0) - m) <= 5 + epsilon }) { continue }
        let kelvin = (mired(m) / 50).rounded() * 50
        if kelvin >= lo && kelvin <= hi { stops.insert(kelvin) }
      }
    }
    return StopSeries.spanning(stops.sorted(), lo: lo, hi: hi, halfStep: 5) { mired($0) - mired($1) }.map(Kelvin.init)
  }

  /// The nearest 10 K: "5600K".
  public func formatted() -> String { Notation.fixed((rawValue / 10).rounded() * 10, decimals: 0) + "K" }
}

/// White-balance tint, green (negative) to magenta (positive).
public struct Tint: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.linear
  /// Multiples of 10, plus the range's own limits when a limit is more than 5 from the nearest.
  public static func stops(in range: ClosedRange<Tint>) -> [Tint] {
    StopSeries.multiples(numerator: 10, denominator: 1, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(Tint.init)
  }

  public func formatted() -> String { Notation.signed(rawValue, decimals: 0) }
}

/// Lens position, 0 (nearest) to 1 (farthest), as `AVCaptureDevice.lensPosition` reports it.
public struct LensPosition: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.linear
  /// Multiples of 0.05, plus the range's own limits when a limit is more than 0.025 from the
  /// nearest.
  public static func stops(in range: ClosedRange<LensPosition>) -> [LensPosition] {
    StopSeries.multiples(numerator: 1, denominator: 20, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(LensPosition.init)
  }

  public func formatted() -> String { Notation.fixed(rawValue, decimals: 2) }
}

/// Zoom on the Camera app's scale (display zoom), not the device's `videoZoomFactor`.
public struct ZoomFactor: CameraParameter, Codable {
  public var rawValue: Double
  public init(_ rawValue: Double) { self.rawValue = rawValue }
  public static let scale = ParameterScale.logarithmic
  private static let anchors: [Double] = [0.5, 1, 2, 3, 5, 10, 15, 25]

  private static let nominal: [Double] = {
    var values = anchors
    for (low, high) in zip(anchors, anchors.dropFirst()) {
      var step = 1
      while true {
        let value = low * pow(2, Double(step) / 6)
        guard value < high else { break }
        step += 1
        let rounded = value.rounded(toDecimals: 1)
        let nearAnchor = anchors.contains { abs(log2(rounded / $0)) <= 1.0 / 12 }
        if !nearAnchor && !values.contains(rounded) { values.append(rounded) }
      }
    }
    return values.sorted()
  }()

  /// The Camera app's anchors 0.5, 1, 2, 3, 5, 10, 15, 25 with 1/6-stop steps between them, plus
  /// the range's own limits when a limit is more than 1/6 stop from the nearest of them.
  public static func stops(in range: ClosedRange<ZoomFactor>) -> [ZoomFactor] {
    StopSeries.logarithmic(nominal, lo: range.lowerBound.rawValue, hi: range.upperBound.rawValue).map(ZoomFactor.init)
  }

  /// "0.5×", "1×", "2.4×".
  public func formatted() -> String { Notation.compact(rawValue) + "×" }
}

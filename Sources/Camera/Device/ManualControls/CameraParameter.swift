import Foundation

public enum ParameterScale: Sendable, Hashable {
  /// Exposure bias, tint, lens position.
  case linear
  /// ISO, shutter speed, zoom. Equal slider steps are equal stops.
  case logarithmic
  /// Color temperature. Equal slider steps are equal mireds.
  case reciprocal
}

/// A camera parameter in its own unit.
public protocol CameraParameter: Sendable, Hashable, Comparable {
  init(_ rawValue: Double)
  var rawValue: Double { get }
  static var scale: ParameterScale { get }
  /// Conventional stops inside `range`: detents, Camera Control values, tick marks.
  static func stops(in range: ClosedRange<Self>) -> [Self]
  /// Camera notation: "ISO 400", "1/250", "0.5\"", "5600K", "+0.7", "2×".
  func formatted() -> String
}

extension CameraParameter {
  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }

  /// `value` on this parameter's perceptual scale: 0 at `range.lowerBound`, 1 at the upper.
  /// A degenerate range gives 0, and a logarithmic or reciprocal scale over a range that is not
  /// positive falls back to linear.
  public static func position(of value: Self, in range: ClosedRange<Self>) -> Double {
    let lo = range.lowerBound.rawValue
    let hi = range.upperBound.rawValue
    let v = value.rawValue
    guard hi > lo, !v.isNaN else { return 0 }
    let position: Double
    switch effectiveScale(lo: lo) {
    case .linear:
      position = (v - lo) / (hi - lo)
    case .logarithmic:
      position = v > 0 ? log2(v / lo) / log2(hi / lo) : 0
    case .reciprocal:
      position = v > 0 ? (1 / lo - 1 / v) / (1 / lo - 1 / hi) : 0
    }
    return position.isFinite ? min(max(position, 0), 1) : (position > 0 ? 1 : 0)
  }

  /// The inverse of `position(of:in:)`. A position outside 0...1 is clamped, so the result is
  /// always inside `range`.
  public static func value(at position: Double, in range: ClosedRange<Self>) -> Self {
    let lo = range.lowerBound.rawValue
    let hi = range.upperBound.rawValue
    guard hi > lo, !position.isNaN else { return range.lowerBound }
    let p = min(max(position, 0), 1)
    if p == 0 { return range.lowerBound }
    if p == 1 { return range.upperBound }
    let raw: Double
    switch effectiveScale(lo: lo) {
    case .linear:
      raw = lo + p * (hi - lo)
    case .logarithmic:
      raw = lo * pow(hi / lo, p)
    case .reciprocal:
      raw = 1 / (1 / lo - p * (1 / lo - 1 / hi))
    }
    return Self(raw.isFinite ? min(max(raw, lo), hi) : lo)
  }

  private static func effectiveScale(lo: Double) -> ParameterScale {
    lo > 0 ? scale : .linear
  }
}

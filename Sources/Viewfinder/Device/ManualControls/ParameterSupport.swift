import Foundation

/// Locale-independent camera notation. `String(format:)` formats with a POSIX locale, so the
/// decimal separator is always ".".
enum Notation {
  static func fixed(_ value: Double, decimals: Int) -> String {
    String(format: "%.\(decimals)f", value.rounded(toDecimals: decimals))
  }

  static func compact(_ value: Double) -> String {
    let rounded = value.rounded(toDecimals: 1)
    return rounded == rounded.rounded() ? fixed(rounded, decimals: 0) : fixed(rounded, decimals: 1)
  }

  static func signed(_ value: Double, decimals: Int) -> String {
    let rounded = value.rounded(toDecimals: decimals)
    if rounded == 0 { return fixed(0, decimals: decimals) }
    return (rounded > 0 ? "+" : "\u{2212}") + fixed(abs(rounded), decimals: decimals)
  }
}

extension Double {
  /// Rounds half away from zero. Never returns -0.
  func rounded(toDecimals decimals: Int) -> Double {
    let factor = pow(10.0, Double(decimals))
    return (self * factor).rounded() / factor + 0
  }
}

enum StopSeries {
  static let epsilon = 1e-9

  static let halfThirdStop = 1.0 / 6.0

  static func stopsBetween(_ low: Double, _ high: Double) -> Double {
    guard low > 0, high > 0 else { return .infinity }
    return log2(high / low)
  }

  static func spanning(
    _ nominal: [Double],
    lo: Double,
    hi: Double,
    halfStep: Double,
    distance: (Double, Double) -> Double
  ) -> [Double] {
    guard lo <= hi else { return [] }
    var stops = nominal.filter { $0 >= lo && $0 <= hi }.sorted()
    guard let first = stops.first, let last = stops.last else {
      return lo == hi ? [lo] : [lo, hi]
    }
    if distance(lo, first) > halfStep + epsilon { stops.insert(lo, at: 0) }
    if distance(last, hi) > halfStep + epsilon { stops.append(hi) }
    return stops
  }

  static func logarithmic(_ nominal: [Double], lo: Double, hi: Double) -> [Double] {
    spanning(nominal, lo: lo, hi: hi, halfStep: halfThirdStop, distance: stopsBetween)
  }

  static func multiples(numerator: Int, denominator: Int, lo: Double, hi: Double) -> [Double] {
    let step = Double(numerator) / Double(denominator)
    let limit = 1e6
    guard lo <= hi, abs(lo) < limit, abs(hi) < limit else { return spanning([], lo: lo, hi: hi, halfStep: step / 2) { $1 - $0 } }
    let first = Int((lo / step - epsilon).rounded(.up))
    let last = Int((hi / step + epsilon).rounded(.down))
    let nominal = first <= last
      ? (first...last).map { min(max(Double($0 * numerator) / Double(denominator), lo), hi) }
      : []
    return spanning(nominal, lo: lo, hi: hi, halfStep: step / 2) { $1 - $0 }
  }
}

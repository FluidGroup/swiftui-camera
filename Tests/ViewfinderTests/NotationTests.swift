import Testing

@testable import Viewfinder

struct NotationTests {
  static let isoCases: [(Double, String)] = [
    (25.0, "ISO 25"), (400, "ISO 400"), (399.6, "ISO 400"), (12800, "ISO 12800"),
  ]

  @Test(arguments: isoCases)
  func isoShowsAnIntegerWithAPrefix(value: Double, expected: String) {
    #expect(ISO(value).formatted() == expected)
  }

  static let shutterCases: [(Double, String)] = [
    (1.0 / 8000, "1/8000"), (1.0 / 250, "1/250"), (1.0 / 13, "1/13"), (0.25, "1/4"), (1.0 / 128_000, "1/128000"),
    (1.0 / 3, "0.3\""), (0.3, "0.3\""), (0.5, "0.5\""), (1, "1\""), (1.3, "1.3\""), (2.5, "2.5\""), (30, "30\""),
    (0.95, "1\""),
  ]

  @Test(arguments: shutterCases)
  func shutterSpeedUsesFractionsBelowThreeTenthsAndSecondsAbove(seconds: Double, expected: String) {
    #expect(ShutterSpeed(seconds).formatted() == expected)
  }

  static let biasCases: [(Double, String)] = [
    (0.7, "+0.7"), (2.0 / 3, "+0.7"), (-1.0 / 3, "\u{2212}0.3"), (0, "0.0"), (-0.04, "0.0"), (0.04, "0.0"),
    (-0.06, "\u{2212}0.1"), (8, "+8.0"), (-8, "\u{2212}8.0"),
  ]

  @Test(arguments: biasCases)
  func exposureBiasHasOneDecimalAndAnExplicitSign(value: Double, expected: String) {
    #expect(ExposureBias(value).formatted() == expected)
  }

  static let kelvinCases: [(Double, String)] = [(5600.0, "5600K"), (5604, "5600K"), (5605, "5610K"), (2000, "2000K"), (10000, "10000K")]

  @Test(arguments: kelvinCases)
  func kelvinRoundsToTenKelvin(value: Double, expected: String) {
    #expect(Kelvin(value).formatted() == expected)
  }

  static let tintCases: [(Double, String)] = [(12.0, "+12"), (-5, "\u{2212}5"), (0, "0"), (-0.4, "0"), (0.4, "0"), (-150, "\u{2212}150")]

  @Test(arguments: tintCases)
  func tintHasAnIntegerAndAnExplicitSign(value: Double, expected: String) {
    #expect(Tint(value).formatted() == expected)
  }

  static let lensPositionCases: [(Double, String)] = [(0.5, "0.50"), (0.0, "0.00"), (1, "1.00"), (0.333, "0.33"), (-0.001, "0.00")]

  @Test(arguments: lensPositionCases)
  func lensPositionHasTwoDecimals(value: Double, expected: String) {
    #expect(LensPosition(value).formatted() == expected)
  }

  static let zoomCases: [(Double, String)] = [(0.5, "0.5×"), (1.0, "1×"), (2.4, "2.4×"), (2.04, "2×"), (10, "10×"), (14.1, "14.1×"), (25, "25×")]

  @Test(arguments: zoomCases)
  func zoomFactorDropsATrailingZeroDecimal(value: Double, expected: String) {
    #expect(ZoomFactor(value).formatted() == expected)
  }

  static let lensLabelCases: [(Double, String)] = [(0.5, "0.5×"), (1.0, "1×"), (2.0, "2×"), (5.0, "5×")]

  @Test(arguments: lensLabelCases)
  func lensLabelMatchesTheZoomFactor(displayZoom: Double, expected: String) {
    let lens = CameraLens(id: "x", position: .back, kind: .wide, displayZoom: displayZoom)
    #expect(lens.label == expected)
  }

  @Test(arguments: [
    (4032, 3024, "12 MP"), (8064, 6048, "49 MP"), (8000, 6000, "48 MP"), (1280, 720, "0.9 MP"), (640, 480, "0.3 MP"),
    (1000, 1000, "1 MP"),
  ])
  func photoResolutionLabelsMegapixels(width: Int, height: Int, expected: String) {
    #expect(PhotoResolution(width: width, height: height).label == expected)
  }

  @Test func manualControlFormatsItsValue() {
    let control = ManualControl(value: ISO(640), range: ISO(25)...ISO(6400))
    #expect(control.formatted() == "ISO 640")
  }

  static let flipCases: [(CameraPosition, CameraPosition)] = [(.back, .front), (.front, .back), (.unspecified, .unspecified)]

  @Test(arguments: flipCases)
  func flipSwapsFrontAndBack(start: CameraPosition, expected: CameraPosition) {
    var position = start
    position.flip()
    #expect(position == expected)
  }
}

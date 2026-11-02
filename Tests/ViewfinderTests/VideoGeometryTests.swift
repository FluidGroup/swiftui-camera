import CoreGraphics
import Testing

@testable import Viewfinder

struct VideoGeometryTests {
  private let portrait = CGSize(width: 3, height: 4)
  private let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)

  @Test func fitLetterboxesAndFillOverflows() {
    #expect(VideoGeometry.rect(videoAspect: portrait, in: bounds, fills: false) == CGRect(x: 37.5, y: 0, width: 225, height: 300))
    #expect(VideoGeometry.rect(videoAspect: portrait, in: bounds, fills: true) == CGRect(x: 0, y: -50, width: 300, height: 400))
  }

  @Test func theCenterIsTheCenterAndPointsRoundTrip() {
    let rect = CGRect(x: 10, y: 20, width: 300, height: 400)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 160, y: 220), in: rect) == .center)
    #expect(VideoGeometry.viewPoint(from: .center, in: rect) == CGPoint(x: 160, y: 220))
    for point in [CGPoint(x: 10, y: 20), CGPoint(x: 310, y: 420), CGPoint(x: 100, y: 300)] {
      let back = VideoGeometry.viewPoint(from: VideoGeometry.devicePoint(from: point, in: rect), in: rect)
      #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
    }
  }

  @Test func theSensorsOriginIsTheViewsTopRight() {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 300, y: 0), in: rect) == DevicePoint(x: 0, y: 0))
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 0, y: 400), in: rect) == DevicePoint(x: 1, y: 1))
  }
}

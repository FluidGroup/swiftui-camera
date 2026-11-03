import CoreGraphics
import Testing

@testable import Viewfinder

struct VideoGeometryTests {
  private let portrait = CGSize(width: 3, height: 4)
  private let bounds = CGRect(x: 0, y: 0, width: 300, height: 300)
  private let backCameraInPortrait = FrameOrientation(quarterTurns: 1, isMirrored: false)
  private let frontCameraInPortrait = FrameOrientation(quarterTurns: 1, isMirrored: true)

  private static let everyOrientation = [0, 1, 2, 3].flatMap { turns in
    [false, true].map { FrameOrientation(quarterTurns: turns, isMirrored: $0) }
  }

  @Test func fitLetterboxesAndFillOverflows() {
    #expect(VideoGeometry.rect(videoAspect: portrait, in: bounds, fills: false) == CGRect(x: 37.5, y: 0, width: 225, height: 300))
    #expect(VideoGeometry.rect(videoAspect: portrait, in: bounds, fills: true) == CGRect(x: 0, y: -50, width: 300, height: 400))
  }

  @Test(arguments: everyOrientation)
  func theCenterIsTheCenterAndPointsRoundTrip(orientation: FrameOrientation) {
    let rect = CGRect(x: 10, y: 20, width: 300, height: 400)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 160, y: 220), in: rect, orientation: orientation) == .center)
    #expect(VideoGeometry.viewPoint(from: .center, in: rect, orientation: orientation) == CGPoint(x: 160, y: 220))
    for point in [CGPoint(x: 10, y: 20), CGPoint(x: 310, y: 420), CGPoint(x: 100, y: 300)] {
      let device = VideoGeometry.devicePoint(from: point, in: rect, orientation: orientation)
      let back = VideoGeometry.viewPoint(from: device, in: rect, orientation: orientation)
      #expect(abs(back.x - point.x) < 1e-9 && abs(back.y - point.y) < 1e-9)
    }
  }

  @Test func theBackCamerasSensorOriginIsTheViewsTopRightInPortrait() {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 300, y: 0), in: rect, orientation: backCameraInPortrait) == DevicePoint(x: 0, y: 0))
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 0, y: 400), in: rect, orientation: backCameraInPortrait) == DevicePoint(x: 1, y: 1))
  }

  @Test func aMirroredPreviewFlipsTheSensorOriginToTheTopLeft() {
    let rect = CGRect(x: 0, y: 0, width: 300, height: 400)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 0, y: 0), in: rect, orientation: frontCameraInPortrait) == DevicePoint(x: 0, y: 0))
  }

  @Test func anUnturnedFrameMapsStraightThrough() {
    let rect = CGRect(x: 0, y: 0, width: 400, height: 300)
    #expect(VideoGeometry.devicePoint(from: CGPoint(x: 100, y: 225), in: rect, orientation: .identity) == DevicePoint(x: 0.25, y: 0.75))
  }

  @Test func angleRoundsToTheNearestQuarterTurn() {
    #expect(FrameOrientation(angle: 90, isMirrored: false).quarterTurns == 1)
    #expect(FrameOrientation(angle: 270, isMirrored: false).quarterTurns == 3)
    #expect(FrameOrientation(angle: 360, isMirrored: false).quarterTurns == 0)
    #expect(FrameOrientation(angle: -90, isMirrored: false).quarterTurns == 3)
  }
}

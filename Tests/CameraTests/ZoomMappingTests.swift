import Testing

@testable import Camera

struct ZoomMappingTests {
  private let ultraWide = CameraLens(id: "uw", position: .back, kind: .ultraWide, displayZoom: 0.5)
  private let wide = CameraLens(id: "w", position: .back, kind: .wide, displayZoom: 1)
  private let crop = CameraLens(id: "w.crop2", deviceID: "w", position: .back, kind: .wide, crop: 2, displayZoom: 2)
  private let telephoto = CameraLens(id: "t", position: .back, kind: .telephoto, displayZoom: 5)

  @Test func eachLensSitsAtItsOwnStopAtFactorOneOrItsCrop() {
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 1, lens: wide) == 1)
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 0.5, lens: ultraWide) == 1)
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 5, lens: telephoto) == 1)
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 2, lens: crop) == 2)
  }

  @Test func zoomingPastAStopScalesTheDeviceFactor() {
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 3, lens: wide) == 3)
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 0.7, lens: ultraWide) == 1.4)
    #expect(ZoomMapping.videoZoomFactor(displayZoom: 10, lens: telephoto) == 2)
  }

  @Test func readingsRoundTrip() {
    for lens in [ultraWide, wide, crop, telephoto] {
      for zoom in [0.5, 1.0, 2.0, 3.3, 10.0] {
        let factor = ZoomMapping.videoZoomFactor(displayZoom: zoom, lens: lens)
        #expect(abs(ZoomMapping.displayZoom(videoZoomFactor: factor, lens: lens) - zoom) < 1e-9)
      }
    }
  }

  @Test func noIntentMeansTheLensStop() {
    #expect(ZoomMapping.target(nil, lens: telephoto) == ZoomFactor(5))
    #expect(ZoomMapping.target(ZoomFactor(7), lens: telephoto) == ZoomFactor(7))
  }

  @Test func theDeviceFactorStaysInsideTheDeviceRange() {
    #expect(ZoomMapping.deviceFactor(for: ZoomFactor(0.1), lens: wide, deviceRange: 1...6) == 1)
    #expect(ZoomMapping.deviceFactor(for: ZoomFactor(50), lens: wide, deviceRange: 1...6) == 6)
    #expect(ZoomMapping.deviceFactor(for: nil, lens: crop, deviceRange: 1...6) == 2)
  }

  @Test func theDisplayRangeFollowsTheLens() {
    let range = ZoomMapping.displayRange(deviceRange: 1...6, lens: telephoto)
    #expect(range == ZoomFactor(5)...ZoomFactor(30))
  }
}

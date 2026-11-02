enum ZoomMapping {
  static func videoZoomFactor(displayZoom: Double, lens: CameraLens) -> Double {
    displayZoom * lens.crop / lens.displayZoom
  }

  static func displayZoom(videoZoomFactor: Double, lens: CameraLens) -> Double {
    videoZoomFactor * lens.displayZoom / lens.crop
  }

  static func target(_ zoom: ZoomFactor?, lens: CameraLens) -> ZoomFactor {
    zoom ?? ZoomFactor(lens.displayZoom)
  }

  static func deviceFactor(for zoom: ZoomFactor?, lens: CameraLens, deviceRange: ClosedRange<Double>) -> Double {
    videoZoomFactor(displayZoom: target(zoom, lens: lens).rawValue, lens: lens).clamped(to: deviceRange)
  }

  static func displayRange(deviceRange: ClosedRange<Double>, lens: CameraLens) -> ClosedRange<ZoomFactor> {
    ZoomFactor(displayZoom(videoZoomFactor: deviceRange.lowerBound, lens: lens))
      ... ZoomFactor(displayZoom(videoZoomFactor: deviceRange.upperBound, lens: lens))
  }
}

extension Comparable {
  func clamped(to range: ClosedRange<Self>) -> Self {
    min(max(self, range.lowerBound), range.upperBound)
  }
}

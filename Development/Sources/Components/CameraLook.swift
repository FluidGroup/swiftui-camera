/// A look the capture carousel offers. The gallery shows it as a Core Image filter on the preview;
/// photos stay as captured.
struct CameraLook: Hashable, Identifiable {
  let id: String
  let name: String
  let symbol: String
  let filterName: String

  static let samples: [CameraLook] = [
    CameraLook(id: "prism", name: "PRISM", symbol: "triangle", filterName: "CIPhotoEffectChrome"),
    CameraLook(id: "retro", name: "RETRO", symbol: "rectangle.bottomhalf.filled", filterName: "CISepiaTone"),
    CameraLook(id: "aurora", name: "AURORA", symbol: "sparkles", filterName: "CIPhotoEffectInstant"),
    CameraLook(id: "grain", name: "GRAIN", symbol: "circle.dotted", filterName: "CIPhotoEffectNoir"),
  ]
}

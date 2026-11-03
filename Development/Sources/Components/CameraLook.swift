/// A look the capture carousel offers. The components draw only its icon and name; what a look
/// does to the photo is up to the screen that uses it.
struct CameraLook: Hashable, Identifiable {
  let id: String
  let name: String
  let symbol: String

  static let samples: [CameraLook] = [
    CameraLook(id: "prism", name: "PRISM", symbol: "triangle"),
    CameraLook(id: "retro", name: "RETRO", symbol: "rectangle.bottomhalf.filled"),
    CameraLook(id: "aurora", name: "AURORA", symbol: "sparkles"),
    CameraLook(id: "grain", name: "GRAIN", symbol: "circle.dotted"),
  ]
}

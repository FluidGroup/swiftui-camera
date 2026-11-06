import Foundation

enum LensResolution {
  static func position(requested: CameraPosition, available: [CameraPosition]) -> CameraPosition {
    guard let first = available.first, !available.contains(requested) else { return requested }
    return available.contains(.unspecified) ? .unspecified : first
  }

  static func defaultLens(at position: CameraPosition, in lenses: [CameraLens], preferredID: CameraLens.ID? = nil) -> CameraLens? {
    let candidates = lenses.filter { $0.position == position }
    if let preferredID, let preferred = candidates.first(where: { $0.id == preferredID }) {
      return preferred
    }
    let fullSensor = candidates.filter { $0.crop == 1 }
    if let wide = fullSensor.first(where: { $0.kind == .wide }) {
      return wide
    }
    return fullSensor.min { abs(log($0.displayZoom)) < abs(log($1.displayZoom)) } ?? candidates.first
  }

  /// The intent's lens when it's discovered at the position the intent resolves to, else that
  /// position's default. A lens ID from another position doesn't count, so a decoded or hand-made
  /// lens that disagrees with its position lands where the position says.
  static func lens(for intent: DeviceIntent, in lenses: [CameraLens], preferredID: CameraLens.ID? = nil) -> CameraLens? {
    let position = position(requested: intent.position, available: positions(of: lenses))
    if let id = intent.lensID, let lens = lenses.first(where: { $0.id == id && $0.position == position }) {
      return lens
    }
    return defaultLens(at: position, in: lenses, preferredID: preferredID)
  }

  static func positions(of lenses: [CameraLens]) -> [CameraPosition] {
    var seen: Set<CameraPosition> = []
    return lenses.map(\.position).filter { seen.insert($0).inserted }
  }
}

struct PhysicalCameraFacts: Sendable, Hashable {
  let id: String
  let position: CameraPosition
  let kind: CameraLens.Kind
  let switchOverZoom: Double
  let displayMultiplier: Double
  let largestPhotoMegapixels: Double
}

enum LensDiscovery {
  static func lenses(from facts: [PhysicalCameraFacts], selection: LensSelection) -> [CameraLens] {
    let positions: [CameraPosition] = [.back, .front, .unspecified]
    var lenses: [CameraLens] = []

    for position in positions {
      let atPosition = facts.filter { $0.position == position }
      let builtIn = atPosition.filter { $0.kind != .external }
      let external = atPosition.filter { $0.kind == .external }

      let selected: [PhysicalCameraFacts]
      if selection.includesEveryPhysicalCamera {
        selected = atPosition
      } else {
        let wide = builtIn.filter { $0.kind == .wide }
        let main = (wide.isEmpty ? builtIn : wide).lowestDisplayZoom
        selected = (main.map { [$0] } ?? []) + external
      }
      lenses += selected.map { lens($0, crop: 1, displayZoom: $0.displayZoom) }

      if selection.includesCrops, let crop = cropLens(among: atPosition) {
        lenses.append(crop)
      }
    }

    return lenses.sorted {
      ($0.position.sortOrder, $0.displayZoom, $0.crop, $0.id) < ($1.position.sortOrder, $1.displayZoom, $1.crop, $1.id)
    }
  }

  private static func cropLens(among atPosition: [PhysicalCameraFacts]) -> CameraLens? {
    guard let wide = atPosition.filter({ $0.kind == .wide }).lowestDisplayZoom,
      wide.largestPhotoMegapixels >= 40
    else { return nil }
    let cropZoom = wide.displayZoom * 2
    guard !atPosition.contains(where: { abs($0.displayZoom - cropZoom) <= 0.05 }) else { return nil }
    return lens(wide, crop: 2, displayZoom: cropZoom)
  }

  private static func lens(_ facts: PhysicalCameraFacts, crop: Double, displayZoom: Double) -> CameraLens {
    CameraLens(
      id: crop == 1 ? facts.id : "\(facts.id).crop2",
      deviceID: facts.id,
      position: facts.position,
      kind: facts.kind,
      crop: crop,
      displayZoom: displayZoom
    )
  }
}

extension PhysicalCameraFacts {
  var displayZoom: Double { switchOverZoom * displayMultiplier }
}

extension Collection<PhysicalCameraFacts> {
  fileprivate var lowestDisplayZoom: PhysicalCameraFacts? {
    self.min { ($0.displayZoom, $0.id) < ($1.displayZoom, $1.id) }
  }
}

extension CameraPosition {
  fileprivate var sortOrder: Int {
    switch self {
    case .back: 0
    case .front: 1
    case .unspecified: 2
    }
  }
}

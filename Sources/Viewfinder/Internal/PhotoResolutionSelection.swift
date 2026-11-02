extension ResolutionPreference {
  private static let standardPixelLimit = 12_500_000

  func resolve(in resolutions: [PhotoResolution]) -> PhotoResolution? {
    switch self {
    case .standard:
      resolutions.last { $0.pixelCount <= Self.standardPixelLimit } ?? resolutions.first
    case .full:
      resolutions.last
    }
  }
}

extension PhotoResolution {
  var pixelCount: Int { width * height }
}

enum PhotoResolutionSelection {
  /// AVFoundation serves 24 MP only through deferred photo delivery, which the library never
  /// enables, so this size is never offered.
  static let deferredDeliveryOnly = PhotoResolution(width: 5712, height: 4284)

  static func resolutions(from sizes: [PhotoResolution]) -> [PhotoResolution] {
    Set(sizes)
      .subtracting([deferredDeliveryOnly])
      .sorted { ($0.pixelCount, $0.width) < ($1.pixelCount, $1.width) }
  }

  /// The sizes a lens offers from its camera's sizes. A crop only covers the standard size's
  /// sensor area; AVFoundation would upscale it to reach a larger size.
  static func offered(_ resolutions: [PhotoResolution], crop: Double) -> [PhotoResolution] {
    crop > 1 ? ResolutionPreference.standard.resolve(in: resolutions).map { [$0] } ?? [] : resolutions
  }
}

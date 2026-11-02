import Foundation

public enum CameraPosition: Sendable, Hashable, Codable {
  case back
  case front
  /// The system default device: built-in and external cameras on macOS, Continuity Camera.
  case unspecified

  /// Swaps front and back. `.unspecified` stays as it is.
  public mutating func flip() {
    switch self {
    case .back: self = .front
    case .front: self = .back
    case .unspecified: break
    }
  }
}

/// One selectable camera, labeled the way the Camera app labels it.
///
/// A lens is a physical camera or a center crop of one. The library never connects a virtual
/// multi-camera device, because full-resolution Apple ProRAW comes only from a physical camera.
public struct CameraLens: Sendable, Hashable, Identifiable, Codable {
  public enum Kind: Sendable, Hashable, Codable {
    case ultraWide
    case wide
    case telephoto
    case external
  }

  public let id: String
  let deviceID: String
  public let position: CameraPosition
  public let kind: Kind
  /// 1 for the full sensor, 2 for a center crop of the same camera.
  public let crop: Double
  /// Zoom on the Camera app's scale: 0.5, 1, 2, 5.
  public let displayZoom: Double

  public init(id: String, position: CameraPosition, kind: Kind, crop: Double = 1, displayZoom: Double) {
    self.init(id: id, deviceID: id, position: position, kind: kind, crop: crop, displayZoom: displayZoom)
  }

  init(id: String, deviceID: String, position: CameraPosition, kind: Kind, crop: Double, displayZoom: Double) {
    self.id = id
    self.deviceID = deviceID
    self.position = position
    self.kind = kind
    self.crop = crop
    self.displayZoom = displayZoom
  }

  /// "0.5×", "1×", "2×", "5×".
  public var label: String {
    ZoomFactor(displayZoom).formatted()
  }
}

/// Which lenses a camera offers at each position.
public struct LensSelection: Sendable, Hashable {
  let includesEveryPhysicalCamera: Bool
  let includesCrops: Bool

  /// The wide camera at each position.
  public static let wide = LensSelection(includesEveryPhysicalCamera: false, includesCrops: false)

  /// Every physical camera, plus a 2× crop of a 40 MP or larger main camera when no physical
  /// camera already sits at 2×.
  public static func physical(includingCrops: Bool = true) -> LensSelection {
    LensSelection(includesEveryPhysicalCamera: true, includesCrops: includingCrops)
  }
}

/// A point in the capture device's normalized space: (0, 0) is the top left of the unrotated
/// sensor and (1, 1) the bottom right. Only `CameraPreviewProxy` converts between this and view
/// points.
public struct DevicePoint: Sendable, Hashable, Codable {
  public var x: Double
  public var y: Double

  public static let center = DevicePoint(x: 0.5, y: 0.5)

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public enum Mirroring: Sendable, Hashable {
  /// Front-camera captures are mirrored like the preview, so what you see is what you save.
  case matchesPreview
  /// Captures keep the sensor's orientation. Only the preview is mirrored.
  case unmirrored
}

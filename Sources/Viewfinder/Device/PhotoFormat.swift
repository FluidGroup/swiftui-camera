import Foundation

public enum PhotoFormat: Sendable, Hashable {
  case jpeg
  case heif
  case appleProRAW

  /// "JPEG", "HEIF", "ProRAW".
  public var label: String {
    switch self {
    case .jpeg: "JPEG"
    case .heif: "HEIF"
    case .appleProRAW: "ProRAW"
    }
  }
}

public enum FlashMode: Sendable, Hashable, Codable {
  case off
  case on
  case auto
}

public struct PhotoResolution: Sendable, Hashable, Identifiable {
  public let width: Int
  public let height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public var id: Int { width * height }
  /// "12 MP", "48 MP". Below 1 MP, one decimal: "0.3 MP".
  public var label: String {
    let megapixels = Double(width) * Double(height) / 1_000_000
    return megapixels < 1
      ? Notation.fixed(megapixels, decimals: 1) + " MP"
      : Notation.fixed(megapixels, decimals: 0) + " MP"
  }
}

/// Resolved against the lens connected when the press reaches the photo output, never earlier,
/// so a lens switch right before the shutter can't leave a size the new lens doesn't support.
public enum ResolutionPreference: Sendable, Hashable, CaseIterable, Codable {
  /// About 12 MP.
  case standard
  /// The largest size the lens delivers without deferred processing.
  case full
}

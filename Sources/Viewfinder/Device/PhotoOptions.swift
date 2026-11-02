import AVFoundation

/// What a camera captures. A change restarts the session, except a change to
/// `customizeSettings` alone, which the camera reads at each press.
public struct PhotoOptions: Sendable {
  enum Encoding: Sendable, Hashable {
    case jpeg(quality: Double)
    case heif
    case appleProRAW(fallback: Fallback)
  }

  let encoding: Encoding

  /// What a ProRAW camera captures on a device without Apple ProRAW.
  public enum Fallback: Sendable, Hashable {
    case heif
    case jpeg
  }

  /// The escape hatch into `AVCapturePhotoSettings` for settings-level options the presets don't
  /// cover and that need nothing from the photo output: `metadata` for a location on iOS, or
  /// `isShutterSoundSuppressionEnabled` where the output supports it. Called on the main actor
  /// for each press, after the library filled in the format, quality prioritization, and preview
  /// request, and before it tracks the request for readiness.
  ///
  /// The library resolves the flash and the size again against the lens connected at capture,
  /// so changes to `flashMode` and `maxPhotoDimensions` are overwritten. It sets
  /// `photoQualityPrioritization` to `.speed` under a manual or priority exposure program, which
  /// is what lets the device's ISO and shutter speed reach the photo; raising it restores the
  /// system's override.
  ///
  /// Depth, Live Photo, and constant color are not supported. Each needs the photo output
  /// enabled for it, which the library doesn't expose, so requesting one here raises an
  /// Objective-C exception and crashes.
  public var customizeSettings: (@MainActor @Sendable (AVCapturePhotoSettings) -> Void)?

  /// JPEG with the orientation written as an EXIF tag instead of redrawing the pixels. Balanced
  /// quality prioritization. On macOS the orientation is `.up`, because `AVCapturePhoto` carries
  /// no orientation metadata there.
  public static func jpeg(quality: Double) -> PhotoOptions {
    PhotoOptions(encoding: .jpeg(quality: quality))
  }

  /// HEIF at balanced quality prioritization.
  public static var heif: PhotoOptions {
    PhotoOptions(encoding: .heif)
  }

  /// RAW-only Apple ProRAW (DNG), or `fallback` on devices without ProRAW. Quality
  /// prioritization, a full-size embedded thumbnail (otherwise Photos shows the DNG at low
  /// resolution), and resolutions that exclude deferred-delivery-only sizes.
  public static func appleProRAW(fallback: Fallback = .heif) -> PhotoOptions {
    PhotoOptions(encoding: .appleProRAW(fallback: fallback))
  }
}

extension PhotoOptions {
  func deliveredFormat(supportsProRAW: Bool, supportsHEVC: Bool) -> PhotoFormat {
    switch encoding {
    case .jpeg: .jpeg
    case .heif: supportsHEVC ? .heif : .jpeg
    case .appleProRAW(let fallback): supportsProRAW ? .appleProRAW : (fallback == .heif && supportsHEVC ? .heif : .jpeg)
    }
  }

  var wantsProRAW: Bool {
    switch encoding {
    case .appleProRAW: true
    case .jpeg, .heif: false
    }
  }

  var jpegQuality: Double? {
    switch encoding {
    case .jpeg(let quality): quality
    case .heif, .appleProRAW: nil
    }
  }

  var qualityPrioritization: AVCapturePhotoOutput.QualityPrioritization {
    switch encoding {
    case .jpeg, .heif: .balanced
    case .appleProRAW: .quality
    }
  }

  /// At `.balanced` or higher the photo output may override the device's ISO and exposure
  /// duration (multi-image fusion in a dark scene), so a fixed ISO or shutter speed reaches the
  /// photo only at `.speed`.
  func qualityPrioritization(for exposure: ExposureProgram) -> AVCapturePhotoOutput.QualityPrioritization {
    switch exposure {
    case .automatic: qualityPrioritization
    case .shutterPriority, .isoPriority, .manual: .speed
    }
  }
}

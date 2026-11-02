import AVFoundation

enum PhotoSettingsBuilder {
  static let previewLongSide = 512

  @MainActor
  static func settings(for shot: PhotoShot, options: PhotoOptions, output: PhotoOutputFacts) -> AVCapturePhotoSettings {
    let settings: AVCapturePhotoSettings
    switch shot.format {
    case .appleProRAW:
      #if os(iOS)
      if let rawPixelFormat = output.rawPixelFormat {
        settings = AVCapturePhotoSettings(rawPixelFormatType: rawPixelFormat)
      } else {
        settings = AVCapturePhotoSettings()
      }
      #else
      settings = AVCapturePhotoSettings()
      #endif
    case .heif:
      settings = output.hasHEVC
        ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.hevc])
        : AVCapturePhotoSettings()
    case .jpeg:
      settings = AVCapturePhotoSettings(format: [
        AVVideoCodecKey: AVVideoCodecType.jpeg,
        AVVideoCompressionPropertiesKey: [AVVideoQualityKey: options.jpegQuality ?? 0.9],
      ])
    }

    if let dimensions = shot.dimensions {
      let ceiling = output.maxDimensions ?? dimensions
      set(dimensions: dimensions.pixelCount <= ceiling.pixelCount ? dimensions : ceiling, on: settings)
    }
    settings.photoQualityPrioritization = options.qualityPrioritization(for: shot.exposure)
    if output.flashModes.contains(shot.flash) {
      settings.flashMode = shot.flash.avFlashMode
    }

    #if os(iOS)
    if case .appleProRAW = shot.format, let codec = settings.availableRawEmbeddedThumbnailPhotoCodecTypes.first {
      // Photos and most viewers show a DNG through its embedded preview, so it must be full size,
      // like the Camera app's. The system clamps it to the photo's actual size.
      settings.rawEmbeddedThumbnailPhotoFormat = [
        AVVideoCodecKey: codec,
        AVVideoWidthKey: settings.maxPhotoDimensions.width,
        AVVideoHeightKey: settings.maxPhotoDimensions.height,
      ]
    }
    if let previewPixelFormat = settings.availablePreviewPhotoPixelFormatTypes.first {
      settings.previewPhotoFormat = [
        kCVPixelBufferPixelFormatTypeKey as String: previewPixelFormat,
        kCVPixelBufferWidthKey as String: previewLongSide,
        kCVPixelBufferHeightKey as String: previewLongSide,
      ]
    }
    #endif
    return settings
  }

  static func apply(_ shot: PhotoShot, to settings: AVCapturePhotoSettings) {
    settings.flashMode = shot.flash.avFlashMode
    if let dimensions = shot.dimensions {
      set(dimensions: dimensions, on: settings)
    }
  }

  private static func set(dimensions: PhotoResolution, on settings: AVCapturePhotoSettings) {
    settings.maxPhotoDimensions = CMVideoDimensions(width: Int32(dimensions.width), height: Int32(dimensions.height))
    #if os(iOS)
    if var thumbnail = settings.rawEmbeddedThumbnailPhotoFormat {
      thumbnail[AVVideoWidthKey] = settings.maxPhotoDimensions.width
      thumbnail[AVVideoHeightKey] = settings.maxPhotoDimensions.height
      settings.rawEmbeddedThumbnailPhotoFormat = thumbnail
    }
    #endif
  }
}

extension FlashMode {
  var avFlashMode: AVCaptureDevice.FlashMode {
    switch self {
    case .off: .off
    case .on: .on
    case .auto: .auto
    }
  }

  init?(_ mode: AVCaptureDevice.FlashMode) {
    switch mode {
    case .off: self = .off
    case .on: self = .on
    case .auto: self = .auto
    @unknown default: return nil
    }
  }
}

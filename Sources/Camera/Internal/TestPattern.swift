import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import UniformTypeIdentifiers

enum TestPattern {
  static let bars: [(red: Double, green: Double, blue: Double)] = [
    (0.75, 0.75, 0.75), (0.75, 0.75, 0), (0, 0.75, 0.75), (0, 0.75, 0),
    (0.75, 0, 0.75), (0.75, 0, 0), (0, 0, 0.75),
  ]

  static func draw(in context: CGContext, rect: CGRect, phase: Double) {
    let barHeight = rect.height * 0.7
    let barWidth = rect.width / Double(bars.count)
    for (index, bar) in bars.enumerated() {
      context.setFillColor(red: bar.red, green: bar.green, blue: bar.blue, alpha: 1)
      context.fill(CGRect(x: rect.minX + barWidth * Double(index), y: rect.minY, width: barWidth.rounded(.up), height: barHeight))
    }
    let steps = 12
    let stepWidth = rect.width / Double(steps)
    for step in 0..<steps {
      let gray = Double(step) / Double(steps - 1)
      context.setFillColor(red: gray, green: gray, blue: gray, alpha: 1)
      context.fill(CGRect(x: rect.minX + stepWidth * Double(step), y: rect.minY + barHeight, width: stepWidth.rounded(.up), height: rect.height - barHeight))
    }
    let radius = min(rect.width, rect.height) * 0.08
    let orbit = min(rect.width, rect.height) * 0.3
    let angle = phase * 2 * .pi
    let center = CGPoint(x: rect.midX + cos(angle) * orbit, y: rect.midY + sin(angle) * orbit)
    context.setFillColor(red: 1, green: 0.45, blue: 0, alpha: 1)
    context.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
  }

  static func image(width: Int, height: Int, phase: Double, mirrored: Bool) -> CGImage? {
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }
    if mirrored {
      context.translateBy(x: Double(width), y: 0)
      context.scaleBy(x: -1, y: 1)
    }
    draw(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height), phase: phase)
    return context.makeImage()
  }

  /// The simulated preview's frames: upright and 3:4, like a phone held in portrait.
  static let frameSize = (width: 720, height: 960)

  /// Draws upright into a BGRA buffer, with the bars at the top as the preview shows them.
  static func draw(into buffer: CVPixelBuffer, phase: Double) {
    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    let width = CVPixelBufferGetWidth(buffer)
    let height = CVPixelBufferGetHeight(buffer)
    guard
      let context = CGContext(
        data: CVPixelBufferGetBaseAddress(buffer),
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return }
    context.translateBy(x: 0, y: Double(height))
    context.scaleBy(x: 1, y: -1)
    draw(in: context, rect: CGRect(x: 0, y: 0, width: width, height: height), phase: phase)
  }

  static func phase() -> Double {
    (Date.now.timeIntervalSinceReferenceDate / 6).truncatingRemainder(dividingBy: 1)
  }
}

enum SimulatedPhoto {
  static let orientation = CGImagePropertyOrientation.right

  static func make(shot: PhotoShot, options: PhotoOptions, phase: Double, snapshot: CameraFailure.Snapshot) -> Result<Photo, CameraFailure> {
    let sensor = shot.dimensions ?? PhotoResolution(width: 4032, height: 3024)
    guard let image = TestPattern.image(width: sensor.width, height: sensor.height, phase: phase, mirrored: shot.isMirrored) else {
      return .failure(CameraFailure(kind: .photoCapture, message: "The simulated photo could not be rendered.", snapshot: snapshot))
    }
    let format: PhotoFormat = shot.format == .jpeg ? .jpeg : .heif
    do {
      let url = try encode(image, format: format, quality: options.jpegQuality ?? 0.9)
      let display = UprightImage.displaySize(width: image.width, height: image.height, orientation: orientation)
      return .success(
        Photo(
          file: CapturedFile(url: url),
          format: format,
          pixelSize: CGSize(width: display.width, height: display.height),
          preview: UprightImage.make(image, orientation: orientation, maxLongSide: PhotoSettingsBuilder.previewLongSide)
        ))
    } catch {
      return .failure(CameraFailure(kind: .photoCapture, error: error, snapshot: snapshot))
    }
  }

  private static func encode(_ image: CGImage, format: PhotoFormat, quality: Double) throws -> URL {
    let type: UTType = format == .jpeg ? .jpeg : .heic
    let url = try CapturedFileStore.makeURL(fileExtension: format.fileExtension)
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else {
      throw EncodingError.destination
    }
    let properties: [CFString: Any] = [
      kCGImagePropertyOrientation: orientation.rawValue,
      kCGImageDestinationLossyCompressionQuality: quality,
    ]
    CGImageDestinationAddImage(destination, image, properties as CFDictionary)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: url)
      throw EncodingError.finalize
    }
    return url
  }

  private enum EncodingError: Error {
    case destination
    case finalize
  }
}

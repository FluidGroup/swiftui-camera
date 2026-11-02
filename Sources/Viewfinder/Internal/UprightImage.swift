import CoreGraphics
import ImageIO

enum UprightImage {
  static func make(_ image: CGImage, orientation: CGImagePropertyOrientation, maxLongSide: Int) -> CGImage? {
    let display = displaySize(width: image.width, height: image.height, orientation: orientation)
    let scale = min(1, Double(maxLongSide) / Double(max(display.width, display.height)))
    let width = max(1, Int((Double(display.width) * scale).rounded()))
    let height = max(1, Int((Double(display.height) * scale).rounded()))
    guard
      let context = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
      )
    else { return nil }
    context.interpolationQuality = .high
    context.scaleBy(x: scale, y: scale)
    context.concatenate(transform(for: orientation, width: Double(image.width), height: Double(image.height)))
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
  }

  static func displaySize(width: Int, height: Int, orientation: CGImagePropertyOrientation) -> (width: Int, height: Int) {
    switch orientation {
    case .left, .leftMirrored, .right, .rightMirrored: (height, width)
    case .up, .upMirrored, .down, .downMirrored: (width, height)
    }
  }

  private static func transform(for orientation: CGImagePropertyOrientation, width: Double, height: Double) -> CGAffineTransform {
    let mirror = CGAffineTransform(translationX: width, y: 0).scaledBy(x: -1, y: 1)
    switch orientation {
    case .up:
      return .identity
    case .upMirrored:
      return mirror
    case .down:
      return CGAffineTransform(translationX: width, y: height).rotated(by: .pi)
    case .downMirrored:
      return CGAffineTransform(translationX: 0, y: height).scaledBy(x: 1, y: -1)
    case .right:
      return CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2)
    case .rightMirrored:
      return CGAffineTransform(translationX: 0, y: width).rotated(by: -.pi / 2).withMirrorFirst(mirror)
    case .left:
      return CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2)
    case .leftMirrored:
      return CGAffineTransform(translationX: height, y: 0).rotated(by: .pi / 2).withMirrorFirst(mirror)
    }
  }
}

extension CGAffineTransform {
  fileprivate func withMirrorFirst(_ mirror: CGAffineTransform) -> CGAffineTransform {
    mirror.concatenating(self)
  }
}

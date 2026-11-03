import CoreImage
import CoreVideo
import ImageIO
import Synchronization

/// One frame for the previews. The hardware delivers it in the sensor's orientation; the
/// simulated camera draws it upright.
struct PreviewFrame {
  let pixelBuffer: CVPixelBuffer
  /// The camera that produced it, `nil` for the simulated camera.
  let deviceID: String?
  /// Whether the previews show it flipped horizontally, as they do for a front camera.
  let isMirrored: Bool
}

/// Hands each frame of one camera to all of its previews. A camera delivers its frames one at a
/// time, from the video data output's queue or from the simulated engine.
final class PreviewFrames: Sendable {
  private let sinks = Mutex<[PreviewSink]>([])

  func add(_ sink: PreviewSink) {
    sinks.withLock { sinks in
      if !sinks.contains(where: { $0 === sink }) { sinks.append(sink) }
    }
  }

  func remove(_ sink: PreviewSink) {
    sinks.withLock { sinks in sinks.removeAll { $0 === sink } }
  }

  func deliver(_ frame: PreviewFrame) {
    for sink in sinks.withLock({ $0 }) {
      sink.render(frame)
    }
  }
}

/// One preview's end of the frame path: turns each frame upright, runs the preview's filter, and
/// renders the result for the display.
final class PreviewSink: Sendable {
  typealias Filter = @Sendable (CIImage) -> CIImage

  /// How to stand one camera's frames upright in this preview: quarter turns clockwise from the
  /// sensor's orientation. `deviceID` is `nil` for the simulated camera.
  struct Turning: Hashable, Sendable {
    var deviceID: String?
    var quarterTurns: Int
  }

  /// Each new size or orientation of the frames shown, for converting points on the main actor.
  let layouts: AsyncStream<FrameLayout>

  private struct Controls {
    var turning: Turning?
    var filter: Filter?
  }

  /// A render holds it throughout, so a sink renders one frame at a time even while a replaced
  /// camera's last frames still arrive.
  private struct Rendering {
    let context = CIContext(options: [.cacheIntermediates: false])
    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
    var pool = PixelBufferPool()
    var layout: FrameLayout?
  }

  private let controls = Mutex(Controls())
  private let rendering = Mutex(Rendering())
  private let output: @Sendable (CVPixelBuffer) -> Void
  private let layoutContinuation: AsyncStream<FrameLayout>.Continuation

  init(output: @escaping @Sendable (CVPixelBuffer) -> Void) {
    self.output = output
    (layouts, layoutContinuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
  }

  deinit {
    layoutContinuation.finish()
  }

  /// Both apply from the next frame. Frames from a camera other than `turning` names are dropped,
  /// so after a switch the display keeps its last frame until the main actor knows how to turn the
  /// new camera's, and nothing shows before it knows the first camera's.
  func update(turning: Turning?, filter: Filter?) {
    controls.withLock { controls in
      controls.turning = turning
      controls.filter = filter
    }
  }

  func render(_ frame: PreviewFrame) {
    let (turning, filter) = controls.withLock { ($0.turning, $0.filter) }
    guard let turning, turning.deviceID == frame.deviceID else { return }
    let orientation = FrameOrientation(quarterTurns: turning.quarterTurns, isMirrored: frame.isMirrored)
    let oriented = CIImage(cvPixelBuffer: frame.pixelBuffer).oriented(orientation.imageOrientation)
    let upright = oriented.transformed(by: CGAffineTransform(translationX: -oriented.extent.minX, y: -oriented.extent.minY))
    let extent = upright.extent
    let image = filter.map { $0(upright) } ?? upright
    let layout = FrameLayout(size: extent.size, orientation: orientation)
    rendering.withLock { rendering in
      guard let buffer = rendering.pool.buffer(width: Int(extent.width), height: Int(extent.height)) else { return }
      rendering.context.render(image, to: buffer, bounds: extent, colorSpace: rendering.colorSpace)
      CVBufferSetAttachment(buffer, kCVImageBufferCGColorSpaceKey, rendering.colorSpace, .shouldPropagate)
      if rendering.layout != layout {
        rendering.layout = layout
        layoutContinuation.yield(layout)
      }
      output(buffer)
    }
  }
}

/// The frames a preview shows: their upright size in pixels and how they were turned from the
/// sensor.
struct FrameLayout: Hashable, Sendable {
  var size: CGSize
  var orientation: FrameOrientation
}

/// How a frame was stood upright: quarter turns clockwise from the sensor's orientation, then a
/// horizontal flip for a mirrored preview.
struct FrameOrientation: Hashable, Sendable {
  let quarterTurns: Int
  let isMirrored: Bool

  init(quarterTurns: Int, isMirrored: Bool) {
    self.quarterTurns = (quarterTurns % 4 + 4) % 4
    self.isMirrored = isMirrored
  }

  /// `angle` in degrees, as `AVCaptureDevice.RotationCoordinator` reports it.
  init(angle: Double, isMirrored: Bool) {
    self.init(quarterTurns: Int((angle / 90).rounded()), isMirrored: isMirrored)
  }

  static let identity = FrameOrientation(quarterTurns: 0, isMirrored: false)

  var imageOrientation: CGImagePropertyOrientation {
    switch (quarterTurns, isMirrored) {
    case (0, false): .up
    case (0, true): .upMirrored
    case (1, false): .right
    case (1, true): .leftMirrored
    case (2, false): .down
    case (2, true): .downMirrored
    case (_, false): .left
    case (_, true): .rightMirrored
    }
  }

  /// Both points run from 0 to 1 with the origin at the top left; the device point is in the
  /// sensor's orientation, the way `AVCaptureDevice` takes points of interest.
  func uprightPoint(from devicePoint: DevicePoint) -> CGPoint {
    let (x, y) = (devicePoint.x, devicePoint.y)
    let turned: CGPoint =
      switch quarterTurns {
      case 0: CGPoint(x: x, y: y)
      case 1: CGPoint(x: 1 - y, y: x)
      case 2: CGPoint(x: 1 - x, y: 1 - y)
      default: CGPoint(x: y, y: 1 - x)
      }
    return isMirrored ? CGPoint(x: 1 - turned.x, y: turned.y) : turned
  }

  func devicePoint(from uprightPoint: CGPoint) -> DevicePoint {
    let x = isMirrored ? 1 - uprightPoint.x : uprightPoint.x
    let y = uprightPoint.y
    return switch quarterTurns {
    case 0: DevicePoint(x: x, y: y)
    case 1: DevicePoint(x: y, y: 1 - x)
    case 2: DevicePoint(x: 1 - x, y: 1 - y)
    default: DevicePoint(x: 1 - y, y: x)
    }
  }
}

/// IOSurface-backed BGRA buffers of one size, remade when the size changes.
struct PixelBufferPool {
  private var pool: CVPixelBufferPool?
  private var size: (width: Int, height: Int) = (0, 0)

  mutating func buffer(width: Int, height: Int) -> CVPixelBuffer? {
    guard width > 0, height > 0 else { return nil }
    if pool == nil || size != (width, height) {
      let attributes: [CFString: Any] = [
        kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey: width,
        kCVPixelBufferHeightKey: height,
        kCVPixelBufferIOSurfacePropertiesKey: [CFString: Any](),
        kCVPixelBufferMetalCompatibilityKey: true,
      ]
      pool = nil
      CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool)
      size = (width, height)
    }
    guard let pool else { return nil }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    return buffer
  }
}

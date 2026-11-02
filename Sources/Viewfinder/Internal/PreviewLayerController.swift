import AVFoundation
import QuartzCore

@MainActor
final class PreviewLayerController {
  let previewLayer: AVCaptureVideoPreviewLayer
  var videoRectDidChange: () -> Void = {}

  private let patternLayer = TestPatternLayer()
  private(set) var content: PreviewContent?
  private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
  private var rotationObservation: NSKeyValueObservation?
  private var patternAnimation: Task<Void, Never>?

  init(previewLayer: AVCaptureVideoPreviewLayer) {
    self.previewLayer = previewLayer
    previewLayer.backgroundColor = CGColor(gray: 0, alpha: 1)
    patternLayer.isHidden = true
    previewLayer.addSublayer(patternLayer)
  }

  func attach(_ content: PreviewContent?, gravity: AVLayerVideoGravity) {
    if previewLayer.videoGravity != gravity {
      previewLayer.videoGravity = gravity
      videoRectDidChange()
    }
    guard content != self.content else { return }
    self.content = content
    switch content {
    case .video(let session, let device):
      stopPattern()
      if previewLayer.session !== session {
        previewLayer.session = session
      }
      follow(device)
    case .testPattern:
      stopFollowing()
      previewLayer.session = nil
      startPattern()
    case nil:
      stopFollowing()
      stopPattern()
      previewLayer.session = nil
    }
    videoRectDidChange()
  }

  func layout(bounds: CGRect, scale: CGFloat) {
    patternLayer.contentsScale = scale
    patternLayer.frame = VideoGeometry.rect(videoAspect: TestPatternLayer.aspect, in: bounds, fills: previewLayer.videoGravity == .resizeAspectFill)
  }

  func videoRect(in bounds: CGRect) -> CGRect {
    switch content {
    case .video where previewLayer.connection != nil:
      previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
    case .testPattern:
      VideoGeometry.rect(videoAspect: TestPatternLayer.aspect, in: bounds, fills: previewLayer.videoGravity == .resizeAspectFill)
    case .video, nil:
      bounds
    }
  }

  func devicePoint(from layerPoint: CGPoint, videoRect: CGRect) -> DevicePoint {
    switch content {
    case .video where previewLayer.connection != nil:
      let point = previewLayer.captureDevicePointConverted(fromLayerPoint: layerPoint)
      return DevicePoint(x: point.x, y: point.y)
    case .video, .testPattern, nil:
      return VideoGeometry.devicePoint(from: layerPoint, in: videoRect)
    }
  }

  func layerPoint(from devicePoint: DevicePoint, videoRect: CGRect) -> CGPoint {
    switch content {
    case .video where previewLayer.connection != nil:
      previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: devicePoint.x, y: devicePoint.y))
    case .video, .testPattern, nil:
      VideoGeometry.viewPoint(from: devicePoint, in: videoRect)
    }
  }

  private func follow(_ device: AVCaptureDevice) {
    guard rotationCoordinator?.device !== device else { return }
    stopFollowing()
    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
    rotationCoordinator = coordinator
    apply(angle: coordinator.videoRotationAngleForHorizonLevelPreview)
    rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
      let angle = coordinator.videoRotationAngleForHorizonLevelPreview
      Task { @MainActor [weak self] in self?.apply(angle: angle) }
    }
  }

  private func stopFollowing() {
    rotationObservation = nil
    rotationCoordinator = nil
  }

  private func apply(angle: CGFloat) {
    guard
      let connection = previewLayer.connection,
      connection.isVideoRotationAngleSupported(angle),
      connection.videoRotationAngle != angle
    else { return }
    connection.videoRotationAngle = angle
    videoRectDidChange()
  }

  private func startPattern() {
    patternLayer.isHidden = false
    patternAnimation?.cancel()
    patternAnimation = Task { @MainActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(33))
        guard !Task.isCancelled, let self else { return }
        self.patternLayer.phase = TestPattern.phase()
        self.patternLayer.setNeedsDisplay()
      }
    }
  }

  private func stopPattern() {
    patternAnimation?.cancel()
    patternAnimation = nil
    patternLayer.isHidden = true
  }
}

final class TestPatternLayer: CALayer {
  static let aspect = CGSize(width: 3, height: 4)

  var phase: Double = 0

  override init() {
    super.init()
    needsDisplayOnBoundsChange = true
  }

  override init(layer: Any) {
    super.init(layer: layer)
    if let layer = layer as? TestPatternLayer {
      phase = layer.phase
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func draw(in context: CGContext) {
    TestPattern.draw(in: context, rect: bounds, phase: phase)
  }
}

enum VideoGeometry {
  static func rect(videoAspect: CGSize, in bounds: CGRect, fills: Bool) -> CGRect {
    guard videoAspect.width > 0, videoAspect.height > 0, bounds.width > 0, bounds.height > 0 else { return bounds }
    let scale = fills
      ? max(bounds.width / videoAspect.width, bounds.height / videoAspect.height)
      : min(bounds.width / videoAspect.width, bounds.height / videoAspect.height)
    let size = CGSize(width: videoAspect.width * scale, height: videoAspect.height * scale)
    return CGRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2, width: size.width, height: size.height)
  }

  /// The sensor is landscape and shown turned a quarter clockwise, so its x axis runs down the
  /// view and its y axis runs from the right edge to the left.
  static func devicePoint(from viewPoint: CGPoint, in videoRect: CGRect) -> DevicePoint {
    guard videoRect.width > 0, videoRect.height > 0 else { return .center }
    return DevicePoint(
      x: (viewPoint.y - videoRect.minY) / videoRect.height,
      y: 1 - (viewPoint.x - videoRect.minX) / videoRect.width
    )
  }

  static func viewPoint(from devicePoint: DevicePoint, in videoRect: CGRect) -> CGPoint {
    CGPoint(
      x: videoRect.minX + (1 - devicePoint.y) * videoRect.width,
      y: videoRect.minY + devicePoint.x * videoRect.height
    )
  }
}

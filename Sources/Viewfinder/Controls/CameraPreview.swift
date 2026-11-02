import AVFoundation
import Observation
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// The live video, and nothing else the library draws.
///
/// The video stays level from its first frame and through lens switches. The front camera's
/// preview is mirrored.
///
/// `overlay` is laid out in the preview's own coordinate space and receives a proxy for
/// converting between view points and device points.
///
/// It shows the camera of the `Camera` it's inside.
public struct CameraPreview<Overlay: View>: View {
  @Environment(CameraModel.self) private var camera: CameraModel?
  @State private var host = PreviewHost()
  @State private var size: CGSize = .zero
  private let contentMode: ContentMode
  private let overlay: (CameraPreviewProxy) -> Overlay

  public init(contentMode: ContentMode = .fit, @ViewBuilder overlay: @escaping (CameraPreviewProxy) -> Overlay) {
    self.contentMode = contentMode
    self.overlay = overlay
  }

  public var body: some View {
    if let camera {
      PreviewLayerView(content: camera.previewContent, gravity: gravity, host: host)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
        .overlay { overlay(proxy) }
    } else {
      Color.black
        .onAppear { reportMissingScope("CameraPreview") }
    }
  }

  private var gravity: AVLayerVideoGravity {
    switch contentMode {
    case .fit: .resizeAspect
    case .fill: .resizeAspectFill
    }
  }

  private var proxy: CameraPreviewProxy {
    _ = host.revision
    let controller = host.view?.controller
    let bounds = CGRect(origin: .zero, size: size)
    let videoRect = controller?.videoRect(in: bounds) ?? bounds
    return CameraPreviewProxy(
      size: size,
      videoRect: videoRect,
      toDevice: { [weak controller] point in
        controller?.devicePoint(from: point, videoRect: videoRect) ?? VideoGeometry.devicePoint(from: point, in: videoRect)
      },
      toView: { [weak controller] point in
        controller?.layerPoint(from: point, videoRect: videoRect) ?? VideoGeometry.viewPoint(from: point, in: videoRect)
      }
    )
  }
}

extension CameraPreview where Overlay == EmptyView {
  public init(contentMode: ContentMode = .fit) {
    self.init(contentMode: contentMode) { _ in EmptyView() }
  }
}

/// Converts between the preview's view points and the device's normalized points, accounting
/// for gravity, rotation, and mirroring. Only valid inside `CameraPreview`'s overlay.
@MainActor
public struct CameraPreviewProxy {
  /// The preview's size.
  public let size: CGSize
  /// Where the video actually is, in the preview's coordinates. Letterboxed under `.fit`,
  /// larger than `size` under `.fill`.
  public let videoRect: CGRect
  private let toDevice: (CGPoint) -> DevicePoint
  private let toView: (DevicePoint) -> CGPoint

  init(size: CGSize, videoRect: CGRect, toDevice: @escaping (CGPoint) -> DevicePoint, toView: @escaping (DevicePoint) -> CGPoint) {
    self.size = size
    self.videoRect = videoRect
    self.toDevice = toDevice
    self.toView = toView
  }

  /// `nil` outside the visible video, so a tap on a letterbox bar doesn't focus.
  public func devicePoint(from viewPoint: CGPoint) -> DevicePoint? {
    guard videoRect.contains(viewPoint) else { return nil }
    return toDevice(viewPoint)
  }

  public func viewPoint(from devicePoint: DevicePoint) -> CGPoint {
    toView(devicePoint)
  }
}

@MainActor
@Observable
final class PreviewHost {
  var revision = 0
  @ObservationIgnored weak var view: PreviewHostView?

  func videoRectDidChange() {
    // Deferred one turn: the first change lands inside the representable's update.
    Task { @MainActor in self.revision += 1 }
  }
}

#if canImport(UIKit)
struct PreviewLayerView: UIViewRepresentable {
  let content: PreviewContent?
  let gravity: AVLayerVideoGravity
  let host: PreviewHost

  func makeUIView(context: Context) -> PreviewHostView {
    let view = PreviewHostView()
    host.view = view
    view.controller.videoRectDidChange = { [weak host] in host?.videoRectDidChange() }
    return view
  }

  func updateUIView(_ view: PreviewHostView, context: Context) {
    view.controller.attach(content, gravity: gravity)
  }
}

final class PreviewHostView: UIView {
  override static var layerClass: AnyClass {
    AVCaptureVideoPreviewLayer.self
  }

  private(set) lazy var controller = PreviewLayerController(previewLayer: layer as! AVCaptureVideoPreviewLayer)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    controller.layout(bounds: bounds, scale: traitCollection.displayScale)
  }
}
#elseif canImport(AppKit)
struct PreviewLayerView: NSViewRepresentable {
  let content: PreviewContent?
  let gravity: AVLayerVideoGravity
  let host: PreviewHost

  func makeNSView(context: Context) -> PreviewHostView {
    let view = PreviewHostView()
    host.view = view
    view.controller.videoRectDidChange = { [weak host] in host?.videoRectDidChange() }
    return view
  }

  func updateNSView(_ view: PreviewHostView, context: Context) {
    view.controller.attach(content, gravity: gravity)
  }
}

final class PreviewHostView: NSView {
  let controller: PreviewLayerController

  override var isFlipped: Bool {
    true
  }

  init() {
    controller = PreviewLayerController(previewLayer: AVCaptureVideoPreviewLayer())
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
    layer?.addSublayer(controller.previewLayer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    controller.previewLayer.frame = bounds
    controller.layout(bounds: bounds, scale: window?.backingScaleFactor ?? 2)
  }
}
#endif

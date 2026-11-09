import AVFoundation
import CoreImage
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
/// preview is mirrored. Add `imageFilter(_:)` to run Core Image on each frame.
///
/// `overlay` is laid out in the preview's own coordinate space and receives a proxy for
/// converting between view points and device points.
public struct CameraPreview<Overlay: View>: View {
  @State private var host = PreviewHost()
  @State private var size: CGSize = .zero
  private let camera: CameraModel
  private let contentMode: ContentMode
  private let overlay: (CameraPreviewProxy) -> Overlay
  private var filter: (@Sendable (CIImage) -> CIImage)?

  public init(
    _ camera: CameraProxy,
    contentMode: ContentMode = .fit,
    @ViewBuilder overlay: @escaping (CameraPreviewProxy) -> Overlay
  ) {
    self.camera = camera.model
    self.contentMode = contentMode
    self.overlay = overlay
  }

  /// Runs `filter` on each frame before this preview shows it.
  ///
  /// The image arrives upright and mirrored as the preview shows it, with its extent at the origin
  /// in pixels, and the result is cropped to that extent. `filter` runs off the main actor for
  /// every frame, so keep it quick and capture the values it reads: `{ [strength] image in ... }`.
  /// A filter from a later view update applies from the next frame.
  ///
  /// It changes only this preview. Photos arrive as the camera captured them.
  public func imageFilter(_ filter: @escaping @Sendable (CIImage) -> CIImage) -> CameraPreview {
    var preview = self
    preview.filter = filter
    return preview
  }

  public var body: some View {
    PreviewLayerView(frames: camera.frames, source: camera.previewSource, gravity: gravity, filter: filter, host: host)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
      .overlay { overlay(proxy) }
  }

  private var gravity: AVLayerVideoGravity {
    switch contentMode {
    case .fit: .resizeAspect
    case .fill: .resizeAspectFill
    }
  }

  private var proxy: CameraPreviewProxy {
    _ = host.revision
    let display = host.view?.display
    let bounds = CGRect(origin: .zero, size: size)
    let videoRect = display?.videoRect(in: bounds) ?? bounds
    let orientation = display?.orientation ?? .identity
    return CameraPreviewProxy(
      size: size,
      videoRect: videoRect,
      toDevice: { point in VideoGeometry.devicePoint(from: point, in: videoRect, orientation: orientation) },
      toView: { point in VideoGeometry.viewPoint(from: point, in: videoRect, orientation: orientation) }
    )
  }
}

extension CameraPreview where Overlay == EmptyView {
  public init(_ camera: CameraProxy, contentMode: ContentMode = .fit) {
    self.init(camera, contentMode: contentMode) { _ in EmptyView() }
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
  let frames: PreviewFrames
  let source: PreviewSource?
  let gravity: AVLayerVideoGravity
  let filter: PreviewSink.Filter?
  let host: PreviewHost

  func makeUIView(context: Context) -> PreviewHostView {
    let view = PreviewHostView()
    host.view = view
    view.display.layoutDidChange = { [weak host] in host?.videoRectDidChange() }
    return view
  }

  func updateUIView(_ view: PreviewHostView, context: Context) {
    view.display.attach(frames: frames, source: source, gravity: gravity, filter: filter)
  }

  static func dismantleUIView(_ view: PreviewHostView, coordinator: ()) {
    view.display.detach()
  }
}

final class PreviewHostView: UIView {
  override static var layerClass: AnyClass {
    AVSampleBufferDisplayLayer.self
  }

  private(set) lazy var display = PreviewDisplay(layer: layer as! AVSampleBufferDisplayLayer)

  override init(frame: CGRect) {
    super.init(frame: frame)
    backgroundColor = .black
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    display.windowDidChange(isInWindow: window != nil)
  }
}
#elseif canImport(AppKit)
struct PreviewLayerView: NSViewRepresentable {
  let frames: PreviewFrames
  let source: PreviewSource?
  let gravity: AVLayerVideoGravity
  let filter: PreviewSink.Filter?
  let host: PreviewHost

  func makeNSView(context: Context) -> PreviewHostView {
    let view = PreviewHostView()
    host.view = view
    view.display.layoutDidChange = { [weak host] in host?.videoRectDidChange() }
    return view
  }

  func updateNSView(_ view: PreviewHostView, context: Context) {
    view.display.attach(frames: frames, source: source, gravity: gravity, filter: filter)
  }

  static func dismantleNSView(_ view: PreviewHostView, coordinator: ()) {
    view.display.detach()
  }
}

final class PreviewHostView: NSView {
  let display = PreviewDisplay(layer: AVSampleBufferDisplayLayer())

  override var isFlipped: Bool {
    true
  }

  init() {
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = CGColor(gray: 0, alpha: 1)
    layer?.addSublayer(display.layer)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    display.layer.frame = bounds
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    display.windowDidChange(isInWindow: window != nil)
  }
}
#endif

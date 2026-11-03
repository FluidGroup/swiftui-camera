import AVFoundation
import CoreImage
import QuartzCore

/// Shows one preview's frames in an `AVSampleBufferDisplayLayer`. Its sink renders on the frame
/// queue and enqueues there, so a busy main actor never stalls the video; the main actor only
/// tells the sink how to turn the frames and which filter to run.
@MainActor
final class PreviewDisplay {
  let layer: AVSampleBufferDisplayLayer
  var layoutDidChange: () -> Void = {}

  private(set) var layout: FrameLayout?
  private let sink: PreviewSink
  private var frames: PreviewFrames?
  private var source: PreviewSource?
  private var isInWindow = false
  private var turning: PreviewSink.Turning?
  private var filter: PreviewSink.Filter?
  private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
  private var rotationObservation: NSKeyValueObservation?
  private var layoutTask: Task<Void, Never>?

  init(layer: AVSampleBufferDisplayLayer) {
    self.layer = layer
    layer.backgroundColor = CGColor(gray: 0, alpha: 1)
    // A camera preview shouldn't keep the screen awake the way video playback does.
    layer.preventsDisplaySleepDuringVideoPlayback = false
    let output = DisplayOutput(renderer: layer.sampleBufferRenderer)
    sink = PreviewSink { buffer in output.enqueue(buffer) }
    let layouts = sink.layouts
    layoutTask = Task { [weak self] in
      for await layout in layouts {
        self?.apply(layout)
      }
    }
  }

  isolated deinit {
    layoutTask?.cancel()
    frames?.remove(sink)
  }

  func attach(frames: PreviewFrames?, source: PreviewSource?, gravity: AVLayerVideoGravity, filter: PreviewSink.Filter?) {
    if layer.videoGravity != gravity {
      layer.videoGravity = gravity
      layoutDidChange()
    }
    if frames !== self.frames {
      self.frames?.remove(sink)
      frames?.add(sink)
      self.frames = frames
    }
    self.filter = filter
    if source != self.source {
      self.source = source
      follow()
    } else {
      sink.update(turning: turning, filter: filter)
    }
  }

  func detach() {
    frames?.remove(sink)
    frames = nil
    source = nil
    follow()
  }

  /// A rotation coordinator reports no rotation for a layer outside a window, so the preview
  /// follows its camera only while it's in one.
  func windowDidChange(isInWindow: Bool) {
    guard isInWindow != self.isInWindow else { return }
    self.isInWindow = isInWindow
    follow()
  }

  func videoRect(in bounds: CGRect) -> CGRect {
    guard let layout else { return bounds }
    return VideoGeometry.rect(videoAspect: layout.size, in: bounds, fills: layer.videoGravity == .resizeAspectFill)
  }

  var orientation: FrameOrientation {
    layout?.orientation ?? .identity
  }

  private func apply(_ layout: FrameLayout) {
    guard layout != self.layout else { return }
    self.layout = layout
    layoutDidChange()
  }

  /// The simulated camera draws its frames upright, so only a device needs turning.
  private func follow() {
    rotationObservation = nil
    rotationCoordinator = nil
    guard isInWindow, let source else {
      setTurning(nil)
      return
    }
    guard case .device(let device) = source else {
      setTurning(PreviewSink.Turning(deviceID: nil, quarterTurns: 0))
      return
    }
    let deviceID = device.uniqueID
    let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: layer)
    rotationCoordinator = coordinator
    setTurning(deviceID: deviceID, angle: coordinator.videoRotationAngleForHorizonLevelPreview)
    rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
      let angle = coordinator.videoRotationAngleForHorizonLevelPreview
      Task { @MainActor [weak self] in
        // A change the previous camera's coordinator queued before the switch doesn't apply.
        guard let self, self.turning?.deviceID == deviceID else { return }
        self.setTurning(deviceID: deviceID, angle: angle)
      }
    }
  }

  private func setTurning(deviceID: String, angle: CGFloat) {
    setTurning(PreviewSink.Turning(deviceID: deviceID, quarterTurns: FrameOrientation(angle: angle, isMirrored: false).quarterTurns))
  }

  private func setTurning(_ turning: PreviewSink.Turning?) {
    self.turning = turning
    sink.update(turning: turning, filter: filter)
  }
}

/// `@unchecked Sendable`: `AVSampleBufferDisplayLayer.sampleBufferRenderer` takes sample buffers
/// from a background thread.
private struct DisplayOutput: @unchecked Sendable {
  let renderer: AVSampleBufferVideoRenderer

  func enqueue(_ buffer: CVPixelBuffer) {
    guard
      let format = try? CMVideoFormatDescription(imageBuffer: buffer),
      let sample = try? CMSampleBuffer(
        imageBuffer: buffer,
        formatDescription: format,
        sampleTiming: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
      )
    else { return }
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true) as? [NSMutableDictionary] {
      attachments.first?[kCMSampleAttachmentKey_DisplayImmediately] = true
    }
    if renderer.status == .failed || renderer.requiresFlushToResumeDecoding {
      renderer.flush()
    }
    renderer.enqueue(sample)
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

  static func devicePoint(from viewPoint: CGPoint, in videoRect: CGRect, orientation: FrameOrientation) -> DevicePoint {
    guard videoRect.width > 0, videoRect.height > 0 else { return .center }
    return orientation.devicePoint(
      from: CGPoint(
        x: (viewPoint.x - videoRect.minX) / videoRect.width,
        y: (viewPoint.y - videoRect.minY) / videoRect.height
      ))
  }

  static func viewPoint(from devicePoint: DevicePoint, in videoRect: CGRect, orientation: FrameOrientation) -> CGPoint {
    let upright = orientation.uprightPoint(from: devicePoint)
    return CGPoint(
      x: videoRect.minX + upright.x * videoRect.width,
      y: videoRect.minY + upright.y * videoRect.height
    )
  }
}

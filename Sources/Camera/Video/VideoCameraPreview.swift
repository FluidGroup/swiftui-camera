@preconcurrency import AVFoundation
import SwiftUI

/// A fitted, orientation-aware preview for the movie being recorded.
public struct VideoCameraPreview: View {
  private let camera: VideoCameraProxy
  @State private var host = PreviewHost()

  public init(_ camera: VideoCameraProxy) { self.camera = camera }

  public var body: some View {
    #if os(iOS)
      if let source = camera.preview {
        VideoPreviewLayer(session: source.session, device: source.device)
      } else {
        frames
      }
    #else
      frames
    #endif
  }

  private var frames: some View {
    PreviewLayerView(
      frames: camera.frames, source: camera.preview.map { .device($0.device) } ?? .simulated,
      gravity: .resizeAspect, filter: nil, host: host)
  }
}

#if os(iOS)
  import UIKit
  /// The live camera feed, fitted to the frame the recording captures.
  ///
  /// Show it only once the session is configured: attaching the preview layer
  /// creates its connection immediately, so the horizon-level rotation applies
  /// from the first frame.
  private struct VideoPreviewLayer: UIViewRepresentable {

    let session: AVCaptureSession
    let device: AVCaptureDevice?

    func makeUIView(context: Context) -> PreviewUIView {
      let view = PreviewUIView()
      view.attach(session: session, device: device)
      return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
      uiView.attach(session: session, device: device)
    }

    final class PreviewUIView: UIView {

      override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
      }

      private var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
      }

      private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
      private var rotationObservation: NSKeyValueObservation?

      override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        // The container already has the recording's aspect ratio, so fitting
        // shows exactly the frame that will be recorded.
        previewLayer.videoGravity = .resizeAspect
      }

      @available(*, unavailable)
      required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
      }

      fileprivate func attach(session: AVCaptureSession, device: AVCaptureDevice?) {
        if previewLayer.session !== session {
          previewLayer.session = session
        }

        guard rotationCoordinator?.device !== device else { return }
        rotationObservation = nil
        rotationCoordinator = nil
        guard let device else { return }

        let coordinator = AVCaptureDevice.RotationCoordinator(
          device: device,
          previewLayer: previewLayer
        )
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(
          \.videoRotationAngleForHorizonLevelPreview,
          options: [.new]
        ) { [weak self] coordinator, _ in
          let angle = coordinator.videoRotationAngleForHorizonLevelPreview
          Task { @MainActor [weak self] in
            self?.applyPreviewRotation(angle)
          }
        }
      }

      private func applyPreviewRotation(_ angle: CGFloat) {
        guard
          let connection = previewLayer.connection,
          connection.isVideoRotationAngleSupported(angle)
        else {
          return
        }
        connection.videoRotationAngle = angle
      }
    }
  }
#endif

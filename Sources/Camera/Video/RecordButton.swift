import SwiftUI
#if os(iOS)
import QuartzCore
import UIKit
import os
#endif

/// Starts a clip on touch-down and finishes it on release or cancellation.
/// Accessibility activation toggles recording without requiring a hold.
public struct RecordButton<Label: View>: View {
  private let camera: VideoCameraProxy
  private let label: (RecordingState) -> Label
  #if !os(iOS)
  @GestureState private var touching = false
  @State private var isTrackingTouch = false
  #endif

  public init(_ camera: VideoCameraProxy, @ViewBuilder label: @escaping (RecordingState) -> Label) {
    self.camera = camera
    self.label = label
  }

  public var body: some View {
    touchSurface
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("Record")
      .accessibilityValue(isRecording ? Text("Recording") : Text(""))
      .accessibilityAction {
        if isRecording { camera.stopRecording() } else { camera.startRecording() }
      }
  }

  private var touchSurface: some View {
    let content = label(camera.recordingState)
      .contentShape(.rect)
    #if os(iOS)
      return content.overlay {
        RecordTouchSurface(camera: camera)
          .accessibilityHidden(true)
      }
    #else
      return content.gesture(
        DragGesture(minimumDistance: 0)
          .updating($touching) { _, touching, _ in touching = true }
          .onChanged { _ in
            guard !isTrackingTouch else {
              return
            }
            isTrackingTouch = true
            camera.begin(.touch)
          }
          .onEnded { _ in endTouch() }
      )
      .onChange(of: touching) { _, touching in
        if !touching {
          endTouch()
        }
      }
      .onDisappear(perform: endTouch)
    #endif
  }

  #if !os(iOS)
  private func endTouch() {
    guard isTrackingTouch else {
      return
    }
    isTrackingTouch = false
    camera.end(.touch)
  }
  #endif

  private var isRecording: Bool {
    if case .recording = camera.recordingState { true } else { false }
  }
}

#if os(iOS)
private struct RecordTouchSurface: UIViewRepresentable {

  let camera: VideoCameraProxy

  func makeUIView(context: Context) -> TouchControl {
    let control = TouchControl(frame: .zero)
    control.isAccessibilityElement = false
    return control
  }

  func updateUIView(_ control: TouchControl, context: Context) {
    control.camera = camera
  }

  static func dismantleUIView(_ control: TouchControl, coordinator: ()) {
    control.finishPress()
  }

  final class TouchControl: UIControl {

    var camera: VideoCameraProxy?
    private var pressedCamera: VideoCameraProxy?
    private let logger = Logger(subsystem: "swiftui-camera", category: "RecordButton")

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
      guard let camera else {
        return false
      }
      let deliveryDelay = CACurrentMediaTime() - touch.timestamp
      pressedCamera = camera
      camera.begin(.touch)
      logger.debug("Record touch delivered after \(deliveryDelay * 1_000, format: .fixed(precision: 1)) ms.")
      return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
      super.endTracking(touch, with: event)
      finishPress()
    }

    override func cancelTracking(with event: UIEvent?) {
      super.cancelTracking(with: event)
      finishPress()
    }

    func finishPress() {
      let camera = pressedCamera
      pressedCamera = nil
      camera?.end(.touch)
    }

  }

}
#endif

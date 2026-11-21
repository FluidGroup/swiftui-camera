import SwiftUI

/// Starts a clip on touch-down and finishes it on release or cancellation.
/// Accessibility activation toggles recording without requiring a hold.
public struct RecordButton<Label: View>: View {
  private let camera: VideoCameraProxy
  private let label: (RecordingState) -> Label
  @GestureState private var touching = false

  public init(_ camera: VideoCameraProxy, @ViewBuilder label: @escaping (RecordingState) -> Label) {
    self.camera = camera
    self.label = label
  }

  public var body: some View {
    label(camera.recordingState)
      .contentShape(.rect)
      .gesture(
        DragGesture(minimumDistance: 0)
          .updating($touching) { _, touching, _ in touching = true }
      )
      .onChange(of: touching) { _, touching in
        if touching {
          camera.begin(.touch)
        } else {
          camera.end(.touch)
        }
      }
      .onDisappear { camera.end(.touch) }
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel("Record")
      .accessibilityValue(isRecording ? Text("Recording") : Text(""))
      .accessibilityAction {
        if isRecording { camera.stopRecording() } else { camera.startRecording() }
      }
  }

  private var isRecording: Bool {
    if case .recording = camera.recordingState { true } else { false }
  }
}

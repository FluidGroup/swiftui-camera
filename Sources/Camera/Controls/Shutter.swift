import SwiftUI

/// The shutter's behavior with your look.
///
/// Lifting outside the shutter cancels, as a button does, so a finger that slides away takes no
/// photo. It feeds the same state machine as Camera Control and the volume buttons: the first
/// source to press owns the press until it ends, and other sources are ignored meanwhile (a volume
/// press can't fire a photo a touch is holding). It is a button for VoiceOver, Voice Control, and
/// Switch Control, labeled "Take Photo". It plays a light impact at each exposure.
///
/// Gate capture with `onPhotoCapture(isEnabled:perform:)`, not `.disabled`, so hardware buttons
/// follow the same rule.
public struct Shutter<Label: View>: View {
  private let camera: CameraModel
  private let label: (ShutterState) -> Label
  @GestureState private var isTouching = false
  @State private var isTrackingTouch = false
  @State private var size: CGSize = .zero

  public init(_ camera: CameraProxy, @ViewBuilder label: @escaping (ShutterState) -> Label) {
    self.camera = camera.model
    self.label = label
  }

  public var body: some View {
    let state = camera.shutter
    return label(state)
      .contentShape(.rect)
      .onGeometryChange(for: CGSize.self) { $0.size } action: { size = $0 }
      .gesture(
        // The press comes from `onChanged`, never from observing `isTouching`: a quick tap can
        // begin and end within one view update, which `onChange(of:)` never sees.
        DragGesture(minimumDistance: 0)
          .updating($isTouching) { _, isTouching, _ in isTouching = true }
          .onChanged { _ in
            guard isTrackingTouch == false else { return }
            isTrackingTouch = true
            camera.receive(.press(.touch))
          }
          .onEnded { value in
            isTrackingTouch = false
            let isInside = CGRect(origin: .zero, size: size).contains(value.location)
            camera.receive(isInside ? .release(.touch) : .cancel(.touch))
          }
      )
      .onChange(of: isTouching) { _, isTouching in
        guard isTouching == false else { return }
        // A system cancellation resets the gesture state without `onEnded`. Deferred one turn
        // so a normal end releases first in either delivery order; the machine then ignores
        // this cancel because the touch no longer owns the press.
        isTrackingTouch = false
        Task { @MainActor [camera] in camera.receive(.cancel(.touch)) }
      }
      .onDisappear {
        // Leaving the hierarchy mid-touch ends the gesture with neither `onEnded` nor a state
        // reset.
        isTrackingTouch = false
        camera.receive(.cancel(.touch))
      }
      .accessibilityElement(children: .ignore)
      .accessibilityAddTraits(.isButton)
      .accessibilityLabel(Text("Take Photo"))
      .accessibilityAction { camera.receive(.activate) }
      .sensoryFeedback(.impact(weight: .light), trigger: state.captureCount)
  }
}

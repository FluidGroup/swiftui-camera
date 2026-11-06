import Camera
import SwiftUI

struct SimpleCameraScreen: View {
  @State private var shots: [CapturedShot] = []
  @State private var failure: CameraFailure?

  var body: some View {
    VStack(spacing: 0) {
      Camera(photo: .jpeg(quality: 0.9)) { camera in
        ZStack(alignment: .bottom) {
          switch camera.status {
          case .available:
            CameraPreview(contentMode: .fill)
            HStack(spacing: 40) {
              if camera.canFlip {
                Button("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera") {
                  camera.settings.position.flip()
                }
                .labelStyle(.iconOnly)
                .font(.title2)
                .foregroundStyle(.white)
              }
              Shutter { state in
                SimpleShutter(state: state)
              }
            }
            .padding(.bottom, 32)
          case .accessDenied:
            ContentUnavailableView(
              "Camera Access Is Off",
              systemImage: "camera",
              description: Text("Allow camera access in Settings.")
            )
          case .unavailable(.noCamera):
            ContentUnavailableView("No Camera", systemImage: "camera")
          case .unavailable(.configurationFailed(let message)):
            ContentUnavailableView(
              "Camera Failed",
              systemImage: "camera",
              description: Text(message)
            )
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black)
        .clipped()
      }
      .onPhotoCapture { photo in
        shots.insert(CapturedShot(photo), at: 0)
      }
      .onFailure { failure = $0 }

      ShotStrip(shots: shots)
    }
    .alertsFailure($failure)
  }
}

private struct SimpleShutter: View {
  let state: ShutterState

  var body: some View {
    Circle()
      .fill(.white)
      .frame(width: 72, height: 72)
      .opacity(state.isDimmed ? 0.4 : 1)
      .scaleEffect(state.isPressed ? 0.92 : 1)
      .animation(.snappy, value: state.isPressed)
  }
}

#Preview("Simple shutter states") {
  HStack(spacing: 24) {
    SimpleShutter(state: ShutterState(phase: .ready))
    SimpleShutter(state: ShutterState(phase: .ready, isPressed: true))
    SimpleShutter(state: ShutterState(phase: .busy(.processing), photosInFlight: 1))
  }
  .padding()
  .background(.black)
}

#Preview("Simple, simulated camera") {
  SimpleCameraScreen()
    .cameraSource(.simulated(CameraSimulation()))
}

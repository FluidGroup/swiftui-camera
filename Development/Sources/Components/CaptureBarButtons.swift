import Camera
import SwiftUI

/// Cycles the flash through off, auto, and on, as the top bar of a capture screen does. The camera
/// resolves the mode against the lens connected at each press.
struct FlashModeButton: View {
  @Binding var mode: FlashMode

  var body: some View {
    Button(title, systemImage: symbol) {
      mode = next
    }
    .labelStyle(.iconOnly)
  }

  private var title: String {
    switch mode {
    case .off: "Flash Off"
    case .auto: "Flash Auto"
    case .on: "Flash On"
    }
  }

  private var symbol: String {
    switch mode {
    case .off: "bolt.slash"
    case .auto: "bolt.badge.automatic"
    case .on: "bolt"
    }
  }

  private var next: FlashMode {
    switch mode {
    case .off: .auto
    case .auto: .on
    case .on: .off
    }
  }
}

/// Switches between the front and back cameras. Show it only while `camera.canFlip` is true.
struct FlipButton: View {
  @Binding var position: CameraPosition

  var body: some View {
    Button("Flip Camera", systemImage: "arrow.triangle.2.circlepath.camera") {
      position.flip()
    }
    .labelStyle(.iconOnly)
  }
}

#Preview("Capture bar buttons") {
  @Previewable @State var flash = FlashMode.off
  @Previewable @State var position = CameraPosition.back
  HStack(spacing: 28) {
    FlashModeButton(mode: $flash)
    FlipButton(position: $position)
  }
  .font(.title3)
  .foregroundStyle(.white)
  .padding()
  .background(.black)
}

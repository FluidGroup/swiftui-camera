import Camera
import SwiftUI

/// The shutter row of VSCO Capture: looks scroll under a shutter that stays in the middle, and the
/// look under the shutter is the selection. The first slot is no look, which shows a plain shutter.
///
/// Swipe the looks on either side, or tap one to bring it under the shutter. A drag that starts on
/// the shutter presses it instead of scrolling.
struct LookCarousel: View {
  let camera: CameraProxy
  let looks: [CameraLook]
  @Binding var selection: CameraLook?

  private let slotSize: CGFloat = 48
  private let spacing: CGFloat = 28
  private let shutterSize: CGFloat = 76

  var body: some View {
    // The margins must be right in the first layout, or the scroll view starts off center.
    GeometryReader { proxy in
      ScrollView(.horizontal) {
        HStack(spacing: spacing) {
          ForEach(slots, id: \.self) { slot in
            Button {
              withAnimation(.snappy) { selection = slot.look }
            } label: {
              LookIcon(symbol: slot.symbol)
                .frame(width: slotSize, height: slotSize)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(slot.name)
          }
        }
        .frame(height: proxy.size.height)
        .scrollTargetLayout()
      }
      .scrollIndicators(.hidden)
      .scrollTargetBehavior(.viewAligned)
      .scrollPosition(id: centeredSlot, anchor: .center)
      .contentMargins(.horizontal, max((proxy.size.width - slotSize) / 2, 0), for: .scrollContent)
    }
    .frame(height: shutterSize)
    .overlay {
      Shutter(camera) { state in
        LookShutter(state: state, look: selection)
      }
      .frame(width: shutterSize, height: shutterSize)
    }
  }

  private var slots: [Slot] {
    [.plain] + looks.map(Slot.look)
  }

  private var centeredSlot: Binding<Slot?> {
    Binding(
      get: { selection.map(Slot.look) ?? .plain },
      set: { slot in
        guard let slot, slot.look != selection else { return }
        selection = slot.look
      }
    )
  }
}

private enum Slot: Hashable {
  case plain
  case look(CameraLook)

  var look: CameraLook? {
    if case .look(let look) = self { look } else { nil }
  }

  var symbol: String {
    look?.symbol ?? "dot.square"
  }

  var name: String {
    look?.name ?? "No Look"
  }
}

private struct LookIcon: View {
  let symbol: String

  var body: some View {
    Circle()
      .fill(Color(white: 0.17))
      .overlay {
        Image(systemName: symbol)
          .foregroundStyle(.white)
      }
  }
}

private struct LookShutter: View {
  let state: ShutterState
  let look: CameraLook?

  var body: some View {
    ZStack {
      Circle()
        .fill(look == nil ? Color(white: 0.17) : .black)
      Circle()
        .strokeBorder(.white, lineWidth: 3)
      if let look {
        Image(systemName: look.symbol)
          .font(.title2)
          .foregroundStyle(.yellow)
      }
      if state.showsProgress {
        ProgressView()
          .tint(.white)
      }
    }
    .opacity(state.isDimmed ? 0.4 : 1)
    .scaleEffect(state.isPressed ? 0.92 : 1)
    .animation(.snappy, value: state.isPressed)
  }
}

#Preview("Look carousel on a simulated camera") {
  @Previewable @State var look: CameraLook?
  Camera { camera in
    LookCarousel(camera: camera, looks: CameraLook.samples, selection: $look)
  }
  .onPhotoCapture { _ in }
  .cameraSource(.simulated(CameraSimulation()))
  .background(.black)
}

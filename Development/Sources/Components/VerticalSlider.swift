import SwiftUI
import Viewfinder

/// The strength slider VSCO Capture puts on the preview's trailing edge: the control's icon, a thin
/// line, and a knob. It is a look for `Dial`, so a drag walks the parameter's stops with a haptic
/// at each, the line's length spans the whole range, and VoiceOver adjusts it one stop per swipe.
struct VerticalSlider<Parameter: CameraParameter>: View {
  @Binding var control: ManualControl<Parameter>
  let symbol: String
  var length: CGFloat = 220

  var body: some View {
    VStack(spacing: 12) {
      Image(systemName: symbol)
        .foregroundStyle(.yellow)
        .accessibilityHidden(true)
      Dial($control, axis: .vertical, pointsPerStop: pointsPerStop) { dial in
        VerticalSliderLook(dial: dial, length: length)
      }
    }
  }

  private var pointsPerStop: CGFloat {
    length / CGFloat(max(control.stops.count - 1, 1))
  }
}

private struct VerticalSliderLook<Parameter: CameraParameter>: View {
  let dial: DialState<Parameter>
  let length: CGFloat

  private let knobSize: CGFloat = 16

  var body: some View {
    ZStack(alignment: .top) {
      Capsule()
        .fill(.yellow)
        .frame(width: 1.5)
      Circle()
        .fill(.yellow)
        .frame(width: knobSize, height: knobSize)
        .scaleEffect(dial.isScrubbing ? 1.3 : 1)
        .overlay(alignment: .trailing) {
          if dial.isScrubbing {
            Text(dial.control.formatted())
              .font(.caption.monospacedDigit().bold())
              .foregroundStyle(.yellow)
              .fixedSize()
              .offset(x: -(knobSize + 8))
          }
        }
        .offset(y: (1 - dial.position) * (length - knobSize))
    }
    .frame(width: 44, height: length)
    .animation(.snappy, value: dial.isScrubbing)
  }
}

#Preview("Vertical slider, scrubbable with no camera") {
  @Previewable @State var bias = ManualControl(
    value: ExposureBias(0),
    range: ExposureBias(-2)...ExposureBias(2),
    supportsAutomatic: false
  )
  VerticalSlider(control: $bias, symbol: "plusminus")
    .padding(40)
    .background(.black)
}

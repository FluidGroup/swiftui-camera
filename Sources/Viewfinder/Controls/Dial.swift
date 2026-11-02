import SwiftUI

/// What a dial look needs: the control, plus whether a finger is scrubbing it.
@dynamicMemberLookup
public struct DialState<Parameter: CameraParameter>: Sendable, Hashable {
  public var control: ManualControl<Parameter>
  /// A drag is in progress. Show a large readout over the preview while it's true.
  public var isScrubbing: Bool

  public init(control: ManualControl<Parameter>, isScrubbing: Bool = false) {
    self.control = control
    self.isScrubbing = isScrubbing
  }

  public subscript<Value>(dynamicMember keyPath: KeyPath<ManualControl<Parameter>, Value>) -> Value {
    control[keyPath: keyPath]
  }
}

/// A headless dial for one manual parameter: a ruler, a wheel, or a knob, drawn by your look.
///
/// It owns what a pro camera dial does and draws nothing:
/// - Dragging along `axis` walks the parameter's stops (third stops for ISO, shutter speed, and
///   bias; the white-balance presets and mired steps for temperature), one stop per
///   `pointsPerStop`, snapping at each. Dragging toward the leading edge (or up) raises the value,
///   the way a ruler slides under a fixed needle. Dragging an automatic control takes it to
///   manual at its current reading, as pro camera apps do.
/// - A selection haptic at each stop it crosses, and none from live readings while automatic.
/// - VoiceOver: one adjustable element whose value is the camera notation ("1/250"); swiping up
///   or down moves one stop.
/// - Inert while `control.isAdjustable` is false (the light meter, an unsupported parameter).
///
/// On a live camera every step is an intent (shown at once, coalesced on the way to the device).
public struct Dial<Parameter: CameraParameter, Content: View>: View {
  private let binding: Binding<ManualControl<Parameter>>
  private let axis: Axis
  private let pointsPerStop: CGFloat
  private let content: (DialState<Parameter>) -> Content
  @GestureState private var isScrubbing = false
  @State private var scrub: (origin: Int, current: Int)?

  public init(
    _ control: Binding<ManualControl<Parameter>>,
    axis: Axis = .horizontal,
    pointsPerStop: CGFloat = 12,
    @ViewBuilder content: @escaping (DialState<Parameter>) -> Content
  ) {
    self.binding = control
    self.axis = axis
    self.pointsPerStop = pointsPerStop
    self.content = content
  }

  public var body: some View {
    let control = binding.wrappedValue
    return content(DialState(control: control, isScrubbing: isScrubbing))
      .contentShape(.rect)
      .allowsHitTesting(control.isAdjustable)
      .gesture(
        DragGesture(minimumDistance: 2)
          .updating($isScrubbing) { _, isScrubbing, _ in isScrubbing = true }
          .onChanged { drag in
            let control = binding.wrappedValue
            let stops = control.stops
            guard !stops.isEmpty else { return }
            let origin = scrub?.origin ?? Self.nearestStop(to: control, in: stops)
            let along = axis == .horizontal ? -drag.translation.width : -drag.translation.height
            let index = (origin + Int((along / pointsPerStop).rounded(.towardZero))).clamped(to: 0...(stops.count - 1))
            scrub = (origin, index)
            if stops[index] != control.value {
              binding.wrappedValue.value = stops[index]
            }
          }
          .onEnded { _ in scrub = nil }
      )
      .onChange(of: isScrubbing) { _, isScrubbing in
        // A system cancellation resets the gesture state without `onEnded`; the next drag must
        // not start from this one's origin.
        if !isScrubbing { scrub = nil }
      }
      .sensoryFeedback(.selection, trigger: scrub?.current) { old, new in
        old != nil && new != nil && old != new
      }
      .accessibilityElement(children: .ignore)
      .accessibilityValue(Text(control.formatted()))
      .accessibilityAdjustableAction { direction in
        guard binding.wrappedValue.isAdjustable else { return }
        let control = binding.wrappedValue
        let stops = control.stops
        guard !stops.isEmpty else { return }
        let current = Self.nearestStop(to: control, in: stops)
        let next: Int =
          switch direction {
          case .increment: current + 1
          case .decrement: current - 1
          @unknown default: current
          }
        guard stops.indices.contains(next) else { return }
        binding.wrappedValue.value = stops[next]
      }
  }

  private static func nearestStop(to control: ManualControl<Parameter>, in stops: [Parameter]) -> Int {
    let position = control.position
    return stops.indices.min {
      abs(Parameter.position(of: stops[$0], in: control.range) - position) < abs(Parameter.position(of: stops[$1], in: control.range) - position)
    } ?? 0
  }
}

public enum ControlAvailability: Sendable, Hashable {
  case adjustable
  /// A read-only live reading. Exposure bias shows the light meter (`exposureTargetOffset`)
  /// while the exposure program is `.manual`.
  case metering
  /// The connected device or format can't set it. A virtual device can't take custom exposure,
  /// for example.
  case unsupported
}

/// One manual parameter as the UI sees it: the value to show, its auto toggle, its range, and
/// the device's live reading.
///
/// A value type. Stock controls bind to it through the camera's proxy, as in
/// `Slider(value: camera.$exposure.iso.position)`, and previews build it with literals.
///
/// Writing is intent. The camera shows a written value at once (optimistic), applies the latest
/// value to the device (intermediate drag values are skipped, never queued), and keeps the
/// device's own value in `reading`. Fields with an internal setter belong to the camera, which
/// ignores them on write.
public struct ManualControl<Parameter: CameraParameter>: Sendable, Hashable {
  /// The target while manual, the live reading while automatic. Writing it takes the parameter
  /// out of automatic, the way dragging an auto slider does in a pro camera app.
  public var value: Parameter {
    didSet { if supportsAutomatic { isAutomatic = false } }
  }

  public var isAutomatic: Bool
  public internal(set) var supportsAutomatic: Bool
  /// The device's current limits. They change with the lens and format; the camera clamps the
  /// target into them and keeps it there.
  public internal(set) var range: ClosedRange<Parameter>
  /// The device's live value in every mode.
  public internal(set) var reading: Parameter
  public internal(set) var availability: ControlAvailability
  /// The device is converging: adjusting exposure, focus, or white balance, or ramping zoom.
  public internal(set) var isAdjusting: Bool

  public init(
    value: Parameter,
    range: ClosedRange<Parameter>,
    isAutomatic: Bool = false,
    supportsAutomatic: Bool = true,
    reading: Parameter? = nil,
    availability: ControlAvailability = .adjustable,
    isAdjusting: Bool = false
  ) {
    self.value = value
    self.range = range
    self.isAutomatic = isAutomatic
    self.supportsAutomatic = supportsAutomatic
    self.reading = reading ?? value
    self.availability = availability
    self.isAdjusting = isAdjusting
  }

  /// Whether a person can change it now. `false` for the light meter and unsupported controls.
  public var isAdjustable: Bool {
    switch availability {
    case .adjustable: true
    case .metering, .unsupported: false
    }
  }

  /// `value` on the parameter's perceptual scale, 0...1 across `range`. Bind a `Slider` here.
  public var position: Double {
    get { Parameter.position(of: value, in: range) }
    set { value = Parameter.value(at: newValue, in: range) }
  }

  public var stops: [Parameter] {
    Parameter.stops(in: range)
  }

  public func formatted() -> String {
    value.formatted()
  }
}

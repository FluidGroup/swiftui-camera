/// Temperature and tint lock together: writing either one locks white balance at both targets, and
/// turning on either one's `isAutomatic` returns both to automatic.
public struct WhiteBalanceControls: Sendable, Hashable {
  public var temperature: ManualControl<Kelvin> {
    didSet {
      if temperature.isAutomatic != oldValue.isAutomatic {
        tint.isAutomatic = temperature.isAutomatic
      }
    }
  }
  public var tint: ManualControl<Tint> {
    didSet {
      if tint.isAutomatic != oldValue.isAutomatic {
        temperature.isAutomatic = tint.isAutomatic
      }
    }
  }

  public init(temperature: ManualControl<Kelvin>, tint: ManualControl<Tint>) {
    self.temperature = temperature
    self.tint = tint
  }

  public var isAutomatic: Bool {
    get { temperature.isAutomatic }
    set {
      temperature.isAutomatic = newValue
      tint.isAutomatic = newValue
    }
  }
}

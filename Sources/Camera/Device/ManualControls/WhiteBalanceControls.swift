/// Temperature and tint lock together: writing either one locks white balance at both targets.
public struct WhiteBalanceControls: Sendable, Hashable {
  public var temperature: ManualControl<Kelvin>
  public var tint: ManualControl<Tint>

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

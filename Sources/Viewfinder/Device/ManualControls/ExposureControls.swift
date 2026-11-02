public enum ExposureProgram: Sendable, Hashable, Codable {
  /// Continuous auto exposure. Bias applies.
  case automatic
  /// Shutter speed fixed, ISO automatic. Bias applies. Native on iOS 27
  /// (`AVCaptureDevice.autoISO`); emulated on iOS 26.
  case shutterPriority(ShutterSpeed)
  /// ISO fixed, shutter speed automatic. Native on iOS 27, emulated on iOS 26.
  case isoPriority(ISO)
  /// Custom exposure with both fixed. Bias becomes a light meter.
  case manual(ShutterSpeed, ISO)
}

/// ISO, shutter speed, and bias, coupled the way the device couples them.
///
/// The two auto toggles are the program: both automatic is `.automatic`, a fixed shutter speed
/// with automatic ISO is `.shutterPriority`, and so on. `program` is computed from the toggles,
/// so the two can never disagree.
public struct ExposureControls: Sendable, Hashable {
  public var iso: ManualControl<ISO>
  public var shutterSpeed: ManualControl<ShutterSpeed>
  /// `.metering` under `.manual`, where it shows `exposureTargetOffset` instead of a bias.
  public var bias: ManualControl<ExposureBias>

  public init(iso: ManualControl<ISO>, shutterSpeed: ManualControl<ShutterSpeed>, bias: ManualControl<ExposureBias>) {
    self.iso = iso
    self.shutterSpeed = shutterSpeed
    self.bias = bias
  }

  public var program: ExposureProgram {
    get {
      switch (iso.isAutomatic, shutterSpeed.isAutomatic) {
      case (true, true): .automatic
      case (true, false): .shutterPriority(shutterSpeed.value)
      case (false, true): .isoPriority(iso.value)
      case (false, false): .manual(shutterSpeed.value, iso.value)
      }
    }
    set {
      switch newValue {
      case .automatic:
        iso.isAutomatic = true
        shutterSpeed.isAutomatic = true
      case .shutterPriority(let speed):
        shutterSpeed.value = speed
        shutterSpeed.isAutomatic = false
        iso.isAutomatic = true
      case .isoPriority(let sensitivity):
        iso.value = sensitivity
        iso.isAutomatic = false
        shutterSpeed.isAutomatic = true
      case .manual(let speed, let sensitivity):
        shutterSpeed.value = speed
        iso.value = sensitivity
        shutterSpeed.isAutomatic = false
        iso.isAutomatic = false
      }
    }
  }
}

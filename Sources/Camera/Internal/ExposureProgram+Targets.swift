extension ExposureProgram {
  var isoTarget: ISO? {
    switch self {
    case .automatic, .shutterPriority: nil
    case .isoPriority(let iso): iso
    case .manual(_, let iso): iso
    }
  }

  var shutterSpeedTarget: ShutterSpeed? {
    switch self {
    case .automatic, .isoPriority: nil
    case .shutterPriority(let speed): speed
    case .manual(let speed, _): speed
    }
  }

  var isManual: Bool {
    switch self {
    case .manual: true
    case .automatic, .shutterPriority, .isoPriority: false
    }
  }

  func clamped(iso isoRange: ClosedRange<ISO>, shutterSpeed speedRange: ClosedRange<ShutterSpeed>) -> ExposureProgram {
    switch self {
    case .automatic: .automatic
    case .shutterPriority(let speed): .shutterPriority(speed.clamped(to: speedRange))
    case .isoPriority(let iso): .isoPriority(iso.clamped(to: isoRange))
    case .manual(let speed, let iso): .manual(speed.clamped(to: speedRange), iso.clamped(to: isoRange))
    }
  }

  func fixing(iso: ISO) -> ExposureProgram {
    switch self {
    case .automatic, .isoPriority: .isoPriority(iso)
    case .shutterPriority(let speed), .manual(let speed, _): .manual(speed, iso)
    }
  }

  func fixing(shutterSpeed: ShutterSpeed) -> ExposureProgram {
    switch self {
    case .automatic, .shutterPriority: .shutterPriority(shutterSpeed)
    case .isoPriority(let iso), .manual(_, let iso): .manual(shutterSpeed, iso)
    }
  }
}

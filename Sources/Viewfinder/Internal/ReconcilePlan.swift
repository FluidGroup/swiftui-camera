enum DeviceAspect: CaseIterable, Sendable, Hashable {
  case lens
  case zoom
  case exposure
  case bias
  case focus
  case whiteBalance
}

extension DeviceIntent {
  func aspects(toReconcileFrom applied: DeviceIntent?, lensChanged: Bool, full: Bool) -> Set<DeviceAspect> {
    guard let applied, !full, !lensChanged else { return Set(DeviceAspect.allCases) }
    var aspects: Set<DeviceAspect> = []
    if zoom != applied.zoom { aspects.insert(.zoom) }
    if exposure != applied.exposure { aspects.insert(.exposure) }
    if bias != applied.bias { aspects.insert(.bias) }
    if focus != applied.focus || focusTap != applied.focusTap { aspects.insert(.focus) }
    if whiteBalance != applied.whiteBalance { aspects.insert(.whiteBalance) }
    return aspects
  }
}

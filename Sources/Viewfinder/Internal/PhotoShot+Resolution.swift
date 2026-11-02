extension PhotoShot {
  /// The shot the tracked settings are built from. While a lens switch is pending, the facts may
  /// describe the previous camera, and the readiness coordinator rejects settings the output
  /// can't take, so the settings carry only what every camera accepts: flash off and the default
  /// size. `resolved(...)` restores the real shot against the connected camera at capture.
  func forTracking(lensSwitchPending: Bool) -> PhotoShot {
    guard lensSwitchPending else { return self }
    var shot = self
    shot.flash = .off
    shot.dimensions = nil
    return shot
  }

  /// `capturePhoto` throws for a flash mode or a size the connected camera doesn't have, so
  /// nothing from the press is trusted here.
  func resolved(flashModes: Set<FlashMode>, offered: [PhotoResolution], ceiling: PhotoResolution?) -> PhotoShot {
    var shot = self
    shot.flash = flashModes.contains(flash) ? flash : .off
    let fitting = offered.filter { size in ceiling.map { size.pixelCount <= $0.pixelCount } ?? true }
    shot.dimensions = resolution.resolve(in: fitting)
    return shot
  }
}

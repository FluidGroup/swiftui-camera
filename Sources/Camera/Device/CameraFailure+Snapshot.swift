extension CameraFailure {

  /// The camera at the press of a photo that failed, as `CameraProxy` showed it then.
  ///
  /// Log it with the failure. A capture that fails only for some settings or scenes shows which
  /// here: pointing the camera elsewhere moves the readings (ISO, shutter speed, focus) even when
  /// every setting stays the same.
  public struct Snapshot: Sendable, Hashable {
    /// What the app asked for.
    public let settings: CameraSettings
    /// The lens connected at the press. It differs from `settings.lens` while a switch is pending.
    public let lens: CameraLens?
    /// What the press asked the device to deliver. `nil` before the camera is configured.
    public let format: PhotoFormat?
    public let resolution: PhotoResolution?
    /// Each control's target and the device's reading.
    public let exposure: ExposureControls
    public let whiteBalance: WhiteBalanceControls
    public let focus: ManualControl<LensPosition>
    public let zoom: ManualControl<ZoomFactor>
    /// The shutter just before the press. `photosInFlight` counts earlier photos still
    /// processing.
    public let shutter: ShutterState
  }
}

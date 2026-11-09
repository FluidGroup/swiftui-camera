import SwiftUI

/// The camera, as `Camera` hands it to its content. Pass it to `CameraPreview` and `Shutter`, read
/// its state directly, or bind a control with `$`, as in
/// `Slider(value: camera.$exposure.iso.position)`. Every binding writes `settings` and reaches the
/// device at once.
///
/// Valid only inside the `Camera` that made it, like `GeometryProxy`.
@MainActor
public struct CameraProxy {
  /// What was asked. The same storage as the binding passed to `Camera`, when there is one.
  @Binding public var settings: CameraSettings

  /// The settings as the device sees them: clamped to the connected lens, with live readings
  /// and availability. Writing one writes `settings` with the values the control showed, so
  /// moving ISO also stores the clamped shutter speed.
  @Binding public var exposure: ExposureControls
  @Binding public var whiteBalance: WhiteBalanceControls
  /// Automatic is continuous autofocus. A target locks focus at that lens position.
  @Binding public var focus: ManualControl<LensPosition>
  /// On the Camera app's scale. Never automatic.
  @Binding public var zoom: ManualControl<ZoomFactor>

  /// Starts as `.accessDenied` when access is already denied, so a denied screen never flashes
  /// an empty preview first.
  public var status: CameraStatus {
    model.status
  }
  /// The positions this device has. Empty until discovery.
  public var availablePositions: [CameraPosition] {
    model.availablePositions
  }
  public var canFlip: Bool {
    model.canFlip
  }
  /// The lenses at the current position, in zoom order. Empty until discovery.
  public var lenses: [CameraLens] {
    model.lenses
  }
  /// What the connected device delivers: Apple ProRAW, or the fallback. `nil` until configured.
  public var photoFormat: PhotoFormat? {
    model.photoFormat
  }
  /// The sizes the connected lens delivers, ascending.
  public var photoResolutions: [PhotoResolution] {
    model.photoResolutions
  }
  public var shutter: ShutterState {
    model.shutter
  }
  public var cameraControlAppearance: CameraControlAppearance {
    model.cameraControlAppearance
  }

  /// The size a press takes for `preference` on the connected lens, so a picker can label each
  /// choice with it. Two preferences resolve to the same size on a lens with one size. `nil`
  /// until configured.
  public func photoResolution(for preference: ResolutionPreference) -> PhotoResolution? {
    model.photoResolution(for: preference)
  }

  /// Takes a photo from code when the shutter is ready: a self-timer, a keyboard shortcut.
  /// VoiceOver's action on `Shutter` is this same press. It is ignored while another source
  /// holds the shutter, and while capture is off.
  public func activateShutter() {
    model.activateShutter()
  }

  let model: CameraModel

  init(model: CameraModel, settings: Binding<CameraSettings>) {
    self.model = model
    _settings = Binding(
      get: { settings.wrappedValue },
      set: { newValue in
        settings.wrappedValue = newValue
        model.sync()
      }
    )
    _exposure = Binding(get: { model.exposure }, set: { model.exposure = $0 })
    _whiteBalance = Binding(get: { model.whiteBalance }, set: { model.whiteBalance = $0 })
    _focus = Binding(get: { model.focus }, set: { model.focus = $0 })
    _zoom = Binding(get: { model.zoom }, set: { model.zoom = $0 })
  }
}

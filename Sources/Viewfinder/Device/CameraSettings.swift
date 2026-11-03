/// What the app or the person asked the camera to do. A value: store it, compare it, restore it.
///
/// The camera writes back what changes on its side: Camera Control, the lens it picked for a
/// position, the position a Mac falls back to, the lens it stays on when a switch fails, and, on
/// iOS, focus returning to automatic when the scene changes after a tap. It never writes live
/// readings or clamped values here; `CameraProxy` shows those. A request the connected lens can't
/// reach stays as asked, so a lens that can reach it applies it again.
public struct CameraSettings: Sendable, Hashable, Codable {
  public enum Focus: Sendable, Hashable, Codable {
    /// Continuous autofocus. A tap from `focus(at:)` runs on top of it.
    case automatic
    case locked(LensPosition)
  }

  public enum WhiteBalance: Sendable, Hashable, Codable {
    case automatic
    case locked(temperature: Kelvin, tint: Tint)
  }

  /// Setting a different position clears `lens` and `zoom`. The camera then picks that
  /// position's default lens and writes it to `lens`.
  public var position: CameraPosition {
    get { storedPosition }
    set {
      guard newValue != storedPosition else { return }
      storedPosition = newValue
      storedLens = nil
      zoom = nil
    }
  }

  /// `nil` until the camera picks the default lens. Setting a different lens also sets
  /// `position` and clears `zoom`.
  public var lens: CameraLens? {
    get { storedLens }
    set {
      guard newValue != storedLens else { return }
      storedLens = newValue
      if let newValue { storedPosition = newValue.position }
      zoom = nil
    }
  }

  /// On the Camera app's scale. `nil` is the lens's own zoom.
  public var zoom: ZoomFactor?
  public var exposure: ExposureProgram
  /// Applies under every program except `.manual`.
  public var exposureBias: ExposureBias
  public var whiteBalance: WhiteBalance

  /// Setting `.locked` ends a tap's focus. Setting `.automatic` during a tap's focus changes
  /// nothing, because the tap already runs on automatic.
  public var focus: Focus {
    get { storedFocus }
    set {
      storedFocus = newValue
      if case .locked = newValue { tapPoint = nil }
    }
  }

  /// Where the last tap asked the camera to focus and expose. On iOS the camera sets it back to
  /// `nil` when the scene changes, so a focus square drawn from it disappears at that moment. A
  /// restored value has none: a tap is not worth saving.
  public var focusPoint: DevicePoint? {
    tapPoint
  }

  /// Resolved against the lens connected when the press reaches the photo output.
  public var photoResolution: ResolutionPreference
  public var flash: FlashMode

  public init(
    position: CameraPosition = .back,
    exposure: ExposureProgram = .automatic,
    exposureBias: ExposureBias = ExposureBias(0),
    whiteBalance: WhiteBalance = .automatic,
    focus: Focus = .automatic,
    photoResolution: ResolutionPreference = .full,
    flash: FlashMode = .off
  ) {
    storedPosition = position
    storedLens = nil
    zoom = nil
    self.exposure = exposure
    self.exposureBias = exposureBias
    self.whiteBalance = whiteBalance
    storedFocus = focus
    self.photoResolution = photoResolution
    self.flash = flash
  }

  /// A tap: a one-shot autofocus and auto exposure at `point`, which also unlocks focus. Tapping
  /// the same point twice focuses twice, which assigning a property can't express.
  public mutating func focus(at point: DevicePoint) {
    storedFocus = .automatic
    tapPoint = point
    tapCount += 1
  }

  /// Unlike the `lens` setter, keeps `zoom`: the device chose this lens, not a person.
  mutating func resolve(to lens: CameraLens) {
    storedPosition = lens.position
    storedLens = lens
  }

  mutating func endTapFocus() {
    tapPoint = nil
  }

  private(set) var tapCount = 0
  private var storedPosition: CameraPosition
  private var storedLens: CameraLens?
  private var storedFocus: Focus
  private var tapPoint: DevicePoint?

  private enum CodingKeys: String, CodingKey {
    case storedPosition = "position"
    case storedLens = "lens"
    case zoom
    case exposure
    case exposureBias
    case whiteBalance
    case storedFocus = "focus"
    case photoResolution
    case flash
  }
}

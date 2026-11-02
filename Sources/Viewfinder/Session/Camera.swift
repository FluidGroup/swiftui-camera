import SwiftUI

/// A photo camera as a container view, the way `Map` and `ScrollView` are containers: it owns
/// the session, draws nothing itself, and hands its content a `CameraProxy`.
///
/// ```swift
/// Camera(photo: .jpeg(quality: 0.9)) { camera in
///   CameraPreview(contentMode: .fill)
///   Shutter { state in MyShutter(state: state) }
/// }
/// .onPhotoCapture { photo in save(photo) }
/// ```
///
/// It lays its content out in a `ZStack`, so controls stack over the preview. The camera runs
/// while the view is on screen, even while the content shows nothing. When the view disappears,
/// the session stops after a start still in flight and after every photo that began has reached
/// `onPhotoCapture`. `CameraPreview`, `Shutter`, and hardware buttons work with the camera of the
/// `Camera` they're inside.
///
/// The session configuration (`photo`, `lenses`, `mirroring`, `hardwareControls`) and the
/// `.cameraSource(_:)` above it are fixed for a session: a change restarts it. A change to
/// `photo.customizeSettings` alone doesn't, because the camera reads it at each press. Everything
/// a person changes while shooting lives in `CameraSettings`, which the camera keeps itself unless
/// you pass a binding to own it.
public struct Camera<Content: View>: View {
  @Environment(\.cameraSource) private var source
  @State private var ownSettings = CameraSettings()
  private let settings: Binding<CameraSettings>?
  private let configuration: EngineConfiguration
  private let content: (CameraProxy) -> Content
  private var capture: CameraCapture?
  private var failureAction: (@MainActor (CameraFailure) -> Void)?

  /// A camera that keeps its own settings, starting from `CameraSettings()`.
  public init(
    photo: PhotoOptions = .heif,
    lenses: LensSelection = .wide,
    mirroring: Mirroring = .matchesPreview,
    hardwareControls: [HardwareControl] = [],
    @ViewBuilder content: @escaping (CameraProxy) -> Content
  ) {
    self.settings = nil
    self.configuration = EngineConfiguration(photo: photo, lensSelection: lenses, mirroring: mirroring, hardwareControls: hardwareControls)
    self.content = content
  }

  /// A camera whose settings the app owns, to save, restore, or change from its own code.
  ///
  /// The camera writes back what changes on its side, such as a Camera Control adjustment or
  /// the lens it picks for a position. A change the app makes reaches the device at the next
  /// view update, and a press sends the latest value before it captures.
  public init(
    settings: Binding<CameraSettings>,
    photo: PhotoOptions = .heif,
    lenses: LensSelection = .wide,
    mirroring: Mirroring = .matchesPreview,
    hardwareControls: [HardwareControl] = [],
    @ViewBuilder content: @escaping (CameraProxy) -> Content
  ) {
    self.settings = settings
    self.configuration = EngineConfiguration(photo: photo, lensSelection: lenses, mirroring: mirroring, hardwareControls: hardwareControls)
    self.content = content
  }

  /// Takes a photo when a press ends, from `Shutter`, Camera Control, or the volume buttons,
  /// following the photo output's readiness. Without it the camera only previews: the shutter
  /// reads `.unavailable` and the volume buttons keep changing the volume.
  ///
  /// - Parameters:
  ///   - isEnabled: The app's own gate. Pressing is ignored while it's false and
  ///     `shutter.phase` reads `.unavailable`.
  ///   - action: Runs on the main actor for each photo in an unstructured task, so an async
  ///     save finishes even if the screen closes meanwhile.
  public func onPhotoCapture(isEnabled: Bool = true, perform action: @escaping @MainActor (Photo) async -> Void) -> Camera {
    var camera = self
    camera.capture = CameraCapture(isEnabled: isEnabled, action: action)
    return camera
  }

  /// A failure that didn't end the session, such as a photo that couldn't be captured or a lens
  /// switch that didn't connect.
  public func onFailure(perform action: @escaping @MainActor (CameraFailure) -> Void) -> Camera {
    var camera = self
    camera.failureAction = action
    return camera
  }

  public var body: some View {
    CameraSession(
      settings: settings ?? $ownSettings,
      configuration: configuration,
      source: source,
      capture: capture,
      failureAction: failureAction,
      content: content
    )
  }
}

extension View {
  /// The source for every `Camera` below. `.automatic` uses hardware on a device and a
  /// simulated camera in the Simulator and in Xcode previews.
  public func cameraSource(_ source: CameraSource) -> some View {
    environment(\.cameraSource, source)
  }
}

extension EnvironmentValues {
  @Entry var cameraSource: CameraSource = .automatic
}

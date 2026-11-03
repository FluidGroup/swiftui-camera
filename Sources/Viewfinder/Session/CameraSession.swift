import AVKit
import SwiftUI
import os

struct CameraSession<Content: View>: View {
  @Binding var settings: CameraSettings
  let configuration: EngineConfiguration
  let source: CameraSource
  let capture: CameraCapture?
  let failureAction: (@MainActor (CameraFailure) -> Void)?
  let content: (CameraProxy) -> Content
  @SessionModel private var model: CameraModel

  init(
    settings: Binding<CameraSettings>,
    configuration: EngineConfiguration,
    source: CameraSource,
    capture: CameraCapture?,
    failureAction: (@MainActor (CameraFailure) -> Void)?,
    content: @escaping (CameraProxy) -> Content
  ) {
    _settings = settings
    self.configuration = configuration
    self.source = source
    self.capture = capture
    self.failureAction = failureAction
    self.content = content
    _model = SessionModel(configuration: configuration, source: source, settings: settings, capture: capture, failureAction: failureAction)
  }

  var body: some View {
    let model = model
    let allowsCapture = capture?.isEnabled ?? false
    let session = SessionKey(configuration: configuration, source: source)
    // The stack exists even while the content is empty, such as before the camera runs, so the
    // session's lifecycle never depends on what the content shows.
    return ZStack {
      content(CameraProxy(model: model, settings: $settings))
    }
    .environment(model)
    .task(id: ObjectIdentifier(model)) { await model.run() }
    .onChange(of: allowsCapture, initial: true) { model.allowsCapture = allowsCapture }
    .onChange(of: settings) { model.sync() }
    .onChange(of: session) {
      model.detach()
      let next = CameraModel(configuration: configuration, source: source, settings: $settings, handlers: model.handlers)
      next.allowsCapture = allowsCapture
      self.model = next
    }
    .modifier(HardwareShutterEvents(camera: model))
  }
}

/// The model for the current session. SwiftUI calls `update()` before each body evaluation,
/// which hands the model the binding and the handlers the closures. The model reads them later,
/// when the engine, a press, or a photo needs them.
@propertyWrapper
struct SessionModel: DynamicProperty {
  @State private var model: CameraModel
  private let settings: Binding<CameraSettings>
  private let customizeSettings: (@MainActor @Sendable (AVCapturePhotoSettings) -> Void)?
  private let deliver: (@MainActor (Photo) async -> Void)?
  private let failureAction: (@MainActor (CameraFailure) -> Void)?

  @MainActor
  init(
    configuration: EngineConfiguration,
    source: CameraSource,
    settings: Binding<CameraSettings>,
    capture: CameraCapture?,
    failureAction: (@MainActor (CameraFailure) -> Void)?
  ) {
    self.settings = settings
    customizeSettings = configuration.photo.customizeSettings
    deliver = capture?.action
    self.failureAction = failureAction
    _model = State(initialValue: CameraModel(configuration: configuration, source: source, settings: settings, handlers: SessionHandlers()))
  }

  @MainActor
  var wrappedValue: CameraModel {
    get { model }
    nonmutating set { model = newValue }
  }

  func update() {
    MainActor.assumeIsolated {
      model.settingsBinding = settings
      model.handlers.customizeSettings = customizeSettings
      model.handlers.deliver = deliver
      model.handlers.failureAction = failureAction
    }
  }
}

/// The app's closures, shared by every model of a session, so a photo or a failure that a
/// replaced model still has in flight reaches the closure from the latest render.
@MainActor
final class SessionHandlers {
  var customizeSettings: (@MainActor @Sendable (AVCapturePhotoSettings) -> Void)?
  var deliver: (@MainActor (Photo) async -> Void)?
  var failureAction: (@MainActor (CameraFailure) -> Void)?
}

struct CameraCapture {
  let isEnabled: Bool
  let action: @MainActor (Photo) async -> Void
}

private struct SessionKey: Hashable {
  let encoding: PhotoOptions.Encoding
  let lensSelection: LensSelection
  let mirroring: Mirroring
  let hardwareControls: [HardwareControl]
  let source: CameraSource

  init(configuration: EngineConfiguration, source: CameraSource) {
    encoding = configuration.photo.encoding
    lensSelection = configuration.lensSelection
    mirroring = configuration.mirroring
    hardwareControls = configuration.hardwareControls
    self.source = source
  }
}

struct HardwareShutterEvents: ViewModifier {
  let camera: CameraModel

  func body(content: Content) -> some View {
    #if os(iOS)
    // `isEnabled` follows whether the camera can respond at all (never readiness), so the
    // volume buttons go back to changing volume exactly when the camera stops listening.
    content.onCameraCaptureEvent(isEnabled: camera.respondsToHardwareButtons) { event in
      switch event.phase {
      case .began:
        camera.receive(.press(.hardware))
      case .ended:
        camera.receive(.release(.hardware))
      case .cancelled:
        camera.receive(.cancel(.hardware))
      @unknown default:
        camera.receive(.cancel(.hardware))
      }
    }
    #else
    content
    #endif
  }
}

@MainActor
func reportMissingScope(_ part: String) {
  #if DEBUG
  guard reportedMissingScopeParts.insert(part).inserted else { return }
  Logger(subsystem: "app.muukii.viewfinder", category: "Scope")
    .fault("\(part, privacy: .public) has no camera. Put it inside a Camera view's content.")
  #endif
}

#if DEBUG
@MainActor private var reportedMissingScopeParts: Set<String> = []
#endif

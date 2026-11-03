import AVFoundation
import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class CameraModel {

  /// Starts as `.accessDenied` when access is already denied (read synchronously at init, which
  /// shows no UI), so a denied screen never flashes an empty preview first.
  private(set) var status: CameraStatus
  var availablePositions: [CameraPosition] {
    facts.positions
  }
  var lenses: [CameraLens] {
    let position = resolvedLens?.position ?? settings.position
    return facts.lenses.filter { $0.position == position }
  }
  var canFlip: Bool {
    availablePositions.contains(.front) && availablePositions.contains(.back)
  }
  var shutter: ShutterState {
    ShutterDerivation.state(
      status: status,
      allowsCapture: allowsCapture,
      readiness: readiness,
      owner: machine.owner,
      photosInFlight: photosInFlight,
      captureCount: captureCount
    )
  }
  private(set) var hardwareControlsAppearance: HardwareControlsAppearance = .inactive
  var photoFormat: PhotoFormat? {
    facts.connected?.photo.format
  }
  var photoResolutions: [PhotoResolution] {
    facts.connected?.photo.resolutions ?? []
  }

  func photoResolution(for preference: ResolutionPreference) -> PhotoResolution? {
    preference.resolve(in: photoResolutions)
  }

  var resolvedLens: CameraLens? {
    LensResolution.lens(for: DeviceIntent(settings), in: facts.lenses, preferredID: facts.defaultLensID)
  }

  var exposure: ExposureControls {
    get {
      let settings = settings
      let program = settings.exposure
      let ranges = ranges
      let adjustable: ControlAvailability = support.customExposure ? .adjustable : .unsupported
      let isoReading = readings.iso ?? ISO(100).clamped(to: ranges.iso)
      let speedReading = readings.shutterSpeed ?? ShutterSpeed(1 / 60).clamped(to: ranges.shutterSpeed)
      let biasReading: ExposureBias
      let biasAvailability: ControlAvailability
      if program.isManual {
        biasReading = ExposureBias(readings.exposureOffset ?? 0)
        biasAvailability = .metering
      } else {
        biasReading = readings.bias ?? settings.exposureBias.clamped(to: ranges.bias)
        biasAvailability = support.exposureBias ? .adjustable : .unsupported
      }
      return ExposureControls(
        iso: ManualControl(
          value: (program.isoTarget ?? isoReading).clamped(to: ranges.iso),
          range: ranges.iso,
          isAutomatic: program.isoTarget == nil,
          reading: isoReading,
          availability: adjustable,
          isAdjusting: readings.isAdjustingExposure
        ),
        shutterSpeed: ManualControl(
          value: (program.shutterSpeedTarget ?? speedReading).clamped(to: ranges.shutterSpeed),
          range: ranges.shutterSpeed,
          isAutomatic: program.shutterSpeedTarget == nil,
          reading: speedReading,
          availability: adjustable,
          isAdjusting: readings.isAdjustingExposure
        ),
        bias: ManualControl(
          value: program.isManual ? biasReading : settings.exposureBias.clamped(to: ranges.bias),
          range: ranges.bias,
          supportsAutomatic: false,
          reading: biasReading,
          availability: biasAvailability
        )
      )
    }
    set {
      let current = exposure
      let ranges = ranges
      let program = newValue.program != current.program
        ? newValue.program.clamped(iso: ranges.iso, shutterSpeed: ranges.shutterSpeed)
        : nil
      var bias: ExposureBias?
      if case .adjustable = current.bias.availability, newValue.bias.value != current.bias.value {
        bias = newValue.bias.value.clamped(to: ranges.bias)
      }
      guard program != nil || bias != nil else { return }
      update {
        if let program { $0.exposure = program }
        if let bias { $0.exposureBias = bias }
      }
    }
  }

  var whiteBalance: WhiteBalanceControls {
    get {
      let ranges = ranges
      let locked: (temperature: Kelvin, tint: Tint)? =
        if case .locked(let temperature, let tint) = settings.whiteBalance { (temperature, tint) } else { nil }
      let temperatureReading = readings.temperature ?? locked?.temperature ?? Kelvin(5500).clamped(to: ranges.temperature)
      let tintReading = readings.tint ?? locked?.tint ?? Tint(0).clamped(to: ranges.tint)
      let availability: ControlAvailability = support.whiteBalanceLock ? .adjustable : .unsupported
      return WhiteBalanceControls(
        temperature: ManualControl(
          value: (locked?.temperature ?? temperatureReading).clamped(to: ranges.temperature),
          range: ranges.temperature,
          isAutomatic: locked == nil,
          reading: temperatureReading,
          availability: availability,
          isAdjusting: readings.isAdjustingWhiteBalance
        ),
        tint: ManualControl(
          value: (locked?.tint ?? tintReading).clamped(to: ranges.tint),
          range: ranges.tint,
          isAutomatic: locked == nil,
          reading: tintReading,
          availability: availability,
          isAdjusting: readings.isAdjustingWhiteBalance
        )
      )
    }
    set {
      let ranges = ranges
      let target: CameraSettings.WhiteBalance =
        newValue.temperature.isAutomatic && newValue.tint.isAutomatic
        ? .automatic
        : .locked(temperature: newValue.temperature.value.clamped(to: ranges.temperature), tint: newValue.tint.value.clamped(to: ranges.tint))
      guard target != settings.whiteBalance else { return }
      update { $0.whiteBalance = target }
    }
  }

  /// Automatic is continuous autofocus. A target locks focus at that lens position.
  var focus: ManualControl<LensPosition> {
    get {
      let range = ranges.lensPosition
      let locked: LensPosition? = if case .locked(let position) = settings.focus { position } else { nil }
      let reading = readings.lensPosition ?? locked ?? LensPosition(0.5).clamped(to: range)
      return ManualControl(
        value: (locked ?? reading).clamped(to: range),
        range: range,
        isAutomatic: locked == nil,
        reading: reading,
        availability: support.lensPositionLock ? .adjustable : .unsupported,
        isAdjusting: readings.isAdjustingFocus
      )
    }
    set {
      let current = focus
      if newValue.isAutomatic {
        guard !current.isAutomatic else { return }
        update { $0.focus = .automatic }
      } else if current.isAutomatic || newValue.value != current.value {
        let target = newValue.value.clamped(to: ranges.lensPosition)
        update { $0.focus = .locked(target) }
      }
    }
  }

  /// On the Camera app's scale. Never automatic.
  var zoom: ManualControl<ZoomFactor> {
    get {
      guard let lens = resolvedLens else {
        return ManualControl(value: ZoomFactor(1), range: ZoomFactor(1)...ZoomFactor(1), supportsAutomatic: false, availability: .unsupported)
      }
      // The range and the reading come from the connected device, which during a switch is still
      // the previous lens.
      let connectedLens = facts.connected.flatMap { connected in facts.lenses.first { $0.id == connected.lensID } } ?? lens
      let range = ZoomMapping.displayRange(deviceRange: ranges.videoZoomFactor, lens: connectedLens)
      let target = ZoomMapping.target(settings.zoom, lens: lens).clamped(to: range)
      let reading = readings.videoZoomFactor.map { ZoomFactor(ZoomMapping.displayZoom(videoZoomFactor: $0, lens: connectedLens)) }
      return ManualControl(
        value: target,
        range: range,
        supportsAutomatic: false,
        reading: reading ?? target,
        availability: support.zoom ? .adjustable : .unsupported,
        isAdjusting: readings.isRampingZoom
      )
    }
    set {
      let current = zoom
      let target = newValue.value.clamped(to: current.range)
      guard target != current.value else { return }
      update { $0.zoom = target }
    }
  }

  func activateShutter() {
    receive(.activate)
  }

  init(configuration: EngineConfiguration, source: CameraSource, settings: Binding<CameraSettings>, handlers: SessionHandlers) {
    let backend = BackendKind.select(source)
    self.backend = backend
    self.configuration = configuration
    self.settingsBinding = settings
    self.handlers = handlers
    let intent = DeviceIntent(settings.wrappedValue)
    self.sentIntent = intent
    self.lane = CommandLane(intent: intent)
    switch (backend.needsAuthorization, CameraAuthorization.status) {
    case (true, .denied), (true, .restricted):
      self.status = .accessDenied
    case (true, .authorized), (true, .notDetermined), (false, _):
      self.status = .available(.stopped)
    }
  }

  @ObservationIgnored var settingsBinding: Binding<CameraSettings>
  @ObservationIgnored let handlers: SessionHandlers
  var allowsCapture: Bool = true

  private(set) var previewSource: PreviewSource?
  @ObservationIgnored let frames = PreviewFrames()
  @ObservationIgnored private let backend: BackendKind
  @ObservationIgnored private let configuration: EngineConfiguration
  @ObservationIgnored private let lane: CommandLane
  @ObservationIgnored private var sentIntent: DeviceIntent
  @ObservationIgnored private var readinessTracker: (any ReadinessTracking)?
  @ObservationIgnored private var engineTask: Task<Void, Never>?
  @ObservationIgnored private var activeRuns = 0
  @ObservationIgnored private var isStarted = false

  private var facts = DeviceFacts()
  private var readings = DeviceReadings()
  private var readiness: ShutterState.Phase = .unavailable
  private var machine = ShutterMachine.State()
  private var photosInFlight = 0
  private var captureCount = 0

  private var settings: CameraSettings {
    get { settingsBinding.wrappedValue }
    set { settingsBinding.wrappedValue = newValue }
  }

  private var ranges: ControlRanges {
    facts.connected?.ranges ?? .placeholder
  }

  private var support: ControlSupport {
    facts.connected?.support ?? .none
  }

  func sync() {
    resolveLens()
    let intent = DeviceIntent(settings)
    guard intent != sentIntent else { return }
    sentIntent = intent
    lane.updateIntent { $0 = intent }
  }

  private func resolveLens() {
    guard let lens = resolvedLens, lens != settings.lens || lens.position != settings.position else { return }
    settings.resolve(to: lens)
  }

  private func update(_ change: (inout CameraSettings) -> Void) {
    var settings = settings
    change(&settings)
    self.settings = settings
    sync()
  }

  private func adoptChange(_ change: (inout CameraSettings) -> Void) {
    let hasUnsentWrite = DeviceIntent(settings) != sentIntent
    var settings = settings
    change(&settings)
    self.settings = settings
    if hasUnsentWrite {
      sync()
      return
    }
    let intent = DeviceIntent(settings)
    sentIntent = intent
    lane.adoptIntent { $0 = intent }
  }

  func detach() {
    settingsBinding = .constant(settings)
  }

  private func report(_ failure: CameraFailure) {
    handlers.failureAction?(failure)
  }

  func run() async {
    if case .unavailable = status { return }
    activeRuns += 1
    defer {
      activeRuns -= 1
      if activeRuns == 0 {
        if isStarted {
          isStarted = false
          machine = ShutterMachine.State()
          lane.send(.stop)
        } else if case .available(.starting) = status {
          status = .available(.stopped)
        }
      }
    }
    if !isStarted {
      if backend.needsAuthorization {
        if case .available(.stopped) = status { status = .available(.starting) }
        let authorization = await CameraAuthorization.request()
        guard !Task.isCancelled else { return }
        guard case .authorized = authorization else {
          status = .accessDenied
          return
        }
      }
      if !isStarted {
        isStarted = true
        machine = ShutterMachine.State()
        status = .available(.starting)
        startEngineIfNeeded()
        sync()
        lane.send(.start)
      }
    }
    await untilCancelled()
  }

  private func untilCancelled() async {
    while !Task.isCancelled {
      try? await Task.sleep(for: .seconds(3600))
    }
  }

  private func startEngineIfNeeded() {
    guard engineTask == nil else { return }
    let (events, sink) = AsyncStream<EngineEvent>.makeStream(bufferingPolicy: .unbounded)
    let engine: any CameraBackend =
      switch backend {
      case .hardware:
        CameraEngine(camera: self, configuration: configuration, intentBox: lane.intentBox, frames: frames, events: sink)
      case .simulated(let simulation):
        SimulatedEngine(simulation: simulation, camera: self, configuration: configuration, intentBox: lane.intentBox, frames: frames, events: sink)
      }
    let commands = lane.commands
    engineTask = Task { @CaptureActor in
      await engine.drain(commands)
      sink.finish()
    }
    Task { @MainActor [weak self] in
      for await event in events {
        self?.apply(event)
      }
    }
  }

  func apply(_ event: EngineEvent) {
    switch event {
    case .status(let status):
      self.status = status
      if case .available(.running) = status {} else { machine = ShutterMachine.State() }
    case .facts(let facts):
      self.facts = facts
      sync()
    case .readings(let readings):
      apply(readings: readings)
    case .readiness(let phase):
      apply(readiness: phase)
    case .readinessTracker(let tracker):
      readinessTracker = tracker
    case .preview(let source):
      previewSource = source
    case .hardwareControls(let appearance):
      hardwareControlsAppearance = appearance
    case .failure(let failure):
      report(failure)
    case .subjectAreaChanged:
      guard settings.focusPoint != nil else { return }
      update { $0.endTapFocus() }
    case .adopt(let adoption):
      adopt(adoption)
    }
  }

  func adopt(_ adoption: IntentAdoption) {
    switch adoption {
    case .lens(let id):
      guard let lens = facts.lenses.first(where: { $0.id == id }) else { return }
      update { $0.lens = lens }
    case .lensSwitchFailed(let requested, let connected):
      guard settings.lens?.id == requested, let lens = facts.lenses.first(where: { $0.id == connected }) else { return }
      update { $0.resolve(to: lens) }
    case .exposure(let program):
      adoptChange { $0.exposure = program }
    case .whiteBalance(let whiteBalance):
      adoptChange { $0.whiteBalance = CameraSettings.WhiteBalance(whiteBalance) }
    case .focus(let focus):
      adoptChange { settings in
        switch focus {
        case .continuous:
          settings.focus = .automatic
          settings.endTapFocus()
        case .point(let point):
          settings.focus(at: point)
        case .locked(let position):
          settings.focus = .locked(position)
        }
      }
    case .zoom(let zoom):
      adoptChange { $0.zoom = zoom }
    case .bias(let bias):
      adoptChange { $0.exposureBias = bias }
    }
  }

  func apply(readings: DeviceReadings) {
    self.readings = readings
  }

  func apply(readiness: ShutterState.Phase) {
    self.readiness = readiness
  }

  func photoWillCapture() {
    captureCount += 1
  }

  func photoDidFinish(_ result: Result<Photo, CameraFailure>) {
    photosInFlight -= 1
    switch result {
    case .success(let photo):
      guard let deliver = handlers.deliver else { return }
      Task { @MainActor in await deliver(photo) }
    case .failure(let failure):
      report(failure)
    }
  }

  func captureCouldNotStart(trackedID: Int64, message: String) {
    readinessTracker?.stopTracking(uniqueID: trackedID)
    photoDidFinish(.failure(CameraFailure(kind: .photoCapture, message: message)))
  }
}

extension CameraModel {
  var respondsToHardwareButtons: Bool {
    switch shutter.phase {
    case .unavailable: false
    case .ready, .busy: true
    }
  }

  func receive(_ input: ShutterInput) {
    var machine = self.machine
    let effect = ShutterMachine.reduce(&machine, input, canPress: shutter.isEnabled)
    self.machine = machine
    guard case .capturePhoto? = effect else { return }
    capturePhoto()
  }

  /// Builds the settings and tracks the request on the main actor before any hop, so readiness
  /// flips synchronously and a queued touch can't fire a second capture.
  private func capturePhoto() {
    sync()
    guard let connected = facts.connected, let readinessTracker else { return }
    let settings = settings
    let lens = resolvedLens
    let shot = PhotoShot(
      format: connected.photo.format,
      flash: settings.flash,
      resolution: settings.photoResolution,
      dimensions: settings.photoResolution.resolve(in: connected.photo.resolutions),
      isMirrored: lens?.position == .front && configuration.mirroring == .matchesPreview,
      exposure: settings.exposure
    )
    let tracked = shot.forTracking(lensSwitchPending: lens?.id != connected.lensID)
    let photoSettings = PhotoSettingsBuilder.settings(for: tracked, options: configuration.photo, output: connected.photo.output)
    handlers.customizeSettings?(photoSettings)
    let request = PhotoRequest(settings: photoSettings, shot: shot)
    readinessTracker.startTracking(request)
    photosInFlight += 1
    lane.send(.capturePhoto(request))
  }
}

extension DeviceIntent {
  init(_ settings: CameraSettings) {
    self.init(position: settings.position)
    lensID = settings.lens?.id
    zoom = settings.zoom
    exposure = settings.exposure
    bias = settings.exposureBias
    focus =
      if let point = settings.focusPoint {
        .point(point)
      } else {
        switch settings.focus {
        case .automatic: .continuous
        case .locked(let position): .locked(position)
        }
      }
    focusTap = settings.tapCount
    whiteBalance =
      switch settings.whiteBalance {
      case .automatic: .automatic
      case .locked(let temperature, let tint): .locked(temperature, tint)
      }
  }
}

extension CameraSettings.WhiteBalance {
  init(_ whiteBalance: DeviceIntent.WhiteBalance) {
    switch whiteBalance {
    case .automatic: self = .automatic
    case .locked(let temperature, let tint): self = .locked(temperature: temperature, tint: tint)
    }
  }
}

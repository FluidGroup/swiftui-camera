import Foundation

@CaptureActor
final class SimulatedEngine: CameraBackend, CameraHardwareClient {
  private let simulation: CameraSimulation
  private let configuration: EngineConfiguration
  private let intentBox: IntentBox
  private let events: AsyncStream<EngineEvent>.Continuation
  private let frames: PreviewFrames
  private weak var camera: CameraModel?

  private var lenses: [CameraLens] = []
  private var connected: (lens: CameraLens, device: ConnectedDevice)?
  private var applied: DeviceIntent?
  private var readings = DeviceReadings()
  private var readingsLoop: Task<Void, Never>?
  private var frameLoop: Task<Void, Never>?
  private var framePool = PixelBufferPool()
  private var subjectAreaTimer: Task<Void, Never>?
  private var isRunning = false
  private var photosInFlight = 0
  var hasCaptureInFlight: Bool { photosInFlight > 0 }
  private let hardware: CameraHardware

  nonisolated init(
    simulation: CameraSimulation,
    hardware: CameraHardware,
    camera: CameraModel,
    configuration: EngineConfiguration,
    intentBox: IntentBox,
    frames: PreviewFrames,
    events: AsyncStream<EngineEvent>.Continuation
  ) {
    self.simulation = simulation
    self.hardware = hardware
    self.camera = camera
    self.configuration = configuration
    self.intentBox = intentBox
    self.frames = frames
    self.events = events
  }

  func drain(_ commands: AsyncStream<LaneCommand>) async {
    for await command in commands {
      switch command {
      case .start(let request): hardware.request(self, request)
      case .stop: hardware.withdraw(self)
      case .reconcile: reconcile(full: false)
      case .capturePhoto(let request, let reservation):
        capture(request)
        reservation.didSubmitCapture()
        hardware.reconcile()
      }
    }
    hardware.withdraw(self)
  }

  func waitingForHardware() {
    events.yield(.status(.available(.interrupted(.inUseByAnotherCamera))))
  }

  func startHardware() -> Bool {
    if lenses.isEmpty {
      lenses = SimulatedDevice.lenses(for: simulation, selection: configuration.lensSelection)
      CapturedFileStore.sweepOrphans()
    }
    guard !lenses.isEmpty else {
      events.yield(.status(.unavailable(.noCamera)))
      return false
    }
    if let camera {
      events.yield(.readinessTracker(SimulatedReadinessTracker(camera: camera)))
    }
    events.yield(.preview(.simulated))
    isRunning = true
    reconcile(full: true)
    events.yield(.status(.available(.running)))
    events.yield(.readiness(.ready))
    startReadingsLoop()
    startFrameLoop()
    return true
  }

  func stopHardware(waiting: Bool) {
    isRunning = false
    readingsLoop?.cancel()
    readingsLoop = nil
    frameLoop?.cancel()
    frameLoop = nil
    subjectAreaTimer?.cancel()
    events.yield(.readiness(.unavailable))
    if waiting { waitingForHardware() }
    else { events.yield(.status(.available(.stopped))) }
  }

  private func reconcile(full: Bool) {
    guard isRunning else { return }
    let intent = intentBox.value
    guard let lens = LensResolution.lens(for: intent, in: lenses) else { return }
    let lensChanged = lens.id != connected?.lens.id
    let aspects = intent.aspects(toReconcileFrom: applied, lensChanged: lensChanged, full: full)
    if lensChanged {
      connected = (lens, SimulatedDevice.connectedDevice(for: lens, options: configuration.photo))
      publishFacts()
    }
    if aspects.contains(.focus) {
      scheduleSubjectAreaChange(for: intent.focus)
    }
    applied = intent
  }

  private func publishFacts() {
    events.yield(
      .facts(
        DeviceFacts(
          lenses: lenses,
          defaultLensID: nil,
          connected: connected?.device
        )))
  }

  private func scheduleSubjectAreaChange(for focus: DeviceIntent.Focus) {
    subjectAreaTimer?.cancel()
    guard case .point = focus else { return }
    subjectAreaTimer = Task { @CaptureActor [events] in
      try? await Task.sleep(for: .seconds(2.5))
      guard !Task.isCancelled else { return }
      events.yield(.subjectAreaChanged)
    }
  }

  private func startReadingsLoop() {
    readingsLoop?.cancel()
    readingsLoop = Task { @CaptureActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled, let self else { return }
        self.stepReadings()
      }
    }
  }

  private func startFrameLoop() {
    frameLoop?.cancel()
    frameLoop = Task { @CaptureActor [weak self] in
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(33))
        guard !Task.isCancelled, let self else { return }
        self.deliverFrame()
      }
    }
  }

  private func deliverFrame() {
    guard let connected, let buffer = framePool.buffer(width: TestPattern.frameSize.width, height: TestPattern.frameSize.height) else { return }
    TestPattern.draw(into: buffer, phase: TestPattern.phase())
    frames.deliver(PreviewFrame(pixelBuffer: buffer, deviceID: nil, isMirrored: connected.lens.position == .front))
  }

  private func stepReadings() {
    guard let connected else { return }
    let targets = SimulatedDevice.targets(for: intentBox.value, lens: connected.lens, ranges: connected.device.ranges)
    let next = SimulatedDevice.step(readings, toward: targets)
    guard next != readings else { return }
    readings = next
    events.yield(.readings(next))
  }

  private func capture(_ request: PhotoRequest) {
    guard let camera, let connected else {
      Task { @MainActor [camera] in
        camera?.captureCouldNotStart(trackedID: request.trackedID, message: "The camera is not running.", snapshot: request.snapshot)
      }
      return
    }
    photosInFlight += 1
    let phase = TestPattern.phase()
    let delay = simulation.processingDelay
    let options = configuration.photo
    let photo = connected.device.photo
    let shot = request.shot.resolved(flashModes: photo.output.flashModes, offered: photo.resolutions, ceiling: photo.output.maxDimensions)
    let snapshot = request.snapshot
    Task { @CaptureActor [weak self, events] in
      try? await Task.sleep(for: .milliseconds(80))
      await camera.photoWillCapture()
      events.yield(.readiness(.busy(.processing)))
      try? await Task.sleep(for: delay)
      let result = SimulatedPhoto.make(shot: shot, options: options, phase: phase, snapshot: snapshot)
      self?.captureDidFinish()
      await camera.photoDidFinish(result)
    }
  }

  private func captureDidFinish() {
    photosInFlight -= 1
    if photosInFlight == 0 {
      events.yield(.readiness(isRunning ? .ready : .unavailable))
      hardware.reconcile()
    }
  }
}

@MainActor
final class SimulatedReadinessTracker: ReadinessTracking {
  private weak var camera: CameraModel?

  nonisolated init(camera: CameraModel) {
    self.camera = camera
  }

  func startTracking(_ request: PhotoRequest) {
    camera?.apply(readiness: .busy(.waitingForCapture))
  }

  func stopTracking(uniqueID: Int64) {
    camera?.apply(readiness: .ready)
  }
}

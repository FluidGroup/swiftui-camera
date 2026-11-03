import AVFoundation

@CaptureActor
final class CameraEngine: CameraBackend {
  let configuration: EngineConfiguration
  let events: AsyncStream<EngineEvent>.Continuation
  let frames: PreviewFrames
  private let intentBox: IntentBox
  private(set) weak var camera: CameraModel?

  var rig: Rig?
  var applied: DeviceIntent?
  var failedLensID: CameraLens.ID?
  var isStarted = false
  var steering: ExposureSteeringMode? {
    didSet {
      steeringGeneration += 1
      isSteeringWriteInFlight = false
    }
  }
  var steeringGeneration = 0
  var isSteeringWriteInFlight = false
  /// Delegates must stay alive until their request finishes.
  private var inFlight: [Int64: PhotoCaptureDelegate] = [:]
  private var awaitingCapture: Set<Int64> = []
  private var stopWaiters: [CheckedContinuation<Void, Never>] = []
  private var captureWaiters: [CheckedContinuation<Void, Never>] = []
  private var observers: [any NSObjectProtocol] = []

  nonisolated init(
    camera: CameraModel,
    configuration: EngineConfiguration,
    intentBox: IntentBox,
    frames: PreviewFrames,
    events: AsyncStream<EngineEvent>.Continuation
  ) {
    self.camera = camera
    self.configuration = configuration
    self.intentBox = intentBox
    self.frames = frames
    self.events = events
  }

  var intent: DeviceIntent {
    intentBox.value
  }

  func drain(_ commands: AsyncStream<LaneCommand>) async {
    for await command in commands {
      switch command {
      case .start: start()
      case .stop: await stop()
      case .reconcile:
        await settleCapturesBeforeLensSwitch()
        reconcile(full: false)
      case .capturePhoto(let request): capture(request)
      }
    }
    tearDown()
  }

  /// Reconfiguring the session can fail a request still waiting for its exposure, so a lens
  /// switch waits until every request has passed `didCapturePhotoFor`. Captured requests keep
  /// processing across the swap.
  private func settleCapturesBeforeLensSwitch() async {
    guard isStarted, let rig, lensToSwitch(for: intent, rig: rig) != nil else { return }
    while !awaitingCapture.isEmpty {
      await withCheckedContinuation { captureWaiters.append($0) }
    }
  }

  private func start() {
    isStarted = true
    if rig == nil {
      CapturedFileStore.sweepOrphans()
      do {
        rig = try configureRig()
      } catch {
        isStarted = false
        events.yield(.status(.unavailable(error.unavailableReason)))
        return
      }
    }
    guard let rig else { return }
    if !rig.session.isRunning {
      rig.session.startRunning()
    }
    reconcile(full: true)
    events.yield(.status(.available(isInterrupted(rig.session) ? .interrupted(.other) : .running)))
  }

  private func isInterrupted(_ session: AVCaptureSession) -> Bool {
    #if os(iOS)
    session.isInterrupted
    #else
    false
    #endif
  }

  private func stop() async {
    isStarted = false
    guard let rig else { return }
    while !inFlight.isEmpty {
      await withCheckedContinuation { stopWaiters.append($0) }
    }
    if rig.session.isRunning {
      rig.session.stopRunning()
    }
    applied = nil
    steering = nil
    events.yield(.status(.available(.stopped)))
  }

  private func tearDown() {
    for observer in observers {
      NotificationCenter.default.removeObserver(observer)
    }
    observers = []
    guard let rig else { return }
    disconnect(rig.connection, from: rig.session)
    rig.connection = nil
    if rig.session.isRunning {
      rig.session.stopRunning()
    }
    self.rig = nil
  }

  private func configureRig() throws(ConfigurationError) -> Rig {
    let discovery = DeviceDiscovery.discover()
    let lenses = LensDiscovery.lenses(from: discovery.facts, selection: configuration.lensSelection)
    let facts = DeviceFacts(
      lenses: lenses,
      defaultLensID: discovery.defaultID
    )
    guard
      let lens = LensResolution.lens(for: intent, in: lenses, preferredID: facts.defaultLensID),
      let device = discovery.devices[lens.deviceID]
    else { throw .noCamera }

    let session = AVCaptureSession()
    let photoOutput = AVCapturePhotoOutput()
    // The previews draw from this output's frames, which the photo preset sizes for a screen.
    let videoOutput = AVCaptureVideoDataOutput()
    videoOutput.alwaysDiscardsLateVideoFrames = true
    let frameOutput = PreviewFrameOutput(frames: frames)
    videoOutput.setSampleBufferDelegate(frameOutput, queue: frameOutput.queue)
    let rig: Rig
    do {
      session.beginConfiguration()
      defer { session.commitConfiguration() }
      session.sessionPreset = .photo
      guard session.canAddOutput(photoOutput) else { throw .cannotAddPhotoOutput }
      session.addOutput(photoOutput)
      guard session.canAddOutput(videoOutput) else { throw .cannotAddVideoOutput }
      session.addOutput(videoOutput)
      let input: AVCaptureDeviceInput
      do {
        input = try AVCaptureDeviceInput(device: device)
      } catch {
        throw .cannotAddInput(error.localizedDescription)
      }
      guard session.canAddInput(input) else {
        throw .cannotAddInput("The camera could not be connected to the capture session.")
      }
      session.addInput(input)
      prepareOutput(photoOutput, for: device)
      rig = Rig(session: session, photoOutput: photoOutput, videoOutput: videoOutput, frameOutput: frameOutput, devices: discovery.devices, facts: facts)
      rig.connection = connect(lens, device: device, input: input, rig: rig)
      prepareFrames(rig)
    }

    if let camera {
      events.yield(.readinessTracker(HardwareReadinessTracker(photoOutput: photoOutput, camera: camera)))
    }
    observe(session)
    publishFacts(rig)
    events.yield(.preview(.device(device)))
    return rig
  }

  /// The frames stay in the sensor's orientation and unmirrored; each preview stands them upright
  /// itself, since only it knows its interface orientation.
  func prepareFrames(_ rig: Rig) {
    guard let connection = rig.videoOutput.connection(with: .video) else { return }
    if connection.isVideoMirroringSupported {
      connection.automaticallyAdjustsVideoMirroring = false
      connection.isVideoMirrored = false
    }
    if connection.isVideoRotationAngleSupported(0) {
      connection.videoRotationAngle = 0
    }
  }

  func prepareOutput(_ photoOutput: AVCapturePhotoOutput, for device: AVCaptureDevice) {
    #if os(iOS)
    photoOutput.isAppleProRAWEnabled = configuration.photo.wantsProRAW && photoOutput.isAppleProRAWSupported
    #endif
    if let largest = resolutions(of: device).last {
      photoOutput.maxPhotoDimensions = CMVideoDimensions(width: Int32(largest.width), height: Int32(largest.height))
    }
    photoOutput.maxPhotoQualityPrioritization = configuration.photo.qualityPrioritization
    photoOutput.isZeroShutterLagEnabled = photoOutput.isZeroShutterLagSupported
    photoOutput.isResponsiveCaptureEnabled = photoOutput.isResponsiveCaptureSupported
    photoOutput.isFastCapturePrioritizationEnabled =
      photoOutput.isFastCapturePrioritizationSupported && !configuration.photo.wantsProRAW
  }

  func resolutions(of device: AVCaptureDevice) -> [PhotoResolution] {
    PhotoResolutionSelection.resolutions(
      from: device.activeFormat.supportedMaxPhotoDimensions.map { PhotoResolution(width: Int($0.width), height: Int($0.height)) })
  }

  func publishFacts(_ rig: Rig) {
    var facts = rig.facts
    facts.connected = rig.connection.map { DeviceDiscovery.connectedDevice(lens: $0.lens, device: $0.device, photoOutput: rig.photoOutput, options: configuration.photo, resolutions: resolutions(of: $0.device)) }
    events.yield(.facts(facts))
  }

  private func observe(_ session: AVCaptureSession) {
    let center = NotificationCenter.default
    observers.append(
      center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: nil) { [weak self] note in
        var reason: Int?
        #if os(iOS)
        reason = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue
        #endif
        Task { @CaptureActor in self?.sessionWasInterrupted(reasonRawValue: reason) }
      })
    observers.append(
      center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: nil) { [weak self] _ in
        Task { @CaptureActor in self?.sessionInterruptionEnded() }
      })
    observers.append(
      center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: nil) { [weak self] note in
        let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
        let code = error?.code
        let message = error?.localizedDescription ?? "The capture session reported an error."
        Task { @CaptureActor in self?.sessionRuntimeError(code: code, message: message) }
      })
  }

  private func sessionWasInterrupted(reasonRawValue: Int?) {
    guard isStarted else { return }
    events.yield(.status(.available(.interrupted(CameraStatus.Interruption(reasonRawValue: reasonRawValue)))))
  }

  private func sessionInterruptionEnded() {
    guard isStarted, let rig else { return }
    if !rig.session.isRunning {
      rig.session.startRunning()
    }
    reconcile(full: true)
    events.yield(.status(.available(.running)))
  }

  private func sessionRuntimeError(code: Int?, message: String) {
    guard isStarted, let rig else { return }
    switch RuntimeErrorPolicy.response(toErrorCode: code) {
    case .restart:
      if !rig.session.isRunning {
        rig.session.startRunning()
      }
      reconcile(full: true)
      events.yield(.status(.available(.running)))
    case .report:
      events.yield(.failure(CameraFailure(kind: .deviceConfiguration, message: message)))
    }
  }

  private func capture(_ request: PhotoRequest) {
    guard
      isStarted, let rig, let connection = rig.connection, let camera, rig.session.isRunning,
      let videoConnection = rig.photoOutput.connection(with: .video)
    else {
      couldNotStart(request, "The camera is not running.")
      return
    }
    // A lens swap queued ahead of this press may have landed on another camera, so the output
    // gets a copy of the tracked settings resolved against the connected one. The copy keeps
    // the app's customizations and has a newer uniqueID, which ends the readiness tracking of
    // the original when it reaches the output.
    let settings = AVCapturePhotoSettings(from: request.settings)
    #if os(iOS)
    if settings.rawPhotoPixelFormatType != 0, !rig.photoOutput.availableRawPhotoPixelFormatTypes.contains(settings.rawPhotoPixelFormatType) {
      couldNotStart(request, "The selected camera does not deliver Apple ProRAW.")
      return
    }
    #endif
    let ceiling = rig.photoOutput.maxPhotoDimensions
    let shot = request.shot.resolved(
      flashModes: Set(rig.photoOutput.supportedFlashModes.compactMap(FlashMode.init)),
      offered: PhotoResolutionSelection.offered(resolutions(of: connection.device), crop: connection.lens.crop),
      ceiling: ceiling.width > 0 && ceiling.height > 0 ? PhotoResolution(width: Int(ceiling.width), height: Int(ceiling.height)) : nil)
    PhotoSettingsBuilder.apply(shot, to: settings)

    let angle = connection.captureRotation.videoRotationAngleForHorizonLevelCapture
    if videoConnection.isVideoRotationAngleSupported(angle) {
      videoConnection.videoRotationAngle = angle
    }
    if videoConnection.isVideoMirroringSupported {
      videoConnection.automaticallyAdjustsVideoMirroring = false
      videoConnection.isVideoMirrored = shot.isMirrored
    }

    let delegate = PhotoCaptureDelegate(shot: shot, uniqueID: settings.uniqueID, camera: camera) { [weak self] uniqueID, progress in
      Task { @CaptureActor in self?.captureDidProgress(uniqueID, progress) }
    }
    inFlight[settings.uniqueID] = delegate
    awaitingCapture.insert(settings.uniqueID)
    rig.photoOutput.capturePhoto(with: settings, delegate: delegate)
  }

  private func couldNotStart(_ request: PhotoRequest, _ message: String) {
    Task { @MainActor [camera] in
      camera?.captureCouldNotStart(trackedID: request.trackedID, message: message)
    }
  }

  private func captureDidProgress(_ uniqueID: Int64, _ progress: CaptureProgress) {
    awaitingCapture.remove(uniqueID)
    if case .finished = progress {
      inFlight[uniqueID] = nil
    }
    if awaitingCapture.isEmpty {
      Self.resume(&captureWaiters)
    }
    if inFlight.isEmpty {
      Self.resume(&stopWaiters)
    }
  }

  private static func resume(_ waiters: inout [CheckedContinuation<Void, Never>]) {
    let resumed = waiters
    waiters = []
    for waiter in resumed {
      waiter.resume()
    }
  }
}

@CaptureActor
final class Rig {
  let session: AVCaptureSession
  let photoOutput: AVCapturePhotoOutput
  let videoOutput: AVCaptureVideoDataOutput
  let frameOutput: PreviewFrameOutput
  let devices: [String: AVCaptureDevice]
  let facts: DeviceFacts
  var connection: DeviceConnection?
  #if os(iOS)
  var controlsDelegate: ControlsDelegate?
  #endif

  init(
    session: AVCaptureSession,
    photoOutput: AVCapturePhotoOutput,
    videoOutput: AVCaptureVideoDataOutput,
    frameOutput: PreviewFrameOutput,
    devices: [String: AVCaptureDevice],
    facts: DeviceFacts
  ) {
    self.session = session
    self.photoOutput = photoOutput
    self.videoOutput = videoOutput
    self.frameOutput = frameOutput
    self.devices = devices
    self.facts = facts
  }
}

@CaptureActor
final class DeviceConnection {
  let lens: CameraLens
  let device: AVCaptureDevice
  let input: AVCaptureDeviceInput
  let captureRotation: AVCaptureDevice.RotationCoordinator
  let readings: DeviceReadingsMonitor
  var subjectAreaObserver: (any NSObjectProtocol)?
  var controls: [AVCaptureControl] = []
  var controlSliders = HardwareSliders()

  init(lens: CameraLens, device: AVCaptureDevice, input: AVCaptureDeviceInput, readings: DeviceReadingsMonitor) {
    self.lens = lens
    self.device = device
    self.input = input
    self.captureRotation = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: nil)
    self.readings = readings
  }
}

enum ExposureSteeringMode: Sendable, Hashable {
  case iso(holding: ShutterSpeed)
  case shutterSpeed(holding: ISO)
}

enum ConfigurationError: Error {
  case noCamera
  case cannotAddInput(String)
  case cannotAddPhotoOutput
  case cannotAddVideoOutput

  var unavailableReason: CameraStatus.UnavailableReason {
    switch self {
    case .noCamera: .noCamera
    case .cannotAddInput(let message): .configurationFailed(message)
    case .cannotAddPhotoOutput: .configurationFailed("The photo output could not be connected to the capture session.")
    case .cannotAddVideoOutput: .configurationFailed("The preview output could not be connected to the capture session.")
    }
  }
}

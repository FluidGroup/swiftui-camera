import AVFoundation

extension CameraEngine {
  func reconcile(full: Bool) {
    reconcile(intent, full: full)
  }

  func reconcile(_ intent: DeviceIntent, full: Bool) {
    guard isStarted, let rig else { return }
    var intent = intent
    if let failedLensID, LensResolution.lens(for: intent, in: rig.facts.lenses, preferredID: rig.facts.defaultLensID)?.id != failedLensID {
      self.failedLensID = nil
    }
    let lensToSwitch = lensToSwitch(for: intent, rig: rig)
    let aspects = intent.aspects(toReconcileFrom: applied, lensChanged: lensToSwitch != nil, full: full)
    if let lens = lensToSwitch, !switchLens(to: lens, rig: rig), let connected = rig.connection?.lens {
      failedLensID = lens.id
      intent.lensID = connected.id
      intent.position = connected.position
      events.yield(.adopt(.lensSwitchFailed(requested: lens.id, connected: connected.id)))
    }
    guard let connection = rig.connection else { return }
    let device = connection.device
    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }
      for aspect in DeviceAspect.allCases where aspects.contains(aspect) {
        switch aspect {
        case .lens: break
        case .zoom: applyZoom(intent, lens: connection.lens, to: device)
        case .exposure: applyExposure(intent, to: device)
        case .bias: applyBias(intent, to: device)
        case .focus: applyFocus(intent, to: device)
        case .whiteBalance: applyWhiteBalance(intent, to: device)
        }
      }
    } catch {
      events.yield(.failure(CameraFailure(kind: .deviceConfiguration, message: error.localizedDescription)))
    }
    applied = intent
    syncControls(with: intent, connection: connection)
  }

  func lensToSwitch(for intent: DeviceIntent, rig: Rig) -> CameraLens? {
    guard
      let lens = LensResolution.lens(for: intent, in: rig.facts.lenses, preferredID: rig.facts.defaultLensID),
      lens.id != rig.connection?.lens.id, lens.id != failedLensID
    else { return nil }
    return lens
  }

  private func switchLens(to lens: CameraLens, rig: Rig) -> Bool {
    guard let device = rig.devices[lens.deviceID] else { return false }
    if let current = rig.connection, current.device === device {
      rig.connection = connect(lens, device: device, input: current.input, rig: rig, reusing: current)
      publishFacts(rig)
      return true
    }
    let input: AVCaptureDeviceInput
    do {
      input = try AVCaptureDeviceInput(device: device)
    } catch {
      events.yield(.failure(CameraFailure(kind: .lensSwitch, message: error.localizedDescription)))
      return false
    }
    let session = rig.session

    session.beginConfiguration()
    let previous = rig.connection
    disconnect(previous, from: session)
    guard session.canAddInput(input) else {
      if let previous {
        session.addInput(previous.input)
        rig.connection = connect(previous.lens, device: previous.device, input: previous.input, rig: rig)
      }
      session.commitConfiguration()
      events.yield(.failure(CameraFailure(kind: .lensSwitch, message: "The camera could not be connected to the capture session.")))
      return false
    }
    session.addInput(input)
    // Leave the new preview connection's rotation alone here. On iOS its preview layer is a
    // view's backing layer, which UIKit lets only the main thread change; `PreviewLayerController`
    // applies the new device's rotation there when the preview event below arrives.
    prepareOutput(rig.photoOutput, for: device)
    rig.connection = connect(lens, device: device, input: input, rig: rig)
    session.commitConfiguration()

    steering = nil
    publishFacts(rig)
    events.yield(.preview(.video(session: session, device: device)))
    return true
  }

  func connect(_ lens: CameraLens, device: AVCaptureDevice, input: AVCaptureDeviceInput, rig: Rig, reusing previous: DeviceConnection? = nil) -> DeviceConnection {
    let readings: DeviceReadingsMonitor
    if let previous {
      readings = previous.readings
      removeControls(previous, from: rig.session)
    } else {
      readings = DeviceReadingsMonitor(
        device: device,
        publish: { [weak camera] readings in
          camera?.apply(readings: readings)
        },
        exposureOffsetDidChange: { [weak self] offset in
          self?.steerExposure(offset: offset)
        }
      )
    }
    let connection = DeviceConnection(lens: lens, device: device, input: input, readings: readings)
    connection.subjectAreaObserver = previous?.subjectAreaObserver ?? observeSubjectArea(of: device)
    installControls(on: connection, rig: rig)
    return connection
  }

  func disconnect(_ connection: DeviceConnection?, from session: AVCaptureSession) {
    guard let connection else { return }
    session.removeInput(connection.input)
    connection.readings.stop()
    if let observer = connection.subjectAreaObserver {
      NotificationCenter.default.removeObserver(observer)
    }
    removeControls(connection, from: session)
  }

  private func observeSubjectArea(of device: AVCaptureDevice) -> (any NSObjectProtocol)? {
    #if os(iOS)
    NotificationCenter.default.addObserver(forName: AVCaptureDevice.subjectAreaDidChangeNotification, object: device, queue: nil) { [events] _ in
      events.yield(.subjectAreaChanged)
    }
    #else
    nil
    #endif
  }

  private func applyZoom(_ intent: DeviceIntent, lens: CameraLens, to device: AVCaptureDevice) {
    #if os(iOS)
    let factor = ZoomMapping.deviceFactor(
      for: intent.zoom, lens: lens, deviceRange: device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor)
    // Camera Control may have put the device here already; writing it again would fight it.
    if abs(device.videoZoomFactor - factor) > 0.001 {
      device.videoZoomFactor = factor
    }
    #endif
  }

  private func applyExposure(_ intent: DeviceIntent, to device: AVCaptureDevice) {
    #if os(iOS)
    let format = device.activeFormat
    let isoRange = max(format.minISO, 1)...max(format.maxISO, format.minISO)
    func duration(_ speed: ShutterSpeed) -> CMTime {
      format.exposureDuration(seconds: speed.rawValue)
    }
    func iso(_ value: ISO) -> Float {
      Float(value.rawValue).clamped(to: isoRange)
    }
    switch intent.exposure {
    case .automatic:
      steering = nil
      applyAutomaticExposure(intent, to: device)
    case .manual(let speed, let sensitivity):
      guard device.isExposureModeSupported(.custom) else { return }
      steering = nil
      device.setExposureModeCustom(duration: duration(speed), iso: iso(sensitivity))
    case .shutterPriority(let speed):
      guard device.isExposureModeSupported(.custom) else { return }
      if #available(iOS 27.0, *),
        format.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: duration(speed), iso: AVCaptureDevice.autoISO)
      {
        steering = nil
        device.setExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: duration(speed), iso: AVCaptureDevice.autoISO)
      } else {
        steering = .iso(holding: ShutterSpeed(duration(speed).seconds))
        device.setExposureModeCustom(duration: duration(speed), iso: AVCaptureDevice.currentISO)
      }
    case .isoPriority(let sensitivity):
      guard device.isExposureModeSupported(.custom) else { return }
      if #available(iOS 27.0, *),
        format.supportsExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: AVCaptureDevice.autoExposureDuration, iso: iso(sensitivity))
      {
        steering = nil
        device.setExposureModeCustom(lensAperture: AVCaptureDevice.currentLensAperture, duration: AVCaptureDevice.autoExposureDuration, iso: iso(sensitivity))
      } else {
        steering = .shutterSpeed(holding: ISO(Double(iso(sensitivity))))
        device.setExposureModeCustom(duration: AVCaptureDevice.currentExposureDuration, iso: iso(sensitivity))
      }
    }
    #else
    switch intent.exposure {
    case .automatic: applyAutomaticExposure(intent, to: device)
    case .manual, .shutterPriority, .isoPriority: break
    }
    #endif
  }

  private func applyAutomaticExposure(_ intent: DeviceIntent, to device: AVCaptureDevice) {
    let (point, mode): (DevicePoint, AVCaptureDevice.ExposureMode) =
      if case .point(let point) = intent.focus { (point, .autoExpose) } else { (.center, .continuousAutoExposure) }
    if device.isExposurePointOfInterestSupported {
      device.exposurePointOfInterest = CGPoint(x: point.x, y: point.y)
    }
    if device.isExposureModeSupported(mode) {
      device.exposureMode = mode
    }
  }

  private func applyBias(_ intent: DeviceIntent, to device: AVCaptureDevice) {
    #if os(iOS)
    // Under custom exposure the bias is a light meter, so writing it would only move the meter.
    guard !intent.exposure.isManual else { return }
    let bias = Float(intent.bias.rawValue).clamped(to: device.minExposureTargetBias...max(device.minExposureTargetBias, device.maxExposureTargetBias))
    if abs(device.exposureTargetBias - bias) > 0.001 {
      device.setExposureTargetBias(bias)
    }
    #endif
  }

  private func applyFocus(_ intent: DeviceIntent, to device: AVCaptureDevice) {
    func focus(_ mode: AVCaptureDevice.FocusMode, at point: DevicePoint) {
      if device.isFocusPointOfInterestSupported {
        device.focusPointOfInterest = CGPoint(x: point.x, y: point.y)
      }
      if device.isFocusModeSupported(mode) {
        device.focusMode = mode
      }
    }
    switch intent.focus {
    case .continuous:
      focus(.continuousAutoFocus, at: .center)
      if case .automatic = intent.exposure {
        applyAutomaticExposure(intent, to: device)
      }
      #if os(iOS)
      device.isSubjectAreaChangeMonitoringEnabled = false
      #endif
    case .point(let point):
      focus(.autoFocus, at: point)
      if case .automatic = intent.exposure {
        applyAutomaticExposure(intent, to: device)
      }
      #if os(iOS)
      device.isSubjectAreaChangeMonitoringEnabled = true
      #endif
    case .locked(let position):
      #if os(iOS)
      device.isSubjectAreaChangeMonitoringEnabled = false
      if device.isLockingFocusWithCustomLensPositionSupported {
        device.setFocusModeLocked(lensPosition: Float(position.rawValue.clamped(to: 0...1)))
      }
      #endif
    }
  }

  private func applyWhiteBalance(_ intent: DeviceIntent, to device: AVCaptureDevice) {
    switch intent.whiteBalance {
    case .automatic:
      if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
        device.whiteBalanceMode = .continuousAutoWhiteBalance
      }
    case .locked(let temperature, let tint):
      #if os(iOS)
      guard device.isLockingWhiteBalanceWithCustomDeviceGainsSupported else { return }
      let values = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(temperature: Float(temperature.rawValue), tint: Float(tint.rawValue))
      var gains = device.deviceWhiteBalanceGains(for: values)
      let limit = 1...max(1, device.maxWhiteBalanceGain)
      gains.redGain = gains.redGain.clamped(to: limit)
      gains.greenGain = gains.greenGain.clamped(to: limit)
      gains.blueGain = gains.blueGain.clamped(to: limit)
      device.setWhiteBalanceModeLocked(with: gains)
      #endif
    }
  }

  func steerExposure(offset: Float) {
    #if os(iOS)
    guard let steering, isStarted, let device = rig?.connection?.device, !isSteeringWriteInFlight else { return }
    let format = device.activeFormat
    let duration: CMTime
    let iso: Float
    switch steering {
    case .iso(let speed):
      let range = ISO(Double(max(format.minISO, 1)))...ISO(Double(max(format.maxISO, format.minISO)))
      guard let next = ExposureSteering.iso(holding: ISO(Double(device.iso)), offset: Double(offset), range: range) else { return }
      duration = format.exposureDuration(seconds: speed.rawValue)
      iso = Float(next.rawValue)
    case .shutterSpeed(let sensitivity):
      let range = ShutterSpeed(format.minExposureDuration.seconds)...ShutterSpeed(max(format.maxExposureDuration.seconds, format.minExposureDuration.seconds))
      guard let next = ExposureSteering.shutterSpeed(holding: ShutterSpeed(device.exposureDuration.seconds), offset: Double(offset), range: range) else { return }
      duration = format.exposureDuration(seconds: next.rawValue)
      iso = Float(sensitivity.rawValue)
    }
    do {
      try device.lockForConfiguration()
    } catch {
      return
    }
    defer { device.unlockForConfiguration() }
    isSteeringWriteInFlight = true
    let generation = steeringGeneration
    device.setExposureModeCustom(duration: duration, iso: iso) { [weak self] _ in
      Task { @CaptureActor in
        guard let self, self.steeringGeneration == generation else { return }
        self.isSteeringWriteInFlight = false
      }
    }
    #endif
  }
}

#if os(iOS)
extension AVCaptureDevice.Format {
  func exposureDuration(seconds: Double) -> CMTime {
    ExposureDuration.clamped(seconds: seconds, min: minExposureDuration, max: maxExposureDuration)
  }
}
#endif

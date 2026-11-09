import AVFoundation

struct CameraControlSliders {
  var iso: CameraControlSlider?
  var shutterSpeed: CameraControlSlider?
  var whiteBalance: CameraControlSlider?
  var focus: CameraControlSlider?
  var lensPicker: AVCaptureIndexPicker?
  var lensesInPicker: [CameraLens] = []
}

/// A slider and its span: the stops sit inside the device range, so a target clamped to that
/// range can still fall outside what the slider accepts.
struct CameraControlSlider {
  let slider: AVCaptureSlider
  let span: ClosedRange<Float>

  init?(_ slider: AVCaptureSlider, values: [Float]) {
    guard let low = values.min(), let high = values.max() else { return nil }
    self.slider = slider
    self.span = low...high
  }

  /// Slider values must change on the action queue, which is the session queue.
  func sync(_ value: Float) {
    guard value.isFinite else { return }
    let clamped = value.clamped(to: span)
    if abs(slider.value - clamped) > 0.0001 {
      slider.value = clamped
    }
  }
}

extension CameraEngine {
  func installControls(on connection: DeviceConnection, rig: Rig) {
    #if os(iOS)
    let session = rig.session
    guard session.supportsControls, !configuration.cameraControl.isEmpty else { return }
    if session.controlsDelegate == nil {
      rig.controlsDelegate = ControlsDelegate(events: events) { [weak self] in
        Task { @CaptureActor in self?.syncControlsWithDevice() }
      }
      session.setControlsDelegate(rig.controlsDelegate, queue: CaptureActor.shared.queue)
    }
    let device = connection.device
    let lens = connection.lens
    let facts = DeviceDiscovery.connectedDevice(lens: lens, device: device, photoOutput: rig.photoOutput, options: configuration.photo, resolutions: resolutions(of: device))
    let queue = CaptureActor.shared.queue
    var sliders = CameraControlSliders()
    var controls: [AVCaptureControl] = []

    for item in configuration.cameraControl.prefix(session.maxControlsCount) {
      let control: AVCaptureControl
      switch item {
      case .zoom:
        guard facts.support.zoom else { continue }
        control = AVCaptureSystemZoomSlider(device: device) { [weak camera, weak self] factor in
          let zoom = ZoomFactor(ZoomMapping.displayZoom(videoZoomFactor: Double(factor), lens: lens))
          camera?.adopt(.zoom(zoom))
          Task { @CaptureActor in self?.applied?.zoom = zoom }
        }
      case .exposureBias:
        guard facts.support.exposureBias else { continue }
        control = AVCaptureSystemExposureBiasSlider(device: device) { [weak camera, weak self] value in
          let bias = ExposureBias(Double(value))
          camera?.adopt(.bias(bias))
          Task { @CaptureActor in self?.applied?.bias = bias }
        }
      case .lensPicker:
        let lenses = rig.facts.lenses.filter { $0.position == lens.position }
        guard lenses.count > 1 else { continue }
        let picker = AVCaptureIndexPicker("Lens", symbolName: "camera.aperture", localizedIndexTitles: lenses.map(\.label))
        picker.selectedIndex = lenses.firstIndex { $0.id == lens.id } ?? 0
        picker.setActionQueue(queue) { [events] index in
          guard lenses.indices.contains(index) else { return }
          events.yield(.adopt(.lens(lenses[index].id)))
        }
        sliders.lensPicker = picker
        sliders.lensesInPicker = lenses
        control = picker
      case .iso:
        guard facts.support.customExposure else { continue }
        let values = ISO.stops(in: facts.ranges.iso).map { Float($0.rawValue) }
        let slider = AVCaptureSlider("ISO", symbolName: "camera.aperture", values: values)
        slider.setActionQueue(queue) { [weak self] value in
          Task { @CaptureActor in self?.cameraControlDidSet(iso: ISO(Double(value))) }
        }
        sliders.iso = CameraControlSlider(slider, values: values)
        control = slider
      case .shutterSpeed:
        guard facts.support.customExposure else { continue }
        let values = ShutterSpeed.stops(in: facts.ranges.shutterSpeed).map { Float($0.rawValue) }
        let slider = AVCaptureSlider("Shutter", symbolName: "camera.shutter.button", values: values)
        slider.setActionQueue(queue) { [weak self] value in
          Task { @CaptureActor in self?.cameraControlDidSet(shutterSpeed: ShutterSpeed(Double(value))) }
        }
        sliders.shutterSpeed = CameraControlSlider(slider, values: values)
        control = slider
      case .whiteBalance:
        guard facts.support.whiteBalanceLock else { continue }
        let values = Kelvin.stops(in: facts.ranges.temperature).map { Float($0.rawValue) }
        let slider = AVCaptureSlider("White Balance", symbolName: "thermometer.medium", values: values)
        slider.localizedValueFormat = "%@K"
        slider.setActionQueue(queue) { [weak self] value in
          Task { @CaptureActor in self?.cameraControlDidSet(temperature: Kelvin(Double(value))) }
        }
        sliders.whiteBalance = CameraControlSlider(slider, values: values)
        control = slider
      case .focus:
        guard facts.support.lensPositionLock else { continue }
        let slider = AVCaptureSlider("Focus", symbolName: "scope", in: 0...1)
        slider.setActionQueue(queue) { [weak self] value in
          Task { @CaptureActor in self?.cameraControlDidSet(lensPosition: LensPosition(Double(value))) }
        }
        sliders.focus = CameraControlSlider(slider, values: [0, 1])
        control = slider
      }
      guard session.canAddControl(control) else { continue }
      session.addControl(control)
      controls.append(control)
    }
    connection.controls = controls
    connection.controlSliders = sliders
    syncControls(with: deviceIntent, connection: connection)
    #endif
  }

  func removeControls(_ connection: DeviceConnection, from session: AVCaptureSession) {
    #if os(iOS)
    for control in connection.controls {
      session.removeControl(control)
    }
    connection.controls = []
    connection.controlSliders = CameraControlSliders()
    #endif
  }

  /// Writes the intent's targets to the sliders, and the device's current value to a slider
  /// whose parameter is automatic. A slider starts at its minimum otherwise, and the first
  /// detent would jump to that extreme instead of moving one stop from the value on screen.
  func syncControls(with intent: DeviceIntent, connection: DeviceConnection) {
    #if os(iOS)
    let sliders = connection.controlSliders
    let device = connection.device
    sliders.iso?.sync(Float(intent.exposure.isoTarget?.rawValue ?? Double(device.iso)))
    sliders.shutterSpeed?.sync(Float(intent.exposure.shutterSpeedTarget?.rawValue ?? device.exposureDuration.seconds))
    if let slider = sliders.whiteBalance {
      let temperature: Float? =
        if case .locked(let temperature, _) = intent.whiteBalance { Float(temperature.rawValue) } else { Self.temperature(of: device) }
      if let temperature {
        slider.sync(temperature)
      }
    }
    if let slider = sliders.focus {
      let position: Float = if case .locked(let position) = intent.focus { Float(position.rawValue) } else { device.lensPosition }
      slider.sync(position)
    }
    if let picker = sliders.lensPicker, let index = sliders.lensesInPicker.firstIndex(where: { $0.id == connection.lens.id }), picker.selectedIndex != index {
      picker.selectedIndex = index
    }
    #endif
  }

  #if os(iOS)
  /// Camera Control shows a slider's value as it becomes active, so an automatic parameter's
  /// slider takes the device's reading then.
  func syncControlsWithDevice() {
    guard let connection = rig?.connection else { return }
    syncControls(with: deviceIntent, connection: connection)
  }

  private static func temperature(of device: AVCaptureDevice) -> Float? {
    let gains = device.deviceWhiteBalanceGains
    guard gains.redGain > 0, gains.greenGain > 0, gains.blueGain > 0 else { return nil }
    return device.temperatureAndTintValues(for: gains).temperature
  }
  #endif

  #if os(iOS)
  private func cameraControlDidSet(iso: ISO) {
    adoptExposure(intent.exposure.fixing(iso: iso))
  }

  private func cameraControlDidSet(shutterSpeed: ShutterSpeed) {
    adoptExposure(intent.exposure.fixing(shutterSpeed: shutterSpeed))
  }

  private func adoptExposure(_ program: ExposureProgram) {
    var next = deviceIntent
    next.exposure = program
    applyAdopted(next)
    events.yield(.adopt(.exposure(program)))
  }

  private func cameraControlDidSet(temperature: Kelvin) {
    var next = deviceIntent
    let tint: Tint = if case .locked(_, let tint) = next.whiteBalance { tint } else { Tint(0) }
    next.whiteBalance = .locked(temperature, tint)
    applyAdopted(next)
    events.yield(.adopt(.whiteBalance(next.whiteBalance)))
  }

  private func cameraControlDidSet(lensPosition: LensPosition) {
    var next = deviceIntent
    next.focus = .locked(lensPosition)
    applyAdopted(next)
    events.yield(.adopt(.focus(next.focus)))
  }

  var deviceIntent: DeviceIntent {
    applied ?? intent
  }

  private func applyAdopted(_ next: DeviceIntent) {
    reconcile(next, full: false)
  }
  #endif
}

#if os(iOS)
final class ControlsDelegate: NSObject, AVCaptureSessionControlsDelegate {
  private let events: AsyncStream<EngineEvent>.Continuation
  private let didBecomeActive: @Sendable () -> Void

  init(events: AsyncStream<EngineEvent>.Continuation, didBecomeActive: @escaping @Sendable () -> Void) {
    self.events = events
    self.didBecomeActive = didBecomeActive
  }

  func sessionControlsDidBecomeActive(_ session: AVCaptureSession) {
    didBecomeActive()
    events.yield(.cameraControlAppearance(.active))
  }

  func sessionControlsWillEnterFullscreenAppearance(_ session: AVCaptureSession) {
    events.yield(.cameraControlAppearance(.fullscreen))
  }

  func sessionControlsWillExitFullscreenAppearance(_ session: AVCaptureSession) {
    events.yield(.cameraControlAppearance(.active))
  }

  func sessionControlsDidBecomeInactive(_ session: AVCaptureSession) {
    events.yield(.cameraControlAppearance(.inactive))
  }
}
#endif

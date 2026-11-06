import Foundation

enum SimulatedDevice {
  static func lenses(for simulation: CameraSimulation, selection: LensSelection) -> [CameraLens] {
    guard simulation.lenses.isEmpty else { return simulation.lenses }
    let facts = [
      PhysicalCameraFacts(id: "simulated.back.ultrawide", position: .back, kind: .ultraWide, switchOverZoom: 1, displayMultiplier: 0.5, largestPhotoMegapixels: 12),
      PhysicalCameraFacts(id: "simulated.back.wide", position: .back, kind: .wide, switchOverZoom: 2, displayMultiplier: 0.5, largestPhotoMegapixels: 48),
      PhysicalCameraFacts(id: "simulated.back.telephoto", position: .back, kind: .telephoto, switchOverZoom: 10, displayMultiplier: 0.5, largestPhotoMegapixels: 12),
      PhysicalCameraFacts(id: "simulated.front.wide", position: .front, kind: .wide, switchOverZoom: 1, displayMultiplier: 1, largestPhotoMegapixels: 12),
    ]
    return LensDiscovery.lenses(from: facts, selection: selection)
  }

  static func connectedDevice(for lens: CameraLens, options: PhotoOptions) -> ConnectedDevice {
    let twelve = PhotoResolution(width: 4032, height: 3024)
    let fortyEight = PhotoResolution(width: 8064, height: 6048)
    let isMain = lens.kind == .wide && lens.crop == 1 && lens.position == .back
    let resolutions = isMain ? [twelve, fortyEight] : [twelve]
    return ConnectedDevice(
      lensID: lens.id,
      ranges: ControlRanges(
        iso: ISO(50)...ISO(6400),
        shutterSpeed: ShutterSpeed(1 / 8000)...ShutterSpeed(1),
        bias: ExposureBias(-2)...ExposureBias(2),
        temperature: Kelvin(3000)...Kelvin(8000),
        tint: Tint(-150)...Tint(150),
        lensPosition: LensPosition(0)...LensPosition(1),
        videoZoomFactor: 1...6
      ),
      support: .everything,
      photo: PhotoFacts(
        format: options.deliveredFormat(supportsProRAW: false, supportsHEVC: true),
        resolutions: resolutions,
        output: PhotoOutputFacts(
          hasHEVC: true,
          flashModes: lens.position == .front ? [.off] : [.off, .on, .auto],
          maxDimensions: resolutions.last
        )
      )
    )
  }

  static func targets(for intent: DeviceIntent, lens: CameraLens, ranges: ControlRanges) -> DeviceReadings {
    var readings = DeviceReadings()
    readings.iso = intent.exposure.isoTarget?.clamped(to: ranges.iso) ?? ISO(100)
    readings.shutterSpeed = intent.exposure.shutterSpeedTarget?.clamped(to: ranges.shutterSpeed) ?? ShutterSpeed(1 / 120)
    readings.bias = intent.bias.clamped(to: ranges.bias)
    readings.exposureOffset = intent.exposure.isManual ? 0.3 : 0
    switch intent.whiteBalance {
    case .automatic:
      readings.temperature = Kelvin(5200)
      readings.tint = Tint(0)
    case .locked(let temperature, let tint):
      readings.temperature = temperature.clamped(to: ranges.temperature)
      readings.tint = tint.clamped(to: ranges.tint)
    }
    switch intent.focus {
    case .continuous: readings.lensPosition = LensPosition(0.6)
    case .point(let point): readings.lensPosition = LensPosition(0.3 + 0.4 * point.y)
    case .locked(let position): readings.lensPosition = position.clamped(to: ranges.lensPosition)
    }
    readings.videoZoomFactor = ZoomMapping.deviceFactor(for: intent.zoom, lens: lens, deviceRange: ranges.videoZoomFactor)
    return readings
  }

  static func step(_ readings: DeviceReadings, toward targets: DeviceReadings) -> DeviceReadings {
    var next = readings
    next.iso = approach(readings.iso?.rawValue, targets.iso?.rawValue).map(ISO.init)
    next.shutterSpeed = approach(readings.shutterSpeed?.rawValue, targets.shutterSpeed?.rawValue).map(ShutterSpeed.init)
    next.bias = approach(readings.bias?.rawValue, targets.bias?.rawValue).map(ExposureBias.init)
    next.exposureOffset = approach(readings.exposureOffset, targets.exposureOffset)
    next.temperature = approach(readings.temperature?.rawValue, targets.temperature?.rawValue).map(Kelvin.init)
    next.tint = approach(readings.tint?.rawValue, targets.tint?.rawValue).map(Tint.init)
    next.lensPosition = approach(readings.lensPosition?.rawValue, targets.lensPosition?.rawValue).map(LensPosition.init)
    next.videoZoomFactor = approach(readings.videoZoomFactor, targets.videoZoomFactor)
    next.isAdjustingExposure = next.iso != targets.iso || next.shutterSpeed != targets.shutterSpeed
    next.isAdjustingFocus = next.lensPosition != targets.lensPosition
    next.isAdjustingWhiteBalance = next.temperature != targets.temperature || next.tint != targets.tint
    next.isRampingZoom = next.videoZoomFactor != targets.videoZoomFactor
    return next
  }

  private static func approach(_ value: Double?, _ target: Double?) -> Double? {
    guard let target else { return value }
    guard let value else { return target }
    let next = value + (target - value) / 3
    let tolerance = max(abs(target) * 0.005, 0.002)
    return abs(next - target) <= tolerance ? target : next
  }
}

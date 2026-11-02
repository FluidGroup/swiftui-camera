struct DeviceFacts: Sendable, Hashable {
  var positions: [CameraPosition] = []
  var lenses: [CameraLens] = []
  var defaultLensID: CameraLens.ID?
  var connected: ConnectedDevice?
}

struct ConnectedDevice: Sendable, Hashable {
  var lensID: CameraLens.ID
  var ranges: ControlRanges
  var support: ControlSupport
  var photo: PhotoFacts
}

struct ControlRanges: Sendable, Hashable {
  var iso: ClosedRange<ISO>
  var shutterSpeed: ClosedRange<ShutterSpeed>
  var bias: ClosedRange<ExposureBias>
  var temperature: ClosedRange<Kelvin>
  var tint: ClosedRange<Tint>
  var lensPosition: ClosedRange<LensPosition>
  var videoZoomFactor: ClosedRange<Double>

  static let placeholder = ControlRanges(
    iso: ISO(32)...ISO(3200),
    shutterSpeed: ShutterSpeed(1 / 8000)...ShutterSpeed(1),
    bias: ExposureBias(-2)...ExposureBias(2),
    temperature: Kelvin(3000)...Kelvin(8000),
    tint: Tint(-150)...Tint(150),
    lensPosition: LensPosition(0)...LensPosition(1),
    videoZoomFactor: 1...1
  )
}

struct ControlSupport: Sendable, Hashable {
  var customExposure = false
  var exposureBias = false
  var lensPositionLock = false
  var whiteBalanceLock = false
  var zoom = false
  var focusPoint = false

  static let none = ControlSupport()
  static let everything = ControlSupport(
    customExposure: true,
    exposureBias: true,
    lensPositionLock: true,
    whiteBalanceLock: true,
    zoom: true,
    focusPoint: true
  )
}

struct PhotoFacts: Sendable, Hashable {
  var format: PhotoFormat
  var resolutions: [PhotoResolution]
  var output: PhotoOutputFacts
}

struct PhotoOutputFacts: Sendable, Hashable {
  var rawPixelFormat: UInt32?
  var hasHEVC = false
  var flashModes: Set<FlashMode> = []
  var maxDimensions: PhotoResolution?
}

struct DeviceReadings: Sendable, Hashable {
  var iso: ISO?
  var shutterSpeed: ShutterSpeed?
  var bias: ExposureBias?
  var exposureOffset: Double?
  var temperature: Kelvin?
  var tint: Tint?
  var lensPosition: LensPosition?
  var videoZoomFactor: Double?
  var isAdjustingExposure = false
  var isAdjustingFocus = false
  var isAdjustingWhiteBalance = false
  var isRampingZoom = false
}

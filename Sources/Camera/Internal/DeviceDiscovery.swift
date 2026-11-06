import AVFoundation

enum DeviceDiscovery {
  struct Discovery {
    var devices: [String: AVCaptureDevice] = [:]
    var facts: [PhysicalCameraFacts] = []
    var defaultID: String?
  }

  static func discover() -> Discovery {
    var discovery = Discovery()
    #if os(iOS)
    let virtualTypes: [AVCaptureDevice.DeviceType] = [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera]
    let virtualDevice = virtualTypes.lazy.compactMap { AVCaptureDevice.default($0, for: .video, position: .back) }.first
    let backCameras =
      virtualDevice?.constituentDevices
      ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back).map { [$0] }
      ?? []
    // Camera n takes over at switch-over factor n - 1.
    let switchOverZooms = [1.0] + (virtualDevice?.virtualDeviceSwitchOverVideoZoomFactors ?? []).map { Double(truncating: $0) }
    let multiplier = virtualDevice.map { Double($0.displayVideoZoomFactorMultiplier) } ?? 1
    for (device, switchOverZoom) in zip(backCameras, switchOverZooms) {
      discovery.add(device, position: .back, switchOverZoom: switchOverZoom, displayMultiplier: multiplier)
    }
    if let front = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
      discovery.add(front, position: .front, switchOverZoom: 1, displayMultiplier: 1)
    }
    let external = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified)
    for device in external.devices {
      discovery.add(device, position: .unspecified, switchOverZoom: 1, displayMultiplier: 1)
    }
    #else
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external], mediaType: .video, position: .unspecified)
    for device in session.devices {
      discovery.add(device, position: .unspecified, switchOverZoom: 1, displayMultiplier: 1)
    }
    discovery.defaultID = AVCaptureDevice.default(for: .video)?.uniqueID
    #endif
    return discovery
  }

  static func kind(of deviceType: AVCaptureDevice.DeviceType) -> CameraLens.Kind? {
    switch deviceType {
    case .builtInWideAngleCamera: .wide
    case .continuityCamera, .external: .external
    #if os(iOS)
    case .builtInUltraWideCamera: .ultraWide
    case .builtInTelephotoCamera: .telephoto
    #endif
    default: nil
    }
  }

  static func connectedDevice(
    lens: CameraLens,
    device: AVCaptureDevice,
    photoOutput: AVCapturePhotoOutput,
    options: PhotoOptions,
    resolutions: [PhotoResolution]
  ) -> ConnectedDevice {
    var ranges = ControlRanges.placeholder
    var support = ControlSupport.none
    support.focusPoint = device.isFocusPointOfInterestSupported
    var supportsProRAW = false
    #if os(iOS)
    let format = device.activeFormat
    ranges.iso = ISO(Double(format.minISO))...ISO(Double(max(format.minISO, format.maxISO)))
    let minDuration = format.minExposureDuration.seconds
    let maxDuration = max(minDuration, format.maxExposureDuration.seconds)
    ranges.shutterSpeed = ShutterSpeed(minDuration)...ShutterSpeed(maxDuration)
    let biasRange = format.systemRecommendedExposureBiasRange ?? device.minExposureTargetBias...device.maxExposureTargetBias
    ranges.bias = ExposureBias(Double(biasRange.lowerBound))...ExposureBias(Double(max(biasRange.lowerBound, biasRange.upperBound)))
    let zoomRange = format.systemRecommendedVideoZoomRange ?? device.minAvailableVideoZoomFactor...device.maxAvailableVideoZoomFactor
    ranges.videoZoomFactor = Double(zoomRange.lowerBound)...Double(max(zoomRange.lowerBound, zoomRange.upperBound))
    support.customExposure = device.isExposureModeSupported(.custom) && !device.isVirtualDevice
    support.exposureBias = true
    support.lensPositionLock = device.isLockingFocusWithCustomLensPositionSupported && device.isFocusModeSupported(.locked)
    support.whiteBalanceLock = device.isLockingWhiteBalanceWithCustomDeviceGainsSupported && device.isWhiteBalanceModeSupported(.locked)
    support.zoom = true
    supportsProRAW = photoOutput.isAppleProRAWSupported
    #endif
    let codecs = photoOutput.availablePhotoCodecTypes
    var output = PhotoOutputFacts()
    #if os(iOS)
    output.rawPixelFormat = photoOutput.availableRawPhotoPixelFormatTypes.first { AVCapturePhotoOutput.isAppleProRAWPixelFormat($0) }
    #endif
    output.hasHEVC = codecs.contains(.hevc)
    output.flashModes = Set(photoOutput.supportedFlashModes.compactMap(FlashMode.init))
    let ceiling = photoOutput.maxPhotoDimensions
    output.maxDimensions = PhotoResolution(width: Int(ceiling.width), height: Int(ceiling.height))
    return ConnectedDevice(
      lensID: lens.id,
      ranges: ranges,
      support: support,
      photo: PhotoFacts(
        format: options.deliveredFormat(supportsProRAW: supportsProRAW && output.rawPixelFormat != nil, supportsHEVC: output.hasHEVC),
        resolutions: PhotoResolutionSelection.offered(resolutions, crop: lens.crop),
        output: output
      )
    )
  }
}

extension DeviceDiscovery.Discovery {
  fileprivate mutating func add(_ device: AVCaptureDevice, position: CameraPosition, switchOverZoom: Double, displayMultiplier: Double) {
    guard let kind = DeviceDiscovery.kind(of: device.deviceType) else { return }
    let megapixels =
      device.formats
      .flatMap(\.supportedMaxPhotoDimensions)
      .map { Double($0.width) * Double($0.height) / 1_000_000 }
      .max() ?? 0
    devices[device.uniqueID] = device
    facts.append(
      PhysicalCameraFacts(
        id: device.uniqueID,
        position: position,
        kind: kind,
        switchOverZoom: switchOverZoom,
        displayMultiplier: displayMultiplier,
        largestPhotoMegapixels: megapixels
      ))
  }
}

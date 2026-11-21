import AVFoundation
import Synchronization

final class DeviceReadingsMonitor {
  private let coalescer: ReadingsCoalescer
  private var observations: [NSKeyValueObservation] = []

  init(
    device: AVCaptureDevice,
    publish: @escaping @MainActor @Sendable (DeviceReadings) -> Void,
    exposureOffsetDidChange: @escaping @CaptureActor @Sendable (Float) -> Void
  ) {
    coalescer = ReadingsCoalescer(publish: publish, exposureOffsetDidChange: exposureOffsetDidChange)
    let coalescer = coalescer
    observations = [
      device.observe(\.isAdjustingExposure, options: [.initial, .new]) { _, change in
        coalescer.update { $0.isAdjustingExposure = change.newValue ?? false }
      },
      device.observe(\.isAdjustingFocus, options: [.initial, .new]) { _, change in
        coalescer.update { $0.isAdjustingFocus = change.newValue ?? false }
      },
      device.observe(\.isAdjustingWhiteBalance, options: [.initial, .new]) { _, change in
        coalescer.update { $0.isAdjustingWhiteBalance = change.newValue ?? false }
      },
    ]
    #if os(iOS)
    observations += [
      device.observe(\.iso, options: [.initial, .new]) { _, change in
        coalescer.update { $0.iso = change.newValue.map { ISO(Double($0)) } }
      },
      device.observe(\.exposureDuration, options: [.initial, .new]) { device, _ in
        let seconds = device.exposureDuration.seconds
        coalescer.update { $0.shutterSpeed = seconds.isFinite && seconds > 0 ? ShutterSpeed(seconds) : nil }
      },
      device.observe(\.exposureTargetBias, options: [.initial, .new]) { _, change in
        coalescer.update { $0.bias = change.newValue.map { ExposureBias(Double($0)) } }
      },
      device.observe(\.exposureTargetOffset, options: [.initial, .new]) { _, change in
        guard let offset = change.newValue else { return }
        coalescer.update { $0.exposureOffset = Double(offset) }
        coalescer.exposureOffsetChanged(offset)
      },
      device.observe(\.deviceWhiteBalanceGains, options: [.initial, .new]) { device, _ in
        guard let values = device.readWhiteBalanceTemperatureAndTint() else {
          return
        }
        coalescer.update {
          $0.temperature = Kelvin(Double(values.temperature))
          $0.tint = Tint(Double(values.tint))
        }
      },
      device.observe(\.lensPosition, options: [.initial, .new]) { _, change in
        coalescer.update { $0.lensPosition = change.newValue.map { LensPosition(Double($0)) } }
      },
      device.observe(\.videoZoomFactor, options: [.initial, .new]) { _, change in
        coalescer.update { $0.videoZoomFactor = change.newValue.map(Double.init) }
      },
      device.observe(\.isRampingVideoZoom, options: [.initial, .new]) { _, change in
        coalescer.update { $0.isRampingZoom = change.newValue ?? false }
      },
    ]
    #endif
  }

  func stop() {
    observations = []
  }
}

#if os(iOS)
extension AVCaptureDevice {

  /// Skips samples that would raise an AVFoundation range exception during conversion.
  func readWhiteBalanceTemperatureAndTint() -> WhiteBalanceTemperatureAndTintValues? {
    let maxGain = maxWhiteBalanceGain
    guard maxGain.isFinite, maxGain >= 1 else {
      return nil
    }

    let gains = deviceWhiteBalanceGains
    let supportedGains = 1...maxGain
    guard
      supportedGains.contains(gains.redGain),
      supportedGains.contains(gains.greenGain),
      supportedGains.contains(gains.blueGain)
    else {
      return nil
    }

    return temperatureAndTintValues(for: gains)
  }

}
#endif

final class ReadingsCoalescer: Sendable {
  private struct State {
    var readings = DeviceReadings()
    var isPublishScheduled = false
    var pendingOffset: Float?
  }

  private let state = Mutex(State())
  private let publish: @MainActor @Sendable (DeviceReadings) -> Void
  private let exposureOffsetDidChange: @CaptureActor @Sendable (Float) -> Void

  init(publish: @escaping @MainActor @Sendable (DeviceReadings) -> Void, exposureOffsetDidChange: @escaping @CaptureActor @Sendable (Float) -> Void) {
    self.publish = publish
    self.exposureOffsetDidChange = exposureOffsetDidChange
  }

  func update(_ change: (inout DeviceReadings) -> Void) {
    let shouldSchedule = state.withLock { state in
      change(&state.readings)
      defer { state.isPublishScheduled = true }
      return !state.isPublishScheduled
    }
    guard shouldSchedule else { return }
    Task { @MainActor [self] in
      let readings = state.withLock { state in
        state.isPublishScheduled = false
        return state.readings
      }
      publish(readings)
    }
  }

  func exposureOffsetChanged(_ offset: Float) {
    let shouldSchedule = state.withLock { state in
      defer { state.pendingOffset = offset }
      return state.pendingOffset == nil
    }
    guard shouldSchedule else { return }
    Task { @CaptureActor [self] in
      let offset = state.withLock { state in
        defer { state.pendingOffset = nil }
        return state.pendingOffset
      }
      if let offset {
        exposureOffsetDidChange(offset)
      }
    }
  }
}

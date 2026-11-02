import Foundation

enum BackendKind: Sendable, Hashable {
  case hardware
  case simulated(CameraSimulation)

  static func select(_ source: CameraSource) -> BackendKind {
    switch source {
    case .hardware: .hardware
    case .simulated(let simulation): .simulated(simulation)
    case .automatic: runsWithoutHardware ? .simulated(CameraSimulation()) : .hardware
    }
  }

  static var runsWithoutHardware: Bool {
    #if targetEnvironment(simulator)
    true
    #else
    ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
    #endif
  }

  var needsAuthorization: Bool {
    switch self {
    case .hardware: true
    case .simulated: false
    }
  }
}

struct EngineConfiguration: Sendable {
  let photo: PhotoOptions
  let lensSelection: LensSelection
  let mirroring: Mirroring
  let hardwareControls: [HardwareControl]
}

@CaptureActor
protocol CameraBackend: AnyObject, Sendable {
  func drain(_ commands: AsyncStream<LaneCommand>) async
}

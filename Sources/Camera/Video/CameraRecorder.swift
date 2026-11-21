@preconcurrency import AVFoundation
import VideoToolbox
import os

/// The source encoding of a movie, for editors that need the actual capture profile.
public enum VideoRecordingProfile: Sendable {
  case appleLog2
  case appleLog
  case standard

  fileprivate var captureColorSpace: AVCaptureColorSpace? {
    #if os(iOS)
      switch self {
      case .appleLog2:
        if #available(iOS 26, *) { return .appleLog2 }
        return nil
      case .appleLog:
        return .appleLog
      case .standard:
        return nil
      }
    #else
      return nil
    #endif
  }

  /// The 10-bit sample format that keeps Log code values intact, or `nil` to
  /// take the camera's default 8-bit buffers.
  fileprivate var tenBitPixelFormat: OSType? {
    switch self {
    case .appleLog2, .appleLog:
      return kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange
    case .standard:
      return nil
    }
  }
}

/// Failures the camera reports while connecting its devices or recording.
private enum CameraRecorderError: LocalizedError, Sendable {
  case cameraUnavailable
  case cannotAddInput
  case cannotAddOutput
  /// The asset writer rejected the HEVC settings for this camera format.
  case hevcUnavailable
  /// The asset writer stopped without completing the movie file.
  case recordingFailed

  var errorDescription: String? {
    switch self {
    case .cameraUnavailable:
      return String(localized: "No camera is available for recording.")
    case .cannotAddInput:
      return String(localized: "The camera could not be connected.")
    case .cannotAddOutput:
      return String(localized: "The camera could not be prepared for recording.")
    case .hevcUnavailable:
      return String(localized: "The camera format cannot be recorded as HEVC.")
    case .recordingFailed:
      return String(localized: "The recording could not be saved.")
    }
  }
}

/// One hardware configuration. Its inputs, delegates and movie writer all live
/// on the capture executor. A new configuration is built after each handoff.
@CaptureActor
final class CameraRecorder {
  let session = AVCaptureSession()
  private(set) var videoDevice: AVCaptureDevice?
  private let simulated: Bool
  let frames: PreviewFrames
  private var simulationTask: Task<Void, Never>?
  private var simulationPool = PixelBufferPool()

  init(simulated: Bool, frames: PreviewFrames) {
    self.simulated = simulated
    self.frames = frames
  }

  private static let recordingFrameRate: Float64 = 30
  private static let maximumRecordingWidth: Int32 = 3840
  private static let bitsPerPixel: Double = 0.2

  private let videoDataOutput = AVCaptureVideoDataOutput()
  private let audioDataOutput = AVCaptureAudioDataOutput()
  private let logger = Logger(subsystem: "swiftui-camera", category: "Camera")

  private var profile: VideoRecordingProfile?
  private var captureRotationCoordinator: AVCaptureDevice.RotationCoordinator?
  /// Kept alive here; the data outputs only point at it.
  private var sampleBufferRelay: SampleBufferRelay?
  /// The movie being written, from shutter press until release.
  private var activeRecording: MovieRecording?

  /// Connects the camera, the microphone, and the sample outputs, preferring
  /// Apple Log 2, then Apple Log, and reports the encoding recordings use.
  ///
  /// - Parameter includesAudio: Whether microphone access was granted.
  func configure(includesAudio: Bool) throws -> VideoRecordingProfile {
    if let profile {
      return profile
    }
    if simulated {
      profile = .standard
      return .standard
    }
    #if os(iOS)
      session.automaticallyConfiguresApplicationAudioSession = includesAudio
      session.configuresApplicationAudioSessionToMixWithOthers = true
      videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
    #else
      videoDevice = AVCaptureDevice.default(for: .video)
    #endif
    guard let videoDevice else {
      throw CameraRecorderError.cameraUnavailable
    }

    let relay = SampleBufferRelay(recorder: self)
    sampleBufferRelay = relay
    let profile = try connect(videoDevice, includesAudio: includesAudio, relay: relay)
    try prepareAutomaticControls(on: videoDevice)

    // The data output's pixel formats follow the committed active format.
    if let pixelFormat = profile.tenBitPixelFormat {
      if videoDataOutput.availableVideoPixelFormatTypes.contains(pixelFormat) {
        videoDataOutput.videoSettings = [
          kCVPixelBufferPixelFormatTypeKey as String: pixelFormat
        ]
      } else {
        throw CameraRecorderError.hevcUnavailable
      }
    }
    #if os(iOS)
      if let connection = videoDataOutput.connection(with: .video),
        connection.isVideoStabilizationSupported
      {
        connection.preferredVideoStabilizationMode = .standard
      }
    #endif
    captureRotationCoordinator = AVCaptureDevice.RotationCoordinator(
      device: videoDevice,
      previewLayer: nil
    )
    self.profile = profile
    return profile
  }

  var hasAudio: Bool { audioDataOutput.connection(with: .audio) != nil }

  func startRunning() throws {
    if simulated {
      simulationTask = Task { @CaptureActor [weak self] in
        while !Task.isCancelled {
          self?.emitSimulatedFrame()
          try? await Task.sleep(for: .milliseconds(33))
        }
      }
    } else {
      session.startRunning()
      guard session.isRunning else { throw CameraRecorderError.cameraUnavailable }
    }
  }

  func stopRunning() {
    simulationTask?.cancel()
    if session.isRunning { session.stopRunning() }
    session.beginConfiguration()
    for input in session.inputs { session.removeInput(input) }
    for output in session.outputs { session.removeOutput(output) }
    session.commitConfiguration()
  }

  private static let simulationSize = CMVideoDimensions(width: 360, height: 640)

  private func emitSimulatedFrame() {
    let size = Self.simulationSize
    guard let buffer = simulationPool.buffer(width: Int(size.width), height: Int(size.height))
    else { return }
    TestPattern.draw(into: buffer, phase: TestPattern.phase())
    frames.deliver(PreviewFrame(pixelBuffer: buffer, deviceID: nil, isMirrored: false))
    guard activeRecording != nil else { return }
    var format: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(
      allocator: nil, imageBuffer: buffer, formatDescriptionOut: &format)
    guard let format else { return }
    var timing = CMSampleTimingInfo(
      duration: CMTime(value: 1, timescale: 30),
      presentationTimeStamp: CMClockGetTime(CMClockGetHostTimeClock()), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    CMSampleBufferCreateReadyWithImageBuffer(
      allocator: nil, imageBuffer: buffer, formatDescription: format, sampleTiming: &timing,
      sampleBufferOut: &sample)
    if let sample { append(sample, from: videoDataOutput) }
  }

  /// Starts writing a new movie file. Each recording is its own file, so one
  /// hold of the shutter becomes one clip.
  ///
  /// The movie's timeline starts at the next video frame.
  func startRecording() throws {
    guard let profile, activeRecording == nil else { throw CameraRecorderError.cameraUnavailable }

    let file = CapturedFile(url: try CapturedFileStore.makeURL(fileExtension: "mov"))
    let writer = try AVAssetWriter(outputURL: file.url, fileType: .mov)

    let dimensions = videoDevice?.activeFormat.formatDescription.dimensions ?? Self.simulationSize
    let videoSettings = Self.makeVideoSettings(
      dimensions: dimensions,
      isTenBit: profile.tenBitPixelFormat != nil
    )
    guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
      throw CameraRecorderError.hevcUnavailable
    }
    // Without AVVideoColorPropertiesKey the movie takes its color tags,
    // including the Apple Log transfer function, from the camera's buffers.
    let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
    videoInput.expectsMediaDataInRealTime = true
    if let captureRotationCoordinator {
      // The UI is portrait-only, but the movie plays back the way the phone
      // was held.
      videoInput.transform = Self.trackTransform(
        rotationAngle: captureRotationCoordinator.videoRotationAngleForHorizonLevelCapture,
        dimensions: dimensions
      )
    }
    writer.add(videoInput)

    var audioInput: AVAssetWriterInput?
    if audioDataOutput.connection(with: .audio) != nil,
      let audioSettings = audioDataOutput.recommendedAudioSettingsForAssetWriter(
        writingTo: .mov
      )
    {
      let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
      input.expectsMediaDataInRealTime = true
      if writer.canAdd(input) {
        writer.add(input)
        audioInput = input
      }
    }

    guard writer.startWriting() else {
      throw writer.error ?? CameraRecorderError.recordingFailed
    }
    activeRecording = MovieRecording(
      file: file,
      writer: writer,
      videoInput: videoInput,
      audioInput: audioInput
    )
  }

  /// Stops the current recording and waits until its file is complete.
  ///
  /// - Returns: The finished movie, or `nil` when nothing was recording or
  ///   the shutter was released too soon to keep a clip.
  func stopRecording(minimumDuration: TimeInterval) async throws -> CapturedFile? {
    guard let recording = activeRecording else { return nil }
    activeRecording = nil

    guard recording.writer.status == .writing else {
      logger.error(
        "The recording failed while writing: \(String(describing: recording.writer.error), privacy: .public)"
      )
      throw recording.writer.error ?? CameraRecorderError.recordingFailed
    }

    guard
      let startTime = recording.startTime,
      let lastVideoTime = recording.lastVideoTime,
      (lastVideoTime - startTime).seconds >= minimumDuration
    else {
      // Cancelling deletes the partial file.
      recording.writer.cancelWriting()
      return nil
    }

    recording.videoInput.markAsFinished()
    recording.audioInput?.markAsFinished()
    await recording.writer.finishWriting()

    guard recording.writer.status == .completed else {
      throw recording.writer.error ?? CameraRecorderError.recordingFailed
    }
    return recording.file
  }

  /// Appends one camera sample to the active recording.
  ///
  /// Runs synchronously on the session queue that also executes this actor.
  fileprivate func append(_ sampleBuffer: CMSampleBuffer, from output: AVCaptureOutput) {
    #if os(macOS)
      if !simulated, output === videoDataOutput, let buffer = sampleBuffer.imageBuffer {
        frames.deliver(
          PreviewFrame(pixelBuffer: buffer, deviceID: videoDevice?.uniqueID, isMirrored: false))
      }
    #endif
    guard var recording = activeRecording, recording.writer.status == .writing else {
      return
    }
    let time = sampleBuffer.presentationTimeStamp

    if output === videoDataOutput {
      if recording.startTime == nil {
        recording.writer.startSession(atSourceTime: time)
        recording.startTime = time
      }
      if recording.videoInput.isReadyForMoreMediaData {
        if recording.videoInput.append(sampleBuffer) { recording.lastVideoTime = time }
      } else {
        logger.debug("Dropped a video frame because the encoder is busy.")
      }
    } else if let audioInput = recording.audioInput,
      let startTime = recording.startTime,
      time >= startTime,
      audioInput.isReadyForMoreMediaData
    {
      // Audio before the first video frame would start before the timeline.
      audioInput.append(sampleBuffer)
    }

    activeRecording = recording
  }

  // MARK: - Private

  /// Adds the inputs and the sample outputs in one configuration, which
  /// commits when this returns.
  private func connect(
    _ videoDevice: AVCaptureDevice,
    includesAudio: Bool,
    relay: SampleBufferRelay
  ) throws -> VideoRecordingProfile {
    session.beginConfiguration()
    defer { session.commitConfiguration() }

    let videoInput = try AVCaptureDeviceInput(device: videoDevice)
    guard session.canAddInput(videoInput) else {
      throw CameraRecorderError.cannotAddInput
    }
    session.addInput(videoInput)

    // A recording keeps every frame; dropping late ones would leave gaps.
    videoDataOutput.alwaysDiscardsLateVideoFrames = false
    videoDataOutput.setSampleBufferDelegate(relay, queue: CaptureActor.shared.queue)
    guard session.canAddOutput(videoDataOutput) else {
      throw CameraRecorderError.cannotAddOutput
    }
    session.addOutput(videoDataOutput)

    if includesAudio, addMicrophone() {
      audioDataOutput.setSampleBufferDelegate(relay, queue: CaptureActor.shared.queue)
      if session.canAddOutput(audioDataOutput) {
        session.addOutput(audioDataOutput)
      }
    }

    #if os(iOS)
      if let logFormat = Self.preferredLogFormat(of: videoDevice) {
        session.automaticallyConfiguresCaptureDeviceForWideColor = false
        session.sessionPreset = .inputPriority
        try apply(logFormat, to: videoDevice)
        return logFormat.profile
      }
    #endif
    session.sessionPreset = session.canSetSessionPreset(.hd4K3840x2160) ? .hd4K3840x2160 : .high
    return .standard
  }

  /// The same physical device may still have a photo camera's manual controls.
  /// Establish the movie defaults after committing the selected recording format.
  private func prepareAutomaticControls(on device: AVCaptureDevice) throws {
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }

    let center = CGPoint(x: 0.5, y: 0.5)
    if device.isFocusPointOfInterestSupported { device.focusPointOfInterest = center }
    if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
    if device.isExposurePointOfInterestSupported { device.exposurePointOfInterest = center }
    if device.isExposureModeSupported(.continuousAutoExposure) {
      device.exposureMode = .continuousAutoExposure
    }
    if device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
      device.whiteBalanceMode = .continuousAutoWhiteBalance
    }
    #if os(iOS)
      device.isSubjectAreaChangeMonitoringEnabled = false
      device.videoZoomFactor = min(
        max(1, device.minAvailableVideoZoomFactor), device.maxAvailableVideoZoomFactor)
      if device.exposureTargetBias != 0 {
        device.setExposureTargetBias(0, completionHandler: nil)
      }
    #endif
  }

  /// - Returns: Whether the microphone is connected.
  private func addMicrophone() -> Bool {
    guard
      let microphone = AVCaptureDevice.default(for: .audio),
      let audioInput = try? AVCaptureDeviceInput(device: microphone),
      session.canAddInput(audioInput)
    else {
      logger.error("The microphone could not be connected; recording without audio.")
      return false
    }
    session.addInput(audioInput)
    return true
  }

  private func apply(_ logFormat: LogFormat, to device: AVCaptureDevice) throws {
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }

    device.activeFormat = logFormat.format
    device.activeColorSpace = logFormat.colorSpace
    // Frame durations reset to the format's default when the format changes.
    let frameDuration = CMTime(
      value: 1,
      timescale: CMTimeScale(Self.recordingFrameRate)
    )
    device.activeVideoMinFrameDuration = frameDuration
    device.activeVideoMaxFrameDuration = frameDuration
  }

  /// HEVC at a bit rate scaled to the frame size; 10-bit sources use Main10
  /// so Log code values are not truncated to 8 bits.
  private static func makeVideoSettings(
    dimensions: CMVideoDimensions,
    isTenBit: Bool
  ) -> [String: Any] {
    let bitRate =
      Double(dimensions.width) * Double(dimensions.height) * recordingFrameRate
      * bitsPerPixel
    var compressionProperties: [String: Any] = [
      AVVideoAverageBitRateKey: Int(bitRate),
      AVVideoExpectedSourceFrameRateKey: recordingFrameRate,
    ]
    if isTenBit {
      compressionProperties[AVVideoProfileLevelKey] =
        kVTProfileLevel_HEVC_Main10_AutoLevel as String
    }
    return [
      AVVideoCodecKey: AVVideoCodecType.hevc,
      AVVideoWidthKey: Int(dimensions.width),
      AVVideoHeightKey: Int(dimensions.height),
      AVVideoCompressionPropertiesKey: compressionProperties,
    ]
  }

  /// The track transform for an unrotated sensor frame, in the same exact
  /// quarter-turn form the Camera app writes.
  private static func trackTransform(
    rotationAngle: CGFloat,
    dimensions: CMVideoDimensions
  ) -> CGAffineTransform {
    let width = CGFloat(dimensions.width)
    let height = CGFloat(dimensions.height)
    switch Int(rotationAngle.rounded()) % 360 {
    case 90:
      return CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: height, ty: 0)
    case 180:
      return CGAffineTransform(a: -1, b: 0, c: 0, d: -1, tx: width, ty: height)
    case 270:
      return CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: width)
    default:
      return .identity
    }
  }

  /// A camera format that records one of the Apple Log color spaces.
  private struct LogFormat {
    let format: AVCaptureDevice.Format
    let profile: VideoRecordingProfile
    let colorSpace: AVCaptureColorSpace
  }

  #if os(iOS)
    /// Picks the largest format up to UHD that records at the camera frame
    /// rate in Apple Log 2, falling back to Apple Log.
    private static func preferredLogFormat(
      of device: AVCaptureDevice
    ) -> LogFormat? {
      for profile in [VideoRecordingProfile.appleLog2, .appleLog] {
        guard let colorSpace = profile.captureColorSpace else { continue }

        let candidates = device.formats.filter { format in
          format.supportedColorSpaces.contains(colorSpace)
            && format.formatDescription.dimensions.width <= maximumRecordingWidth
            && format.videoSupportedFrameRateRanges.contains {
              $0.minFrameRate <= recordingFrameRate
                && recordingFrameRate <= $0.maxFrameRate
            }
        }
        // Among equally large formats, a binned one trades detail for low light.
        let preferred = candidates.max { lhs, rhs in
          let lhsArea = lhs.formatDescription.dimensions.area
          let rhsArea = rhs.formatDescription.dimensions.area
          if lhsArea != rhsArea {
            return lhsArea < rhsArea
          }
          return lhs.isVideoBinned && rhs.isVideoBinned == false
        }
        if let preferred {
          return LogFormat(format: preferred, profile: profile, colorSpace: colorSpace)
        }
      }
      return nil
    }
  #endif
}

/// The writer state of one recording, owned by ``CameraRecorder``.
private nonisolated struct MovieRecording {
  let file: CapturedFile
  let writer: AVAssetWriter
  let videoInput: AVAssetWriterInput
  let audioInput: AVAssetWriterInput?
  /// The first video frame's time, where the movie's timeline starts.
  var startTime: CMTime?
  var lastVideoTime: CMTime?
}

/// Forwards camera samples to the recorder that owns the delegate queue.
@CaptureActor
private final class SampleBufferRelay: NSObject,
  @preconcurrency AVCaptureVideoDataOutputSampleBufferDelegate,
  @preconcurrency AVCaptureAudioDataOutputSampleBufferDelegate
{
  private weak var recorder: CameraRecorder?

  init(recorder: CameraRecorder) {
    self.recorder = recorder
  }

  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    // The outputs deliver on the recorder's executor queue.
    recorder?.append(sampleBuffer, from: output)
  }
}

extension CMVideoDimensions {

  fileprivate nonisolated var area: Int64 {
    Int64(width) * Int64(height)
  }
}

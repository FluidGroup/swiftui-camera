import AVFoundation

/// Feeds the session's video frames to the previews, on a queue of its own so rendering never
/// waits behind session work.
final class PreviewFrameOutput: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, Sendable {
  let queue = DispatchQueue(label: "Viewfinder.PreviewFrames", qos: .userInteractive)
  private let frames: PreviewFrames

  init(frames: PreviewFrames) {
    self.frames = frames
  }

  /// Each frame names its own camera, read from the connection that delivered it, so frames still
  /// arriving from the previous camera during a switch keep that camera's mirroring.
  func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
    guard
      let pixelBuffer = sampleBuffer.imageBuffer,
      let device = (connection.inputPorts.first?.input as? AVCaptureDeviceInput)?.device
    else { return }
    frames.deliver(PreviewFrame(pixelBuffer: pixelBuffer, deviceID: device.uniqueID, isMirrored: device.position == .front))
  }
}

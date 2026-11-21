import AVFoundation
import SwiftUI
import Testing

@testable import Camera

@MainActor
struct VideoCameraTests {
  @Test func handoffDeliversOneSilentMovieAndRestoresThePhotoCamera() async throws {
    let hardware = CameraHardware()
    let video = VideoCameraProxy()
    var movies: [Video] = []
    let videoRun = Task {
      await video.run(
        source: .simulated(.init()), simulationHardware: hardware, microphoneEnabled: false)
    }
    defer { videoRun.cancel() }
    try await wait { video.status == .available(.running) }
    // Installing a delivery closure after the session starts enables capture.
    video.startRecording()
    #expect(video.recordingState == .idle)
    video.update(
      .init(
        minimumDuration: 0.5, deliver: { _ in Issue.record("Stale delivery") },
        failure: { Issue.record("Recording failed: \($0)") }))
    video.startRecording()
    video.stopRecording()
    try await wait { video.recordingState == .idle }
    #expect(movies.isEmpty)
    video.startRecording()
    try await Task.sleep(for: .seconds(1.2))

    // A render during the hold changes the recipient. This clip keeps the
    // duration policy from touch-down.
    video.update(
      .init(
        minimumDuration: 60, deliver: { movies.append($0) },
        failure: { Issue.record("Recording failed: \($0)") }))
    let photo = CameraModel(
      configuration: .init(
        photo: .heif, lensSelection: .wide, mirroring: .matchesPreview, cameraControl: []),
      source: .simulated(.init()), settings: .constant(.init()), handlers: SessionHandlers(),
      simulationHardware: hardware)
    let photoRun = Task { await photo.run() }
    defer { photoRun.cancel() }
    try await wait { photo.status == .available(.interrupted(.inUseByAnotherCamera)) }
    #expect(video.status == .available(.running))
    // Closing the screen and releasing the shutter converge on the same finish.
    video.stopRecording()
    videoRun.cancel()
    await videoRun.value
    try await wait { photo.status == .available(.running) }
    #expect(movies.count == 1)
    let clip = try #require(movies.first)
    #expect(clip.profile == .standard)
    let asset = AVURLAsset(url: clip.file.url)
    #expect(try await asset.loadTracks(withMediaType: .audio).isEmpty)
    #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    #expect(try await asset.load(.duration).seconds >= 0.5)
  }

  private func wait(_ condition: () -> Bool) async throws {
    let timeout = ContinuousClock.now + .seconds(8)
    while !condition() {
      guard ContinuousClock.now < timeout else { throw Timeout() }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private struct Timeout: Error {}
}

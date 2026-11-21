import AVFoundation
import SwiftUI
import Testing

@testable import Camera

@MainActor
struct VideoCameraTests {
  @Test func dismissalDuringTouchDownReleasesTheCamera() async throws {
    let hardware = CameraHardware()
    let video = VideoCameraProxy()
    video.update(.init(deliver: { _ in }))
    let run = Task {
      await video.run(
        source: .simulated(.init()), simulationHardware: hardware, microphoneEnabled: false)
    }
    defer { run.cancel() }
    try await wait { video.status == .available(.running) }

    // Dismiss synchronously when the press changes state, before begin returns.
    withObservationTracking {
      _ = video.recordingState
    } onChange: {
      run.cancel()
    }
    video.startRecording()
    await run.value

    let next = VideoCameraProxy()
    let nextRun = Task {
      await next.run(
        source: .simulated(.init()), simulationHardware: hardware, microphoneEnabled: false)
    }
    defer { nextRun.cancel() }
    try await wait { next.status == .available(.running) }
  }

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

  @Test func consecutiveTouchesDeliverSeparatePlayableMovies() async throws {
    let hardware = CameraHardware()
    let video = VideoCameraProxy()
    var movies: [Video] = []
    video.update(.init(
      deliver: { movies.append($0) },
      failure: { Issue.record("Recording failed: \($0)") }
    ))
    let run = Task {
      await video.run(
        source: .simulated(.init()), simulationHardware: hardware, microphoneEnabled: false)
    }
    defer { run.cancel() }
    try await wait { video.status == .available(.running) }

    for _ in 0..<2 {
      video.begin(.touch)
      try await Task.sleep(for: .milliseconds(500))
      video.end(.touch)
      video.end(.touch)
      try await wait { video.recordingState == .idle }
    }

    #expect(movies.count == 2)
    #expect(Set(movies.map(\.file.url)).count == 2)
    for movie in movies {
      let asset = AVURLAsset(url: movie.file.url)
      #expect(try await asset.load(.duration).seconds > 0)
      #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
    }
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

#if canImport(AppKit)
import AppKit
import Observation
import SwiftUI
import Testing

@testable import Viewfinder

@MainActor
struct CameraViewTests {
  @MainActor
  private final class Screen {
    var statuses: [CameraStatus] = []
    var camera: CameraProxy?
    var photos: [Photo] = []
    var renderedGeneration = 0
    var customizedGenerations: [Int] = []
    var photoGenerations: [Int] = []
    var failureGenerations: [Int] = []
  }

  @MainActor
  @Observable
  fileprivate final class Driver {
    var generation = 0
    var jpeg = true
  }

  /// Every closure it hands the camera captures the generation it was made in.
  private struct GenerationHost: View {
    let driver: Driver
    let screen: Screen
    let processingDelay: Duration

    var body: some View {
      let generation = driver.generation
      var photo: PhotoOptions = driver.jpeg ? .jpeg(quality: 0.8) : .heif
      photo.customizeSettings = { _ in screen.customizedGenerations.append(generation) }
      return Camera(photo: photo) { camera in
        let _ = (screen.camera = camera, screen.renderedGeneration = generation)
        Color.black
      }
      .onPhotoCapture { _ in screen.photoGenerations.append(generation) }
      .onFailure { _ in screen.failureGenerations.append(generation) }
      .cameraSource(.simulated(CameraSimulation(processingDelay: processingDelay)))
    }
  }

  @MainActor
  @Observable
  fileprivate final class Store {
    var a = CameraSettings()
    var b = CameraSettings(position: .front)
    var usesB = false
  }

  private struct StoreHost: View {
    @Bindable var store: Store
    let screen: Screen

    var body: some View {
      Camera(settings: store.usesB ? $store.b : $store.a) { camera in
        let _ = (screen.camera = camera)
        Color.black
      }
      .cameraSource(.simulated(CameraSimulation()))
    }
  }

  private func show(_ view: some View) -> NSWindow {
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 240, height: 240), styleMask: [.borderless], backing: .buffered, defer: false)
    // ARC owns the window; `close()` must not release it a second time.
    window.isReleasedWhenClosed = false
    window.contentView = NSHostingView(rootView: view)
    window.orderFrontRegardless()
    return window
  }

  private func waitUntil(_ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + .seconds(5)
    while !condition(), ContinuousClock.now < deadline {
      try await Task.sleep(for: .milliseconds(20))
    }
  }

  @Test func contentThatStartsEmptyStillRunsTheCamera() async throws {
    let screen = Screen()
    let window = show(
      VStack {
        Camera { camera in
          let _ = screen.statuses.append(camera.status)
          if case .available(.running) = camera.status {
            Text("Running")
          }
        }
      }
      .cameraSource(.simulated(CameraSimulation()))
    )
    defer { window.close() }

    try await waitUntil { screen.statuses.last == .available(.running) }
    #expect(screen.statuses.last == .available(.running))
  }

  @Test func aPhotoFromAHostedCameraReachesOnPhotoCapture() async throws {
    let screen = Screen()
    let window = show(
      Camera(photo: .jpeg(quality: 0.8)) { camera in
        let _ = (screen.camera = camera)
        Color.black
      }
      .onPhotoCapture { photo in screen.photos.append(photo) }
      .cameraSource(.simulated(CameraSimulation(processingDelay: .milliseconds(30))))
    )
    defer { window.close() }

    try await waitUntil { screen.camera?.shutter.isEnabled == true }
    screen.camera?.activateShutter()
    try await waitUntil { !screen.photos.isEmpty }
    #expect(screen.photos.count == 1)
  }

  @Test func aDifferentSettingsBindingTakesOverTheCamera() async throws {
    let (store, screen) = (Store(), Screen())
    let window = show(StoreHost(store: store, screen: screen))
    defer { window.close() }
    try await waitUntil { store.a.lens != nil }

    store.usesB = true
    try await waitUntil { store.b.lens != nil }
    #expect(store.b.lens?.position == .front)
    screen.camera?.exposure.iso.value = ISO(400)
    #expect(store.b.exposure == .isoPriority(ISO(400)))
    #expect(store.a.exposure == .automatic)
  }

  @Test func aNewCustomizeSettingsReachesTheRunningCamera() async throws {
    let (driver, screen) = (Driver(), Screen())
    let window = show(GenerationHost(driver: driver, screen: screen, processingDelay: .milliseconds(30)))
    defer { window.close() }
    try await waitUntil { screen.camera?.shutter.isEnabled == true }
    let model = screen.camera?.model

    driver.generation = 1
    try await waitUntil { screen.renderedGeneration == 1 }
    screen.camera?.activateShutter()
    #expect(screen.camera?.model === model)
    #expect(screen.customizedGenerations == [1])
    try await waitUntil { !screen.photoGenerations.isEmpty }
  }

  @Test func aReplacedModelSendsWhatItHasInFlightToTheLatestClosures() async throws {
    let (driver, screen) = (Driver(), Screen())
    let window = show(GenerationHost(driver: driver, screen: screen, processingDelay: .milliseconds(800)))
    defer { window.close() }
    try await waitUntil { screen.camera?.shutter.isEnabled == true }
    let replaced = try #require(screen.camera?.model)
    replaced.activateShutter()

    driver.jpeg = false
    try await waitUntil { screen.camera?.model !== replaced }
    driver.generation = 1
    try await waitUntil { screen.renderedGeneration == 1 }
    replaced.apply(.failure(CameraFailure(kind: .photoCapture, message: "The photo could not be captured.")))
    try await waitUntil { !screen.photoGenerations.isEmpty }
    #expect(screen.photoGenerations == [1])
    #expect(screen.failureGenerations == [1])
  }
}
#endif

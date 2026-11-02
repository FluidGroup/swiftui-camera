#if canImport(AppKit)
import AppKit
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
}
#endif

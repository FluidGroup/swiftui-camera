import CoreGraphics
import Foundation
import ImageIO
import SwiftUI
import Testing

@testable import Viewfinder

@MainActor
struct SimulatedCameraTests {
  @MainActor
  private final class Screen {
    var settings: CameraSettings
    var photos: [Photo] = []
    var failures: [CameraFailure] = []

    init(settings: CameraSettings) {
      self.settings = settings
    }

    var binding: Binding<CameraSettings> {
      Binding(get: { self.settings }, set: { self.settings = $0 })
    }
  }

  private func makeCamera(
    photo: PhotoOptions = .heif,
    lenses: LensSelection = .wide,
    settings: CameraSettings = CameraSettings(),
    simulation: CameraSimulation = CameraSimulation(processingDelay: .milliseconds(30))
  ) -> (Screen, CameraModel, CameraProxy) {
    let screen = Screen(settings: settings)
    let model = CameraModel(
      configuration: EngineConfiguration(photo: photo, lensSelection: lenses, mirroring: .matchesPreview, hardwareControls: []),
      source: .simulated(simulation),
      settings: screen.binding
    )
    model.deliver = { photo in screen.photos.append(photo) }
    model.failureAction = { failure in screen.failures.append(failure) }
    return (screen, model, CameraProxy(model: model, settings: screen.binding))
  }

  private func waitUntil(_ what: String, timeout: Duration = .seconds(5), _ condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
      guard ContinuousClock.now < deadline else {
        throw TimeoutError(what: what)
      }
      try await Task.sleep(for: .milliseconds(10))
    }
  }

  private struct TimeoutError: Error, CustomStringConvertible {
    let what: String
    var description: String { "timed out waiting for \(what)" }
  }

  private func isRunning(_ camera: CameraProxy) -> Bool {
    if case .available(.running) = camera.status { true } else { false }
  }

  @Test func runsDiscoversAndReflectsIntents() async throws {
    let (screen, model, camera) = makeCamera(photo: .appleProRAW(fallback: .heif), lenses: .physical(includingCrops: true))
    guard case .available(.stopped) = camera.status else {
      Issue.record("a fresh camera is stopped, not \(camera.status)")
      return
    }
    #expect(camera.lenses.isEmpty)
    #expect(!camera.shutter.isEnabled)

    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }
    try await waitUntil("readiness") { camera.shutter.isEnabled }

    #expect(camera.availablePositions == [.back, .front])
    #expect(camera.lenses.map(\.label) == ["0.5×", "1×", "2×", "5×"])
    #expect(screen.settings.lens?.label == "1×")
    #expect(camera.canFlip)
    #expect(camera.photoFormat == .heif)
    #expect(camera.photoResolutions == [PhotoResolution(width: 4032, height: 3024), PhotoResolution(width: 8064, height: 6048)])
    #expect(camera.exposure.program == .automatic)
    #expect(camera.exposure.iso.isAdjustable)
    #expect(camera.zoom.value == ZoomFactor(1))

    camera.exposure.iso.value = ISO(400)
    #expect(camera.exposure.program == .isoPriority(ISO(400)))
    #expect(screen.settings.exposure == .isoPriority(ISO(400)))
    try await waitUntil("the ISO reading") { camera.exposure.iso.reading == ISO(400) && !camera.exposure.iso.isAdjusting }

    camera.exposure.shutterSpeed.value = ShutterSpeed(1 / 250)
    #expect(camera.exposure.program == .manual(ShutterSpeed(1 / 250), ISO(400)))
    #expect(camera.exposure.bias.availability == .metering)

    camera.whiteBalance.temperature.value = Kelvin(4000)
    #expect(!camera.whiteBalance.isAutomatic)
    try await waitUntil("the temperature reading") { camera.whiteBalance.temperature.reading == Kelvin(4000) }

    camera.zoom.value = ZoomFactor(3)
    try await waitUntil("the zoom reading") { camera.zoom.reading == ZoomFactor(3) }

    camera.settings.focus(at: DevicePoint(x: 0.2, y: 0.8))
    #expect(screen.settings.focusPoint == DevicePoint(x: 0.2, y: 0.8))
    #expect(camera.focus.isAutomatic)
    camera.focus.value = LensPosition(0.25)
    #expect(screen.settings.focusPoint == nil)
    #expect(!camera.focus.isAutomatic)
    try await waitUntil("the lens position reading") { camera.focus.reading == LensPosition(0.25) }

    camera.settings.lens = camera.lenses[3]
    #expect(screen.settings.lens?.label == "5×")
    #expect(camera.zoom.value == ZoomFactor(5))
    try await waitUntil("the telephoto facts") { camera.photoResolutions == [PhotoResolution(width: 4032, height: 3024)] }

    camera.settings.position.flip()
    #expect(screen.settings.position == .front)
    #expect(screen.settings.lens?.position == .front)
    #expect(camera.lenses.map(\.label) == ["1×"])
    try await waitUntil("the front facts") { camera.photoResolutions.count == 1 && camera.photoFormat == .heif }
  }

  @Test func aPressDeliversAPhotoWhoseFileLivesWithTheToken() async throws {
    let (screen, model, camera) = makeCamera(photo: .jpeg(quality: 0.8))
    let run = Task { await model.run() }
    try await waitUntil("readiness") { camera.shutter.isEnabled }
    #expect(screen.settings.photoResolution == .full)
    camera.settings.photoResolution = .standard

    camera.activateShutter()
    #expect(!camera.shutter.isEnabled)
    #expect(camera.shutter.photosInFlight == 1)
    try await waitUntil("a delivered photo") { !screen.photos.isEmpty }

    let url: URL = try {
      let photo = screen.photos.removeFirst()
      #expect(photo.format == .jpeg)
      #expect(photo.pixelSize == CGSize(width: 3024, height: 4032))
      #expect(photo.preview?.width == 384)
      #expect(photo.preview?.height == 512)
      let source = try #require(CGImageSourceCreateWithURL(photo.file.url as CFURL, nil))
      let properties = try #require(CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any])
      #expect(properties[kCGImagePropertyPixelWidth] as? Int == 4032)
      #expect(properties[kCGImagePropertyPixelHeight] as? Int == 3024)
      #expect(properties[kCGImagePropertyOrientation] as? UInt32 == CGImagePropertyOrientation.right.rawValue)
      #expect(try photo.data().count > 0)
      return photo.file.url
    }()
    try await waitUntil("the token's file to be deleted") { !FileManager.default.fileExists(atPath: url.path) }

    try await waitUntil("the shutter to settle") { camera.shutter.isIdle && camera.shutter.isEnabled }
    #expect(camera.shutter.captureCount == 1)

    run.cancel()
    try await waitUntil("stopped") {
      if case .available(.stopped) = camera.status { true } else { false }
    }
    #expect(!camera.shutter.isEnabled)
  }

  @Test func aPressRightAfterTheAppChangesTheLensTakesThePhotoOnTheNewLens() async throws {
    let (screen, model, camera) = makeCamera(photo: .jpeg(quality: 0.8), lenses: .physical(includingCrops: true))
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("readiness") { camera.shutter.isEnabled }
    #expect(camera.photoResolution(for: .full) == PhotoResolution(width: 8064, height: 6048))

    screen.settings.lens = camera.lenses[3]
    camera.activateShutter()
    try await waitUntil("a delivered photo") { !screen.photos.isEmpty }
    #expect(screen.photos.first?.pixelSize == CGSize(width: 3024, height: 4032))
  }

  @Test func aFailedLensSwitchRevertsToTheConnectedLensUnlessTheChoiceMovedOn() async throws {
    let (screen, model, camera) = makeCamera(lenses: .physical(includingCrops: true), simulation: CameraSimulation())
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }
    let (main, telephoto, ultraWide) = (camera.lenses[1], camera.lenses[3], camera.lenses[0])

    camera.settings.lens = telephoto
    model.adopt(.lensSwitchFailed(requested: telephoto.id, connected: main.id))
    #expect(screen.settings.lens == main)

    camera.settings.lens = telephoto
    camera.settings.lens = ultraWide
    model.adopt(.lensSwitchFailed(requested: telephoto.id, connected: main.id))
    #expect(screen.settings.lens == ultraWide)
  }

  @Test func cameraControlWritesBackWithoutDroppingAnUnsentChangeFromTheApp() async throws {
    let (screen, model, camera) = makeCamera()
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }

    screen.settings.whiteBalance = .locked(temperature: Kelvin(4000), tint: Tint(0))
    model.adopt(.exposure(.isoPriority(ISO(800))))
    model.adopt(.bias(ExposureBias(1)))
    model.adopt(.zoom(ZoomFactor(2)))
    #expect(screen.settings.exposure == .isoPriority(ISO(800)))
    #expect(screen.settings.exposureBias == ExposureBias(1))
    #expect(screen.settings.zoom == ZoomFactor(2))
    try await waitUntil("the app's white balance on the device") { camera.whiteBalance.temperature.reading == Kelvin(4000) }
  }

  @Test func aSceneChangeEndsTheTapsFocus() async throws {
    let (screen, model, camera) = makeCamera()
    camera.settings.focus(at: .center)
    #expect(screen.settings.focusPoint == .center)

    model.apply(.subjectAreaChanged)
    #expect(screen.settings.focusPoint == nil)
    #expect(camera.focus.isAutomatic)
  }

  @Test func aRequestOutsideTheLensRangeStaysAsAsked() async throws {
    let (screen, model, camera) = makeCamera()
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }

    camera.settings.exposure = .isoPriority(ISO(12800))
    #expect(camera.exposure.iso.value == ISO(6400))
    #expect(screen.settings.exposure == .isoPriority(ISO(12800)))
    try await waitUntil("the clamped ISO reading") { camera.exposure.iso.reading == ISO(6400) }

    camera.exposure.shutterSpeed.value = ShutterSpeed(1 / 250)
    #expect(screen.settings.exposure == .manual(ShutterSpeed(1 / 250), ISO(6400)))
  }

  @Test func restoredSettingsStartOnTheirLens() async throws {
    var restored = CameraSettings()
    restored.lens = CameraLens(id: "simulated.back.telephoto", position: .back, kind: .telephoto, displayZoom: 5)
    let (screen, model, camera) = makeCamera(lenses: .physical(includingCrops: true), settings: restored)
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("readiness") { camera.shutter.isEnabled }

    #expect(camera.photoResolutions == [PhotoResolution(width: 4032, height: 3024)])
    #expect(screen.settings.lens == camera.lenses.first { $0.id == "simulated.back.telephoto" })
  }

  @Test func aPositionWithoutALensStartsOnItsDefaultLens() async throws {
    let (screen, model, camera) = makeCamera(lenses: .physical(includingCrops: true), settings: CameraSettings(position: .front))
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }

    #expect(screen.settings.lens?.position == .front)
    #expect(camera.lenses.map(\.label) == ["1×"])
  }

  @Test func theLensTheCameraPicksKeepsTheZoomAskedFor() async throws {
    var settings = CameraSettings()
    settings.zoom = ZoomFactor(2)
    let (screen, model, camera) = makeCamera(lenses: .physical(includingCrops: true), settings: settings)
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }
    #expect(screen.settings.lens?.label == "1×")
    #expect(screen.settings.zoom == ZoomFactor(2))

    screen.settings.position = .front
    screen.settings.zoom = ZoomFactor(1.5)
    model.sync()
    #expect(screen.settings.lens?.position == .front)
    #expect(screen.settings.zoom == ZoomFactor(1.5))
  }

  @Test func aReplacedModelNoLongerWritesTheSettings() {
    let (screen, model, _) = makeCamera()
    model.detach()
    model.adopt(.zoom(ZoomFactor(2)))
    model.apply(.subjectAreaChanged)
    #expect(screen.settings.zoom == nil)
  }

  @Test func failuresReachTheHandler() {
    let (screen, model, _) = makeCamera()
    let failure = CameraFailure(kind: .lensSwitch, message: "The lens could not be connected.")
    model.apply(.failure(failure))
    #expect(screen.failures == [failure])
  }

  @Test func aPressDoesNotOutliveTheSessionItBeganIn() async throws {
    let (_, model, camera) = makeCamera()
    var run = Task { await model.run() }
    try await waitUntil("readiness") { camera.shutter.isEnabled }
    model.receive(.press(.hardware))
    #expect(camera.shutter.isPressed)

    run.cancel()
    try await waitUntil("stopped") { camera.status == .available(.stopped) }
    #expect(!camera.shutter.isPressed)

    run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("readiness") { camera.shutter.isEnabled }
    camera.activateShutter()
    #expect(camera.shutter.photosInFlight == 1)
  }

  @Test func aPreviewOnlyCameraNeverCaptures() async throws {
    let (_, model, camera) = makeCamera(simulation: CameraSimulation())
    model.allowsCapture = false
    let run = Task { await model.run() }
    defer { run.cancel() }
    try await waitUntil("running") { isRunning(camera) }
    try await Task.sleep(for: .milliseconds(50))
    #expect(!camera.shutter.isEnabled)
    camera.activateShutter()
    #expect(camera.shutter.photosInFlight == 0)
    model.allowsCapture = true
    #expect(camera.shutter.isEnabled)
  }
}

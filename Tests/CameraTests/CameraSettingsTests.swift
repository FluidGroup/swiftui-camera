import Foundation
import Testing

@testable import Camera

struct CameraSettingsTests {
  private let telephoto = CameraLens(id: "tele", position: .back, kind: .telephoto, displayZoom: 5)
  private let frontWide = CameraLens(id: "front", position: .front, kind: .wide, displayZoom: 1)

  @Test func choosingALensSetsItsPositionAndResetsZoom() {
    var settings = CameraSettings()
    settings.zoom = ZoomFactor(2)
    settings.lens = frontWide
    #expect(settings.position == .front)
    #expect(settings.zoom == nil)
  }

  @Test func choosingAnotherPositionLeavesTheLensToTheCamera() {
    var settings = CameraSettings()
    settings.lens = telephoto
    settings.position = .back
    #expect(settings.lens == telephoto)
    settings.position.flip()
    #expect(settings.position == .front)
    #expect(settings.lens == nil)
  }

  @Test func tappingTheSamePointTwiceIsTwoChanges() {
    var settings = CameraSettings()
    settings.focus(at: .center)
    let afterFirstTap = settings
    settings.focus(at: .center)
    #expect(settings != afterFirstTap)
    #expect(settings.focusPoint == .center)
  }

  @Test func lockingFocusEndsATapAndATapUnlocks() {
    var settings = CameraSettings()
    settings.focus(at: .center)
    settings.focus = .locked(LensPosition(0.3))
    #expect(settings.focusPoint == nil)
    settings.focus(at: DevicePoint(x: 0.2, y: 0.8))
    #expect(settings.focus == .automatic)
  }

  @Test func theCameraEndsATapWhenTheSceneChanges() {
    var settings = CameraSettings()
    settings.focus(at: .center)
    settings.endTapFocus()
    #expect(settings.focusPoint == nil)
  }

  @Test func aRestoredValueKeepsTheRequestButNotTheTap() throws {
    var settings = CameraSettings(
      exposure: .shutterPriority(ShutterSpeed(1 / 250)),
      whiteBalance: .locked(temperature: Kelvin(5600), tint: Tint(0)),
      photoResolution: .standard,
      flash: .auto
    )
    settings.lens = telephoto
    settings.zoom = ZoomFactor(7)
    let untapped = settings
    settings.focus(at: .center)

    let restored = try JSONDecoder().decode(CameraSettings.self, from: JSONEncoder().encode(settings))
    #expect(restored == untapped)
    #expect(restored.focusPoint == nil)
  }
}

import Testing

@testable import Viewfinder

struct LensResolutionTests {
  private let ultraWide = CameraLens(id: "uw", position: .back, kind: .ultraWide, displayZoom: 0.5)
  private let wide = CameraLens(id: "w", position: .back, kind: .wide, displayZoom: 1)
  private let crop = CameraLens(id: "w.crop2", deviceID: "w", position: .back, kind: .wide, crop: 2, displayZoom: 2)
  private let telephoto = CameraLens(id: "t", position: .back, kind: .telephoto, displayZoom: 5)
  private let front = CameraLens(id: "f", position: .front, kind: .wide, displayZoom: 1)
  private let builtIn = CameraLens(id: "mac", position: .unspecified, kind: .wide, displayZoom: 1)
  private let continuity = CameraLens(id: "iphone", position: .unspecified, kind: .external, displayZoom: 1)

  private var iPhone: [CameraLens] { [ultraWide, wide, crop, telephoto, front] }
  private var mac: [CameraLens] { [builtIn, continuity] }

  @Test func positionsKeepLensOrderWithoutRepeats() {
    #expect(LensResolution.positions(of: iPhone) == [.back, .front])
    #expect(LensResolution.positions(of: mac) == [.unspecified])
    #expect(LensResolution.positions(of: []) == [])
  }

  @Test func aRequestedPositionTheDeviceHasIsKept() {
    #expect(LensResolution.position(requested: .front, available: [.back, .front]) == .front)
  }

  @Test func aMissingPositionFallsBackToUnspecifiedThenToTheFirst() {
    #expect(LensResolution.position(requested: .back, available: [.unspecified]) == .unspecified)
    #expect(LensResolution.position(requested: .front, available: [.back]) == .back)
  }

  @Test func beforeDiscoveryTheRequestStands() {
    #expect(LensResolution.position(requested: .front, available: []) == .front)
  }

  @Test func thePositionStartsOnItsFullSensorWideCamera() {
    #expect(LensResolution.defaultLens(at: .back, in: iPhone)?.id == "w")
    #expect(LensResolution.defaultLens(at: .front, in: iPhone)?.id == "f")
    #expect(LensResolution.defaultLens(at: .unspecified, in: iPhone) == nil)
  }

  @Test func withoutAWideCameraTheLensNearestOneTimesWins() {
    let lenses = [
      CameraLens(id: "a", position: .back, kind: .telephoto, displayZoom: 3),
      CameraLens(id: "b", position: .back, kind: .ultraWide, displayZoom: 0.5),
      CameraLens(id: "c", position: .back, kind: .telephoto, displayZoom: 1.5),
    ]
    #expect(LensResolution.defaultLens(at: .back, in: lenses)?.id == "c")
  }

  @Test func theSystemDefaultCameraWinsAtItsPosition() {
    #expect(LensResolution.defaultLens(at: .unspecified, in: mac, preferredID: "iphone")?.id == "iphone")
    #expect(LensResolution.defaultLens(at: .unspecified, in: mac, preferredID: "w")?.id == "mac")
  }

  @Test func anIntentSelectsItsLensWhenDiscoveredElseThePositionsDefault() {
    var intent = DeviceIntent(position: .back)
    #expect(LensResolution.lens(for: intent, in: iPhone)?.id == "w")
    intent.lensID = "t"
    #expect(LensResolution.lens(for: intent, in: iPhone)?.id == "t")
    intent.lensID = "gone"
    #expect(LensResolution.lens(for: intent, in: iPhone)?.id == "w")
    #expect(LensResolution.lens(for: intent, in: []) == nil)
  }

  @Test func aLensFromAnotherPositionGivesWayToThatPositionsDefault() {
    var intent = DeviceIntent(position: .front)
    intent.lensID = "t"
    #expect(LensResolution.lens(for: intent, in: iPhone)?.id == "f")
  }

  @Test func aLensAtThePositionTheDeviceFallsBackToIsKept() {
    var intent = DeviceIntent(position: .unspecified)
    intent.lensID = "uw"
    #expect(LensResolution.lens(for: intent, in: iPhone)?.id == "uw")
  }

  @Test func anIPhoneIntentOnAMacLandsOnTheMacCamera() {
    let intent = DeviceIntent(position: .back)
    #expect(LensResolution.lens(for: intent, in: mac, preferredID: "mac")?.id == "mac")
  }
}

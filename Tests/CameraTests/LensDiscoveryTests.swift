import Testing

@testable import Camera

struct LensDiscoveryTests {
  private func camera(
    _ id: String,
    _ kind: CameraLens.Kind,
    position: CameraPosition = .back,
    switchOver: Double = 1,
    multiplier: Double = 1,
    megapixels: Double = 12
  ) -> PhysicalCameraFacts {
    PhysicalCameraFacts(
      id: id,
      position: position,
      kind: kind,
      switchOverZoom: switchOver,
      displayMultiplier: multiplier,
      largestPhotoMegapixels: megapixels
    )
  }

  private func summary(_ lenses: [CameraLens]) -> [String] {
    lenses.map { "\($0.id)@\($0.label)" }
  }

  private var iPhone16Pro: [PhysicalCameraFacts] {
    [
      camera("uw", .ultraWide, switchOver: 1, multiplier: 0.5, megapixels: 48),
      camera("w", .wide, switchOver: 2, multiplier: 0.5, megapixels: 48),
      camera("t", .telephoto, switchOver: 10, multiplier: 0.5, megapixels: 12),
    ]
  }

  private var iPhone14Pro: [PhysicalCameraFacts] {
    [
      camera("uw", .ultraWide, switchOver: 1, multiplier: 0.5),
      camera("w", .wide, switchOver: 2, multiplier: 0.5, megapixels: 48),
      camera("t", .telephoto, switchOver: 6, multiplier: 0.5),
    ]
  }

  private var iPhone15: [PhysicalCameraFacts] {
    [
      camera("uw", .ultraWide, switchOver: 1, multiplier: 0.5),
      camera("w", .wide, switchOver: 2, multiplier: 0.5, megapixels: 48),
    ]
  }

  private var iPhone13Mini: [PhysicalCameraFacts] {
    [
      camera("uw", .ultraWide, switchOver: 1, multiplier: 0.5),
      camera("w", .wide, switchOver: 2, multiplier: 0.5),
    ]
  }

  @Test func iPhone16ProOffersFourLensesWithATwoTimesCrop() {
    let lenses = LensDiscovery.lenses(from: iPhone16Pro, selection: .physical())
    #expect(summary(lenses) == ["uw@0.5×", "w@1×", "w.crop2@2×", "t@5×"])
  }

  @Test func iPhone14ProPutsTheCropBetweenTheMainAndTheThreeTimesTelephoto() {
    let lenses = LensDiscovery.lenses(from: iPhone14Pro, selection: .physical())
    #expect(summary(lenses) == ["uw@0.5×", "w@1×", "w.crop2@2×", "t@3×"])
  }

  @Test func iPhone15CropsItsFortyEightMegapixelMain() {
    let lenses = LensDiscovery.lenses(from: iPhone15, selection: .physical())
    #expect(summary(lenses) == ["uw@0.5×", "w@1×", "w.crop2@2×"])
  }

  @Test func iPhone13MiniHasNoCropForATwelveMegapixelMain() {
    let lenses = LensDiscovery.lenses(from: iPhone13Mini, selection: .physical())
    #expect(summary(lenses) == ["uw@0.5×", "w@1×"])
  }

  @Test func iPhoneSEHasOneLensAtOneTimes() {
    let lenses = LensDiscovery.lenses(from: [camera("w", .wide)], selection: .physical())
    #expect(summary(lenses) == ["w@1×"])
  }

  @Test func aFrontCameraSitsAtOneTimes() {
    let lenses = LensDiscovery.lenses(from: [camera("f", .wide, position: .front)], selection: .physical())
    #expect(lenses.map(\.position) == [.front])
    #expect(summary(lenses) == ["f@1×"])
  }

  @Test func aMacExternalCameraIsAnUnspecifiedExternalLens() {
    let lenses = LensDiscovery.lenses(from: [camera("usb", .external, position: .unspecified)], selection: .physical())
    #expect(lenses.map(\.kind) == [.external])
    #expect(lenses.map(\.position) == [.unspecified])
    #expect(summary(lenses) == ["usb@1×"])
  }

  @Test func aCropKeepsItsCameraAndMarksTheCropFactor() throws {
    let lenses = LensDiscovery.lenses(from: iPhone16Pro, selection: .physical())
    let crop = try #require(lenses.first { $0.crop == 2 })
    #expect(crop.id == "w.crop2")
    #expect(crop.deviceID == "w")
    #expect(crop.kind == .wide)
    #expect(crop.position == .back)
    #expect(crop.displayZoom == 2)
    #expect(lenses.filter { $0.crop == 1 }.allSatisfy { $0.id == $0.deviceID })
  }

  @Test func physicalWithoutCropsOmitsTheCrop() {
    let lenses = LensDiscovery.lenses(from: iPhone16Pro, selection: .physical(includingCrops: false))
    #expect(summary(lenses) == ["uw@0.5×", "w@1×", "t@5×"])
  }

  @Test func wideSelectionKeepsOnlyTheMainCameraPerPosition() {
    let facts = iPhone16Pro + [camera("f", .wide, position: .front), camera("usb", .external, position: .unspecified)]
    let lenses = LensDiscovery.lenses(from: facts, selection: .wide)
    #expect(summary(lenses) == ["w@1×", "f@1×", "usb@1×"])
  }

  @Test func wideSelectionFallsBackToTheLowestZoomWhenAPositionHasNoWideCamera() {
    let facts = [
      camera("t", .telephoto, switchOver: 4, multiplier: 1),
      camera("uw", .ultraWide, switchOver: 1, multiplier: 0.5),
    ]
    let lenses = LensDiscovery.lenses(from: facts, selection: .wide)
    #expect(summary(lenses) == ["uw@0.5×"])
  }

  @Test func wideSelectionNeverAddsACrop() {
    let lenses = LensDiscovery.lenses(from: iPhone16Pro, selection: .wide)
    #expect(summary(lenses) == ["w@1×"])
  }

  @Test func noCropWhenAPhysicalCameraAlreadySitsNearTwoTimes() {
    let facts = [
      camera("w", .wide, switchOver: 1, multiplier: 1, megapixels: 48),
      camera("t", .telephoto, switchOver: 2.04, multiplier: 1),
    ]
    #expect(summary(LensDiscovery.lenses(from: facts, selection: .physical())) == ["w@1×", "t@2×"])
  }

  @Test func aCameraJustOutsideTheToleranceStillGetsACrop() {
    let facts = [
      camera("w", .wide, megapixels: 48),
      camera("t", .telephoto, switchOver: 2.1),
    ]
    #expect(summary(LensDiscovery.lenses(from: facts, selection: .physical())) == ["w@1×", "w.crop2@2×", "t@2.1×"])
  }

  @Test func theCropThresholdIsFortyMegapixels() {
    #expect(summary(LensDiscovery.lenses(from: [camera("w", .wide, megapixels: 40)], selection: .physical())) == ["w@1×", "w.crop2@2×"])
    #expect(summary(LensDiscovery.lenses(from: [camera("w", .wide, megapixels: 39.9)], selection: .physical())) == ["w@1×"])
  }

  @Test func lensesAreSortedByPositionThenZoom() {
    let facts =
      [camera("f", .wide, position: .front), camera("usb", .external, position: .unspecified)]
      + iPhone16Pro.reversed()
    let lenses = LensDiscovery.lenses(from: facts, selection: .physical())
    #expect(lenses.map(\.id) == ["uw", "w", "w.crop2", "t", "f", "usb"])
  }

  @Test func eachPositionGetsItsOwnCrop() {
    let facts = [
      camera("w", .wide, megapixels: 48),
      camera("f", .wide, position: .front, megapixels: 48),
    ]
    let lenses = LensDiscovery.lenses(from: facts, selection: .physical())
    #expect(summary(lenses) == ["w@1×", "w.crop2@2×", "f@1×", "f.crop2@2×"])
  }

  @Test func noCamerasYieldNoLenses() {
    #expect(LensDiscovery.lenses(from: [], selection: .physical()).isEmpty)
    #expect(LensDiscovery.lenses(from: [], selection: .wide).isEmpty)
  }
}

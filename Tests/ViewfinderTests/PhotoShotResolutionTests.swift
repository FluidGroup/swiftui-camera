import Testing

@testable import Viewfinder

struct PhotoShotResolutionTests {
  private let twelve = PhotoResolution(width: 4032, height: 3024)
  private let fortyEight = PhotoResolution(width: 8064, height: 6048)

  private func shot(flash: FlashMode = .auto, resolution: ResolutionPreference = .full, dimensions: PhotoResolution?) -> PhotoShot {
    PhotoShot(format: .heif, flash: flash, resolution: resolution, dimensions: dimensions, isMirrored: false, exposure: .automatic)
  }

  @Test func trackingDuringAPendingLensSwitchAsksForNothingACameraCouldReject() {
    let pressed = shot(flash: .on, dimensions: fortyEight)
    let tracked = pressed.forTracking(lensSwitchPending: true)
    #expect(tracked.flash == .off)
    #expect(tracked.dimensions == nil)
    #expect(tracked.resolution == .full)
    #expect(pressed.forTracking(lensSwitchPending: false) == pressed)
  }

  @Test func thePreferenceIsResolvedAgainOnTheConnectedLens() {
    let fromTheMainCamera = shot(resolution: .full, dimensions: fortyEight)
    #expect(fromTheMainCamera.resolved(flashModes: [.off], offered: [twelve], ceiling: twelve).dimensions == twelve)

    let fromTheTelephoto = shot(resolution: .full, dimensions: twelve)
    #expect(fromTheTelephoto.resolved(flashModes: [.off], offered: [twelve, fortyEight], ceiling: fortyEight).dimensions == fortyEight)

    let standard = shot(resolution: .standard, dimensions: twelve)
    #expect(standard.resolved(flashModes: [.off], offered: [twelve, fortyEight], ceiling: fortyEight).dimensions == twelve)
  }

  @Test func theOutputCeilingCapsTheSize() {
    let full = shot(resolution: .full, dimensions: fortyEight)
    #expect(full.resolved(flashModes: [.off], offered: [twelve, fortyEight], ceiling: twelve).dimensions == twelve)
    #expect(full.resolved(flashModes: [.off], offered: [twelve, fortyEight], ceiling: nil).dimensions == fortyEight)
    #expect(full.resolved(flashModes: [.off], offered: [], ceiling: nil).dimensions == nil)
  }

  @Test func aFlashTheConnectedCameraLacksTurnsOff() {
    let withFlash = shot(flash: .auto, dimensions: twelve)
    #expect(withFlash.resolved(flashModes: [.off], offered: [twelve], ceiling: nil).flash == .off)
    #expect(withFlash.resolved(flashModes: [.off, .on, .auto], offered: [twelve], ceiling: nil).flash == .auto)
  }

  @Test func aCropOffersOnlyTheStandardSize() {
    #expect(PhotoResolutionSelection.offered([twelve, fortyEight], crop: 2) == [twelve])
    #expect(PhotoResolutionSelection.offered([twelve, fortyEight], crop: 1) == [twelve, fortyEight])
    #expect(PhotoResolutionSelection.offered([], crop: 2) == [])
  }
}

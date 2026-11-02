import Testing

@testable import Viewfinder

struct PhotoFormatTests {
  @Test func eachPreferenceResolvesToTheSizeTheShutterUses() {
    let resolutions = [
      PhotoResolution(width: 4032, height: 3024),
      PhotoResolution(width: 8064, height: 6048),
    ]
    #expect(ResolutionPreference.standard.resolve(in: resolutions) == PhotoResolution(width: 4032, height: 3024))
    #expect(ResolutionPreference.full.resolve(in: resolutions) == PhotoResolution(width: 8064, height: 6048))
  }

  @Test func aLensWithOneSizeResolvesBothPreferencesToIt() {
    let resolutions = [PhotoResolution(width: 4032, height: 3024)]
    #expect(ResolutionPreference.standard.resolve(in: resolutions) == ResolutionPreference.full.resolve(in: resolutions))
  }

  @Test func noResolutionBeforeConfiguration() {
    #expect(ResolutionPreference.full.resolve(in: []) == nil)
  }

  @Test func formatLabels() {
    #expect([PhotoFormat.jpeg, .heif, .appleProRAW].map(\.label) == ["JPEG", "HEIF", "ProRAW"])
  }

  @Test func aProRAWCameraWithoutProRAWDeliversItsProcessedFallback() {
    #expect(PhotoOptions.appleProRAW().deliveredFormat(supportsProRAW: true, supportsHEVC: true) == .appleProRAW)
    #expect(PhotoOptions.appleProRAW(fallback: .heif).deliveredFormat(supportsProRAW: false, supportsHEVC: true) == .heif)
    #expect(PhotoOptions.appleProRAW(fallback: .heif).deliveredFormat(supportsProRAW: false, supportsHEVC: false) == .jpeg)
    #expect(PhotoOptions.appleProRAW(fallback: .jpeg).deliveredFormat(supportsProRAW: false, supportsHEVC: true) == .jpeg)
  }
}

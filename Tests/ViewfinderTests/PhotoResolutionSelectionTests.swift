import Testing

@testable import Viewfinder

struct PhotoResolutionSelectionTests {
  private let twelve = PhotoResolution(width: 4032, height: 3024)
  private let twentyFour = PhotoResolution(width: 5712, height: 4284)
  private let fortyEight = PhotoResolution(width: 8064, height: 6048)
  private let small = PhotoResolution(width: 1920, height: 1440)

  @Test func sizesAreAscendingUniqueAndNeverTheDeferredOnlyOne() {
    let sizes = PhotoResolutionSelection.resolutions(from: [fortyEight, twelve, twentyFour, twelve, small])
    #expect(sizes == [small, twelve, fortyEight])
  }

  @Test func standardIsTheLargestSizeUpToTwelveMegapixels() {
    #expect(ResolutionPreference.standard.resolve(in: [small, twelve, fortyEight]) == twelve)
    #expect(ResolutionPreference.full.resolve(in: [small, twelve, fortyEight]) == fortyEight)
  }

  @Test func aLensWithOnlyLargeSizesOffersItsSmallestAsStandard() {
    let sixteen = PhotoResolution(width: 4608, height: 3456)
    #expect(ResolutionPreference.standard.resolve(in: [sixteen, fortyEight]) == sixteen)
  }

  @Test func aSingleSizeServesBothPreferences() {
    #expect(ResolutionPreference.standard.resolve(in: [twelve]) == twelve)
    #expect(ResolutionPreference.full.resolve(in: [twelve]) == twelve)
    #expect(ResolutionPreference.full.resolve(in: []) == nil)
  }
}

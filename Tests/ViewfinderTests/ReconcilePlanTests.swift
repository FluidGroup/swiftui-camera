import Testing

@testable import Viewfinder

struct ReconcilePlanTests {
  private let base = DeviceIntent(position: .back)

  @Test func theSameIntentTwiceWritesNothing() {
    #expect(base.aspects(toReconcileFrom: base, lensChanged: false, full: false).isEmpty)
  }

  @Test func nothingAppliedYetOrAFullRequestWritesEverything() {
    #expect(base.aspects(toReconcileFrom: nil, lensChanged: false, full: false) == Set(DeviceAspect.allCases))
    #expect(base.aspects(toReconcileFrom: base, lensChanged: false, full: true) == Set(DeviceAspect.allCases))
  }

  @Test func aLensChangeRewritesEveryAspectOnTheNewDevice() {
    #expect(base.aspects(toReconcileFrom: base, lensChanged: true, full: false) == Set(DeviceAspect.allCases))
  }

  @Test func onlyTheChangedAspectsAreWritten() {
    var next = base
    next.exposure = .isoPriority(ISO(400))
    next.whiteBalance = .locked(Kelvin(5500), Tint(0))
    #expect(next.aspects(toReconcileFrom: base, lensChanged: false, full: false) == [.exposure, .whiteBalance])

    var zoomed = base
    zoomed.zoom = ZoomFactor(2)
    zoomed.bias = ExposureBias(0.3)
    #expect(zoomed.aspects(toReconcileFrom: base, lensChanged: false, full: false) == [.zoom, .bias])
  }

  @Test func aSecondTapAtTheSamePointRefocuses() {
    var tapped = base
    tapped.focus = .point(.center)
    tapped.focusTap = 1
    var again = tapped
    again.focusTap = 2
    #expect(tapped.aspects(toReconcileFrom: base, lensChanged: false, full: false) == [.focus])
    #expect(again.aspects(toReconcileFrom: tapped, lensChanged: false, full: false) == [.focus])
  }

  @Test func selectingALensIsNotAnAspectOfItsOwnUntilTheEngineSwaps() {
    var next = base
    next.lensID = "t"
    #expect(next.aspects(toReconcileFrom: base, lensChanged: false, full: false).isEmpty)
  }
}

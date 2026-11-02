import AVFoundation
import Testing

@testable import Viewfinder

@MainActor
struct PhotoSettingsBuilderTests {
  private func shot(format: PhotoFormat = .heif, exposure: ExposureProgram) -> PhotoShot {
    PhotoShot(format: format, flash: .off, resolution: .full, dimensions: nil, isMirrored: false, exposure: exposure)
  }

  @Test func aFixedISOOrShutterSpeedTakesThePhotoAtSpeedPrioritization() {
    let output = PhotoOutputFacts()
    for program in [ExposureProgram.manual(ShutterSpeed(1 / 250), ISO(400)), .shutterPriority(ShutterSpeed(1 / 250)), .isoPriority(ISO(400))] {
      let settings = PhotoSettingsBuilder.settings(for: shot(exposure: program), options: .heif, output: output)
      #expect(settings.photoQualityPrioritization == .speed, "\(program)")
      let raw = PhotoSettingsBuilder.settings(for: shot(format: .appleProRAW, exposure: program), options: .appleProRAW(), output: output)
      #expect(raw.photoQualityPrioritization == .speed, "\(program)")
    }
  }

  @Test func automaticExposureKeepsTheOptionsPrioritization() {
    let output = PhotoOutputFacts()
    #expect(PhotoSettingsBuilder.settings(for: shot(exposure: .automatic), options: .heif, output: output).photoQualityPrioritization == .balanced)
    #expect(PhotoSettingsBuilder.settings(for: shot(exposure: .automatic), options: .jpeg(quality: 0.8), output: output).photoQualityPrioritization == .balanced)
    #expect(
      PhotoSettingsBuilder.settings(for: shot(format: .appleProRAW, exposure: .automatic), options: .appleProRAW(), output: output).photoQualityPrioritization
        == .quality)
  }
}

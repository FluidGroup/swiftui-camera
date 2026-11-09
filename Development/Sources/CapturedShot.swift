import Camera
import SwiftUI

struct CapturedShot: Identifiable {
  let id = UUID()
  let preview: Image?
  let format: PhotoFormat
  let pixelSize: CGSize

  init(_ photo: Photo) {
    preview = photo.preview.map { Image(decorative: $0, scale: 1) }
    format = photo.format
    pixelSize = photo.pixelSize
  }

  var caption: String {
    "\(format.label)\n\(Int(pixelSize.width))×\(Int(pixelSize.height))"
  }
}

struct ShotStrip: View {
  let shots: [CapturedShot]

  var body: some View {
    ScrollView(.horizontal) {
      HStack(spacing: 8) {
        ForEach(shots) { shot in
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6)
              .fill(.gray.opacity(0.3))
              .overlay { shot.preview?.resizable().scaledToFill() }
              .frame(width: 64, height: 64)
              .clipShape(.rect(cornerRadius: 6))
            Text(shot.caption)
              .font(.caption2.monospacedDigit())
              .multilineTextAlignment(.center)
          }
        }
      }
      .padding(.horizontal)
    }
    .scrollBounceBehavior(.basedOnSize)
    .frame(height: 96)
  }
}

extension View {
  func alertsFailure(_ failure: Binding<CameraFailure?>) -> some View {
    alert(
      "Camera Failure",
      isPresented: Binding(
        get: { failure.wrappedValue != nil },
        set: { if $0 == false { failure.wrappedValue = nil } }
      ),
      presenting: failure.wrappedValue
    ) { _ in
      Button("OK") {}
    } message: { failure in
      Text([failure.message, failure.snapshot?.summary, failure.underlyingError.map { "\($0)" }].compactMap(\.self).joined(separator: "\n\n"))
    }
  }
}

extension CameraFailure.Snapshot {
  var summary: String {
    [
      [format?.label, resolution.map { "\($0.width)×\($0.height)" }, lens?.label].compactMap(\.self).joined(separator: " · "),
      [describe(exposure.iso), describe(exposure.shutterSpeed), "bias " + describe(exposure.bias)].joined(separator: " · "),
      ["focus " + describe(focus), describe(whiteBalance.temperature), "tint " + describe(whiteBalance.tint)].joined(separator: " · "),
      ["zoom " + describe(zoom), "\(shutter.photosInFlight) in flight"].joined(separator: " · "),
    ].joined(separator: "\n")
  }

  private func describe<Parameter>(_ control: ManualControl<Parameter>) -> String {
    let words: [String?] = [control.reading.formatted(), control.isAutomatic ? "auto" : nil, control.isAdjusting ? "adjusting" : nil]
    return words.compactMap(\.self).joined(separator: " ")
  }
}

#Preview("Shot strip") {
  ShotStrip(shots: [])
}

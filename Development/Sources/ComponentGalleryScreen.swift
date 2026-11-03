import CoreImage
import SwiftUI
import Viewfinder

/// The VSCO Capture components one by one, on a live camera where they need one, before a screen
/// puts them together.
struct ComponentGalleryScreen: View {
  @State private var settings = CameraSettings()
  @State private var look: CameraLook?
  @State private var mode = SampleMode.photo
  @State private var photoCount = 0

  var body: some View {
    Camera(settings: $settings, photo: .jpeg(quality: 0.9)) { camera in
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          GallerySection(title: "Preview", note: "The camera the components below drive, with the look's Core Image filter.") {
            CameraPreview(contentMode: .fill)
              .imageFilter { [filterName = look?.filterName] image in
                filterName.map { image.applyingFilter($0) } ?? image
              }
              .frame(height: 180)
              .clipShape(.rect(cornerRadius: 8))
              .padding(.horizontal, 16)
          }

          GallerySection(title: "Capture bar buttons", note: "Flash \(settings.flash), \(settings.position) camera.") {
            HStack(spacing: 32) {
              FlashModeButton(mode: $settings.flash)
              if camera.canFlip {
                FlipButton(position: $settings.position)
              }
            }
            .font(.title3)
            .foregroundStyle(.white)
          }

          GallerySection(title: "Look carousel", note: "\(look?.name ?? "No look") under the shutter. Photos taken: \(photoCount).") {
            LookCarousel(looks: CameraLook.samples, selection: $look)
          }

          GallerySection(title: "Mode switcher", note: "The first title follows the look. The modes are labels only; Viewfinder takes photos.") {
            ModeSwitcher(modes: SampleMode.allCases, selection: $mode) { mode in
              mode == .photo ? look?.name ?? mode.title : mode.title
            }
          }

          GallerySection(title: "Vertical slider", note: "Exposure bias and white balance on the live camera. Drag a knob.") {
            HStack(spacing: 64) {
              VerticalSlider(control: camera.$exposure.bias, symbol: "plusminus")
              VerticalSlider(control: camera.$whiteBalance.temperature, symbol: "thermometer.medium")
            }
          }

          GallerySection(title: "Coach mark", note: "A hint with its arrow on any edge.") {
            VStack(spacing: 16) {
              CoachMark(text: "Swipe to try looks", arrowEdge: .bottom)
              CoachMark(text: "Slide to adjust the exposure", arrowEdge: .trailing)
              CoachMark(text: "Tap to flip the camera", arrowEdge: .top)
            }
          }
        }
        .padding()
      }
    }
    .onPhotoCapture { _ in photoCount += 1 }
    .background(.black)
    .preferredColorScheme(.dark)
  }
}

private enum SampleMode: CaseIterable {
  case photo
  case dsco
  case video
  case multi

  var title: String {
    switch self {
    case .photo: "PHOTO"
    case .dsco: "DSCO"
    case .video: "VIDEO"
    case .multi: "MULTI"
    }
  }
}

private struct GallerySection<Content: View>: View {
  let title: String
  let note: String
  @ViewBuilder let content: Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.headline)
      Text(note)
        .font(.caption)
        .foregroundStyle(.secondary)
      content
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(white: 0.08), in: .rect(cornerRadius: 12))
    }
  }
}

#Preview("Component gallery, simulated camera") {
  ComponentGalleryScreen()
    .cameraSource(.simulated(CameraSimulation()))
}

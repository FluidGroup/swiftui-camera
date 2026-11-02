import Foundation
import SwiftUI
import Viewfinder

struct ProCameraScreen: View {
  private static let settingsKey = "ViewfinderDemo.proCameraSettings"

  @State private var settings: CameraSettings
  @State private var shots: [CapturedShot] = []
  @State private var failure: CameraFailure?
  @State private var showsManualControls = false

  init() {
    let saved = UserDefaults.standard.data(forKey: Self.settingsKey)
    _settings = State(initialValue: saved.flatMap { try? JSONDecoder().decode(CameraSettings.self, from: $0) } ?? CameraSettings())
  }

  var body: some View {
    Camera(
      settings: $settings,
      photo: .appleProRAW(fallback: .heif),
      lenses: .physical(includingCrops: true),
      hardwareControls: [.lensPicker, .exposureBias]
    ) { camera in
      ScrollView {
        VStack(spacing: 16) {
          CaptureOptionsBar(camera: camera, resolution: $settings.photoResolution)

          CameraPreview(contentMode: .fit) { preview in
            FocusLayer(preview: preview, settings: $settings)
          }
          .aspectRatio(3 / 4, contentMode: .fit)
          .overlay(alignment: .bottom) {
            ISORuler(iso: camera.$exposure.iso)
              .padding(.bottom, 12)
          }

          if showsManualControls {
            ManualControlsPanel(camera: camera)
          }

          LensPicker(lenses: camera.lenses, selection: $settings.lens)

          HStack {
            LastCaptureThumbnail(image: shots.first?.preview)
            Spacer()
            Shutter { state in
              ProShutter(state: state)
            }
            Spacer()
            Toggle("Manual", systemImage: "slider.horizontal.3", isOn: $showsManualControls)
              .toggleStyle(.button)
              .labelStyle(.iconOnly)
          }

          ShotStrip(shots: shots)
        }
        .padding(.horizontal)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
      }
    }
    .onPhotoCapture { photo in
      shots.insert(CapturedShot(photo), at: 0)
      shots = Array(shots.prefix(12))
    }
    .onFailure { failure = $0 }
    .onChange(of: settings) { _, settings in
      UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: Self.settingsKey)
    }
    .background(.black)
    .preferredColorScheme(.dark)
    .alertsFailure($failure)
  }
}

private struct FocusLayer: View {
  let preview: CameraPreviewProxy
  @Binding var settings: CameraSettings

  var body: some View {
    Color.clear
      .contentShape(.rect)
      .onTapGesture { location in
        if let point = preview.devicePoint(from: location) {
          settings.focus(at: point)
        }
      }
    if let focusPoint = settings.focusPoint {
      FocusSquare()
        .position(preview.viewPoint(from: focusPoint))
        .id(focusPoint)
    }
  }
}

private struct FocusSquare: View {
  var body: some View {
    Rectangle()
      .strokeBorder(.yellow, lineWidth: 1.5)
      .frame(width: 72, height: 72)
  }
}

private struct LensPicker: View {
  let lenses: [CameraLens]
  @Binding var selection: CameraLens?

  var body: some View {
    Picker("Lens", selection: $selection) {
      ForEach(lenses) { lens in
        Text(lens.label).tag(Optional(lens))
      }
    }
    .pickerStyle(.segmented)
  }
}

private struct ISORuler: View {
  @Binding var iso: ManualControl<ISO>

  var body: some View {
    Dial($iso, axis: .horizontal, pointsPerStop: 14) { dial in
      ISORulerLook(dial: dial)
    }
  }
}

private struct ISORulerLook: View {
  let dial: DialState<ISO>

  var body: some View {
    VStack(spacing: 4) {
      Text(dial.isAutomatic ? "AUTO \(dial.control.formatted())" : dial.control.formatted())
        .font(.caption.monospacedDigit().bold())
        .foregroundStyle(dial.isScrubbing ? .yellow : .white)
      Capsule()
        .fill(.white.opacity(0.6))
        .frame(width: 160, height: 2)
        .overlay(alignment: .leading) {
          Capsule().fill(.yellow).frame(width: 2, height: 12).offset(x: 160 * dial.position)
        }
    }
    .padding(8)
    .background(.black.opacity(dial.isScrubbing ? 0.6 : 0.3), in: .capsule)
  }
}

private struct CaptureOptionsBar: View {
  let camera: CameraProxy
  @Binding var resolution: ResolutionPreference

  var body: some View {
    HStack {
      Text(camera.photoFormat?.label ?? "")
        .font(.caption.bold())
        .foregroundStyle(.yellow)
      Spacer()
      let standard = camera.photoResolution(for: .standard)
      let full = camera.photoResolution(for: .full)
      if let standard, let full, standard != full {
        Picker("Resolution", selection: $resolution) {
          Text(standard.label).tag(ResolutionPreference.standard)
          Text(full.label).tag(ResolutionPreference.full)
        }
        .pickerStyle(.segmented)
        .fixedSize()
      } else if let full {
        Text(full.label)
          .font(.caption)
      }
    }
  }
}

private struct ProShutter: View {
  let state: ShutterState

  var body: some View {
    ZStack {
      Circle()
        .strokeBorder(.white, lineWidth: 4)
        .frame(width: 78, height: 78)
      Circle()
        .fill(.white)
        .frame(width: 64, height: 64)
        .opacity(state.isDimmed ? 0.35 : 1)
      if state.showsProgress {
        ProgressView()
          .tint(.black)
      }
    }
    .scaleEffect(state.isPressed ? 0.92 : 1)
    .animation(.snappy, value: state.isPressed)
  }
}

private struct ManualControlsPanel: View {
  let camera: CameraProxy

  var body: some View {
    VStack(spacing: 12) {
      ManualControlRow(title: "ISO", control: camera.$exposure.iso)
      ManualControlRow(title: "Shutter", control: camera.$exposure.shutterSpeed)
      ManualControlRow(title: "EV", control: camera.$exposure.bias)
      ManualControlRow(title: "Temperature", control: camera.$whiteBalance.temperature)
      ManualControlRow(title: "Tint", control: camera.$whiteBalance.tint)
      ManualControlRow(title: "Focus", control: camera.$focus)
    }
    .opacity(camera.hardwareControlsAppearance == .fullscreen ? 0 : 1)
  }
}

private struct ManualControlRow<Parameter: CameraParameter>: View {
  let title: String
  @Binding var control: ManualControl<Parameter>

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack {
        Text(title)
        Spacer()
        Text(control.formatted())
          .monospacedDigit()
        if control.supportsAutomatic {
          Toggle("Auto", isOn: $control.isAutomatic)
            .toggleStyle(.button)
        }
      }
      Slider(value: $control.position)
        .disabled(control.isAdjustable == false)
    }
  }
}

private struct LastCaptureThumbnail: View {
  let image: Image?

  var body: some View {
    RoundedRectangle(cornerRadius: 8)
      .fill(.gray.opacity(0.3))
      .overlay { image?.resizable().scaledToFill() }
      .frame(width: 48, height: 48)
      .clipShape(.rect(cornerRadius: 8))
  }
}

#Preview("Pro shutter states") {
  HStack(spacing: 24) {
    ProShutter(state: ShutterState(phase: .ready))
    ProShutter(state: ShutterState(phase: .busy(.momentarily)))
    ProShutter(state: ShutterState(phase: .busy(.waitingForCapture)))
    ProShutter(state: ShutterState(phase: .busy(.processing), photosInFlight: 2))
  }
  .padding()
  .background(.black)
}

#Preview("Manual ISO row") {
  @Previewable @State var iso = ManualControl(value: ISO(400), range: ISO(32)...ISO(3200))
  ManualControlRow(title: "ISO", control: $iso)
    .padding()
}

#Preview("ISO ruler look, scrubbable with no camera") {
  @Previewable @State var iso = ManualControl(
    value: ISO(400),
    range: ISO(32)...ISO(3200),
    isAutomatic: true
  )
  ISORuler(iso: $iso)
    .padding()
    .background(.black)
}

#Preview("Lens picker with literals") {
  @Previewable @State var lens: CameraLens?
  LensPicker(
    lenses: [
      CameraLens(id: "ultraWide", position: .back, kind: .ultraWide, displayZoom: 0.5),
      CameraLens(id: "wide", position: .back, kind: .wide, displayZoom: 1),
    ],
    selection: $lens
  )
  .padding()
}

#Preview("Controls on a simulated camera") {
  @Previewable @State var settings = CameraSettings()
  Camera(settings: $settings, lenses: .physical()) { camera in
    VStack {
      LensPicker(lenses: camera.lenses, selection: $settings.lens)
      ISORuler(iso: camera.$exposure.iso)
      ManualControlsPanel(camera: camera)
    }
  }
  .cameraSource(.simulated(CameraSimulation()))
}

#Preview("Pro, simulated camera") {
  ProCameraScreen()
    .cameraSource(.simulated(CameraSimulation()))
}

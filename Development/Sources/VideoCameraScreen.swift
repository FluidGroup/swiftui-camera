import AVKit
import Camera
import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

struct VideoCameraScreen: View {

  @State private var wantsMicrophone = false
  @State private var lastClip: Video?
  @State private var showPlayback = false
  @State private var failure: String?

  var body: some View {
    VideoCamera(microphoneEnabled: wantsMicrophone) { camera in
      VStack(spacing: 0) {
        ZStack {
          Color.black
          switch camera.status {
          case .available(.running):
            VideoCameraPreview(camera)
              .safeAreaInset(edge: .bottom) {
                shutter(camera)
              }
          case .available(.starting), .available(.stopped):
            ProgressView("Starting Camera")
          case .available(.interrupted(.inUseByAnotherCamera)):
            ProgressView("Waiting for Camera")
          case .available(.interrupted):
            ContentUnavailableView("Camera Interrupted", systemImage: "video.slash")
          case .accessDenied:
            ContentUnavailableView(
              "Camera Access Is Off", systemImage: "video.slash",
              description: Text("Allow camera access in Settings or choose the simulated source."))
          case .unavailable(.noCamera):
            ContentUnavailableView(
              "No Camera", systemImage: "video.slash",
              description: Text("Choose the simulated source to try recording."))
          case .unavailable(.configurationFailed(let message)):
            ContentUnavailableView("Camera Failed", systemImage: "video.slash", description: Text(message))
          }
        }
        .environment(\.colorScheme, .dark)

        VStack(spacing: 8) {
          HStack {
            Toggle("Microphone", isOn: $wantsMicrophone)
              .toggleStyle(.switch)
              .fixedSize()
              .disabled(camera.status != .available(.running) || camera.recordingState != .idle)
            Spacer()
            Button("Play Last Clip", systemImage: "play.fill") { showPlayback = true }
              .disabled(lastClip == nil || camera.recordingState != .idle)
          }

          if wantsMicrophone, camera.status == .available(.running), !camera.microphoneEnabled {
            Text("Microphone unavailable. Clips will be silent.")
              .font(.footnote)
          }
        }
        .padding()
      }
    }
    .onVideoCapture { lastClip = $0 }
    .onFailure { failure = $0 }
    .navigationDestination(isPresented: $showPlayback) {
      if let lastClip { ClipPlayback(clip: lastClip) }
    }
    .alert(
      "Recording Failed",
      isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } }),
      presenting: failure
    ) { _ in
      Button("OK") {}
    } message: { message in
      Text(message)
    }
  }

  private func shutter(_ camera: VideoCameraProxy) -> some View {
    VStack(spacing: 8) {
      switch camera.recordingState {
      case .idle: Text("Hold to Record")
      case .recording(let start): Text(start, style: .timer).monospacedDigit()
      case .finishing: Text("Finishing…")
      }

      RecordButton(camera) { state in
        ZStack {
          Circle().strokeBorder(.white, lineWidth: 3)
          switch state {
          case .idle: Circle().fill(.red).padding(6)
          case .recording: RoundedRectangle(cornerRadius: 5).fill(.red).padding(17)
          case .finishing: ProgressView().tint(.white)
          }
        }
        .frame(width: 64, height: 64)
      }
    }
    .font(.subheadline)
    .foregroundStyle(.white)
    .padding()
    .frame(maxWidth: .infinity)
    .background(.black)
  }
}

private struct ClipPlayback: View {

  let clip: Video
  @State private var player: AVPlayer?
  @State private var showExporter = false
  @State private var exportFailure: String?

  var body: some View {
    let movie = RecordedMovie(file: clip.file)

    return playerView
      .navigationTitle("Last Clip")
      .toolbar {
        ToolbarItemGroup(placement: .primaryAction) {
          Button("Save Clip", systemImage: "square.and.arrow.down") {
            showExporter = true
          }
          ShareLink(item: movie, preview: SharePreview("Recorded Clip")) {
            Label("Share Clip", systemImage: "square.and.arrow.up")
          }
        }
      }
      .fileExporter(
        isPresented: $showExporter,
        item: movie,
        contentTypes: [.quickTimeMovie],
        defaultFilename: RecordedMovie.filename,
        onCompletion: { result in
          if case .failure(let error) = result {
            exportFailure = error.localizedDescription
          }
        }
      )
      .alert(
        "Couldn’t Save Clip",
        isPresented: Binding(get: { exportFailure != nil }, set: { if !$0 { exportFailure = nil } }),
        presenting: exportFailure
      ) { _ in
        Button("OK") {}
      } message: { message in
        Text(message)
      }
      .onAppear {
        player = AVPlayer(url: clip.file.url)
        player?.play()
      }
      .onDisappear {
        player?.pause()
      }
  }

  private var playerView: some View {
    #if os(macOS)
      MacClipPlayer(player: player)
    #else
      VideoPlayer(player: player)
    #endif
  }
}

#if os(macOS)
private struct MacClipPlayer: NSViewRepresentable {

  let player: AVPlayer?

  func makeNSView(context: Context) -> AVPlayerView {
    let view = AVPlayerView()
    view.showsSharingServiceButton = false
    return view
  }

  func updateNSView(_ view: AVPlayerView, context: Context) {
    if view.player !== player {
      view.player = player
    }
  }

}
#endif

private nonisolated struct RecordedMovie: Transferable {

  static let filename = "CameraDemo Recording.mov"
  let file: CapturedFile

  static var transferRepresentation: some TransferRepresentation {
    FileRepresentation(exportedContentType: .quickTimeMovie) { movie in
      SentTransferredFile(movie.file.url)
    }
    .suggestedFileName(filename)
  }

}

#Preview("Video, simulated camera") {
  VideoCameraScreen()
    .cameraSource(.simulated(.init()))
}

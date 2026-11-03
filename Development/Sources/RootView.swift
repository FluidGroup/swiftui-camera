import SwiftUI
import Viewfinder

private enum Demo: Hashable, CaseIterable {
  case simple
  case pro
  case components

  var title: String {
    switch self {
    case .simple: "Simple"
    case .pro: "Pro"
    case .components: "Components"
    }
  }
}

enum SourceChoice: Hashable, CaseIterable, Identifiable {
  case automatic
  case simulated

  var id: Self { self }

  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .simulated: "Simulated"
    }
  }

  var cameraSource: CameraSource {
    switch self {
    case .automatic: .automatic
    case .simulated: .simulated(CameraSimulation())
    }
  }
}

struct RootView: View {
  @State private var sourceChoice = SourceChoice.automatic

  var body: some View {
    NavigationStack {
      List(Demo.allCases, id: \.self) { demo in
        NavigationLink(demo.title, value: demo)
      }
      .navigationTitle("Viewfinder")
      .toolbar { SourcePicker(choice: $sourceChoice) }
      .navigationDestination(for: Demo.self) { demo in
        DemoScreen(demo: demo, sourceChoice: $sourceChoice)
      }
    }
  }
}

private struct DemoScreen: View {
  let demo: Demo
  @Binding var sourceChoice: SourceChoice

  var body: some View {
    screen
      .cameraSource(sourceChoice.cameraSource)
      .navigationTitle(demo.title)
      .toolbar { SourcePicker(choice: $sourceChoice) }
  }

  @ViewBuilder
  private var screen: some View {
    switch demo {
    case .simple: SimpleCameraScreen()
    case .pro: ProCameraScreen()
    case .components: ComponentGalleryScreen()
    }
  }
}

private struct SourcePicker: ToolbarContent {
  @Binding var choice: SourceChoice

  var body: some ToolbarContent {
    ToolbarItem(placement: .primaryAction) {
      Picker("Camera Source", selection: $choice) {
        ForEach(SourceChoice.allCases) { choice in
          Text(choice.title).tag(choice)
        }
      }
      .pickerStyle(.menu)
    }
  }
}

#Preview {
  RootView()
}

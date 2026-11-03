# swiftui-camera

Viewfinder runs the camera behind a SwiftUI photo screen and leaves every pixel to you. You draw
the preview frame, the shutter, and the dials. Viewfinder makes them behave like a camera's: the
shutter follows the photo output's readiness, a dial snaps to third stops, and a tap focuses on
the part of the sensor under the finger.

The library is the `Viewfinder` product. In the Simulator and in Xcode previews, the same code
runs a simulated camera that shows a moving test pattern and delivers photos rendered from it.

This capture screen shows the live preview and draws its own shutter:

```swift
import SwiftUI
import Viewfinder

struct CaptureScreen: View {
  let onCapture: (Data) -> Void

  var body: some View {
    Camera(photo: .jpeg(quality: 0.9)) { camera in
      ZStack(alignment: .bottom) {
        CameraPreview(contentMode: .fill)
        Shutter { state in
          Circle()
            .fill(.white)
            .frame(width: 72, height: 72)
            .opacity(state.isDimmed ? 0.4 : 1)
            .scaleEffect(state.isPressed ? 0.92 : 1)
        }
        .padding(.bottom, 32)
      }
    }
    .onPhotoCapture { photo in
      guard let data = try? photo.data() else { return }
      onCapture(data)
    }
  }
}
```

## Requirements

- iOS 26.1 or later, or macOS 26 or later
- Swift 6.2 or later

## Installation

Add the package and its `Viewfinder` product. Your package's platforms must be at least the ones
Viewfinder supports:

```swift
platforms: [
  .iOS("26.1"),
  .macOS(.v26),
],
dependencies: [
  .package(url: "https://github.com/FluidGroup/swiftui-camera", branch: "main")
],
targets: [
  .target(
    name: "YourApp",
    dependencies: [
      .product(name: "Viewfinder", package: "swiftui-camera")
    ]
  )
]
```

An app that uses the camera needs `NSCameraUsageDescription` in its Info.plist. A sandboxed macOS
app also needs the camera entitlement, `com.apple.security.device.camera`.

## Take a photo

A screen puts its camera parts inside a `Camera` view and receives photos in `onPhotoCapture`, as
the example at the top of this page shows.

`Camera` runs the camera while it is on screen. It asks for camera access, configures the
session, and stops the session when the view goes away. `CameraPreview` and `Shutter` work with
the camera of the `Camera` they're inside. Each photo arrives in the `onPhotoCapture` closure on
the main actor, even when the screen closed before the photo finished processing.

The content closure receives a `CameraProxy`, named `camera` in the example. It reads the camera's state
and binds manual controls. It is valid only inside its `Camera`, the way `GeometryProxy` is valid
only inside its `GeometryReader`. `Camera` lays its content out in a `ZStack`, and the camera runs
even while the content shows nothing, for example before the status reads
`.available(.running)`.

On iOS, the volume buttons, Camera Control, and AirPods stem presses take photos through the same
shutter as the screen. The first source to press owns the press until it ends, so a volume press
can't take a photo while a finger holds the on-screen shutter.

Leave out `onPhotoCapture` for a screen that only shows the preview, such as an onboarding step.
The shutter is then `.unavailable`, and the volume buttons keep changing the volume.

## Choose the photo format

Pass `PhotoOptions` to `Camera`:

- `.heif` is the default.
- `.jpeg(quality:)` writes the orientation as an EXIF tag instead of redrawing the pixels.
- `.appleProRAW(fallback:)` captures a DNG with a full-size embedded preview, or the fallback
  format on a device without Apple ProRAW. Read `camera.photoFormat` for the format the device
  delivers.

For a per-photo setting the presets don't cover, such as `metadata` with the location on iOS,
set `customizeSettings`. It receives each press's `AVCapturePhotoSettings` on the main actor after
Viewfinder fills in the format. Viewfinder resolves the flash and the size again against the
connected lens at capture, so changes to those two don't survive. Depth, Live Photos, and constant
color need the photo output configured for them, which Viewfinder doesn't do, so enabling them
there raises an Objective-C exception and crashes the app.

A change to the photo options, the lens selection, mirroring, or the Camera Control items
restarts the session, and the preview blanks briefly. A change to `customizeSettings` alone
doesn't, because the camera reads it at each press.

Set `settings.photoResolution` to `.standard` (about 12 MP) or `.full`. Viewfinder resolves the
preference against the lens connected when the press reaches the photo output, so a lens tapped
just before the shutter decides the size. To label a picker's choices, call
`camera.photoResolution(for:)`, which returns the size each preference takes on the connected
lens. On a lens with one size, both preferences return the same size.

## Own the settings

What a person changes while shooting lives in `CameraSettings`: the lens, exposure, white
balance, focus, zoom, resolution, and flash. `Camera` keeps its own settings until you pass a
binding:

```swift
@State private var settings = CameraSettings()

var body: some View {
  Camera(settings: $settings) { camera in
    // ...
  }
}
```

With a binding, the app changes the camera from its own code and compares or saves the value.
`CameraSettings` is `Codable`, so keeping the settings across launches takes one `onChange`:

```swift
.onChange(of: settings) { _, settings in
  UserDefaults.standard.set(try? JSONEncoder().encode(settings), forKey: "cameraSettings")
}
```

The camera writes back what changes on its side: the lens it picks for a position, a Camera
Control adjustment, a lens switch that fails, and the end of a tap's focus. A lens the camera
picks keeps the `zoom` you asked for. It never writes live readings or clamped values. A request the connected lens can't reach, such as ISO 6400 on a lens
that stops at 3200, stays in `settings`, and `camera.exposure` shows the value in effect. A lens
that can reach it applies it again.

A change the app makes reaches the device at the next view update. A press sends the latest
settings before it captures, so a lens chosen in the same moment as the shutter decides the
photo. `flash` starts at `.off` for every format.

## Keep or move the file

A `Photo` is a file on disk plus its `format`, its `pixelSize`, and a small upright `preview`
image. The file lives as long as `photo.file`, a `CapturedFile`. When the last reference to it goes
away, Viewfinder deletes the file, so a dropped photo can't leak a 75 MB DNG.

To keep a photo, move the file before you release it. This example moves it into Photos:

```swift
func save(_ photo: Photo) async throws {
  let url = photo.file.url
  try await PHPhotoLibrary.shared().performChanges {
    let options = PHAssetResourceCreationOptions()
    options.shouldMoveFile = true
    PHAssetCreationRequest.forAsset().addResource(with: .photo, fileURL: url, options: options)
  }
  withExtendedLifetime(photo.file) {}
}
```

The `withExtendedLifetime` call keeps the file until the move finishes.

## Draw the shutter

`Shutter` tracks the press, takes the photo, makes itself a button for VoiceOver ("Take Photo"),
and plays a light impact at each exposure. Your look receives a `ShutterState`:

- `isDimmed` follows Apple's readiness guidance. It is true while the camera waits for a capture
  or processes one, and false between rapid presses so the shutter doesn't flicker.
- `showsProgress` is true while the camera processes a photo.
- `isPressed` is true while any source holds the press, so the on-screen shutter also animates
  for a volume press.
- `captureCount` increases at each exposure. Use it as an animation trigger.
- `isIdle` is true when nothing is pressed and no photo is in flight, so the screen can close.

To stop capture, pass `isEnabled: false` to `onPhotoCapture`, not `.disabled` to `Shutter`. The
hardware buttons follow `isEnabled` too.

To take a photo from code, such as a self-timer, call `camera.activateShutter()`. Code outside
the view tree, such as an App Intent, can't reach the camera. It changes app state, and the screen
turns that change into the call.

## Show status and failures

Switch on `camera.status` to choose what the screen shows:

```swift
Camera { camera in
  switch camera.status {
  case .available:
    CameraPreview(contentMode: .fill)
  case .accessDenied:
    ContentUnavailableView("Camera Access Is Off", systemImage: "camera")
  case .unavailable:
    ContentUnavailableView("No Camera", systemImage: "camera")
  }
}
```

A failure that doesn't stop the camera, such as a failed capture, arrives in `onFailure`. Keep it
in state to show an alert:

```swift
.onFailure { failure in self.failure = failure }
```

To ask for camera access before the capture screen, for example during onboarding, call
`CameraAuthorization.request()`.

## Switch lenses

`camera.lenses` lists the lenses at the current position in zoom order, each labeled the way the
Camera app labels it ("0.5×", "1×", "2×"). Set `settings.lens` to switch, for example from a
picker:

```swift
Picker("Lens", selection: $settings.lens) {
  ForEach(camera.lenses) { lens in
    Text(lens.label).tag(Optional(lens))
  }
}
```

Without a binding of your own, use the proxy's: `camera.$settings.lens`. Choose which lenses exist
with the `lenses` argument of `Camera`:

- `.wide` offers the wide camera at each position.
- `.physical(includingCrops:)` offers every physical camera, plus a 2× crop of the main camera
  when it has 40 MP or more and no camera sits at 2×. Each lens is a physical camera, so Apple
  ProRAW captures at the lens's full resolution.

To switch between the front and back cameras, check `camera.canFlip` and call
`camera.settings.position.flip()`. The camera picks that position's default lens and writes it to
`settings.lens`.

## Add manual controls

`camera.exposure`, `camera.whiteBalance`, `camera.focus`, and `camera.zoom` are the settings as the
device sees them. `camera.focus` and `camera.zoom` are `ManualControl` values. `camera.exposure`
groups ISO, shutter speed, and bias, and `camera.whiteBalance` groups temperature and tint, each
a `ManualControl`. A `ManualControl` has the `value` to show, an
`isAutomatic` toggle, the device's `range`, and its live `reading`. Writing `value` takes the
parameter out of automatic, the way dragging a slider does in a pro camera app.

Bind a stock control through the proxy's `$` to `position`, which maps the range onto a perceptual
scale from 0 to 1. ISO and shutter speed are logarithmic, so equal slider steps are equal stops.

```swift
Slider(value: camera.$exposure.iso.position)
Toggle("Auto ISO", isOn: camera.$exposure.iso.isAutomatic)
```

A write through a control stores the values the control showed. Moving ISO on a lens that clamps
the shutter speed therefore stores the clamped shutter speed too.

The two exposure toggles together choose the exposure program. To set one from code, write it to
the settings:

```swift
settings.exposure = .shutterPriority(ShutterSpeed(1 / 250))
```

While both ISO and shutter speed are manual, `camera.exposure.bias` turns into a read-only light
meter. Its `availability` is then `.metering`, and `isAdjustable` is false.

On a Mac, the manual controls report `.unsupported`, because AVFoundation offers custom exposure,
white balance, and lens position only on iOS.

For a ruler or a wheel, use `Dial`. It walks the parameter's stops as the finger drags, plays a
selection haptic at each stop, and works as an adjustable element in VoiceOver:

```swift
Dial(camera.$exposure.iso, pointsPerStop: 14) { dial in
  Text(dial.value.formatted())
    .foregroundStyle(dial.isScrubbing ? .yellow : .white)
}
```

## Focus where the person taps

`CameraPreview` lays out its overlay in the preview's coordinates and passes it a
`CameraPreviewProxy`, which converts between view points and device points:

```swift
CameraPreview(contentMode: .fit) { preview in
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
  }
}
```

`focus(at:)` is a method because a tap is an event: tapping the same point twice focuses twice.
`devicePoint(from:)` returns `nil` for a tap on a letterbox bar. On iOS, when the scene changes
after a tap, the camera returns to continuous autofocus and sets `focusPoint` back to `nil`, so
the focus square disappears at the same moment. A Mac camera reports no scene changes, so there
the focus point stays until the app focuses again. Saved settings don't keep a tap.

## Build controls in other views

Pass a subview the values and bindings it needs, or the proxy itself:

```swift
struct LensPicker: View {
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
```

Inside the content, write `LensPicker(lenses: camera.lenses, selection: $settings.lens)`. A view
that takes plain values needs no camera in a preview. `CameraPreview` and `Shutter` placed
outside every `Camera` render as an unavailable camera and log a fault in debug builds.

## Use Camera Control

To put controls on Camera Control (iPhone 16 and later), list them in `Camera`'s initializer, in
the order they appear:

```swift
Camera(photo: .appleProRAW(fallback: .heif), hardwareControls: [.lensPicker, .exposureBias]) { camera in
  // ...
}
```

Each one stays in sync with the on-screen control of the same name, and a change made on Camera
Control is written back to the settings. When Camera Control shows its full-screen overlay,
`camera.hardwareControlsAppearance` is `.fullscreen`. Hide the sliders the overlay duplicates.

## Preview looks without a camera

Looks take plain values, so `#Preview` builds your looks from literals:

```swift
#Preview {
  @Previewable @State var iso = ManualControl(value: ISO(400), range: ISO(32)...ISO(3200))
  VStack {
    ShutterLook(state: ShutterState(phase: .busy(.processing), photosInFlight: 2))
    Dial($iso) { dial in RulerLook(dial: dial) }
  }
}
```

`Dial($control)` drives a binding and needs no camera. For a whole screen, put
`.cameraSource(.simulated(CameraSimulation()))` above it, or rely on `.automatic`, which picks the
simulated camera in the Simulator and in previews.

## Try the demo app

`Development` holds a demo app that [Tuist](https://tuist.dev) generates. It has a simple capture
screen and a pro screen with manual controls, lens switching, and settings that persist across
launches. In the Simulator it runs on the simulated camera, and a toolbar menu switches the source.

`mise.toml` pins the Tuist version. Install it with [mise](https://mise.jdx.dev), then generate
the workspace from `Development`:

```bash
mise install
cd Development
tuist generate
```

To run the demo on an iPhone, pass your team when you generate:

```bash
TUIST_DEVELOPMENT_TEAM=<your team ID> tuist generate
```

## Change Viewfinder

Before you change the package, read [How Viewfinder works](ARCHITECTURE.md). Run the tests from
the repository root:

```bash
swift test
```

## License

Apache License 2.0. See [LICENSE](LICENSE).

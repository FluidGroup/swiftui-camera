# How Viewfinder works

This page is for the engineer who changes Viewfinder. It explains how the parts fit and why they
are shaped this way. For how to use the package in an app, read the [README](README.md).

## Three layers

Viewfinder splits a camera screen into three layers, and each one knows only the layer below it.

- The device layer is `CameraSettings`, the intent as a value the app may own, and the internal
  `CameraModel`, an observable store on the main actor for everything the device reports. Apps
  see the model only through `CameraProxy`, which reads its state (`status`, `lenses`, `shutter`)
  and binds manual controls, so stock SwiftUI controls bind to it.
- The session layer is the `Camera` view. It runs one `CameraModel` per session,
  hands its content a `CameraProxy`, puts the model in the environment for the parts, routes the
  hardware shutter buttons, and delivers photos and failures.
- The control layer is `CameraPreview`, `Shutter`, and `Dial`. They own behavior and draw nothing.
  `CameraPreview` and `Shutter` find the model in the environment and render as an unavailable
  camera without one, so a misplaced part logs a fault in debug builds instead of crashing. `Dial`
  drives a binding, usually one from the proxy.

The model is a class, not a struct, because it has identity: one capture session, one set of
devices, and photos in flight that outlive any single view update. A change to the session
configuration or the source replaces the model, which restarts the session. The content keeps its
identity, so its own state survives the restart. The replaced model still finishes its photos in
flight. Every model of a session reads the app's closures from one `SessionHandlers`, so those
photos reach the latest `onPhotoCapture` closure.

## Every write is an intent

Intent lives in `CameraSettings`, in storage that the app or the `Camera` view owns. `CameraModel`
never stores it. It reads the binding `Camera` hands over at each update. A getter composes the
settings with the facts and readings the engine publishes, so a write shows at once, before the
device has applied it.

`sync()` derives a `DeviceIntent` from the settings and sends it to the lane when it differs from
what the lane last carried. A write through `CameraProxy` syncs at once. The app's own writes sync
at the next view update, from `onChange(of: settings)`. A press syncs before it sends its capture,
so the lane's order is still the order of what the person did.

The camera writes into the settings only for what changes on its side: the lens it resolves for a
position (with the position a device without the requested one uses), a failed lens switch, the
end of a tap's focus, and Camera Control adjustments. A lens the camera resolves keeps `zoom`,
because the device chose that lens, not a person. The model and both engines resolve the lens with
`LensResolution.lens(for:)`, so the lens the proxy shows before the write-back is the lens the
engine connects. The camera never clamps a value on its own. A request
outside the connected lens's range stays in the settings, and the getters clamp what they show. A
write through a proxy control stores the values the control showed, which are already clamped,
because the person set them against what they saw.

`CommandLane` carries the intent to the session queue. It is one FIFO `AsyncStream` whose `send`
runs synchronously on the main actor, so the lane's order is the order of the calls. A lens
tapped just before the shutter is honored, and a focus tap lands before the next capture. The
latest intent sits beside the stream in a `Mutex`. A `.reconcile` command reads it when the engine
processes the command, which is how a 120 Hz slider drag becomes as many device writes as the
device can take, and no more.

The engine reconciles by diff. It keeps the intent it applied last, and
`DeviceIntent.aspects(toReconcileFrom:lensChanged:full:)` names the parameters that changed. The
same intent twice writes nothing. After a start, an interruption, or a media-services reset, the
engine re-applies everything, because another app may have used the camera meanwhile.

Camera Control reaches the settings in three ways. The ISO, shutter speed, white balance, and focus
sliders write the device on the session queue and report the value as an `IntentAdoption`. The
system zoom and exposure-bias sliders write the device themselves and call the model directly. For
both, the model writes the value into the settings and records it as sent, so the lane doesn't
write it to the device again. When the app has a write the lane hasn't carried yet, the model
sends both in one reconcile instead. The engine has already applied the adopted value, so its diff
writes only the app's change. The lens picker writes nothing to the device. Its choice goes into
the settings, and the lane carries it like any other change.

## The press

`ShutterMachine` is a pure reducer over presses from the touch shutter, the hardware buttons, and
`activateShutter()`. The first source to press owns the press until it ends, and readiness is
checked when a press begins, so an accepted press always captures.

When a press ends inside the shutter, the model syncs the settings, then builds the photo
settings on the main actor and registers them with the readiness coordinator before any hop. Readiness then flips synchronously,
and a second touch already queued on the main actor sees a busy shutter. The settings travel to
the session queue in a `PhotoRequest`. There the engine copies them, resolves the flash mode and
the dimensions against the device that is connected at that moment, and captures. A per-request
delegate writes the file and delivers the `Photo` through `onPhotoCapture`'s closure in an
unstructured main-actor task, so a save finishes even after the screen closed.

`ShutterState` is computed when it is read, from the press owner, the readiness, the photos in
flight, the capture count, and the status. No stored copy can disagree with its sources.

## Engine to camera

The engine tells the model what happened on one ordered `AsyncStream<EngineEvent>` that the
model drains on the main actor, such as status changes, device facts, preview content, failures,
and Camera Control adoptions. Some updates call the model on the main actor directly instead:
photo readiness and photo progress from both backends, and on hardware, live readings and the
system sliders' adoptions. `ReadingsCoalescer` merges the hardware readings (ISO, exposure
duration, white-balance gains, lens position, zoom) so the main actor gets at most one update per
turn instead of one per video frame.

## Concurrency boundaries

`CaptureActor` is a global actor whose executor is the capture session's serial queue. Every
AVFoundation object the library owns lives there: the session, the devices, the outputs, the
capture rotation coordinator, and the Camera Control controls, whose actions must run on the
session's queue. `CameraModel`, the views, the preview's rotation coordinator, and the readiness
coordinator calls run on the main actor.

Three types cross that boundary with `@unchecked Sendable`, and each states its invariant where
it is declared:

- `PhotoRequest` hands one press's settings to the session queue. The main actor never touches
  them after tracking starts, and the engine captures with its own copy.
- `PreviewContent` hands the session and device to the preview layer and its rotation
  coordinator on the main actor, which only read them. This is Apple's AVCam pattern.
- `HardwareReadinessTracker` wraps the readiness coordinator, which is created on the session
  queue and used only on the main actor afterward.

## Two backends

`BackendKind.select(_:)` picks a backend once, from `CameraSource`. The hardware backend is
`CameraEngine` with its reconcile and Camera Control extensions, `DeviceDiscovery`,
`DeviceReadingsMonitor`, and `PhotoCaptureDelegate`. The simulated backend is `SimulatedEngine`,
`SimulatedDevice`, and `TestPattern`. `.automatic` picks the simulated backend in the Simulator
and in Xcode previews. Both backends speak the same lane and event stream, so apart from building
the engine and asking for camera access, `CameraModel` has no branch that asks which one is
running.

## Where the decisions live

Decisions that don't need a device are pure functions with unit tests: `ShutterMachine`,
`ShutterDerivation`, `LensDiscovery`, `LensResolution`, `ZoomMapping`,
`PhotoResolutionSelection`, `ExposureSteering`, the reconcile plan (`DeviceAspect`), the
interruption mapping, the parameter scales, stops, and notation, and the `CameraSettings` rules.
`SimulatedCameraTests` runs the whole camera through `CameraProxy` on the simulated backend, with a
binding standing in for the app's settings.

Behavior that depends on real hardware has no automated test. That covers lens switching and the
rotation carried across it, Apple ProRAW output, readiness under responsive capture, priority
exposure, Camera Control, interruptions, and the preview's point conversion. Check those on an
iPhone with the demo app in `Development` after changing them.

## Why photos only

Video roughly doubled the design: a sample-buffer writer on the session queue, format and color
space selection, audio, and recording states in the shutter. Without it, every capture is one
`Photo` type, so `onPhotoCapture` has one signature and the session actor stays internal. Adding video later
is mostly additive. The exception is `ShutterState.Phase`: new recording cases would break apps
that switch on it exhaustively.

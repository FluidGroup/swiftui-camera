import CoreImage
import CoreVideo
import Synchronization
import Testing

@testable import Camera

struct PreviewFramesTests {
  /// What the sink handed the display, copied out of the buffer as BGRA bytes.
  struct Shown: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    init(_ buffer: CVPixelBuffer) {
      CVPixelBufferLockBaseAddress(buffer, .readOnly)
      defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
      width = CVPixelBufferGetWidth(buffer)
      height = CVPixelBufferGetHeight(buffer)
      let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
      let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
      var pixels: [UInt8] = []
      for y in 0..<height {
        pixels.append(contentsOf: UnsafeBufferPointer(start: base + y * rowBytes, count: width * 4))
      }
      self.pixels = pixels
    }

    /// Blue, green, red.
    func color(x: Int, y: Int) -> (blue: UInt8, green: UInt8, red: UInt8) {
      let index = (y * width + x) * 4
      return (pixels[index], pixels[index + 1], pixels[index + 2])
    }

    var brightest: (x: Int, y: Int) {
      let index = stride(from: 0, to: pixels.count, by: 4).max { pixels[$0 + 1] < pixels[$1 + 1] }! / 4
      return (index % width, index / width)
    }
  }

  private func turning(_ quarterTurns: Int = 0, deviceID: String? = nil) -> PreviewSink.Turning {
    PreviewSink.Turning(deviceID: deviceID, quarterTurns: quarterTurns)
  }

  final class Display: Sendable {
    private let shown = Mutex<[Shown]>([])

    var frames: [Shown] {
      shown.withLock { $0 }
    }

    func show(_ buffer: CVPixelBuffer) {
      let frame = Shown(buffer)
      shown.withLock { $0.append(frame) }
    }
  }

  private func frame(width: Int, height: Int, deviceID: String? = nil, isMirrored: Bool = false, color: (Int, Int) -> (UInt8, UInt8, UInt8)) -> PreviewFrame {
    var pool = PixelBufferPool()
    let buffer = pool.buffer(width: width, height: height)!
    CVPixelBufferLockBaseAddress(buffer, [])
    let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let base = CVPixelBufferGetBaseAddress(buffer)!.assumingMemoryBound(to: UInt8.self)
    for y in 0..<height {
      for x in 0..<width {
        let (red, green, blue) = color(x, y)
        let pixel = base + y * rowBytes + x * 4
        (pixel[0], pixel[1], pixel[2], pixel[3]) = (blue, green, red, 255)
      }
    }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    return PreviewFrame(pixelBuffer: buffer, deviceID: deviceID, isMirrored: isMirrored)
  }

  @Test(arguments: [0, 1, 2, 3], [false, true])
  func aShownFrameStandsWhereTheGeometrySays(quarterTurns: Int, isMirrored: Bool) throws {
    let (width, height) = (8, 6)
    let marked = (x: 1, y: 2)
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.update(turning: turning(quarterTurns), filter: nil)

    sink.render(frame(width: width, height: height, isMirrored: isMirrored) { x, y in
      (x, y) == marked ? (255, 255, 255) : (0, 0, 0)
    })

    let shown = try #require(display.frames.last)
    let orientation = FrameOrientation(quarterTurns: quarterTurns, isMirrored: isMirrored)
    let expected = orientation.uprightPoint(
      from: DevicePoint(x: (Double(marked.x) + 0.5) / Double(width), y: (Double(marked.y) + 0.5) / Double(height)))
    let found = shown.brightest
    #expect(abs((Double(found.x) + 0.5) / Double(shown.width) - expected.x) < 1e-6)
    #expect(abs((Double(found.y) + 0.5) / Double(shown.height) - expected.y) < 1e-6)
    #expect((shown.width, shown.height) == (quarterTurns % 2 == 0 ? (width, height) : (height, width)))
  }

  @Test func theFilterChangesWhatIsShown() throws {
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.update(turning: turning(), filter: { $0.applyingFilter("CIColorInvert") })

    sink.render(frame(width: 4, height: 4) { _, _ in (255, 0, 0) })

    let color = try #require(display.frames.last).color(x: 2, y: 2)
    #expect(color.red < 10 && color.green > 245 && color.blue > 245)
  }

  @Test func aFilterWithoutBoundsIsCroppedToTheFrame() throws {
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.update(turning: turning(), filter: { _ in CIImage(color: CIColor(red: 0, green: 1, blue: 0)) })

    sink.render(frame(width: 6, height: 4) { _, _ in (255, 0, 0) })

    let shown = try #require(display.frames.last)
    #expect((shown.width, shown.height) == (6, 4))
    #expect(shown.color(x: 3, y: 2).green > 245)
  }

  @Test func aNewSizeOrOrientationIsReported() async throws {
    let sink = PreviewSink { _ in }
    sink.update(turning: turning(), filter: nil)
    var layouts = sink.layouts.makeAsyncIterator()

    sink.render(frame(width: 8, height: 6) { _, _ in (0, 0, 0) })
    #expect(await layouts.next() == FrameLayout(size: CGSize(width: 8, height: 6), orientation: .identity))

    sink.update(turning: turning(1), filter: nil)
    sink.render(frame(width: 8, height: 6, isMirrored: true) { _, _ in (0, 0, 0) })
    #expect(await layouts.next() == FrameLayout(size: CGSize(width: 6, height: 8), orientation: FrameOrientation(quarterTurns: 1, isMirrored: true)))
  }

  @Test func aRemovedSinkGetsNoMoreFrames() {
    let frames = PreviewFrames()
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.update(turning: turning(), filter: nil)
    frames.add(sink)
    frames.deliver(frame(width: 2, height: 2) { _, _ in (0, 0, 0) })
    frames.remove(sink)
    frames.deliver(frame(width: 2, height: 2) { _, _ in (0, 0, 0) })
    #expect(display.frames.count == 1)
  }

  @Test func nothingShowsBeforeThePreviewKnowsHowToTurnTheCamera() {
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.render(frame(width: 2, height: 2) { _, _ in (0, 0, 0) })
    #expect(display.frames.isEmpty)
  }

  @Test func anotherCamerasFramesWaitUntilThePreviewTurnsForIt() {
    let display = Display()
    let sink = PreviewSink { display.show($0) }
    sink.update(turning: turning(1, deviceID: "back"), filter: nil)

    sink.render(frame(width: 4, height: 2, deviceID: "front") { _, _ in (0, 0, 0) })
    #expect(display.frames.isEmpty)

    sink.render(frame(width: 4, height: 2, deviceID: "back") { _, _ in (0, 0, 0) })
    #expect(display.frames.count == 1)
  }
}

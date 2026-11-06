import CoreGraphics
import Foundation

/// A file in the library's cache directory that lives exactly as long as this token.
///
/// Move the file (`PHAssetCreationRequest` with `shouldMoveFile`, or your own storage) or drop
/// every reference and the file is deleted. A save task that captures the token keeps the file
/// until it finishes.
public final class CapturedFile: Sendable {
  public let url: URL

  init(url: URL) {
    self.url = url
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

/// A delivered photo. One type for every format.
public struct Photo: Sendable {
  /// JPEG, HEIF, or DNG on disk.
  public let file: CapturedFile
  /// The format the device actually delivered.
  public let format: PhotoFormat
  /// The display size, width and height already swapped for a quarter-turn orientation.
  public let pixelSize: CGSize
  /// A small upright preview (about 512 points on the long side) for thumbnails.
  public let preview: CGImage?

  init(file: CapturedFile, format: PhotoFormat, pixelSize: CGSize, preview: CGImage?) {
    self.file = file
    self.format = format
    self.pixelSize = pixelSize
    self.preview = preview
  }

  /// The encoded bytes. A JPEG carries its orientation as an EXIF tag.
  public func data() throws -> Data {
    try Data(contentsOf: file.url)
  }
}

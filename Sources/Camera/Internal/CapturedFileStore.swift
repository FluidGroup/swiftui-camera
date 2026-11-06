import Foundation

enum CapturedFileStore {
  static let directory = URL.cachesDirectory.appending(path: "swiftui-camera/Captures", directoryHint: .isDirectory)

  private static let firstSweepDate = Date()

  static func makeURL(fileExtension: String) throws -> URL {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory.appending(path: UUID().uuidString).appendingPathExtension(fileExtension)
  }

  static func sweepOrphans() {
    let cutoff = firstSweepDate
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: [.contentModificationDateKey])
    else { return }
    for file in files {
      let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
      if modified < cutoff {
        try? FileManager.default.removeItem(at: file)
      }
    }
  }
}

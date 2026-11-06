// swift-tools-version: 6.2

import PackageDescription

let swiftSettings: [SwiftSetting] = [
  .enableUpcomingFeature("ExistentialAny"),
  .enableUpcomingFeature("MemberImportVisibility"),
  .enableUpcomingFeature("NonisolatedNonsendingByDefault"),
  .enableUpcomingFeature("InferIsolatedConformances"),
]

let package = Package(
  name: "swiftui-camera",
  platforms: [
    .iOS("26.1"),
    .macOS(.v26),
  ],
  products: [
    .library(name: "Camera", targets: ["Camera"])
  ],
  targets: [
    .target(
      name: "Camera",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "CameraTests",
      dependencies: ["Camera"],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)

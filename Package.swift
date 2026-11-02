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
    .library(name: "Viewfinder", targets: ["Viewfinder"])
  ],
  targets: [
    .target(
      name: "Viewfinder",
      swiftSettings: swiftSettings
    ),
    .testTarget(
      name: "ViewfinderTests",
      dependencies: ["Viewfinder"],
      swiftSettings: swiftSettings
    ),
  ],
  swiftLanguageModes: [.v6]
)

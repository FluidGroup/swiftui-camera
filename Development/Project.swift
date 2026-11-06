import ProjectDescription

let project = Project(
  name: "CameraDemo",
  packages: [
    .local(path: "..")
  ],
  settings: .settings(
    base: [
      "SWIFT_VERSION": "6.0",
      "SWIFT_APPROACHABLE_CONCURRENCY": "YES",
      "SWIFT_UPCOMING_FEATURE_MEMBER_IMPORT_VISIBILITY": "YES",
      "SWIFT_UPCOMING_FEATURE_EXISTENTIAL_ANY": "YES",
    ]
  ),
  targets: [
    .target(
      name: "CameraDemo",
      destinations: [.iPhone, .iPad, .mac],
      product: .app,
      bundleId: "app.muukii.CameraDemo",
      deploymentTargets: .multiplatform(
        iOS: "26.1",
        macOS: "26.0"
      ),
      infoPlist: .extendingDefault(with: [
        "CFBundleDisplayName": "Camera Demo",
        "ITSAppUsesNonExemptEncryption": false,
        "LSApplicationCategoryType": "public.app-category.developer-tools",
        "NSCameraUsageDescription": "The demo uses the camera to try the Camera library.",
        "UILaunchScreen": .dictionary([:]),
      ]),
      buildableFolders: ["Sources"],
      dependencies: [
        .package(product: "Camera")
      ],
      settings: .settings(
        base: [
          "DEVELOPMENT_TEAM": .string(Environment.developmentTeam.getString(default: "")),
          "SWIFT_DEFAULT_ACTOR_ISOLATION": "MainActor",
          "ENABLE_APP_SANDBOX": "YES",
          "ENABLE_HARDENED_RUNTIME": "YES",
          "ENABLE_RESOURCE_ACCESS_CAMERA[sdk=macosx*]": "YES",
        ]
      )
    )
  ]
)

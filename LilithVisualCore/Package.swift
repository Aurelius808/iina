// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "LilithVisualCore",
  platforms: [
    .macOS(.v11),
    .iOS(.v15),
  ],
  products: [
    .library(name: "LilithVisualCore", targets: ["LilithVisualCore"]),
    .library(name: "LilithJamSessionsiOSStub", targets: ["LilithJamSessionsiOSStub"]),
  ],
  targets: [
    .target(name: "LilithVisualCore"),
    .target(
      name: "LilithJamSessionsiOSStub",
      dependencies: ["LilithVisualCore"]
    ),
    .testTarget(
      name: "LilithVisualCoreTests",
      dependencies: ["LilithVisualCore"]
    ),
  ]
)

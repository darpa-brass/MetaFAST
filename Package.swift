// swift-tools-version:4.0

import PackageDescription

let package = Package(
  name: "Adapt",
  products: [
    .executable(name: "FlightTest", targets: ["FlightTest"]),
    .library(name: "Adapt", targets: ["Adapt"]),
    .library(name: "FlightTestUtils", targets: ["FlightTestUtils"]),
  ],
  dependencies: [
    .package(url: "https://github.com/Daniel1of1/CSwiftV", .exact("0.0.7")),
    .package(url: "https://github.com/IBM-Swift/HeliumLogger", .exact("1.7.1")),
    .package(url: "https://github.com/nicklockwood/Expression", .exact("0.12.11")),
    .package(url: "git@github.mit.edu:proteus/swift-ast", .exact("0.2.0")),
    .package(url: "git@github.mit.edu:proteus/MulticonstrainedOptimizer", .exact("0.0.15")),
  ],
  targets: [
    .target(name: "Adapt", dependencies: [
      "HeliumLogger", "Expression", "SwiftAST", "CSwiftV", "MulticonstrainedOptimizer"]),
    .target(name: "FlightTestUtils", dependencies: []),
    .target(name: "FlightTest", dependencies: ["Adapt", "FlightTestUtils"]),
    .testTarget(name: "AdaptTests", dependencies: ["Adapt", "FlightTestUtils"])
  ],
  swiftLanguageVersions: [4]
)

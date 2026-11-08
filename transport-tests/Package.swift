// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TransportChecks", platforms: [.macOS(.v13)], products: [], targets: [
    .target(name: "TransportChecks", path: "Sources"),
    .testTarget(name: "TransportChecksTests", dependencies: ["TransportChecks"], path: "Tests")
])

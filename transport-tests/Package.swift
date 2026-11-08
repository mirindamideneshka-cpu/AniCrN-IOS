// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "TransportChecks", platforms: [.macOS(.v13)], products: [], dependencies: [.package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.6.0")], targets: [
    .target(name: "TransportChecks", dependencies: ["SwiftSoup"], path: "Sources"),
    .testTarget(name: "TransportChecksTests", dependencies: ["TransportChecks"], path: "Tests")
])

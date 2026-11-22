// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ZoopTransport", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "ZoopTransport", targets: ["ZoopTransport"])
], targets: [.target(name: "ZoopTransport"),
             .testTarget(name: "ZoopTransportTests", dependencies: ["ZoopTransport"])])

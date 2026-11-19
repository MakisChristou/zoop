// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZoopProtocol",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZoopProtocol", targets: ["ZoopProtocol"]),
    ],
    targets: [
        .target(name: "ZoopProtocol"),
        .testTarget(name: "ZoopProtocolTests", dependencies: ["ZoopProtocol"]),
    ]
)

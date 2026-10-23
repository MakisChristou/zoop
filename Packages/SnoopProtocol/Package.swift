// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnoopProtocol",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SnoopProtocol", targets: ["SnoopProtocol"]),
    ],
    targets: [
        .target(name: "SnoopProtocol"),
        .testTarget(name: "SnoopProtocolTests", dependencies: ["SnoopProtocol"]),
    ]
)

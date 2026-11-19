// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZoopECG",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ZoopECG", targets: ["ZoopECG"])],
    dependencies: [.package(path: "../ZoopProtocol")],
    targets: [
        .target(name: "ZoopECG", dependencies: ["ZoopProtocol"]),
        .testTarget(name: "ZoopECGTests", dependencies: ["ZoopECG", "ZoopProtocol"])
    ]
)

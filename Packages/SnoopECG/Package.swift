// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnoopECG",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SnoopECG", targets: ["SnoopECG"])],
    dependencies: [.package(path: "../SnoopProtocol")],
    targets: [
        .target(name: "SnoopECG", dependencies: ["SnoopProtocol"]),
        .testTarget(name: "SnoopECGTests", dependencies: ["SnoopECG", "SnoopProtocol"])
    ]
)

// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ZoopBattery",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ZoopBattery", targets: ["ZoopBattery"])],
    targets: [
        .target(name: "ZoopBattery"),
        .testTarget(name: "ZoopBatteryTests", dependencies: ["ZoopBattery"]),
    ]
)

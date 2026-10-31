// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "SnoopBattery",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "SnoopBattery", targets: ["SnoopBattery"])],
    targets: [
        .target(name: "SnoopBattery"),
        .testTarget(name: "SnoopBatteryTests", dependencies: ["SnoopBattery"]),
    ]
)

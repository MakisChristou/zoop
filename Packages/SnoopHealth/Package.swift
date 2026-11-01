// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "SnoopHealth", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "SnoopHealth", targets: ["SnoopHealth"])], targets: [.target(name: "SnoopHealth"), .testTarget(name: "SnoopHealthTests", dependencies: ["SnoopHealth"])])

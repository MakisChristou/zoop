// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ZoopHealth", platforms: [.iOS(.v17), .macOS(.v14)], products: [.library(name: "ZoopHealth", targets: ["ZoopHealth"])], targets: [.target(name: "ZoopHealth"), .testTarget(name: "ZoopHealthTests", dependencies: ["ZoopHealth"])])

// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ZoopSync", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "ZoopSync", targets: ["ZoopSync"])
], targets: [.target(name: "ZoopSync", linkerSettings: [.linkedLibrary("sqlite3")]),
             .testTarget(name: "ZoopSyncTests", dependencies: ["ZoopSync"])])

// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ZoopSync", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "ZoopSync", targets: ["ZoopSync"])
], dependencies: [.package(path: "../ZoopTransport")], targets: [.target(name: "ZoopSync", dependencies: ["ZoopTransport"], linkerSettings: [.linkedLibrary("sqlite3")]),
             .testTarget(name: "ZoopSyncTests", dependencies: ["ZoopSync"])])

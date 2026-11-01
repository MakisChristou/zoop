// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "SnoopSync", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "SnoopSync", targets: ["SnoopSync"])
], targets: [.target(name: "SnoopSync", linkerSettings: [.linkedLibrary("sqlite3")]),
             .testTarget(name: "SnoopSyncTests", dependencies: ["SnoopSync"])])

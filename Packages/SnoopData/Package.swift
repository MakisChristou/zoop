// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "SnoopData", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "SnoopData", targets: ["SnoopData"])
], targets: [.target(name: "SnoopData"), .testTarget(name: "SnoopDataTests", dependencies: ["SnoopData"])])

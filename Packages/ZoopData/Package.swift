// swift-tools-version: 5.10
import PackageDescription
let package = Package(name: "ZoopData", platforms: [.iOS(.v17), .macOS(.v14)], products: [
    .library(name: "ZoopData", targets: ["ZoopData"])
], dependencies: [.package(path: "../ZoopTransport")], targets: [.target(name: "ZoopData", dependencies: ["ZoopTransport"]), .testTarget(name: "ZoopDataTests", dependencies: ["ZoopData"])])

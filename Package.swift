// swift-tools-version: 5.9
import PackageDescription
let package = Package(name: "CloudWatchCore", platforms: [.macOS(.v13), .watchOS(.v10)], products: [.library(name: "CloudWatchCore", targets: ["CloudWatchCore"])], targets: [.target(name: "CloudWatchCore", path: "CloudWatch/Core"), .executableTarget(name: "NativeProbe", dependencies: ["CloudWatchCore"], path: "Tools/NativeProbe"), .testTarget(name: "CloudWatchCoreTests", dependencies: ["CloudWatchCore"], path: "Tests/CloudWatchCoreTests")])

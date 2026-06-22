// swift-tools-version:5.9
import PackageDescription

// Pure-Foundation core engine, ported from lib/sleep.ts. Kept platform-agnostic
// so it builds and unit-tests on macOS (`swift test`) and links into the iOS app.
let package = Package(
    name: "SleepEngine",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "SleepEngine", targets: ["SleepEngine"]),
    ],
    targets: [
        .target(name: "SleepEngine"),
        .testTarget(name: "SleepEngineTests", dependencies: ["SleepEngine"]),
    ]
)

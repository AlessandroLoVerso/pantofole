// swift-tools-version: 6.0
import PackageDescription

// Pure logic of the alarm (no UIKit, AlarmKit or Core NFC), so it can be tested on the Mac with `swift test`.
let package = Package(
    name: "SvegliaCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "SvegliaCore", targets: ["SvegliaCore"]),
    ],
    targets: [
        .target(name: "SvegliaCore"),
        .testTarget(name: "SvegliaCoreTests", dependencies: ["SvegliaCore"]),
    ]
)

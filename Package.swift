// swift-tools-version: 6.0
import Foundation
import PackageDescription

var targets: [Target] = [
    .executableTarget(name: "Breathy", path: "Sources/Breathy"),
]
// Testler sadece geliştirici Mac'inde durur (depoda yok); klasör varsa test hedefi eklenir.
if FileManager.default.fileExists(atPath: Context.packageDirectory + "/Tests/BreathyTests") {
    targets.append(.testTarget(name: "BreathyTests", dependencies: ["Breathy"], path: "Tests/BreathyTests"))
}

let package = Package(
    name: "Breathy",
    defaultLocalization: "tr",
    platforms: [.macOS(.v14)],
    targets: targets
)

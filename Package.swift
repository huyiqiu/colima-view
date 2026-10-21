// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "ColimaDesk",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ColimaDesk", targets: ["ColimaDesk"]),
        .executable(name: "colima-desk-check", targets: ["ColimaProbe"])
    ],
    targets: [
        .target(name: "ColimaCore", resources: [.process("Resources")]),
        .executableTarget(name: "ColimaDesk", dependencies: ["ColimaCore"]),
        .executableTarget(name: "ColimaProbe", dependencies: ["ColimaCore"]),
        .testTarget(name: "ColimaCoreTests", dependencies: ["ColimaCore"])
    ]
)

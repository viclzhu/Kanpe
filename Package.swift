// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kanpe",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic (models, key notation, site matching, pack loading). No AppKit.
        .target(name: "KanpeCore"),
        // The menu-bar app: activation, Accessibility reading, panel UI.
        .executableTarget(name: "Kanpe", dependencies: ["KanpeCore"]),
        // `swift run KanpeSelfTest` — assertion-based checks for KanpeCore.
        // (XCTest / swift-testing are unavailable with Command Line Tools only.)
        .executableTarget(name: "KanpeSelfTest", dependencies: ["KanpeCore"]),
    ]
)

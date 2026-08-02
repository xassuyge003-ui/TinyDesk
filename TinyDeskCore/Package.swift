// swift-tools-version: 5.9
// TinyDeskCore —— 不依赖 SwiftUI / AppKit 的核心数据层。
//
// 测试策略: Swift Testing 与 XCTest 在仅 Command Line Tools 的工具链下不可用,
// 故提供一个不依赖测试框架的可执行 target TinyDeskSelfTests 跑纯断言。
// 装好 Xcode 后再补 XCTest / Swift Testing 套件, 断言逻辑保持一致。
import PackageDescription

let package = Package(
    name: "TinyDeskCore",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "TinyDeskCore", targets: ["TinyDeskCore"]),
        .executable(name: "TinyDeskSelfTests", targets: ["TinyDeskSelfTests"]),
    ],
    targets: [
        .target(
            name: "TinyDeskCore",
            path: "Sources/TinyDeskCore"
        ),
        .executableTarget(
            name: "TinyDeskSelfTests",
            dependencies: ["TinyDeskCore"],
            path: "Sources/TinyDeskSelfTests"
        ),
    ]
)

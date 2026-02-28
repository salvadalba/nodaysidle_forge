// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Forge",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "Forge", targets: ["ForgeApp"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", from: "0.9.0"),
    ],
    targets: [
        // Shared types used across all modules
        .target(
            name: "ForgeShared",
            dependencies: []
        ),

        // Core text editing engine: gap buffer, syntax highlighting
        .target(
            name: "ForgeEditorEngine",
            dependencies: [
                "ForgeShared",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
            ]
        ),

        // Metal GPU-accelerated rendering
        .target(
            name: "ForgeRendering",
            dependencies: [
                "ForgeShared",
                "ForgeEditorEngine",
            ],
            resources: [
                .copy("Shaders.metal"),
            ]
        ),

        // Language Server Protocol coordinator
        .target(
            name: "ForgeLSP",
            dependencies: [
                "ForgeShared",
            ]
        ),

        // On-device semantic indexing with CoreML
        .target(
            name: "ForgeIndexer",
            dependencies: [
                "ForgeShared",
                "ForgePersistence",
            ]
        ),

        // SwiftData persistence layer
        .target(
            name: "ForgePersistence",
            dependencies: [
                "ForgeShared",
            ]
        ),

        // Main application entry point
        .executableTarget(
            name: "ForgeApp",
            dependencies: [
                "ForgeShared",
                "ForgeEditorEngine",
                "ForgeRendering",
                "ForgeLSP",
                "ForgeIndexer",
                "ForgePersistence",
            ]
        ),

        // Tests
        .testTarget(
            name: "ForgeEditorEngineTests",
            dependencies: ["ForgeEditorEngine"]
        ),
        .testTarget(
            name: "ForgeLSPTests",
            dependencies: ["ForgeLSP"]
        ),
    ]
)

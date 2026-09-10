// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Clonie",
    platforms: [
        .macOS("26.0")
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .target(
            name: "ClonieCore",
            path: "Sources/ClonieCore"
        ),
        .target(
            name: "ClonieEmbedding",
            path: "Sources/ClonieEmbedding"
        ),
        .target(
            name: "ClonieIndex",
            dependencies: ["ClonieCore", "ClonieEmbedding"],
            path: "Sources/ClonieIndex"
        ),
        .target(
            name: "ClonieCloud",
            path: "Sources/ClonieCloud"
        ),
        .target(
            name: "ClonieDocuments",
            path: "Sources/ClonieDocuments"
        ),
        .executableTarget(
            name: "Clonie",
            dependencies: [
                "ClonieCore",
                "ClonieEmbedding",
                "ClonieIndex",
                "ClonieCloud",
                "ClonieDocuments"
            ],
            path: "Sources/Clonie",
            linkerSettings: [
                .linkedFramework("Carbon")
            ]
        ),
        .target(
            name: "ClonieMCP",
            dependencies: [
                "ClonieCore",
                "ClonieEmbedding",
                "ClonieIndex",
                "ClonieDocuments",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/ClonieMCP"
        ),
        .executableTarget(
            name: "clonie-mcp",
            dependencies: [
                "ClonieMCP",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/clonie-mcp"
        ),
        .testTarget(
            name: "ClonieCoreTests",
            dependencies: ["ClonieCore"],
            path: "tests/ClonieCoreTests"
        ),
        .testTarget(
            name: "ClonieEmbeddingTests",
            dependencies: ["ClonieEmbedding"],
            path: "tests/ClonieEmbeddingTests"
        ),
        .testTarget(
            name: "ClonieIndexTests",
            dependencies: ["ClonieIndex"],
            path: "tests/ClonieIndexTests"
        ),
        .testTarget(
            name: "ClonieCloudTests",
            dependencies: ["ClonieCloud"],
            path: "tests/ClonieCloudTests"
        ),
        .testTarget(
            name: "ClonieDocumentsTests",
            dependencies: ["ClonieDocuments"],
            path: "tests/ClonieDocumentsTests"
        ),
        .testTarget(
            name: "ClonieMCPTests",
            dependencies: [
                "ClonieMCP",
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "tests/ClonieMCPTests"
        )
    ]
)

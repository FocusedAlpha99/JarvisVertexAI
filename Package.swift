// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JarvisVertexAI",
    platforms: [
        .iOS(.v17)
    ],
    products: [
        .library(
            name: "JarvisVertexAI",
            targets: ["JarvisVertexAI"]
        ),
    ],
    dependencies: [
        // ObjectBox for local database
        .package(
            url: "https://github.com/objectbox/objectbox-swift.git",
            from: "4.0.0"
        ),
        
        // Google Cloud SDK for Vertex AI
        .package(
            url: "https://github.com/googleapis/google-cloud-swift.git",
            from: "1.0.0"
        ),
        
        // Alamofire for networking (optional, for better control)
        .package(
            url: "https://github.com/Alamofire/Alamofire.git",
            from: "5.8.0"
        ),
        
        // SwiftProtobuf for Gemini API
        .package(
            url: "https://github.com/apple/swift-protobuf.git",
            from: "1.25.0"
        ),
        
        // CryptoSwift for additional encryption
        .package(
            url: "https://github.com/krzyzanowskim/CryptoSwift.git",
            from: "1.8.0"
        ),
        
        // KeychainAccess for secure storage
        .package(
            url: "https://github.com/kishikawakatsumi/KeychainAccess.git",
            from: "4.2.0"
        )
    ],
    targets: [
        .target(
            name: "JarvisVertexAI",
            dependencies: [
                .product(name: "ObjectBox", package: "objectbox-swift"),
                .product(name: "GoogleCloudVertexAI", package: "google-cloud-swift"),
                .product(name: "Alamofire", package: "Alamofire"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "CryptoSwift", package: "CryptoSwift"),
                .product(name: "KeychainAccess", package: "KeychainAccess")
            ],
            path: ".",
            exclude: [
                "Tests",
                "README.md",
                "Package.swift",
                "Info.plist"
            ],
            resources: [
                .process("Resources")
            ],
            swiftSettings: [
                .define("PRIVACY_MODE"),
                .define("LOCAL_ONLY_DB"),
                .define("PHI_REDACTION"),
                .unsafeFlags([
                    "-enable-strict-concurrency=complete",
                    "-warn-concurrency"
                ])
            ]
        ),
        
        .testTarget(
            name: "JarvisVertexAITests",
            dependencies: ["JarvisVertexAI"],
            path: "Tests"
        )
    ],
    swiftLanguageVersions: [.v5]
)
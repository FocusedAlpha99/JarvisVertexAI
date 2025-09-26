// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JarvisVertexAI",
    platforms: [
        .iOS(.v17),
        .macOS(.v10_15)
    ],
    products: [
        .library(
            name: "JarvisVertexAI",
            targets: ["JarvisVertexAI"]
        ),
    ],
    dependencies: [
        // ObjectBox for local database (temporarily disabled)
        // .package(
        //     url: "https://github.com/objectbox/objectbox-swift.git",
        //     from: "4.0.0"
        // ),
        
        
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
                // .product(name: "ObjectBox", package: "objectbox-swift"),
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
            swiftSettings: [
                .define("PRIVACY_MODE"),
                .define("LOCAL_ONLY_DB"),
                .define("PHI_REDACTION")
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
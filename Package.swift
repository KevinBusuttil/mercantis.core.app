// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mercantis",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        // The Core engine, importable by Hub or any third-party app via
        // .package(url: ...). UI code (UIShell/, Views/) and the App entry
        // (mercantis_coreApp.swift) deliberately stay in the Xcode app target
        // and are not part of this library product. (ADR-007, P2.6)
        .library(name: "MercantisCore", targets: ["MercantisCore"]),
        .executable(name: "mercantis", targets: ["mercantis"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/groue/GRDB.swift", from: "6.0.0")
    ],
    targets: [
        .systemLibrary(
            name: "SQLite3",
            path: "MercantisCLI/SQLite3",
            pkgConfig: "sqlite3",
            providers: [
                .apt(["libsqlite3-dev"]),
                .brew(["sqlite3"])
            ]
        ),
        .target(
            name: "MercantisCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "mercantis core",
            exclude: [
                "Assets.xcassets",
                "mercantis_coreApp.swift",
                "UIShell",
                "Views"
            ]
        ),
        .executableTarget(
            name: "mercantis",
            dependencies: [
                "SQLite3",
                "MercantisCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "MercantisCLI/Sources",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

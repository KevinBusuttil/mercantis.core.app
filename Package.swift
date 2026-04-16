// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "mercantis",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "mercantis", targets: ["mercantis"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0")
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
        .executableTarget(
            name: "mercantis",
            dependencies: [
                "SQLite3",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "MercantisCLI/Sources",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)

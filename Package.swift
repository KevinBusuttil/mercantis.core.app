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
        // (mercantis_coreApp.swift) deliberately stay out of this library
        // product so headless / server-side consumers don't pull SwiftUI.
        // (ADR-007, P2.6)
        .library(name: "MercantisCore", targets: ["MercantisCore"]),
        // The metadata-driven SwiftUI shell (`GenericFormView`,
        // `GenericListView`, …) sourced from `mercantis core/UIShell/`.
        // Sits on top of `MercantisCore`, so apps that want the
        // out-of-the-box renderer can `import MercantisCoreUI` and apps
        // that don't need SwiftUI can stick with `MercantisCore`. (P2.7)
        .library(name: "MercantisCoreUI", targets: ["MercantisCoreUI"]),
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
            // `UIShell` stays excluded here so its sources can be claimed
            // by the `MercantisCoreUI` target below; SwiftPM rejects
            // overlapping source paths between targets, so the exclude is
            // load-bearing. `Views/` is design-system scaffolding still
            // built only by the Xcode app target.
            exclude: [
                "Assets.xcassets",
                "mercantis_coreApp.swift",
                "UIShell",
                "Views"
            ]
        ),
        .target(
            name: "MercantisCoreUI",
            dependencies: [
                "MercantisCore",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            path: "mercantis core/UIShell"
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
        ),
        .testTarget(
            name: "MercantisCoreUITests",
            dependencies: ["MercantisCoreUI", "MercantisCore"],
            path: "Tests/MercantisCoreUITests"
        )
    ]
)

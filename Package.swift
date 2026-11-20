// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DCMap",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DCMap",
            path: "Sources/DCMap",
            resources: [
                .copy("Resources/d3.v7.min.js"),
                .copy("Resources/D3-LICENSE.txt")
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)

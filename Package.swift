// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "copy-on-select",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "copy-on-select",
            path: "Sources/CopyOnSelect",
            exclude: ["Info.plist"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                // SwiftPM has no .app product type. Embedding the Info.plist
                // directly in the __TEXT segment gives the executable a bundle
                // identifier and LSUIElement without assembling a bundle.
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/CopyOnSelect/Info.plist",
                ]),
            ]
        ),
    ]
)

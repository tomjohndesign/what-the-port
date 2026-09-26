// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "WhatThePort",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
        .package(url: "https://github.com/laurieesc/flicker-dot", exact: "0.2.0")
    ],
    targets: [
        .executableTarget(
            name: "WhatThePort",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "FlickerDot", package: "flicker-dot"),
            ],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "WhatThePortTests", dependencies: ["WhatThePort"])
    ]
)

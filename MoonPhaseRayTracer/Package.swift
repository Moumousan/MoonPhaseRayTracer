// swift-tools-version:5.9
// This file defines the Swift package for the MoonPhaseRayTracer library.  The
// package is intended to be integrated into an iOS project and provides a
// single target that exposes a function to render a PNG of the Moon for a
// given date and location using SceneKit.  To use this package, include
// `fullMoon.png` in the Resources folder with a high‑resolution texture of the
// Moon.

import PackageDescription

let package = Package(
    name: "MoonPhaseRayTracer",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "MoonPhaseRayTracer",
            targets: ["MoonPhaseRayTracer"])
    ],
    dependencies: [
        // No external dependencies are required.
    ],
    targets: [
        .target(
            name: "MoonPhaseRayTracer",
            dependencies: [],
            resources: [
                // Include any image assets located in the Resources directory.
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MoonPhaseRayTracerTests",
            dependencies: ["MoonPhaseRayTracer"]
        )
    ]
)
// swift-tools-version: 6.0
import PackageDescription
import Foundation

// The prebuilt C++ stack is consumed as a remote binaryTarget (a GitHub release
// asset) by default, so the package builds on a fresh checkout with no local
// xcframework. For local iteration on the xcframework itself, build it with
// `magentart-xcframework-builder`, mirror it into Frameworks/, and set
// `MRT_LOCAL_XCFRAMEWORK=1` to use the local copy instead of the release.
let magentartCore: Target = ProcessInfo.processInfo.environment["MRT_LOCAL_XCFRAMEWORK"] != nil
    ? .binaryTarget(name: "MagentartCore", path: "Frameworks/Magentart.xcframework")
    : .binaryTarget(
        name: "MagentartCore",
        url: "https://github.com/mnmly/magentart-xcframework-builder/releases/download/v0.0.1/Magentart.xcframework.zip",
        checksum: "0c12708ed8ec8a135b0cde611ef4b1b8677eee64abf9402f7488aadd8a2297c9"
      )

// MagentaRT — Swift bridge to the magentart::core C++ inference engine (MLX on
// Metal), packaged as a prebuilt static-library xcframework and consumed via
// Swift/C++ interoperability.
//
// Build the xcframework first with `magentart-xcframework-builder` and mirror it
// (+ mlx.metallib) into Frameworks/. Anything that *runs* MLX should be launched
// via Xcode/xcodebuild so mlx.metallib is bundled next to the binary (MLX uses a
// colocated lookup); bare `swift run`/`swift test` does not place it reliably.

// Every target that transitively imports `MagentaRT` must also enable C++
// interop (a known SPM propagation constraint), so we apply this to all of them.
let cxx: [SwiftSetting] = [.interoperabilityMode(.Cxx)]

// Frameworks the merged static archive (MLX + TFLite + SentencePiece) needs at
// final link. Declared on the library target so they propagate to every product.
let coreLinkerSettings: [LinkerSetting] = [
    .linkedFramework("Metal"),
    .linkedFramework("MetalPerformanceShaders"),
    .linkedFramework("Accelerate"),
    .linkedFramework("Foundation"),
]

let package = Package(
    name: "MagentaRT",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "MagentaRT", targets: ["MagentaRT"]),
        .library(name: "MagentaRTPlayer", targets: ["MagentaRTPlayer"]),
        .executable(name: "mrt-cli", targets: ["mrt-cli"]),
        .executable(name: "mrt-play", targets: ["mrt-play"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.4.3"),
    ],
    targets: [
        // The prebuilt C++ stack: merged static lib + Headers (incl. the
        // magentart_swift.hpp facade) + module map. Remote release asset by
        // default; local override via MRT_LOCAL_XCFRAMEWORK (see top of file).
        magentartCore,

        // Ergonomic Swift API over the facade reference types.
        .target(
            name: "MagentaRT",
            dependencies: ["MagentartCore"],
            swiftSettings: cxx,
            linkerSettings: coreLinkerSettings
        ),

        // AVAudioEngine realtime player built on the RealtimeEngine facade.
        .target(
            name: "MagentaRTPlayer",
            dependencies: ["MagentaRT"],
            swiftSettings: cxx
        ),

        // CLI tools (live under Tools/, not Sources/).
        // Offline generate → WAV (port of examples/hello_mrt2).
        .executableTarget(
            name: "mrt-cli",
            dependencies: ["MagentaRT"],
            path: "Tools/mrt-cli",
            swiftSettings: cxx
        ),

        // Live streaming demo.
        .executableTarget(
            name: "mrt-play",
            dependencies: ["MagentaRTPlayer"],
            path: "Tools/mrt-play",
            swiftSettings: cxx
        ),

        .testTarget(
            name: "MagentaRTTests",
            dependencies: ["MagentaRT"],
            swiftSettings: cxx
        ),
    ],
    cxxLanguageStandard: .cxx20
)

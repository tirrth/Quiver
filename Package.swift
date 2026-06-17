// swift-tools-version: 6.0
//
// This manifest exists ONLY to open Quiver in Xcode for editing, autocomplete, inline docs,
// SwiftUI Previews, the View Debugger, and Instruments. It is NOT the production build.
//
//   • The shippable, signed `Quiver.app` is still produced by `./build.sh` (which assembles the
//     bundle, Info.plist, entitlements, icon, and the stable local code-signing identity that keeps
//     the Accessibility grant across rebuilds). Keep using build.sh / install.sh to actually run it.
//   • Running the executable scheme straight from Xcode produces a bare binary with no .app bundle,
//     so LSUIElement / menu-bar-agent / signing behavior will be wrong. Use Xcode to *write* code;
//     use build.sh to *run* it. See docs/control-center-hub.md for the screencapture loop.
//
// Open it with:  xed .      (or: File ▸ Open ▸ this folder in Xcode)

import PackageDescription
import Foundation

// AutoRaise's experimental FOCUS_FIRST path uses private SkyLight SPIs (SLPS*) via @_silgen_name, so
// it must link the private framework. Mirror build.sh: only enable it when SkyLight is present.
let skyLightFramework = "/System/Library/PrivateFrameworks/SkyLight.framework"
let hasSkyLight = FileManager.default.fileExists(atPath: skyLightFramework)

// @main lives in main.swift, so parse-as-library to honor the attribute (matches build.sh).
var quiverSwiftSettings: [SwiftSetting] = [
    .define("OLD_ACTIVATION_METHOD"),
    .unsafeFlags(["-parse-as-library"]),
]
// `import ApplicationServices`/`import Carbon` auto-link, but be explicit to match build.sh.
var quiverLinkerSettings: [LinkerSetting] = [
    .linkedFramework("ApplicationServices"),
    .linkedFramework("Carbon"),
]
if hasSkyLight {
    quiverSwiftSettings.append(.define("FOCUS_FIRST"))
    quiverLinkerSettings.append(
        .unsafeFlags(["-F", "/System/Library/PrivateFrameworks", "-framework", "SkyLight"])
    )
}

let package = Package(
    name: "Quiver",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Quiver", targets: ["Quiver"]),
        .executable(name: "QuiverHelper", targets: ["QuiverHelper"]),
    ],
    targets: [
        .executableTarget(
            name: "Quiver",
            path: "Sources/Quiver",
            swiftSettings: quiverSwiftSettings,
            linkerSettings: quiverLinkerSettings
        ),
        .executableTarget(
            name: "QuiverHelper",
            path: "Sources/QuiverHelper",
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ],
    // The codebase is written for Swift 5 mode (build.sh doesn't opt into Swift 6); keep Xcode in the
    // same mode so it doesn't drown the project in strict-concurrency errors that build.sh never sees.
    swiftLanguageModes: [.v5]
)

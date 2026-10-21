// swift-tools-version: 5.9
// Used when the app has Flutter's Swift Package Manager support on; CocoaPods
// builds use ../sigma.podspec instead.

import PackageDescription

let package = Package(
    name: "sigma",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "sigma", targets: ["sigma"])
    ],
    dependencies: [
        // The native iOS SDK; Sigma's engine is not in it (a session downloads it).
        .package(url: "https://github.com/CodeSyncr/sigma-ios.git", from: "2.1.1")
    ],
    targets: [
        .target(
            name: "sigma",
            dependencies: [.product(name: "NimbusSigma", package: "sigma-ios")],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)

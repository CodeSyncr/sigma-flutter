// swift-tools-version: 5.9
// Used when the app has Flutter's Swift Package Manager support on; CocoaPods
// builds use ../sigma_flutter.podspec instead.

import PackageDescription

let package = Package(
    name: "sigma_flutter",
    platforms: [
        .iOS("16.0")
    ],
    products: [
        .library(name: "sigma-flutter", targets: ["sigma_flutter"])
    ],
    dependencies: [
        // The native iOS SDK; Sigma's engine is not in it (a session downloads it).
        .package(url: "https://github.com/CodeSyncr/sigma-ios.git", from: "2.1.1")
    ],
    targets: [
        .target(
            name: "sigma_flutter",
            dependencies: [.product(name: "NimbusSigma", package: "sigma-ios")],
            resources: [.process("PrivacyInfo.xcprivacy")]
        )
    ]
)

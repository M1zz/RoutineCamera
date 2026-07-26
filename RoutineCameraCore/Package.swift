// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RoutineCameraCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "RoutineCameraCore", targets: ["RoutineCameraCore"])
    ],
    targets: [
        .target(name: "RoutineCameraCore"),
        .testTarget(name: "RoutineCameraCoreTests", dependencies: ["RoutineCameraCore"])
    ]
)

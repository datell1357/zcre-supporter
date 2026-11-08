// swift-tools-version: 6.0
// 구성: 순수 데이터 코어와 macOS 실행 앱, 두 Swift 테스트 타깃을 분리한다.
import PackageDescription
import Foundation

let storeBuild = ProcessInfo.processInfo.environment["DISTRIBUTION_CHANNEL"] == "app-store"

let package = Package(
    name: "ZCREBunny",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ZCREBunny", targets: ["ZCREBunny"])],
    dependencies: storeBuild ? [] : [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "ZCRECore"),
        .executableTarget(name: "ZCREBunny", dependencies: [.target(name: "ZCRECore")] + (storeBuild ? [] : [.product(name: "Sparkle", package: "Sparkle")]), resources: [.copy("Resources/ReadSnapshot.js"), .copy("Resources/ReadOutputs.js"), .copy("Resources/ReadCreatorMetrics.js"), .copy("Resources/ObserveSession.js"), .copy("Resources/Zic"), .copy("Resources/Sounds"), .copy("Resources/ReviewDemo")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "ZCRECoreTests", dependencies: ["ZCRECore"]),
        .testTarget(name: "ZCREBunnyTests", dependencies: ["ZCREBunny"])
    ]
)

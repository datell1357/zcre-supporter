// swift-tools-version: 6.0
// 구성: 순수 데이터 코어와 macOS 실행 앱, 두 Swift 테스트 타깃을 분리한다.
import PackageDescription

let package = Package(
    name: "ZCREBunny",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ZCREBunny", targets: ["ZCREBunny"])],
    targets: [
        .target(name: "ZCRECore"),
        .executableTarget(name: "ZCREBunny", dependencies: ["ZCRECore"], resources: [.copy("Resources/ReadSnapshot.js"), .copy("Resources/ReadOutputs.js"), .copy("Resources/ObserveSession.js"), .copy("Resources/Zic"), .copy("Resources/Sounds")]),
        .testTarget(name: "ZCRECoreTests", dependencies: ["ZCRECore"]),
        .testTarget(name: "ZCREBunnyTests", dependencies: ["ZCREBunny"])
    ]
)

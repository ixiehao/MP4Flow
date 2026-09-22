// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MP4Flow",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MP4Flow", targets: ["FastConvert"])],
    targets: [.executableTarget(name: "FastConvert")]
)

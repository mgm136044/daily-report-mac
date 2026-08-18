// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "daily-report-mac",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DailyReportKit", targets: ["DailyReportKit"]),
        .executable(name: "daily-report-runner", targets: ["daily-report-runner"]),
        .executable(name: "DailyReport", targets: ["DailyReport"]),
    ],
    targets: [
        .target(name: "DailyReportKit"),
        .executableTarget(
            name: "daily-report-runner",
            dependencies: ["DailyReportKit"]),
        .executableTarget(
            name: "DailyReport",
            dependencies: ["DailyReportKit"],
            resources: [.copy("Resources/design-system.css")]),
        .testTarget(
            name: "DailyReportKitTests",
            dependencies: ["DailyReportKit"]),
    ]
)

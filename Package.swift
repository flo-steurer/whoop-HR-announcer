// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WhoopHRAnnouncerCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "WhoopHRAnnouncerCore", targets: ["WhoopHRAnnouncerCore"])
    ],
    targets: [
        .target(
            name: "WhoopHRAnnouncerCore",
            path: "WhoopHRAnnouncer",
            exclude: [
                "AppModel.swift",
                "AppSettings.swift",
                "BluetoothHeartRateManager.swift",
                "ContentView.swift",
                "Info.plist",
                "SpeechAnnouncer.swift",
                "WorkoutPlanViews.swift",
                "WhoopHRAnnouncerApp.swift"
            ],
            sources: [
                "AnnouncementEngine.swift",
                "HeartRateParser.swift",
                "WorkoutModels.swift",
                "WorkoutRunner.swift",
                "WorkoutStore.swift"
            ]
        ),
        .testTarget(
            name: "WhoopHRAnnouncerCoreTests",
            dependencies: ["WhoopHRAnnouncerCore"],
            path: "WhoopHRAnnouncerTests"
        )
    ]
)

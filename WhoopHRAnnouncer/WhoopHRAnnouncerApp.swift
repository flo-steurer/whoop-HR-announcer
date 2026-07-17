import SwiftUI

@main
struct WhoopHRAnnouncerApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings: AppSettings
    @StateObject private var workoutStore: WorkoutPlanStore
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        let workoutStore = WorkoutPlanStore()
        _settings = StateObject(wrappedValue: settings)
        _workoutStore = StateObject(wrappedValue: workoutStore)
        _model = StateObject(
            wrappedValue: AppModel(
                settings: settings,
                workoutStore: workoutStore
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                model: model,
                settings: settings,
                workoutStore: workoutStore
            )
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active {
                    model.refreshWorkout()
                } else {
                    model.checkpointWorkout()
                }
            }
        }
    }
}

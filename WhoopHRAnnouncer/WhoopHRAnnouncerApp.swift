import SwiftUI

@main
struct WhoopHRAnnouncerApp: App {
    @StateObject private var settings: AppSettings
    @StateObject private var model: AppModel

    init() {
        let settings = AppSettings()
        _settings = StateObject(wrappedValue: settings)
        _model = StateObject(wrappedValue: AppModel(settings: settings))
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model, settings: settings)
        }
    }
}

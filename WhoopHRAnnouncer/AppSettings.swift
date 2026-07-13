import Foundation
import Combine

enum OtherAudioMode: String, CaseIterable, Identifiable {
    case duck
    case mix

    var id: String { rawValue }
    var label: String { self == .duck ? "Duck other audio" : "Mix at full volume" }
}

final class AppSettings: ObservableObject {
    private enum Key {
        static let minimumBPM = "minimumBPM"
        static let maximumBPM = "maximumBPM"
        static let normalInterval = "normalInterval"
        static let warningInterval = "warningInterval"
        static let confirmationDelay = "confirmationDelay"
        static let audioMode = "audioMode"
    }

    @Published var minimumBPM: Int { didSet { defaults.set(minimumBPM, forKey: Key.minimumBPM) } }
    @Published var maximumBPM: Int { didSet { defaults.set(maximumBPM, forKey: Key.maximumBPM) } }
    @Published var normalInterval: Double { didSet { defaults.set(normalInterval, forKey: Key.normalInterval) } }
    @Published var warningInterval: Double { didSet { defaults.set(warningInterval, forKey: Key.warningInterval) } }
    @Published var confirmationDelay: Double { didSet { defaults.set(confirmationDelay, forKey: Key.confirmationDelay) } }
    @Published var audioMode: OtherAudioMode { didSet { defaults.set(audioMode.rawValue, forKey: Key.audioMode) } }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedMinimum = defaults.object(forKey: Key.minimumBPM) as? Int ?? 135
        let storedMaximum = defaults.object(forKey: Key.maximumBPM) as? Int ?? 155
        if (30...240).contains(storedMinimum),
           (30...240).contains(storedMaximum),
           storedMinimum < storedMaximum {
            minimumBPM = storedMinimum
            maximumBPM = storedMaximum
        } else {
            minimumBPM = 135
            maximumBPM = 155
        }
        normalInterval = defaults.object(forKey: Key.normalInterval) as? Double ?? 60
        warningInterval = defaults.object(forKey: Key.warningInterval) as? Double ?? 10
        confirmationDelay = defaults.object(forKey: Key.confirmationDelay) as? Double ?? 5
        audioMode = OtherAudioMode(rawValue: defaults.string(forKey: Key.audioMode) ?? "") ?? .duck
    }

    var isValid: Bool {
        (30...240).contains(minimumBPM)
            && (30...240).contains(maximumBPM)
            && minimumBPM < maximumBPM
    }

    var announcementConfiguration: AnnouncementConfiguration {
        AnnouncementConfiguration(
            minimumBPM: minimumBPM,
            maximumBPM: maximumBPM,
            normalInterval: normalInterval,
            warningInterval: warningInterval,
            confirmationDelay: confirmationDelay
        )
    }
}

import Foundation

enum HeartRateZoneState: String, Equatable {
    case belowRange
    case inRange
    case aboveRange
}

struct AnnouncementConfiguration: Equatable {
    var minimumBPM: Int
    var maximumBPM: Int
    var normalInterval: TimeInterval
    var warningInterval: TimeInterval
    var confirmationDelay: TimeInterval
}

enum AnnouncementReason: Equatable {
    case initial
    case periodic
    case rangeChanged
    case returnedToRange
}

struct AnnouncementEvent: Equatable {
    let bpm: Int
    let state: HeartRateZoneState
    let reason: AnnouncementReason

    var spokenText: String {
        switch reason {
        case .returnedToRange:
            return "Heart rate \(bpm), back in range"
        case .initial, .rangeChanged:
            switch state {
            case .belowRange: return "Heart rate \(bpm), below range"
            case .inRange: return "Heart rate \(bpm), in range"
            case .aboveRange: return "Heart rate \(bpm), above range"
            }
        case .periodic:
            switch state {
            case .belowRange: return "Heart rate \(bpm), below range"
            case .inRange: return "Heart rate \(bpm)"
            case .aboveRange: return "Heart rate \(bpm), above range"
            }
        }
    }
}

struct AnnouncementEngine {
    private(set) var stableState: HeartRateZoneState?
    private var candidateState: HeartRateZoneState?
    private var candidateSince: TimeInterval?
    private var lastAnnouncementTime: TimeInterval?

    mutating func reset() {
        stableState = nil
        candidateState = nil
        candidateSince = nil
        lastAnnouncementTime = nil
    }

    mutating func ingest(
        bpm: Int,
        at timestamp: TimeInterval,
        configuration: AnnouncementConfiguration
    ) -> AnnouncementEvent? {
        let measuredState = Self.classify(bpm: bpm, configuration: configuration)

        guard let stableState else {
            return confirmInitialState(
                measuredState,
                bpm: bpm,
                at: timestamp,
                delay: configuration.confirmationDelay
            )
        }

        if measuredState != stableState {
            if candidateState != measuredState {
                candidateState = measuredState
                candidateSince = timestamp
            }

            guard timestamp - (candidateSince ?? timestamp) >= configuration.confirmationDelay else {
                return nil
            }

            let previousState = stableState
            self.stableState = measuredState
            candidateState = nil
            candidateSince = nil
            lastAnnouncementTime = timestamp

            let reason: AnnouncementReason = measuredState == .inRange && previousState != .inRange
                ? .returnedToRange
                : .rangeChanged
            return AnnouncementEvent(bpm: bpm, state: measuredState, reason: reason)
        }

        candidateState = nil
        candidateSince = nil

        let interval = stableState == .inRange
            ? configuration.normalInterval
            : configuration.warningInterval
        guard timestamp - (lastAnnouncementTime ?? timestamp) >= interval else { return nil }

        lastAnnouncementTime = timestamp
        return AnnouncementEvent(bpm: bpm, state: stableState, reason: .periodic)
    }

    private mutating func confirmInitialState(
        _ state: HeartRateZoneState,
        bpm: Int,
        at timestamp: TimeInterval,
        delay: TimeInterval
    ) -> AnnouncementEvent? {
        if candidateState != state {
            candidateState = state
            candidateSince = timestamp
        }

        guard timestamp - (candidateSince ?? timestamp) >= delay else { return nil }

        stableState = state
        candidateState = nil
        candidateSince = nil
        lastAnnouncementTime = timestamp
        return AnnouncementEvent(bpm: bpm, state: state, reason: .initial)
    }

    static func classify(
        bpm: Int,
        configuration: AnnouncementConfiguration
    ) -> HeartRateZoneState {
        if bpm < configuration.minimumBPM { return .belowRange }
        if bpm > configuration.maximumBPM { return .aboveRange }
        return .inRange
    }
}

struct SessionAnnouncementOutput: Equatable {
    let zone: HeartRateZoneState?
    let event: AnnouncementEvent?
    let spokenText: String?
}

struct SessionAnnouncementCoordinator {
    private var engine = AnnouncementEngine()

    var stableState: HeartRateZoneState? { engine.stableState }

    mutating func reset() {
        engine.reset()
    }

    mutating func ingest(
        bpm: Int,
        at timestamp: TimeInterval,
        configuration: AnnouncementConfiguration,
        phaseAnnouncement: String? = nil,
        suppressSpeech: Bool = false
    ) -> SessionAnnouncementOutput {
        guard !suppressSpeech else {
            return SessionAnnouncementOutput(
                zone: AnnouncementEngine.classify(
                    bpm: bpm,
                    configuration: configuration
                ),
                event: nil,
                spokenText: nil
            )
        }

        let event = engine.ingest(
            bpm: bpm,
            at: timestamp,
            configuration: configuration
        )
        let spokenText: String?
        switch (phaseAnnouncement, event?.spokenText) {
        case let (phase?, heartRate?):
            spokenText = "\(phase) \(heartRate)."
        case let (phase?, nil):
            spokenText = phase
        case let (nil, heartRate?):
            spokenText = heartRate
        case (nil, nil):
            spokenText = nil
        }

        return SessionAnnouncementOutput(
            zone: engine.stableState,
            event: event,
            spokenText: spokenText
        )
    }
}

import Foundation

enum SessionMode: String, Codable, CaseIterable, Identifiable {
    case manual
    case workout

    var id: String { rawValue }
    var label: String { self == .manual ? "Manual Range" : "Workout Plan" }
}

struct WorkoutPhase: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var durationSeconds: Int
    var minimumBPM: Int
    var maximumBPM: Int

    init(
        id: UUID = UUID(),
        name: String = "New Phase",
        durationSeconds: Int = 300,
        minimumBPM: Int = 135,
        maximumBPM: Int = 155
    ) {
        self.id = id
        self.name = name
        self.durationSeconds = durationSeconds
        self.minimumBPM = minimumBPM
        self.maximumBPM = maximumBPM
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...86_400).contains(durationSeconds)
            && (30...240).contains(minimumBPM)
            && (30...240).contains(maximumBPM)
            && minimumBPM < maximumBPM
    }

    var targetText: String {
        "\(name.trimmingCharacters(in: .whitespacesAndNewlines)). Target \(minimumBPM) to \(maximumBPM)."
    }
}

struct WorkoutRepeatGroup: Identifiable, Codable, Equatable {
    var id: UUID
    var phases: [WorkoutPhase]
    var repetitions: Int

    init(
        id: UUID = UUID(),
        phases: [WorkoutPhase] = [
            WorkoutPhase(name: "Fast interval", durationSeconds: 180, minimumBPM: 160, maximumBPM: 180),
            WorkoutPhase(name: "Recovery", durationSeconds: 120, minimumBPM: 125, maximumBPM: 145)
        ],
        repetitions: Int = 4
    ) {
        self.id = id
        self.phases = phases
        self.repetitions = repetitions
    }

    var isValid: Bool {
        (2...99).contains(repetitions)
            && !phases.isEmpty
            && phases.allSatisfy(\.isValid)
    }
}

enum WorkoutBlock: Identifiable, Codable, Equatable {
    case phase(WorkoutPhase)
    case repeatGroup(WorkoutRepeatGroup)

    private enum CodingKeys: String, CodingKey {
        case type
        case phase
        case repeatGroup
    }

    private enum BlockType: String, Codable {
        case phase
        case repeatGroup
    }

    var id: UUID {
        switch self {
        case .phase(let phase): return phase.id
        case .repeatGroup(let group): return group.id
        }
    }

    var isValid: Bool {
        switch self {
        case .phase(let phase): return phase.isValid
        case .repeatGroup(let group): return group.isValid
        }
    }

    var expandedPhaseCount: Int {
        switch self {
        case .phase: return 1
        case .repeatGroup(let group): return group.phases.count * group.repetitions
        }
    }

    var totalDurationSeconds: Int {
        switch self {
        case .phase(let phase):
            return phase.durationSeconds
        case .repeatGroup(let group):
            return group.phases.reduce(0) { $0 + $1.durationSeconds } * group.repetitions
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(BlockType.self, forKey: .type) {
        case .phase:
            self = .phase(try container.decode(WorkoutPhase.self, forKey: .phase))
        case .repeatGroup:
            self = .repeatGroup(
                try container.decode(WorkoutRepeatGroup.self, forKey: .repeatGroup)
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .phase(let phase):
            try container.encode(BlockType.phase, forKey: .type)
            try container.encode(phase, forKey: .phase)
        case .repeatGroup(let group):
            try container.encode(BlockType.repeatGroup, forKey: .type)
            try container.encode(group, forKey: .repeatGroup)
        }
    }
}

struct WorkoutPlan: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var blocks: [WorkoutBlock]

    init(
        id: UUID = UUID(),
        name: String = "New Workout",
        blocks: [WorkoutBlock] = [
            .phase(WorkoutPhase(name: "Warm-up", durationSeconds: 600, minimumBPM: 120, maximumBPM: 145))
        ]
    ) {
        self.id = id
        self.name = name
        self.blocks = blocks
    }

    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !blocks.isEmpty
            && blocks.allSatisfy(\.isValid)
            && !expandedPhases.isEmpty
    }

    var expandedPhaseCount: Int {
        blocks.reduce(0) { $0 + $1.expandedPhaseCount }
    }

    var totalDurationSeconds: Int {
        blocks.reduce(0) { $0 + $1.totalDurationSeconds }
    }

    var expandedPhases: [ScheduledWorkoutPhase] {
        var result: [ScheduledWorkoutPhase] = []
        for block in blocks {
            switch block {
            case .phase(let phase):
                result.append(
                    ScheduledWorkoutPhase(
                        id: "\(block.id.uuidString)-0-\(phase.id.uuidString)",
                        sourcePhaseID: phase.id,
                        name: phase.name,
                        durationSeconds: phase.durationSeconds,
                        minimumBPM: phase.minimumBPM,
                        maximumBPM: phase.maximumBPM,
                        repetitionNumber: nil,
                        repetitionCount: nil
                    )
                )
            case .repeatGroup(let group):
                for repetition in 1...group.repetitions {
                    for phase in group.phases {
                        result.append(
                            ScheduledWorkoutPhase(
                                id: "\(group.id.uuidString)-\(repetition)-\(phase.id.uuidString)",
                                sourcePhaseID: phase.id,
                                name: phase.name,
                                durationSeconds: phase.durationSeconds,
                                minimumBPM: phase.minimumBPM,
                                maximumBPM: phase.maximumBPM,
                                repetitionNumber: repetition,
                                repetitionCount: group.repetitions
                            )
                        )
                    }
                }
            }
        }
        return result
    }

    func duplicated() -> WorkoutPlan {
        let duplicatedBlocks = blocks.map { block -> WorkoutBlock in
            switch block {
            case .phase(let phase):
                return .phase(
                    WorkoutPhase(
                        name: phase.name,
                        durationSeconds: phase.durationSeconds,
                        minimumBPM: phase.minimumBPM,
                        maximumBPM: phase.maximumBPM
                    )
                )
            case .repeatGroup(let group):
                return .repeatGroup(
                    WorkoutRepeatGroup(
                        phases: group.phases.map {
                            WorkoutPhase(
                                name: $0.name,
                                durationSeconds: $0.durationSeconds,
                                minimumBPM: $0.minimumBPM,
                                maximumBPM: $0.maximumBPM
                            )
                        },
                        repetitions: group.repetitions
                    )
                )
            }
        }
        return WorkoutPlan(name: "\(name) Copy", blocks: duplicatedBlocks)
    }
}

struct ScheduledWorkoutPhase: Identifiable, Codable, Equatable {
    let id: String
    let sourcePhaseID: UUID
    let name: String
    let durationSeconds: Int
    let minimumBPM: Int
    let maximumBPM: Int
    let repetitionNumber: Int?
    let repetitionCount: Int?

    var iterationText: String? {
        guard let repetitionNumber, let repetitionCount else { return nil }
        return "Repeat \(repetitionNumber) of \(repetitionCount)"
    }

    var targetText: String {
        "\(name). Target \(minimumBPM) to \(maximumBPM)."
    }
}

extension Array {
    mutating func moveElements(from offsets: IndexSet, to destination: Int) {
        let validOffsets = offsets.filter { indices.contains($0) }.sorted()
        guard !validOffsets.isEmpty else { return }

        let elements = validOffsets.map { self[$0] }
        for index in validOffsets.reversed() {
            remove(at: index)
        }

        let removedBeforeDestination = validOffsets.filter { $0 < destination }.count
        let insertionIndex = Swift.max(
            0,
            Swift.min(count, destination - removedBeforeDestination)
        )
        insert(contentsOf: elements, at: insertionIndex)
    }
}

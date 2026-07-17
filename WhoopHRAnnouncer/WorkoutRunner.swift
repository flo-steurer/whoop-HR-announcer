import Foundation

protocol MonotonicClock {
    var now: TimeInterval { get }
}

struct SystemMonotonicClock: MonotonicClock {
    var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
}

enum WorkoutRunStatus: String, Codable, Equatable {
    case running
    case paused
}

struct ActiveWorkoutSnapshot: Codable, Equatable {
    static let currentVersion = 1

    var version: Int = Self.currentVersion
    var planID: UUID
    var planName: String
    var phases: [ScheduledWorkoutPhase]
    var currentIndex: Int
    var status: WorkoutRunStatus
    var phaseStartedAt: TimeInterval
    var pausedRemaining: TimeInterval?
    var checkpointRemaining: TimeInterval
    var savedUptime: TimeInterval
    var savedAt: Date

    var isStructurallyValid: Bool {
        version == Self.currentVersion
            && !phases.isEmpty
            && phases.indices.contains(currentIndex)
            && phases.allSatisfy {
                (1...86_400).contains($0.durationSeconds)
                    && (30...240).contains($0.minimumBPM)
                    && (30...240).contains($0.maximumBPM)
                    && $0.minimumBPM < $0.maximumBPM
            }
    }
}

struct WorkoutRunUpdate: Equatable {
    let phaseChanged: Bool
    let completed: Bool
    let currentPhase: ScheduledWorkoutPhase?

    static let none = WorkoutRunUpdate(
        phaseChanged: false,
        completed: false,
        currentPhase: nil
    )
}

struct WorkoutPresentation: Equatable {
    let planName: String
    let currentPhase: ScheduledWorkoutPhase
    let upcomingPhase: ScheduledWorkoutPhase?
    let remainingSeconds: TimeInterval
    let overallProgress: Double
    let status: WorkoutRunStatus
}

final class WorkoutRunner {
    private(set) var state: ActiveWorkoutSnapshot?

    private let clock: MonotonicClock
    private let wallNow: () -> Date

    init(
        clock: MonotonicClock = SystemMonotonicClock(),
        wallNow: @escaping () -> Date = Date.init
    ) {
        self.clock = clock
        self.wallNow = wallNow
    }

    @discardableResult
    func start(plan: WorkoutPlan) -> WorkoutRunUpdate {
        let phases = plan.expandedPhases
        guard plan.isValid, let first = phases.first else {
            state = nil
            return .none
        }

        let now = clock.now
        state = ActiveWorkoutSnapshot(
            planID: plan.id,
            planName: plan.name,
            phases: phases,
            currentIndex: 0,
            status: .running,
            phaseStartedAt: now,
            pausedRemaining: nil,
            checkpointRemaining: TimeInterval(first.durationSeconds),
            savedUptime: now,
            savedAt: wallNow()
        )
        return WorkoutRunUpdate(
            phaseChanged: true,
            completed: false,
            currentPhase: first
        )
    }

    @discardableResult
    func restore(_ snapshot: ActiveWorkoutSnapshot) -> WorkoutRunUpdate {
        guard snapshot.isStructurallyValid else {
            state = nil
            return .none
        }

        state = snapshot
        if snapshot.status == .running && !isSameBoot(snapshot) {
            let remaining = boundedRemaining(
                snapshot.checkpointRemaining,
                phase: snapshot.phases[snapshot.currentIndex]
            )
            state?.status = .paused
            state?.pausedRemaining = remaining
            state?.phaseStartedAt = clock.now
            checkpoint()
            return WorkoutRunUpdate(
                phaseChanged: false,
                completed: false,
                currentPhase: currentPhase
            )
        }

        return advance()
    }

    @discardableResult
    func advance() -> WorkoutRunUpdate {
        guard var state, state.status == .running else {
            return WorkoutRunUpdate(
                phaseChanged: false,
                completed: false,
                currentPhase: currentPhase
            )
        }

        let now = clock.now
        var changed = false
        while true {
            let phase = state.phases[state.currentIndex]
            let phaseEnd = state.phaseStartedAt + TimeInterval(phase.durationSeconds)
            guard now >= phaseEnd else { break }

            let nextIndex = state.currentIndex + 1
            guard state.phases.indices.contains(nextIndex) else {
                self.state = nil
                return WorkoutRunUpdate(
                    phaseChanged: changed,
                    completed: true,
                    currentPhase: nil
                )
            }

            state.currentIndex = nextIndex
            state.phaseStartedAt = phaseEnd
            state.pausedRemaining = nil
            changed = true
        }

        self.state = state
        return WorkoutRunUpdate(
            phaseChanged: changed,
            completed: false,
            currentPhase: currentPhase
        )
    }

    @discardableResult
    func pause() -> WorkoutRunUpdate {
        let caughtUp = advance()
        guard !caughtUp.completed, var state, state.status == .running else {
            return caughtUp
        }

        let remaining = remainingSeconds(for: state, at: clock.now)
        state.status = .paused
        state.pausedRemaining = remaining
        state.checkpointRemaining = remaining
        self.state = state
        checkpoint()
        return WorkoutRunUpdate(
            phaseChanged: caughtUp.phaseChanged,
            completed: false,
            currentPhase: currentPhase
        )
    }

    @discardableResult
    func resume() -> WorkoutRunUpdate {
        guard var state, state.status == .paused else {
            return WorkoutRunUpdate(
                phaseChanged: false,
                completed: false,
                currentPhase: currentPhase
            )
        }

        let phase = state.phases[state.currentIndex]
        let remaining = boundedRemaining(
            state.pausedRemaining ?? state.checkpointRemaining,
            phase: phase
        )
        let elapsed = TimeInterval(phase.durationSeconds) - remaining
        state.status = .running
        state.phaseStartedAt = clock.now - elapsed
        state.pausedRemaining = nil
        self.state = state
        checkpoint()
        return WorkoutRunUpdate(
            phaseChanged: true,
            completed: false,
            currentPhase: currentPhase
        )
    }

    @discardableResult
    func previous() -> WorkoutRunUpdate {
        let caughtUp = advance()
        guard !caughtUp.completed, var state else { return caughtUp }

        state.currentIndex = max(0, state.currentIndex - 1)
        restartCurrentPhase(in: &state)
        self.state = state
        checkpoint()
        return WorkoutRunUpdate(
            phaseChanged: true,
            completed: false,
            currentPhase: currentPhase
        )
    }

    @discardableResult
    func next() -> WorkoutRunUpdate {
        let caughtUp = advance()
        guard !caughtUp.completed, var state else { return caughtUp }

        let nextIndex = state.currentIndex + 1
        guard state.phases.indices.contains(nextIndex) else {
            self.state = nil
            return WorkoutRunUpdate(
                phaseChanged: false,
                completed: true,
                currentPhase: nil
            )
        }

        state.currentIndex = nextIndex
        restartCurrentPhase(in: &state)
        self.state = state
        checkpoint()
        return WorkoutRunUpdate(
            phaseChanged: true,
            completed: false,
            currentPhase: currentPhase
        )
    }

    func stop() {
        state = nil
    }

    @discardableResult
    func checkpoint() -> ActiveWorkoutSnapshot? {
        guard var state else { return nil }
        let now = clock.now
        let remaining = remainingSeconds(for: state, at: now)
        state.checkpointRemaining = remaining
        state.savedUptime = now
        state.savedAt = wallNow()
        self.state = state
        return state
    }

    var currentPhase: ScheduledWorkoutPhase? {
        guard let state, state.phases.indices.contains(state.currentIndex) else { return nil }
        return state.phases[state.currentIndex]
    }

    var presentation: WorkoutPresentation? {
        guard let state,
              state.phases.indices.contains(state.currentIndex)
        else { return nil }

        let phase = state.phases[state.currentIndex]
        let remaining = remainingSeconds(for: state, at: clock.now)
        let completedDuration = state.phases[..<state.currentIndex]
            .reduce(0) { $0 + $1.durationSeconds }
        let currentElapsed = TimeInterval(phase.durationSeconds) - remaining
        let totalDuration = state.phases.reduce(0) { $0 + $1.durationSeconds }
        let progress = totalDuration > 0
            ? (TimeInterval(completedDuration) + currentElapsed) / TimeInterval(totalDuration)
            : 0
        let nextIndex = state.currentIndex + 1

        return WorkoutPresentation(
            planName: state.planName,
            currentPhase: phase,
            upcomingPhase: state.phases.indices.contains(nextIndex)
                ? state.phases[nextIndex]
                : nil,
            remainingSeconds: remaining,
            overallProgress: min(1, max(0, progress)),
            status: state.status
        )
    }

    private func restartCurrentPhase(in state: inout ActiveWorkoutSnapshot) {
        let duration = TimeInterval(state.phases[state.currentIndex].durationSeconds)
        state.phaseStartedAt = clock.now
        state.checkpointRemaining = duration
        if state.status == .paused {
            state.pausedRemaining = duration
        } else {
            state.pausedRemaining = nil
        }
    }

    private func remainingSeconds(
        for state: ActiveWorkoutSnapshot,
        at now: TimeInterval
    ) -> TimeInterval {
        let phase = state.phases[state.currentIndex]
        if state.status == .paused {
            return boundedRemaining(
                state.pausedRemaining ?? state.checkpointRemaining,
                phase: phase
            )
        }
        return boundedRemaining(
            state.phaseStartedAt + TimeInterval(phase.durationSeconds) - now,
            phase: phase
        )
    }

    private func boundedRemaining(
        _ remaining: TimeInterval,
        phase: ScheduledWorkoutPhase
    ) -> TimeInterval {
        min(TimeInterval(phase.durationSeconds), max(0, remaining))
    }

    private func isSameBoot(_ snapshot: ActiveWorkoutSnapshot) -> Bool {
        let savedBootReference = snapshot.savedAt.timeIntervalSince1970 - snapshot.savedUptime
        let currentBootReference = wallNow().timeIntervalSince1970 - clock.now
        return abs(savedBootReference - currentBootReference) <= 5
    }
}

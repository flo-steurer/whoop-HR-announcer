import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import WhoopHRAnnouncerCore
#else
@testable import HR_Announcer
#endif

private final class TestMonotonicClock: MonotonicClock {
    var now: TimeInterval

    init(now: TimeInterval = 0) {
        self.now = now
    }
}

struct WorkoutRunnerTests {
    @Test func advancesAtExactBoundaryAndCalculatesProgress() throws {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        runner.start(plan: twoPhasePlan)

        clock.now = 9.9
        #expect(!runner.advance().phaseChanged)
        clock.now = 10
        let transition = runner.advance()

        #expect(transition.phaseChanged)
        #expect(transition.currentPhase?.name == "Recovery")
        #expect(runner.presentation?.remainingSeconds == 20)
        #expect(runner.presentation?.overallProgress == 1.0 / 3.0)
    }

    @Test func delayedCallbackCrossesMultiplePhases() {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        let plan = WorkoutPlan(
            name: "Three",
            blocks: [
                .phase(phase("One", 10)),
                .phase(phase("Two", 10)),
                .phase(phase("Three", 10))
            ]
        )
        runner.start(plan: plan)

        clock.now = 25
        let update = runner.advance()

        #expect(update.phaseChanged)
        #expect(update.currentPhase?.name == "Three")
        #expect(runner.presentation?.remainingSeconds == 5)
    }

    @Test func delayedCallbackCompletesWorkout() {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        runner.start(plan: twoPhasePlan)

        clock.now = 30
        let update = runner.advance()

        #expect(update.completed)
        #expect(runner.state == nil)
    }

    @Test func pauseAndResumeFreezeRemainingTime() {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        runner.start(plan: twoPhasePlan)

        clock.now = 4
        runner.pause()
        clock.now = 100
        #expect(runner.presentation?.remainingSeconds == 6)
        #expect(runner.advance().currentPhase?.name == "Fast")

        runner.resume()
        clock.now = 105.9
        #expect(!runner.advance().phaseChanged)
        clock.now = 106
        #expect(runner.advance().currentPhase?.name == "Recovery")
    }

    @Test func manualSkippingRestartsFullPhaseAndPreservesPause() {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        runner.start(plan: twoPhasePlan)

        clock.now = 3
        runner.next()
        #expect(runner.presentation?.currentPhase.name == "Recovery")
        #expect(runner.presentation?.remainingSeconds == 20)

        runner.pause()
        runner.previous()
        #expect(runner.presentation?.currentPhase.name == "Fast")
        #expect(runner.presentation?.remainingSeconds == 10)
        #expect(runner.presentation?.status == .paused)

        runner.next()
        #expect(runner.presentation?.status == .paused)
        #expect(runner.presentation?.remainingSeconds == 20)
        #expect(runner.next().completed)
    }

    @Test func sameBootRestorationCatchesUp() throws {
        let clock = TestMonotonicClock(now: 100)
        var wall = Date(timeIntervalSince1970: 10_000)
        let runner = WorkoutRunner(clock: clock, wallNow: { wall })
        runner.start(plan: twoPhasePlan)
        let snapshot = try #require(runner.checkpoint())

        clock.now = 115
        wall = wall.addingTimeInterval(15)
        let restored = WorkoutRunner(clock: clock, wallNow: { wall })
        let update = restored.restore(snapshot)

        #expect(update.phaseChanged)
        #expect(update.currentPhase?.name == "Recovery")
        #expect(restored.presentation?.remainingSeconds == 15)
        #expect(restored.presentation?.status == .running)
    }

    @Test func rebootRestorationFallsBackToPausedCheckpoint() throws {
        let clock = TestMonotonicClock(now: 100)
        var wall = Date(timeIntervalSince1970: 10_000)
        let runner = WorkoutRunner(clock: clock, wallNow: { wall })
        runner.start(plan: twoPhasePlan)
        clock.now = 104
        wall = wall.addingTimeInterval(4)
        let snapshot = try #require(runner.checkpoint())

        let rebootedClock = TestMonotonicClock(now: 10)
        wall = wall.addingTimeInterval(30)
        let restored = WorkoutRunner(clock: rebootedClock, wallNow: { wall })
        restored.restore(snapshot)

        #expect(restored.presentation?.status == .paused)
        #expect(restored.presentation?.remainingSeconds == 6)
    }

    @Test func phaseConfigurationFlowsThroughAnnouncementDebounce() {
        let clock = TestMonotonicClock()
        let runner = makeRunner(clock: clock)
        runner.start(plan: twoPhasePlan)
        var coordinator = SessionAnnouncementCoordinator()
        let fastConfiguration = configuration(for: tryPhase(runner.currentPhase))

        _ = coordinator.ingest(bpm: 130, at: 0, configuration: fastConfiguration)
        _ = coordinator.ingest(bpm: 130, at: 5, configuration: fastConfiguration)

        clock.now = 10
        let transition = runner.advance()
        let recovery = tryPhase(transition.currentPhase)
        let phaseText = recovery.targetText
        let first = coordinator.ingest(
            bpm: 150,
            at: 10,
            configuration: configuration(for: recovery),
            phaseAnnouncement: phaseText
        )
        let confirmed = coordinator.ingest(
            bpm: 150,
            at: 15,
            configuration: configuration(for: recovery)
        )

        #expect(first.spokenText == phaseText)
        #expect(confirmed.event?.state == .aboveRange)
        #expect(confirmed.event?.reason == .rangeChanged)
    }

    @Test func coordinatorCombinesSpeechAndSuppressesPausedSession() {
        var coordinator = SessionAnnouncementCoordinator()
        let configuration = AnnouncementConfiguration(
            minimumBPM: 100,
            maximumBPM: 140,
            normalInterval: 60,
            warningInterval: 10,
            confirmationDelay: 0
        )
        let combined = coordinator.ingest(
            bpm: 150,
            at: 0,
            configuration: configuration,
            phaseAnnouncement: "Fast. Target 160 to 180."
        )
        let paused = coordinator.ingest(
            bpm: 150,
            at: 100,
            configuration: configuration,
            suppressSpeech: true
        )

        #expect(combined.spokenText
            == "Fast. Target 160 to 180. Heart rate 150, above range.")
        #expect(paused.spokenText == nil)
        #expect(paused.zone == .aboveRange)
    }

    @Test func manualCoordinatorBehaviorMatchesExistingEngine() {
        var coordinator = SessionAnnouncementCoordinator()
        let configuration = AnnouncementConfiguration(
            minimumBPM: 100,
            maximumBPM: 140,
            normalInterval: 60,
            warningInterval: 10,
            confirmationDelay: 5
        )

        #expect(coordinator.ingest(
            bpm: 120,
            at: 0,
            configuration: configuration
        ).spokenText == nil)
        #expect(coordinator.ingest(
            bpm: 120,
            at: 5,
            configuration: configuration
        ).spokenText == "Heart rate 120, in range")
    }

    private var twoPhasePlan: WorkoutPlan {
        WorkoutPlan(
            name: "Intervals",
            blocks: [
                .phase(phase("Fast", 10, minimum: 100, maximum: 140)),
                .phase(phase("Recovery", 20, minimum: 120, maximum: 145))
            ]
        )
    }

    private func phase(
        _ name: String,
        _ duration: Int,
        minimum: Int = 100,
        maximum: Int = 140
    ) -> WorkoutPhase {
        WorkoutPhase(
            name: name,
            durationSeconds: duration,
            minimumBPM: minimum,
            maximumBPM: maximum
        )
    }

    private func makeRunner(clock: TestMonotonicClock) -> WorkoutRunner {
        WorkoutRunner(
            clock: clock,
            wallNow: {
                Date(timeIntervalSince1970: 1_000 + clock.now)
            }
        )
    }

    private func configuration(
        for phase: ScheduledWorkoutPhase
    ) -> AnnouncementConfiguration {
        AnnouncementConfiguration(
            minimumBPM: phase.minimumBPM,
            maximumBPM: phase.maximumBPM,
            normalInterval: 60,
            warningInterval: 10,
            confirmationDelay: 5
        )
    }

    private func tryPhase(_ phase: ScheduledWorkoutPhase?) -> ScheduledWorkoutPhase {
        guard let phase else {
            Issue.record("Expected a current workout phase")
            return WorkoutPlan().expandedPhases[0]
        }
        return phase
    }
}

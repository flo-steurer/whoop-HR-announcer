import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import WhoopHRAnnouncerCore
#else
@testable import HR_Announcer
#endif

struct WorkoutModelsTests {
    @Test func expandsRepeatGroupsInOrderWithIterationMetadata() {
        let warmup = WorkoutPhase(
            name: "Warm-up",
            durationSeconds: 60,
            minimumBPM: 120,
            maximumBPM: 145
        )
        let fast = WorkoutPhase(
            name: "Fast",
            durationSeconds: 30,
            minimumBPM: 160,
            maximumBPM: 180
        )
        let recovery = WorkoutPhase(
            name: "Recovery",
            durationSeconds: 20,
            minimumBPM: 125,
            maximumBPM: 145
        )
        let plan = WorkoutPlan(
            name: "Intervals",
            blocks: [
                .phase(warmup),
                .repeatGroup(
                    WorkoutRepeatGroup(
                        phases: [fast, recovery],
                        repetitions: 3
                    )
                )
            ]
        )

        #expect(plan.expandedPhases.map(\.name) == [
            "Warm-up", "Fast", "Recovery", "Fast", "Recovery", "Fast", "Recovery"
        ])
        #expect(plan.expandedPhases[1].repetitionNumber == 1)
        #expect(plan.expandedPhases[5].repetitionNumber == 3)
        #expect(plan.expandedPhases[5].repetitionCount == 3)
        #expect(plan.expandedPhaseCount == 7)
        #expect(plan.totalDurationSeconds == 210)
    }

    @Test func planRoundTripsThroughCodable() throws {
        let original = WorkoutPlan(
            name: "Mixed",
            blocks: [
                .phase(WorkoutPhase()),
                .repeatGroup(WorkoutRepeatGroup())
            ]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WorkoutPlan.self, from: data)

        #expect(decoded == original)
    }

    @Test func validationRejectsInvalidPhasesAndGroups() {
        #expect(!WorkoutPhase(name: "", durationSeconds: 60).isValid)
        #expect(!WorkoutPhase(durationSeconds: 0).isValid)
        #expect(!WorkoutPhase(minimumBPM: 160, maximumBPM: 150).isValid)
        #expect(!WorkoutRepeatGroup(phases: [], repetitions: 4).isValid)
        #expect(!WorkoutRepeatGroup(repetitions: 1).isValid)
        #expect(!WorkoutPlan(name: "", blocks: []).isValid)
    }

    @Test func duplicateCreatesIndependentIdentifiers() {
        let original = WorkoutPlan(
            name: "Intervals",
            blocks: [
                .repeatGroup(WorkoutRepeatGroup())
            ]
        )

        let copy = original.duplicated()

        #expect(copy.name == "Intervals Copy")
        #expect(copy.id != original.id)
        #expect(copy.blocks[0].id != original.blocks[0].id)
        #expect(copy.expandedPhases.map(\.sourcePhaseID)
            != original.expandedPhases.map(\.sourcePhaseID))
    }

    @Test func storePersistsCRUDSelectionAndOrdering() throws {
        let suiteName = "WorkoutModelsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = WorkoutPlan(name: "First")
        let second = WorkoutPlan(name: "Second")
        let store = WorkoutPlanStore(defaults: defaults)
        store.add(first)
        store.add(second)
        store.move(from: IndexSet(integer: 1), to: 0)
        let copy = try #require(store.duplicate(planID: first.id))

        #expect(store.plans.map(\.name) == ["Second", "First", "First Copy"])
        #expect(store.selectedPlanID == copy.id)

        store.delete(at: IndexSet(integer: 0))
        let restored = WorkoutPlanStore(defaults: defaults)
        #expect(restored.plans.map(\.name) == ["First", "First Copy"])
        #expect(restored.selectedPlanID == copy.id)
    }

    @Test func storeRoundTripsActiveSnapshotAndRejectsCorruption() throws {
        let suiteName = "WorkoutActiveStoreTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let clock = TestStoreClock()
        let runner = WorkoutRunner(
            clock: clock,
            wallNow: { Date(timeIntervalSince1970: 10_000 + clock.now) }
        )
        runner.start(plan: WorkoutPlan())
        let snapshot = try #require(runner.checkpoint())
        let store = WorkoutPlanStore(defaults: defaults)
        store.saveActiveWorkout(snapshot)

        #expect(store.loadActiveWorkout() == snapshot)
        #expect(!store.discardedInvalidActiveWorkout)

        defaults.set(Data("not-json".utf8), forKey: "activeWorkout.v1")
        #expect(store.loadActiveWorkout() == nil)
        #expect(store.discardedInvalidActiveWorkout)
    }
}

private final class TestStoreClock: MonotonicClock {
    var now: TimeInterval = 100
}

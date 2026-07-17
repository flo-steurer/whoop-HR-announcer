import Foundation
import Combine

final class WorkoutPlanStore: ObservableObject {
    private enum Key {
        static let plans = "workoutPlans.v1"
        static let activeWorkout = "activeWorkout.v1"
        static let selectedMode = "selectedSessionMode"
        static let selectedPlanID = "selectedWorkoutPlanID"
    }

    private struct Versioned<Value: Codable>: Codable {
        let version: Int
        let value: Value
    }

    @Published private(set) var plans: [WorkoutPlan]
    @Published var selectedMode: SessionMode {
        didSet { defaults.set(selectedMode.rawValue, forKey: Key.selectedMode) }
    }
    @Published var selectedPlanID: UUID? {
        didSet {
            defaults.set(selectedPlanID?.uuidString, forKey: Key.selectedPlanID)
        }
    }
    private(set) var discardedInvalidActiveWorkout = false

    private let defaults: UserDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        if let data = defaults.data(forKey: Key.plans),
           let persisted = try? decoder.decode(
               Versioned<[WorkoutPlan]>.self,
               from: data
           ),
           persisted.version == 1 {
            plans = persisted.value
        } else {
            plans = []
        }

        selectedMode = SessionMode(
            rawValue: defaults.string(forKey: Key.selectedMode) ?? ""
        ) ?? .manual
        selectedPlanID = defaults.string(forKey: Key.selectedPlanID)
            .flatMap(UUID.init(uuidString:))

        if selectedPlanID != nil && selectedPlan == nil {
            selectedPlanID = plans.first?.id
        }
    }

    var selectedPlan: WorkoutPlan? {
        plans.first { $0.id == selectedPlanID }
    }

    func add(_ plan: WorkoutPlan) {
        plans.append(plan)
        selectedPlanID = plan.id
        persistPlans()
    }

    func update(_ plan: WorkoutPlan) {
        guard let index = plans.firstIndex(where: { $0.id == plan.id }) else { return }
        plans[index] = plan
        persistPlans()
    }

    @discardableResult
    func duplicate(planID: UUID) -> WorkoutPlan? {
        guard let index = plans.firstIndex(where: { $0.id == planID }) else { return nil }
        let copy = plans[index].duplicated()
        plans.insert(copy, at: index + 1)
        selectedPlanID = copy.id
        persistPlans()
        return copy
    }

    func delete(at offsets: IndexSet) {
        let deletedIDs = Set(offsets.compactMap { plans.indices.contains($0) ? plans[$0].id : nil })
        for index in offsets.sorted().reversed() where plans.indices.contains(index) {
            plans.remove(at: index)
        }
        if let selectedPlanID, deletedIDs.contains(selectedPlanID) {
            self.selectedPlanID = plans.first?.id
        }
        persistPlans()
    }

    func move(from offsets: IndexSet, to destination: Int) {
        plans.moveElements(from: offsets, to: destination)
        persistPlans()
    }

    func saveActiveWorkout(_ snapshot: ActiveWorkoutSnapshot) {
        let persisted = Versioned(version: 1, value: snapshot)
        defaults.set(try? encoder.encode(persisted), forKey: Key.activeWorkout)
    }

    func loadActiveWorkout() -> ActiveWorkoutSnapshot? {
        guard let data = defaults.data(forKey: Key.activeWorkout) else {
            discardedInvalidActiveWorkout = false
            return nil
        }
        guard
              let persisted = try? decoder.decode(
                  Versioned<ActiveWorkoutSnapshot>.self,
                  from: data
              ),
              persisted.version == 1,
              persisted.value.isStructurallyValid
        else {
            discardedInvalidActiveWorkout = true
            defaults.removeObject(forKey: Key.activeWorkout)
            return nil
        }
        discardedInvalidActiveWorkout = false
        return persisted.value
    }

    func clearActiveWorkout() {
        defaults.removeObject(forKey: Key.activeWorkout)
    }

    private func persistPlans() {
        let persisted = Versioned(version: 1, value: plans)
        defaults.set(try? encoder.encode(persisted), forKey: Key.plans)
    }
}

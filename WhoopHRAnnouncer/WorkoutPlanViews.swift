import SwiftUI

struct WorkoutPlanLibraryView: View {
    @ObservedObject var store: WorkoutPlanStore
    @State private var newPlan: WorkoutPlan?

    var body: some View {
        List {
            if store.plans.isEmpty {
                ContentUnavailableView(
                    "No Workout Plans",
                    systemImage: "figure.run",
                    description: Text("Create a plan with timed heart-rate phases.")
                )
            } else {
                ForEach(store.plans) { plan in
                    NavigationLink {
                        WorkoutPlanEditorView(plan: plan) {
                            store.update($0)
                        }
                    } label: {
                        planRow(plan)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            if let index = store.plans.firstIndex(where: { $0.id == plan.id }) {
                                store.delete(at: IndexSet(integer: index))
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            _ = store.duplicate(planID: plan.id)
                        } label: {
                            Label("Duplicate", systemImage: "plus.square.on.square")
                        }
                        .tint(.blue)
                    }
                }
                .onDelete(perform: store.delete)
                .onMove(perform: store.move)
            }
        }
        .navigationTitle("Workout Plans")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !store.plans.isEmpty {
                    EditButton()
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    newPlan = WorkoutPlan()
                } label: {
                    Label("New Plan", systemImage: "plus")
                }
            }
        }
        .sheet(item: $newPlan) { plan in
            NavigationStack {
                WorkoutPlanEditorView(
                    plan: plan,
                    isNew: true
                ) { savedPlan in
                    store.add(savedPlan)
                    newPlan = nil
                }
            }
        }
    }

    private func planRow(_ plan: WorkoutPlan) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(plan.name)
                .font(.headline)
            Text(
                "\(plan.expandedPhaseCount) phases • \(formatWorkoutDuration(plan.totalDurationSeconds))"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

struct WorkoutPlanEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: WorkoutPlan
    @FocusState private var isPlanNameFocused: Bool

    let isNew: Bool
    let onSave: (WorkoutPlan) -> Void

    init(
        plan: WorkoutPlan,
        isNew: Bool = false,
        onSave: @escaping (WorkoutPlan) -> Void
    ) {
        _draft = State(initialValue: plan)
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        List {
            Section("Plan") {
                HStack {
                    TextField("Plan name", text: $draft.name)
                        .focused($isPlanNameFocused)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { isPlanNameFocused = true }
                )
            }

            Section {
                ForEach(draft.blocks.indices, id: \.self) { index in
                    blockRow(at: index)
                }
                .onDelete { draft.blocks.remove(atOffsets: $0) }
                .onMove { draft.blocks.moveElements(from: $0, to: $1) }

                Menu {
                    Button {
                        draft.blocks.append(.phase(WorkoutPhase()))
                    } label: {
                        Label("Phase", systemImage: "timer")
                    }
                    Button {
                        draft.blocks.append(.repeatGroup(WorkoutRepeatGroup()))
                    } label: {
                        Label("Repeat Group", systemImage: "repeat")
                    }
                } label: {
                    Label("Add Block", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            } header: {
                Text("Phases")
            } footer: {
                Text("Repeat groups run their contained phases in order for each repetition.")
            }

            if !draft.isValid {
                Section {
                    Label(
                        "Give the plan and every phase a name, positive duration, and a valid BPM range.",
                        systemImage: "exclamationmark.triangle.fill"
                    )
                    .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle(isNew ? "New Plan" : "Edit Plan")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            if isNew {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(draft)
                    dismiss()
                }
                .disabled(!draft.isValid)
            }
        }
    }

    @ViewBuilder
    private func blockRow(at index: Int) -> some View {
        switch draft.blocks[index] {
        case .phase(let phase):
            NavigationLink {
                WorkoutPhaseEditorView(phase: phaseBinding(at: index))
            } label: {
                phaseRow(phase)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
        case .repeatGroup(let group):
            NavigationLink {
                WorkoutRepeatGroupEditorView(group: groupBinding(at: index))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Label(
                        "Repeat \(group.repetitions) times",
                        systemImage: "repeat"
                    )
                    .font(.headline)
                    Text(
                        "\(group.phases.count) phases • \(formatWorkoutDuration(group.phases.reduce(0) { $0 + $1.durationSeconds } * group.repetitions))"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }

    private func phaseRow(_ phase: WorkoutPhase) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(phase.name)
                .font(.headline)
            Text(
                "\(formatWorkoutDuration(phase.durationSeconds)) • \(phase.minimumBPM)–\(phase.maximumBPM) BPM"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func phaseBinding(at index: Int) -> Binding<WorkoutPhase> {
        Binding {
            guard draft.blocks.indices.contains(index),
                  case .phase(let phase) = draft.blocks[index]
            else { return WorkoutPhase() }
            return phase
        } set: { phase in
            guard draft.blocks.indices.contains(index) else { return }
            draft.blocks[index] = .phase(phase)
        }
    }

    private func groupBinding(at index: Int) -> Binding<WorkoutRepeatGroup> {
        Binding {
            guard draft.blocks.indices.contains(index),
                  case .repeatGroup(let group) = draft.blocks[index]
            else { return WorkoutRepeatGroup() }
            return group
        } set: { group in
            guard draft.blocks.indices.contains(index) else { return }
            draft.blocks[index] = .repeatGroup(group)
        }
    }
}

struct WorkoutRepeatGroupEditorView: View {
    @Binding var group: WorkoutRepeatGroup

    var body: some View {
        List {
            Section("Repeat") {
                Stepper(
                    "Run group \(group.repetitions) times",
                    value: $group.repetitions,
                    in: 2...99
                )
            }

            Section {
                ForEach(group.phases.indices, id: \.self) { index in
                    NavigationLink {
                        WorkoutPhaseEditorView(
                            phase: Binding(
                                get: { group.phases[index] },
                                set: { group.phases[index] = $0 }
                            )
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(group.phases[index].name)
                            Text(
                                "\(formatWorkoutDuration(group.phases[index].durationSeconds)) • \(group.phases[index].minimumBPM)–\(group.phases[index].maximumBPM) BPM"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                }
                .onDelete { group.phases.remove(atOffsets: $0) }
                .onMove { group.phases.moveElements(from: $0, to: $1) }

                Button {
                    group.phases.append(WorkoutPhase())
                } label: {
                    Label("Add Phase", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            } header: {
                Text("Group Phases")
            } footer: {
                if group.phases.isEmpty {
                    Text("A repeat group needs at least one phase.")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Repeat Group")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
        }
    }
}

struct WorkoutPhaseEditorView: View {
    private enum Field: Hashable {
        case name
        case minutes
        case seconds
    }

    @Binding var phase: WorkoutPhase
    @FocusState private var focusedField: Field?

    private var minutes: Binding<Int> {
        Binding {
            phase.durationSeconds / 60
        } set: { newValue in
            let boundedMinutes = min(1_440, max(0, newValue))
            let seconds = boundedMinutes == 1_440 ? 0 : phase.durationSeconds % 60
            phase.durationSeconds = boundedMinutes * 60 + seconds
        }
    }

    private var seconds: Binding<Int> {
        Binding {
            phase.durationSeconds % 60
        } set: { newValue in
            let boundedSeconds = min(59, max(0, newValue))
            let minutes = min(1_440, phase.durationSeconds / 60)
            phase.durationSeconds = min(86_400, minutes * 60 + boundedSeconds)
        }
    }

    var body: some View {
        Form {
            Section("Phase") {
                HStack {
                    TextField("Phase name", text: $phase.name)
                        .focused($focusedField, equals: .name)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture().onEnded { focusedField = .name }
                )
            }

            Section("Duration") {
                HStack {
                    TextField("Minutes", value: minutes, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .minutes)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded { focusedField = .minutes }
                        )
                    Text("min")
                        .foregroundStyle(.secondary)
                    TextField("Seconds", value: seconds, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .seconds)
                        .contentShape(Rectangle())
                        .simultaneousGesture(
                            TapGesture().onEnded { focusedField = .seconds }
                        )
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
                if !(1...86_400).contains(phase.durationSeconds) {
                    Text("Duration must be between 1 second and 24 hours.")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section("Target Heart Rate") {
                Stepper(
                    "Minimum: \(phase.minimumBPM) BPM",
                    value: $phase.minimumBPM,
                    in: 30...max(30, phase.maximumBPM - 1)
                )
                Stepper(
                    "Maximum: \(phase.maximumBPM) BPM",
                    value: $phase.maximumBPM,
                    in: min(240, phase.minimumBPM + 1)...240
                )
            }
        }
        .navigationTitle("Edit Phase")
        .navigationBarTitleDisplayMode(.inline)
    }
}

func formatWorkoutDuration(_ totalSeconds: Int) -> String {
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let seconds = totalSeconds % 60
    if hours > 0 {
        return seconds > 0
            ? "\(hours)h \(minutes)m \(seconds)s"
            : "\(hours)h \(minutes)m"
    }
    if minutes > 0 {
        return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
    }
    return "\(seconds)s"
}

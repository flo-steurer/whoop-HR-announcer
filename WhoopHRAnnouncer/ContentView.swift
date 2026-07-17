import SwiftUI

struct ContentView: View {
    private enum BPMField: Hashable {
        case minimum
        case maximum
    }

    @ObservedObject var model: AppModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var workoutStore: WorkoutPlanStore
    @State private var showingDevices = false
    @FocusState private var focusedBPMField: BPMField?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    heartRateCard

                    if model.activeSessionMode == .workout {
                        TimelineView(.periodic(from: .now, by: 1)) { _ in
                            if let presentation = model.workoutPresentation {
                                workoutCard(presentation)
                            }
                        }
                    } else {
                        if !model.isSessionActive {
                            modeCard
                        }
                        if model.isSessionActive || workoutStore.selectedMode == .manual {
                            settingsCard
                        } else {
                            workoutSelectionCard
                        }
                        sessionControls
                    }

                    if model.activeSessionMode == .workout {
                        chooseDeviceButton
                    }
                    setupCard
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("HR Announcer")
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focusedBPMField = nil }
                }
            }
            .sheet(isPresented: $showingDevices, onDismiss: model.stopScanning) {
                devicePicker
            }
        }
    }

    private var heartRateCard: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                Circle()
                    .fill(model.connectionStatus.isConnected ? Color.green : Color.orange)
                    .frame(width: 9, height: 9)
                Text(model.connectionStatus.title)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(alignment: .firstTextBaseline, spacing: 7) {
                Text(model.currentHeartRate.map(String.init) ?? "—")
                    .font(.system(size: 72, weight: .bold, design: .rounded))
                    .contentTransition(.numericText())
                Text("BPM")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(zoneTitle)
                .font(.title3.weight(.semibold))
                .foregroundStyle(zoneColor)

            if let lastUpdated = model.lastUpdated {
                Text("Last sensor reading: \(lastUpdated.formatted(date: .omitted, time: .standard))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let audioIssue = model.audioIssue {
                Label(audioIssue, systemImage: "speaker.slash.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.background, in: RoundedRectangle(cornerRadius: 20))
    }

    private var modeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Session", systemImage: "figure.run")
                .font(.headline)
            Picker("Session type", selection: $workoutStore.selectedMode) {
                ForEach(SessionMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var workoutSelectionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Workout Plan", systemImage: "list.bullet.rectangle")
                .font(.headline)

            if workoutStore.plans.isEmpty {
                Text("Create a plan before starting a planned workout.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Plan", selection: $workoutStore.selectedPlanID) {
                    Text("Choose a plan").tag(nil as UUID?)
                    ForEach(workoutStore.plans) { plan in
                        Text(plan.name).tag(plan.id as UUID?)
                    }
                }
                .pickerStyle(.navigationLink)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())

                if let plan = workoutStore.selectedPlan {
                    Text(
                        "\(plan.expandedPhaseCount) phases • \(formatWorkoutDuration(plan.totalDurationSeconds))"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
            }

            NavigationLink {
                WorkoutPlanLibraryView(store: workoutStore)
            } label: {
                Label("Manage Workout Plans", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var sessionControls: some View {
        VStack(spacing: 12) {
            Button {
                model.isSessionActive ? model.stopSession() : model.startSession()
            } label: {
                Label(
                    sessionButtonTitle,
                    systemImage: model.isSessionActive ? "stop.fill" : "speaker.wave.2.fill"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.borderedProminent)
            .tint(model.isSessionActive ? .red : .accentColor)
            .disabled(startIsDisabled)

            chooseDeviceButton
        }
    }

    private var chooseDeviceButton: some View {
        Button {
            showingDevices = true
            model.scanForDevices()
        } label: {
            Label(
                model.selectedDeviceName.map { "WHOOP: \($0)" } ?? "Choose WHOOP",
                systemImage: "dot.radiowaves.left.and.right"
            )
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bordered)
    }

    private func workoutCard(_ presentation: WorkoutPresentation) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label(
                    presentation.status == .paused ? "Workout Paused" : presentation.planName,
                    systemImage: presentation.status == .paused ? "pause.circle.fill" : "figure.run"
                )
                .font(.headline)
                Spacer()
                Text("\(Int((presentation.overallProgress * 100).rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.currentPhase.name)
                    .font(.title2.weight(.bold))
                if let iterationText = presentation.currentPhase.iterationText {
                    Text(iterationText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text(
                    "Target \(presentation.currentPhase.minimumBPM)–\(presentation.currentPhase.maximumBPM) BPM"
                )
                .font(.headline)
                .foregroundStyle(.tint)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(formatCountdown(presentation.remainingSeconds))
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text("remaining")
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: presentation.overallProgress)

            HStack {
                Text("Up next")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(presentation.upcomingPhase?.name ?? "Finish")
                    .fontWeight(.semibold)
            }
            .font(.subheadline)

            HStack(spacing: 10) {
                Button(action: model.previousWorkoutPhase) {
                    Label("Previous", systemImage: "backward.end.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Previous phase")
                Button {
                    model.isWorkoutPaused
                        ? model.resumeWorkout()
                        : model.pauseWorkout()
                } label: {
                    Label(
                        model.isWorkoutPaused ? "Resume" : "Pause",
                        systemImage: model.isWorkoutPaused ? "play.fill" : "pause.fill"
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                Button(action: model.nextWorkoutPhase) {
                    Label("Next", systemImage: "forward.end.fill")
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Next phase")
            }
            .buttonStyle(.bordered)

            Button(role: .destructive, action: model.stopSession) {
                Label("Stop Workout", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)

            NavigationLink {
                WorkoutPlanLibraryView(store: workoutStore)
            } label: {
                Label("Manage Workout Plans", systemImage: "list.bullet")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var settingsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Announcements", systemImage: "slider.horizontal.3")
                .font(.headline)

            bpmControl(
                title: "Minimum",
                value: $settings.minimumBPM,
                allowedRange: 30...(settings.maximumBPM - 1),
                field: .minimum
            )
            bpmControl(
                title: "Maximum",
                value: $settings.maximumBPM,
                allowedRange: (settings.minimumBPM + 1)...240,
                field: .maximum
            )

            if !settings.isValid {
                Label("Minimum must be lower than maximum.", systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Divider()
            intervalStepper(
                title: "Normal interval",
                value: $settings.normalInterval,
                range: 15...600,
                step: 15
            )
            intervalStepper(
                title: "Outside-range interval",
                value: $settings.warningInterval,
                range: 5...120,
                step: 5
            )
            intervalStepper(
                title: "Boundary confirmation",
                value: $settings.confirmationDelay,
                range: 0...15,
                step: 1
            )

            Picker("Other audio", selection: $settings.audioMode) {
                ForEach(OtherAudioMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.menu)
        }
        .padding()
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Before you run", systemImage: "info.circle.fill")
                .font(.headline)
            Text("In the WHOOP app, open Device Settings and enable Heart Rate Broadcast. Keep this app's announcing session running when you lock your phone.")
            Text("If you manually force-quit this app, iOS stops Bluetooth background monitoring until you open it again.")
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var devicePicker: some View {
        NavigationStack {
            List {
                if model.devices.isEmpty {
                    HStack {
                        ProgressView()
                        Text("Searching… Make sure HR Broadcast is enabled.")
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ForEach(model.devices) { device in
                        Button {
                            model.selectDevice(device)
                            showingDevices = false
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(device.name)
                                    Text(device.id.uuidString)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: signalIcon(for: device.signalStrength))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
            .navigationTitle("Choose WHOOP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { showingDevices = false }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Rescan") { model.scanForDevices() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func intervalStepper(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double
    ) -> some View {
        Stepper(value: value, in: range, step: step) {
            Text("\(title): \(Int(value.wrappedValue)) sec")
        }
    }

    private func bpmControl(
        title: String,
        value: Binding<Int>,
        allowedRange: ClosedRange<Int>,
        field: BPMField
    ) -> some View {
        let boundedValue = Binding<Int>(
            get: { value.wrappedValue },
            set: { newValue in
                value.wrappedValue = min(
                    max(newValue, allowedRange.lowerBound),
                    allowedRange.upperBound
                )
            }
        )
        let sliderValue = Binding<Double>(
            get: { Double(value.wrappedValue) },
            set: { newValue in
                boundedValue.wrappedValue = Int(newValue.rounded())
            }
        )

        return VStack(spacing: 8) {
            HStack {
                Text(title)
                Spacer()
                TextField("BPM", value: boundedValue, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 68)
                    .contentShape(Rectangle())
                    .focused($focusedBPMField, equals: field)
                Text("BPM")
                    .foregroundStyle(.secondary)
            }

            Slider(
                value: sliderValue,
                in: Double(allowedRange.lowerBound)...Double(allowedRange.upperBound),
                step: 1
            )
            .accessibilityLabel("\(title) heart rate")
            .accessibilityValue("\(value.wrappedValue) beats per minute")
        }
    }

    private var startIsDisabled: Bool {
        if model.isSessionActive { return false }
        switch workoutStore.selectedMode {
        case .manual: return !settings.isValid
        case .workout: return !(workoutStore.selectedPlan?.isValid ?? false)
        }
    }

    private var sessionButtonTitle: String {
        if model.isSessionActive { return "Stop Announcing" }
        return workoutStore.selectedMode == .workout
            ? "Start Workout"
            : "Start Announcing"
    }

    private var zoneTitle: String {
        guard model.currentHeartRate != nil else { return "Waiting for heart rate" }
        switch model.currentZone {
        case .belowRange: return "Below range"
        case .inRange: return "In range"
        case .aboveRange: return "Above range"
        case nil: return "Confirming range…"
        }
    }

    private var zoneColor: Color {
        switch model.currentZone {
        case .inRange: return .green
        case .belowRange, .aboveRange: return .orange
        case nil: return .secondary
        }
    }

    private func formatCountdown(_ seconds: TimeInterval) -> String {
        let rounded = max(0, Int(ceil(seconds)))
        return String(format: "%02d:%02d", rounded / 60, rounded % 60)
    }

    private func signalIcon(for rssi: Int) -> String {
        if rssi >= -60 { return "wifi" }
        if rssi >= -80 { return "wifi.exclamationmark" }
        return "antenna.radiowaves.left.and.right.slash"
    }
}

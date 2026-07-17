import Foundation
import Combine

final class AppModel: ObservableObject {
    static let sessionActiveKey = "announcementSessionActive"

    @Published private(set) var connectionStatus: HeartRateConnectionStatus = .unavailable("Bluetooth is starting")
    @Published private(set) var devices: [DiscoveredHeartRateDevice] = []
    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var currentZone: HeartRateZoneState?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var audioIssue: String?
    @Published private(set) var isSessionActive: Bool
    @Published private(set) var activeSessionMode: SessionMode?
    @Published private(set) var selectedDeviceName: String?
    @Published private(set) var workoutRevision = 0

    private let settings: AppSettings
    private let workoutStore: WorkoutPlanStore
    private let bluetooth: BluetoothHeartRateManager
    private let speech = SpeechAnnouncer()
    private let clock: MonotonicClock
    private let runner: WorkoutRunner
    private var announcementCoordinator = SessionAnnouncementCoordinator()
    private let defaults: UserDefaults
    private var lastWorkoutCheckpointAt: TimeInterval?

    init(
        settings: AppSettings,
        workoutStore: WorkoutPlanStore,
        defaults: UserDefaults = .standard,
        clock: MonotonicClock = SystemMonotonicClock(),
        wallNow: @escaping () -> Date = Date.init
    ) {
        self.settings = settings
        self.workoutStore = workoutStore
        self.defaults = defaults
        self.clock = clock
        runner = WorkoutRunner(clock: clock, wallNow: wallNow)
        bluetooth = BluetoothHeartRateManager(defaults: defaults)
        isSessionActive = defaults.bool(forKey: Self.sessionActiveKey)
        activeSessionMode = isSessionActive ? .manual : nil
        selectedDeviceName = bluetooth.rememberedDeviceName

        var restoredPhaseAnnouncement: String?
        var restoredCompletion = false
        if let snapshot = workoutStore.loadActiveWorkout() {
            let update = runner.restore(snapshot)
            if update.completed {
                restoredCompletion = true
                isSessionActive = false
                activeSessionMode = nil
                defaults.set(false, forKey: Self.sessionActiveKey)
                workoutStore.clearActiveWorkout()
            } else if runner.state != nil {
                isSessionActive = true
                activeSessionMode = .workout
                defaults.set(true, forKey: Self.sessionActiveKey)
                if runner.state?.status == .running, update.phaseChanged {
                    restoredPhaseAnnouncement = update.currentPhase?.targetText
                }
                persistWorkout(force: true)
            }
        } else if workoutStore.discardedInvalidActiveWorkout {
            isSessionActive = false
            activeSessionMode = nil
            defaults.set(false, forKey: Self.sessionActiveKey)
        }

        bluetooth.onStatusChange = { [weak self] status in
            self?.connectionStatus = status
        }
        bluetooth.onDevicesChange = { [weak self] devices in
            self?.devices = devices
        }
        bluetooth.onHeartRate = { [weak self] bpm in
            self?.receive(bpm: bpm)
        }
        bluetooth.onDisconnect = { [weak self] in
            self?.handleDisconnect()
        }
        speech.onAudioSessionStatus = { [weak self] issue in
            self?.audioIssue = issue
        }

        if restoredCompletion {
            DispatchQueue.main.async { [weak self] in
                self?.speech.speak(
                    "Workout complete",
                    audioMode: self?.settings.audioMode ?? .duck
                )
            }
        } else if isSessionActive {
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.bluetooth.startSession()
                if let restoredPhaseAnnouncement {
                    self.speech.speak(
                        restoredPhaseAnnouncement,
                        audioMode: self.settings.audioMode
                    )
                }
            }
        }
    }

    var workoutPresentation: WorkoutPresentation? {
        _ = workoutRevision
        return runner.presentation
    }

    var isWorkoutPaused: Bool {
        runner.state?.status == .paused
    }

    func startSession() {
        switch workoutStore.selectedMode {
        case .manual:
            startManualSession()
        case .workout:
            guard let plan = workoutStore.selectedPlan, plan.isValid else { return }
            startWorkout(plan)
        }
    }

    func stopSession() {
        isSessionActive = false
        activeSessionMode = nil
        defaults.set(false, forKey: Self.sessionActiveKey)
        runner.stop()
        workoutStore.clearActiveWorkout()
        bluetooth.stopSession()
        speech.stop()
        audioIssue = nil
        announcementCoordinator.reset()
        currentHeartRate = nil
        currentZone = nil
        lastUpdated = nil
        workoutRevision += 1
    }

    func pauseWorkout() {
        guard activeSessionMode == .workout else { return }
        let update = runner.pause()
        if update.completed {
            completeWorkout()
            return
        }

        speech.stop()
        announcementCoordinator.reset()
        currentZone = currentHeartRate.flatMap { bpm in
            currentConfiguration.map { configuration in
                AnnouncementEngine.classify(bpm: bpm, configuration: configuration)
            }
        }
        persistWorkout(force: true)
        workoutRevision += 1
    }

    func resumeWorkout() {
        guard activeSessionMode == .workout,
              runner.state?.status == .paused
        else { return }

        let update = runner.resume()
        announcementCoordinator.reset()
        persistWorkout(force: true)
        workoutRevision += 1
        if let phase = update.currentPhase {
            speech.speak(phase.targetText, audioMode: settings.audioMode)
        }
    }

    func previousWorkoutPhase() {
        changeWorkoutPhase(using: runner.previous)
    }

    func nextWorkoutPhase() {
        changeWorkoutPhase(using: runner.next)
    }

    func refreshWorkout() {
        guard activeSessionMode == .workout,
              runner.state?.status == .running
        else { return }

        let update = runner.advance()
        if update.completed {
            completeWorkout()
            return
        }

        guard update.phaseChanged, let phase = update.currentPhase else { return }
        announcePhaseChange(phase)
        persistWorkout(force: true)
        workoutRevision += 1
    }

    func checkpointWorkout() {
        persistWorkout(force: true)
    }

    func scanForDevices() {
        bluetooth.scan()
    }

    func stopScanning() {
        bluetooth.stopScanning()
    }

    func selectDevice(_ device: DiscoveredHeartRateDevice) {
        selectedDeviceName = device.name
        bluetooth.select(deviceID: device.id)
        if isSessionActive {
            // Selecting connects immediately; startSession also enables future reconnects.
            bluetooth.startSession()
        }
    }

    private func startManualSession() {
        guard settings.isValid else { return }
        runner.stop()
        workoutStore.clearActiveWorkout()
        speech.prepare(audioMode: settings.audioMode)
        announcementCoordinator.reset()
        currentZone = nil
        activeSessionMode = .manual
        isSessionActive = true
        defaults.set(true, forKey: Self.sessionActiveKey)
        bluetooth.startSession()
    }

    private func startWorkout(_ plan: WorkoutPlan) {
        let update = runner.start(plan: plan)
        guard let firstPhase = update.currentPhase else { return }

        speech.prepare(audioMode: settings.audioMode)
        announcementCoordinator.reset()
        currentZone = nil
        activeSessionMode = .workout
        isSessionActive = true
        defaults.set(true, forKey: Self.sessionActiveKey)
        persistWorkout(force: true)
        workoutRevision += 1
        bluetooth.startSession()
        speech.speak(firstPhase.targetText, audioMode: settings.audioMode)
    }

    private func receive(bpm: Int) {
        currentHeartRate = bpm
        lastUpdated = Date()

        guard isSessionActive else {
            currentZone = AnnouncementEngine.classify(
                bpm: bpm,
                configuration: settings.announcementConfiguration
            )
            return
        }

        switch activeSessionMode {
        case .workout:
            receiveWorkoutHeartRate(bpm)
        case .manual:
            guard settings.isValid else { return }
            let output = announcementCoordinator.ingest(
                bpm: bpm,
                at: clock.now,
                configuration: settings.announcementConfiguration
            )
            currentZone = output.zone
            if let spokenText = output.spokenText {
                speech.speak(spokenText, audioMode: settings.audioMode)
            }
        case nil:
            break
        }
    }

    private func receiveWorkoutHeartRate(_ bpm: Int) {
        if runner.state?.status == .paused {
            guard let configuration = currentConfiguration else { return }
            let output = announcementCoordinator.ingest(
                bpm: bpm,
                at: clock.now,
                configuration: configuration,
                suppressSpeech: true
            )
            currentZone = output.zone
            return
        }

        let update = runner.advance()
        if update.completed {
            completeWorkout()
            return
        }

        guard let configuration = currentConfiguration else {
            stopSession()
            return
        }
        let output = announcementCoordinator.ingest(
            bpm: bpm,
            at: clock.now,
            configuration: configuration,
            phaseAnnouncement: update.phaseChanged
                ? update.currentPhase?.targetText
                : nil
        )
        currentZone = output.zone
        if let spokenText = output.spokenText {
            speech.speak(spokenText, audioMode: settings.audioMode)
        }

        persistWorkout(force: update.phaseChanged)
        if update.phaseChanged {
            workoutRevision += 1
        }
    }

    private func changeWorkoutPhase(
        using operation: () -> WorkoutRunUpdate
    ) {
        guard activeSessionMode == .workout else { return }
        let update = operation()
        if update.completed {
            completeWorkout()
            return
        }

        if let phase = update.currentPhase,
           runner.state?.status == .running {
            announcePhaseChange(phase)
        } else if let bpm = currentHeartRate,
                  let configuration = currentConfiguration {
            currentZone = AnnouncementEngine.classify(
                bpm: bpm,
                configuration: configuration
            )
        }
        persistWorkout(force: true)
        workoutRevision += 1
    }

    private func announcePhaseChange(_ phase: ScheduledWorkoutPhase) {
        if let bpm = currentHeartRate {
            let output = announcementCoordinator.ingest(
                bpm: bpm,
                at: clock.now,
                configuration: configuration(for: phase),
                phaseAnnouncement: phase.targetText
            )
            currentZone = output.zone
            if let spokenText = output.spokenText {
                speech.speak(spokenText, audioMode: settings.audioMode)
            }
        } else {
            speech.speak(phase.targetText, audioMode: settings.audioMode)
        }
    }

    private func completeWorkout() {
        isSessionActive = false
        activeSessionMode = nil
        defaults.set(false, forKey: Self.sessionActiveKey)
        runner.stop()
        workoutStore.clearActiveWorkout()
        bluetooth.stopSession()
        announcementCoordinator.reset()
        currentHeartRate = nil
        currentZone = nil
        lastUpdated = nil
        workoutRevision += 1
        speech.speak("Workout complete", audioMode: settings.audioMode)
    }

    private var currentConfiguration: AnnouncementConfiguration? {
        guard let phase = runner.currentPhase else { return nil }
        return configuration(for: phase)
    }

    private func configuration(
        for phase: ScheduledWorkoutPhase
    ) -> AnnouncementConfiguration {
        var configuration = settings.announcementConfiguration
        configuration.minimumBPM = phase.minimumBPM
        configuration.maximumBPM = phase.maximumBPM
        return configuration
    }

    private func persistWorkout(force: Bool) {
        guard activeSessionMode == .workout else { return }
        let now = clock.now
        if !force,
           let lastWorkoutCheckpointAt,
           now - lastWorkoutCheckpointAt < 15 {
            return
        }
        guard let snapshot = runner.checkpoint() else { return }
        workoutStore.saveActiveWorkout(snapshot)
        lastWorkoutCheckpointAt = now
    }

    private func handleDisconnect() {
        currentHeartRate = nil
        currentZone = nil
        lastUpdated = nil
        announcementCoordinator.reset()
        if isSessionActive,
           activeSessionMode != .workout || runner.state?.status == .running {
            speech.speak(
                "Heart-rate monitor disconnected",
                audioMode: settings.audioMode
            )
        }
    }
}

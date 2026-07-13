import Foundation
import Combine

final class AppModel: ObservableObject {
    static let sessionActiveKey = "announcementSessionActive"

    @Published private(set) var connectionStatus: HeartRateConnectionStatus = .unavailable("Bluetooth is starting")
    @Published private(set) var devices: [DiscoveredHeartRateDevice] = []
    @Published private(set) var currentHeartRate: Int?
    @Published private(set) var currentZone: HeartRateZoneState?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var isSessionActive: Bool
    @Published private(set) var selectedDeviceName: String?

    private let settings: AppSettings
    private let bluetooth: BluetoothHeartRateManager
    private let speech = SpeechAnnouncer()
    private var engine = AnnouncementEngine()
    private let defaults: UserDefaults

    init(settings: AppSettings, defaults: UserDefaults = .standard) {
        self.settings = settings
        self.defaults = defaults
        bluetooth = BluetoothHeartRateManager(defaults: defaults)
        isSessionActive = defaults.bool(forKey: Self.sessionActiveKey)
        selectedDeviceName = bluetooth.rememberedDeviceName

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

        if isSessionActive {
            DispatchQueue.main.async { [weak self] in
                self?.bluetooth.startSession()
            }
        }
    }

    func startSession() {
        guard settings.isValid else { return }
        engine.reset()
        currentZone = nil
        isSessionActive = true
        defaults.set(true, forKey: Self.sessionActiveKey)
        bluetooth.startSession()
    }

    func stopSession() {
        isSessionActive = false
        defaults.set(false, forKey: Self.sessionActiveKey)
        bluetooth.stopSession()
        speech.stop()
        engine.reset()
        currentHeartRate = nil
        currentZone = nil
        lastUpdated = nil
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

    private func receive(bpm: Int) {
        currentHeartRate = bpm
        lastUpdated = Date()

        guard isSessionActive, settings.isValid else {
            currentZone = AnnouncementEngine.classify(
                bpm: bpm,
                configuration: settings.announcementConfiguration
            )
            return
        }

        let event = engine.ingest(
            bpm: bpm,
            at: ProcessInfo.processInfo.systemUptime,
            configuration: settings.announcementConfiguration
        )
        currentZone = engine.stableState

        if let event {
            speech.speak(event.spokenText, audioMode: settings.audioMode)
        }
    }

    private func handleDisconnect() {
        currentHeartRate = nil
        currentZone = nil
        lastUpdated = nil
        engine.reset()
        if isSessionActive {
            speech.speak("Heart-rate monitor disconnected", audioMode: settings.audioMode)
        }
    }
}

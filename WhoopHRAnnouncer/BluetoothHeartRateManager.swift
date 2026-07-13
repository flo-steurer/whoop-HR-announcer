import Foundation
import CoreBluetooth

enum HeartRateConnectionStatus: Equatable {
    case unavailable(String)
    case ready
    case scanning
    case connecting(String)
    case connected(String)
    case reconnecting(String)

    var title: String {
        switch self {
        case .unavailable(let reason): return reason
        case .ready: return "Ready to connect"
        case .scanning: return "Searching for heart-rate monitors"
        case .connecting(let name): return "Connecting to \(name)"
        case .connected(let name): return "Connected to \(name)"
        case .reconnecting(let name): return "Reconnecting to \(name)"
        }
    }

    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }
}

struct DiscoveredHeartRateDevice: Identifiable, Equatable {
    let id: UUID
    let name: String
    let signalStrength: Int
}

final class BluetoothHeartRateManager: NSObject {
    static let heartRateService = CBUUID(string: "180D")
    static let heartRateMeasurement = CBUUID(string: "2A37")

    var onStatusChange: ((HeartRateConnectionStatus) -> Void)?
    var onDevicesChange: (([DiscoveredHeartRateDevice]) -> Void)?
    var onHeartRate: ((Int) -> Void)?
    var onDisconnect: (() -> Void)?

    private enum DefaultsKey {
        static let peripheralID = "selectedPeripheralID"
        static let peripheralName = "selectedPeripheralName"
    }

    private lazy var central: CBCentralManager = CBCentralManager(
        delegate: self,
        queue: .main,
        options: [CBCentralManagerOptionRestoreIdentifierKey: "WhoopHRAnnouncer.Central"]
    )
    private var selectedPeripheral: CBPeripheral?
    private var peripherals: [UUID: CBPeripheral] = [:]
    private var discoveredDevices: [UUID: DiscoveredHeartRateDevice] = [:]
    private var reconnectWhenDisconnected = false
    private var scanWhenReady = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        super.init()
        _ = central
    }

    var rememberedDeviceName: String? {
        defaults.string(forKey: DefaultsKey.peripheralName)
    }

    func scan() {
        discoveredDevices.removeAll()
        onDevicesChange?([])
        guard central.state == .poweredOn else {
            scanWhenReady = true
            publishState(central.state)
            return
        }

        central.stopScan()
        onStatusChange?(.scanning)
        central.scanForPeripherals(
            withServices: [Self.heartRateService],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
    }

    func stopScanning() {
        central.stopScan()
        if let selectedPeripheral, selectedPeripheral.state == .connected {
            onStatusChange?(.connected(displayName(for: selectedPeripheral)))
        } else {
            onStatusChange?(.ready)
        }
    }

    func select(deviceID: UUID) {
        guard let peripheral = peripherals[deviceID] else { return }
        remember(peripheral)
        // Persistent reconnects begin only when the user starts an announcing session.
        reconnectWhenDisconnected = false
        connect(peripheral)
    }

    func startSession() {
        reconnectWhenDisconnected = true
        connectRememberedDeviceOrScan()
    }

    func stopSession() {
        reconnectWhenDisconnected = false
        scanWhenReady = false
        central.stopScan()
        if let selectedPeripheral {
            central.cancelPeripheralConnection(selectedPeripheral)
        }
        selectedPeripheral = nil
        onStatusChange?(.ready)
    }

    private func connectRememberedDeviceOrScan() {
        guard central.state == .poweredOn else {
            scanWhenReady = true
            publishState(central.state)
            return
        }

        if let selectedPeripheral {
            connect(selectedPeripheral)
            return
        }

        if let idString = defaults.string(forKey: DefaultsKey.peripheralID),
           let id = UUID(uuidString: idString),
           let peripheral = central.retrievePeripherals(withIdentifiers: [id]).first {
            remember(peripheral)
            connect(peripheral)
            return
        }

        scan()
    }

    private func connect(_ peripheral: CBPeripheral) {
        central.stopScan()
        selectedPeripheral = peripheral
        peripheral.delegate = self
        let name = displayName(for: peripheral)

        if peripheral.state == .connected {
            onStatusChange?(.connected(name))
            peripheral.discoverServices([Self.heartRateService])
        } else {
            onStatusChange?(.connecting(name))
            central.connect(peripheral)
        }
    }

    private func remember(_ peripheral: CBPeripheral) {
        selectedPeripheral = peripheral
        peripherals[peripheral.identifier] = peripheral
        defaults.set(peripheral.identifier.uuidString, forKey: DefaultsKey.peripheralID)
        defaults.set(displayName(for: peripheral), forKey: DefaultsKey.peripheralName)
    }

    private func displayName(for peripheral: CBPeripheral) -> String {
        peripheral.name ?? defaults.string(forKey: DefaultsKey.peripheralName) ?? "WHOOP"
    }

    private func publishState(_ state: CBManagerState) {
        switch state {
        case .poweredOn:
            onStatusChange?(.ready)
        case .poweredOff:
            onStatusChange?(.unavailable("Bluetooth is off"))
        case .unauthorized:
            onStatusChange?(.unavailable("Bluetooth permission denied"))
        case .unsupported:
            onStatusChange?(.unavailable("Bluetooth is unsupported"))
        case .resetting:
            onStatusChange?(.unavailable("Bluetooth is resetting"))
        case .unknown:
            onStatusChange?(.unavailable("Bluetooth is starting"))
        @unknown default:
            onStatusChange?(.unavailable("Bluetooth unavailable"))
        }
    }
}

extension BluetoothHeartRateManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        publishState(central.state)
        if central.state == .poweredOn && scanWhenReady {
            scanWhenReady = false
            if reconnectWhenDisconnected {
                connectRememberedDeviceOrScan()
            } else {
                scan()
            }
        }
    }

    func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        peripherals[peripheral.identifier] = peripheral
        let advertisedName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        let name = advertisedName ?? peripheral.name ?? "Heart Rate Monitor"
        discoveredDevices[peripheral.identifier] = DiscoveredHeartRateDevice(
            id: peripheral.identifier,
            name: name,
            signalStrength: RSSI.intValue
        )
        onDevicesChange?(
            discoveredDevices.values.sorted {
                if $0.signalStrength == $1.signalStrength { return $0.name < $1.name }
                return $0.signalStrength > $1.signalStrength
            }
        )
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        remember(peripheral)
        onStatusChange?(.connected(displayName(for: peripheral)))
        peripheral.discoverServices([Self.heartRateService])
    }

    func centralManager(
        _ central: CBCentralManager,
        didFailToConnect peripheral: CBPeripheral,
        error: Error?
    ) {
        guard reconnectWhenDisconnected else {
            onStatusChange?(.ready)
            return
        }
        onStatusChange?(.reconnecting(displayName(for: peripheral)))
        central.connect(peripheral)
    }

    func centralManager(
        _ central: CBCentralManager,
        didDisconnectPeripheral peripheral: CBPeripheral,
        error: Error?
    ) {
        onDisconnect?()
        guard reconnectWhenDisconnected else {
            onStatusChange?(.ready)
            return
        }
        onStatusChange?(.reconnecting(displayName(for: peripheral)))
        central.connect(peripheral)
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        guard let restored = dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral],
              let peripheral = restored.first else { return }
        remember(peripheral)
        peripheral.delegate = self
        reconnectWhenDisconnected = defaults.bool(forKey: AppModel.sessionActiveKey)
        if peripheral.state == .connected {
            onStatusChange?(.connected(displayName(for: peripheral)))
            peripheral.discoverServices([Self.heartRateService])
        }
    }
}

extension BluetoothHeartRateManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil,
              let service = peripheral.services?.first(where: { $0.uuid == Self.heartRateService })
        else { return }
        peripheral.discoverCharacteristics([Self.heartRateMeasurement], for: service)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didDiscoverCharacteristicsFor service: CBService,
        error: Error?
    ) {
        guard error == nil,
              let characteristic = service.characteristics?.first(where: {
                  $0.uuid == Self.heartRateMeasurement
              })
        else { return }
        peripheral.setNotifyValue(true, for: characteristic)
    }

    func peripheral(
        _ peripheral: CBPeripheral,
        didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil,
              characteristic.uuid == Self.heartRateMeasurement,
              let data = characteristic.value,
              let bpm = HeartRatePacketParser.parse(data)
        else { return }
        onHeartRate?(bpm)
    }
}

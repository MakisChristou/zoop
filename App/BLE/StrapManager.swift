import Combine
import CoreBluetooth
import Foundation
import OSLog
import SnoopProtocol

/// Owns the Bluetooth link to the strap.
///
/// The official WHOOP app bonds the strap to the phone at the OS level; this manager
/// rides that bond: it looks for an already-connected or known peripheral exposing the
/// `fd4b` service, subscribes to the four notification channels, sends the client hello,
/// and from then on turns every notification into complete frames. Every frame is
/// handed to `onFrame` (for the queue) and decoded for the live view and the offload
/// loop.
final class StrapManager: NSObject, ObservableObject {
    enum State: Equatable {
        case bluetoothOff, scanning, connecting, connected, ready
        case failed(String)
    }

    @Published private(set) var state: State = .scanning
    @Published private(set) var serial = ""
    @Published private(set) var model = ""
    @Published private(set) var firmware: String?
    @Published private(set) var liveHeartRate: UInt8?
    @Published private(set) var liveRR: [UInt16] = []
    /// When the live heart rate was last updated, for "x s ago" and smoothing.
    @Published private(set) var liveUpdatedAt: Date?
    /// Recent live samples (time, bpm) for a stable displayed value.
    @Published private(set) var recentHeartRates: [(Date, UInt8)] = []
    @Published private(set) var realtimeStreaming = false
    @Published private(set) var started = false
    @Published private(set) var lastBiometric: Biometric?
    @Published private(set) var batteryPercent: Double?
    @Published private(set) var batteryUpdatedAt: Date?
    @Published private(set) var framesReceived = 0
    @Published private(set) var offloadChunks = 0
    @Published private(set) var lastDataRange: DataRange?

    /// Called with every complete frame and the notify channel it arrived on (3,4,5,7).
    var onFrame: ((_ bytes: [UInt8], _ channel: Int) -> Void)?

    static let restoreIdentifier = "snoop.strap"
    private let log = Logger(subsystem: "snoop", category: "ble")
    static let offloadInterval: TimeInterval = 600

    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var reassemblers: [CBUUID: Reassembler] = [:]
    private var sequence: UInt8 = 1
    private var offloadTimer: Timer?

    private let serviceUUID = CBUUID(string: GATT.service)
    private let commandUUID = CBUUID(string: GATT.commandWrite)
    private let notifyUUIDs = GATT.notifyCharacteristics.map(CBUUID.init(string:))
    private let channelByUUID: [CBUUID: Int] = [
        CBUUID(string: GATT.notifyCommandResponse): 3,
        CBUUID(string: GATT.notifyEvents): 4,
        CBUUID(string: GATT.notifyData): 5,
        CBUUID(string: GATT.notifyDiagnostics): 7,
    ]

    override init() {
        super.init()
    }

    /// Creates the central manager, which triggers the system Bluetooth permission
    /// prompt. Called after onboarding has explained why, or at launch once onboarded.
    func start() {
        guard !started else { return }
        started = true
        central = CBCentralManager(delegate: self, queue: nil, options: [
            CBCentralManagerOptionRestoreIdentifierKey: Self.restoreIdentifier,
            CBCentralManagerOptionShowPowerAlertKey: true,
        ])
    }

    /// Turns the beat-by-beat stream on or off. On while the Today screen is visible.
    func setRealtimeHeartRate(_ on: Bool) {
        guard state == .ready, realtimeStreaming != on else { return }
        realtimeStreaming = on
        send(Command.toggleRealtimeHeartRate(on, sequence: nextSequence()))
    }

    /// Median of the live readings from the last ten seconds, so the hero number does
    /// not flicker with every beat.
    var smoothedHeartRate: UInt8? {
        let cutoff = Date().addingTimeInterval(-10)
        let recent = recentHeartRates.filter { $0.0 >= cutoff }.map(\.1).sorted()
        guard !recent.isEmpty else { return liveHeartRate }
        return recent[recent.count / 2]
    }

    // MARK: - Connection

    func connect() {
        guard let central, central.state == .poweredOn else { return }
        // Prefer a strap the system already has connected (the official app's bond).
        if let known = central.retrieveConnectedPeripherals(withServices: [serviceUUID]).first {
            log.info("found system-connected strap \(known.identifier)")
            attach(known)
            return
        }
        log.info("no connected strap; scanning for fd4b service")
        state = .scanning
        central.scanForPeripherals(withServices: [serviceUUID], options: nil)
    }

    private func attach(_ p: CBPeripheral) {
        central.stopScan()
        peripheral = p
        p.delegate = self
        state = .connecting
        central.connect(p, options: [
            CBConnectPeripheralOptionNotifyOnConnectionKey: true,
            CBConnectPeripheralOptionNotifyOnDisconnectionKey: true,
        ])
    }

    /// Starts a history offload round, the way the official app does every ~10 minutes.
    func requestOffload() {
        send(Command.sendHistoricalData(sequence: nextSequence()))
        send(Command.getDataRange(sequence: nextSequence()))
        send(Command.sendHistoricalData(sequence: nextSequence()))
    }

    private func send(_ frame: [UInt8]) {
        guard let peripheral, let commandCharacteristic else {
            log.error("send skipped: no command characteristic")
            return
        }
        log.debug("write \(frame.count) bytes, cmd \(frame.count > 10 ? frame[10] : 0)")
        peripheral.writeValue(Data(frame), for: commandCharacteristic, type: .withResponse)
    }

    private func nextSequence() -> UInt8 {
        sequence &+= 1
        if sequence == 0 { sequence = 1 }
        return sequence
    }

    // MARK: - Frame handling

    private func handle(frame: [UInt8], channel: Int) {
        framesReceived += 1
        onFrame?(frame, channel)
        let decoded: Decoded
        do { decoded = try FrameDecoder.decode(frame) } catch {
            log.error("frame on channel \(channel) failed to decode: \(String(describing: error))")
            return
        }
        if framesReceived <= 20 || framesReceived % 500 == 0 {
            log.info("frame #\(self.framesReceived) ch\(channel) type \(frame[8]) len \(frame.count)")
        }
        switch decoded {
        case let .realtimeHeartRate(hr):
            recordLive(hr.heartRate, rr: hr.rrMilliseconds)
        case let .biometric(b):
            lastBiometric = b
            if !realtimeStreaming { recordLive(b.heartRate, rr: b.rrMilliseconds) }
        case let .event(event):
            if case let .batteryLevel(level) = event.payload {
                let at = Date(timeIntervalSince1970: TimeInterval(event.unixSeconds))
                // Stored events replay in offload order; keep the newest reading.
                if batteryUpdatedAt.map({ at >= $0 }) ?? true {
                    batteryPercent = Double(level.stateOfChargeTenths) / 10
                    batteryUpdatedAt = at
                }
            }
        case let .metadata(meta):
            if let token = meta.historyEndToken, let ack = try? Command.historyAck(sequence: nextSequence(), token: token) {
                offloadChunks += 1
                send(ack)
            } else if meta.kind == .historyComplete {
                send(Command.abortHistoricalTransmits(sequence: nextSequence()))
            }
        case let .commandResponse(response):
            if let range = response.dataRange { lastDataRange = range }
            if response.command == Command.getHello.code { state = .ready }
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension StrapManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: log.info("bluetooth on"); connect()
        case .poweredOff: log.warning("bluetooth off"); state = .bluetoothOff
        case .unauthorized: state = .failed("Bluetooth permission denied")
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = restored
            restored.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        attach(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        log.info("connected to \(peripheral.name ?? "strap")")
        state = .connected
        reassemblers = [:]
        peripheral.discoverServices([serviceUUID, CBUUID(string: GATT.deviceInformationService)])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        log.error("connect failed: \(error?.localizedDescription ?? "unknown")")
        state = .failed(error?.localizedDescription ?? "connect failed")
        scheduleReconnect()
    }

    private func recordLive(_ bpm: UInt8, rr: [UInt16]) {
        guard bpm > 0 else { return }
        liveHeartRate = bpm
        liveUpdatedAt = Date()
        if !rr.isEmpty { liveRR = rr }
        recentHeartRates.append((Date(), bpm))
        if recentHeartRates.count > 60 { recentHeartRates.removeFirst(recentHeartRates.count - 60) }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        log.warning("disconnected: \(error?.localizedDescription ?? "clean")")
        state = .connecting
        realtimeStreaming = false
        offloadTimer?.invalidate()
        central.connect(peripheral, options: nil) // iOS retries this until the strap is in range again
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.connect() }
    }
}

// MARK: - CBPeripheralDelegate

extension StrapManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        log.info("service \(service.uuid): \((service.characteristics ?? []).map { $0.uuid.uuidString }.joined(separator: ","))")
        for characteristic in service.characteristics ?? [] {
            switch characteristic.uuid {
            case commandUUID:
                commandCharacteristic = characteristic
            case let uuid where notifyUUIDs.contains(uuid):
                reassemblers[uuid] = Reassembler()
                peripheral.setNotifyValue(true, for: characteristic)
            case CBUUID(string: GATT.serialNumberString), CBUUID(string: GATT.modelNumberString), CBUUID(string: GATT.firmwareRevisionString):
                peripheral.readValue(for: characteristic)
            default:
                break
            }
        }
        if service.uuid == serviceUUID, commandCharacteristic != nil {
            // Subscriptions are requested above; the hello goes out once they confirm.
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            log.error("subscribe \(characteristic.uuid) failed: \(error.localizedDescription)")
            state = .failed("subscribe \(characteristic.uuid): \(error.localizedDescription)")
            return
        }
        log.info("subscribed \(characteristic.uuid)")
        let subscribed = notifyUUIDs.filter { uuid in
            peripheral.services?.flatMap { $0.characteristics ?? [] }.first { $0.uuid == uuid }?.isNotifying == true
        }
        if subscribed.count == notifyUUIDs.count {
            log.info("all channels subscribed; sending hello")
            send(Command.clientHello)
            send(Command.getAdvertisingName(sequence: nextSequence()))
            requestOffload()
            offloadTimer?.invalidate()
            offloadTimer = Timer.scheduledTimer(withTimeInterval: Self.offloadInterval, repeats: true) { [weak self] _ in
                self?.requestOffload()
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log.error("write failed: \(error.localizedDescription)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { log.error("read \(characteristic.uuid) failed: \(error.localizedDescription)") }
        guard let data = characteristic.value else { return }
        switch characteristic.uuid {
        case CBUUID(string: GATT.serialNumberString):
            serial = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            if model.isEmpty { model = serial.hasPrefix(GATT.serialPrefixMG) ? "MG" : "5.0" }
        case CBUUID(string: GATT.modelNumberString):
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            if !text.isEmpty { model = text }
        case CBUUID(string: GATT.firmwareRevisionString):
            let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .controlCharacters)
            if !text.isEmpty { firmware = text }
        default:
            guard let channel = channelByUUID[characteristic.uuid] else { return }
            for frame in reassemblers[characteristic.uuid, default: Reassembler()].feed([UInt8](data)) {
                handle(frame: frame, channel: channel)
            }
        }
    }
}

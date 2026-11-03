import Observation
import CoreBluetooth
import Foundation
import OSLog
import SnoopProtocol
import SnoopBattery

/// Owns the Bluetooth link to the strap.
///
/// The official WHOOP app bonds the strap to the phone at the OS level; this manager
/// rides that bond: it looks for an already-connected or known peripheral exposing the
/// `fd4b` service, subscribes to the four notification channels, sends the client hello,
/// and from then on turns every notification into complete frames. Every frame is
/// handed to `onFrame` (for the queue) and decoded for the live view and the offload
/// loop.
@MainActor
@Observable
final class StrapManager: NSObject {
    enum State: Equatable {
        case bluetoothOff, scanning, connecting, connected, ready
        case failed(String)
    }

    private(set) var state: State = .scanning
    /// Simulator builds can be launched with `-demoSerial X` so the read screens have
    /// a device id to ask the server about; the simulator has no Bluetooth.
    private(set) var serial: String = {
        #if targetEnvironment(simulator)
        UserDefaults.standard.string(forKey: "demoSerial") ?? ""
        #else
        ""
        #endif
    }()
    private(set) var model = ""
    private(set) var firmware: String?
    private(set) var liveHeartRate: UInt8?
    private(set) var liveRR: [UInt16] = []
    /// When the live heart rate was last updated, for "x s ago" and smoothing.
    private(set) var liveUpdatedAt: Date?
    /// Recent live samples (time, bpm) for a stable displayed value.
    private(set) var recentHeartRates: [(Date, UInt8)] = []
    private(set) var realtimeStreaming = false
    private(set) var started = false
    private(set) var lastBiometric: Biometric?
    private(set) var batteryPercent: Double?
    private(set) var batteryUpdatedAt: Date?
    private(set) var framesReceived = 0
    private(set) var offloadChunks = 0
    private(set) var lastDataRange: DataRange?

    /// Called with every complete frame and the notify channel it arrived on (3,4,5,7).
    var onFrame: ((_ bytes: [UInt8], _ channel: Int, _ saved: @escaping () -> Void) -> Void)?
    var onSerial: ((String) -> Void)?
    var onBatteryDevice: ((String) -> Void)?
    var onBatteryLevel: ((Double, Date, Bool, BatteryReadingSource) -> Void)?
    var onCharging: ((Bool, Date, Bool) -> Void)?
    var onPackInfo: ((BatteryPackInfo, Date, Bool, Bool) -> Void)?
    var onPackPresence: ((Bool, Date, Bool) -> Void)?
    var onBatteryDisconnect: (() -> Void)?
    var onECGFrame: ((Data, Date, TimeInterval) -> Void)?
    var onECGInvalidFrame: (() -> Void)?
    var onECGAvailability: (() -> Void)?

    static let restoreIdentifier = "snoop.strap"
    private let log = Logger(subsystem: "snoop", category: "ble")
    static let offloadInterval: TimeInterval = 600

    private var central: CBCentralManager!
    var storageOwner: String? { peripheral?.identifier.uuidString }
    private var peripheral: CBPeripheral?
    private var commandCharacteristic: CBCharacteristic?
    private var reassemblers: [CBUUID: Reassembler] = [:]
    private var connectionEpoch = UUID()
    private var storagePaused = false
    private var sequence: UInt8 = 1
    private var ecgRequest: ECGCommandRequest?
    private static let ecgCommandTimeout: Duration = .seconds(8)
    private var offloadTimer: Timer?
    private var lastBatteryRequest: Date = .distantPast
    private var packRequest: (sequence: UInt8, at: Date)?
    private var packQueryUnavailable = false
    private static let packRequestTimeout: TimeInterval = 10

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
        guard state == .ready, (!storagePaused || !on), realtimeStreaming != on else { return }
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
        connectionEpoch = UUID()
        packRequest = nil
        packQueryUnavailable = false
        onBatteryDevice?(p.identifier.uuidString)
        central.stopScan()
        if peripheral?.identifier != p.identifier { serial = ""; model = ""; firmware = nil }
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
        guard state == .ready, !storagePaused else { return }
        requestBattery()
        send(Command.sendHistoricalData(sequence: nextSequence()))
        send(Command.getDataRange(sequence: nextSequence()))
        send(Command.sendHistoricalData(sequence: nextSequence()))
    }

    /// Withhold history acknowledgements while the phone cannot retain data.
    func pauseHistoryForStorage() {
        guard !storagePaused else { return }
        storagePaused = true
        if state == .ready {
            send(Command.abortHistoricalTransmits(sequence: nextSequence()))
            setRealtimeHeartRate(false)
        }
    }

    func resumeHistoryAfterStorage() {
        guard storagePaused else { return }
        storagePaused = false
        requestOffload()
    }

    /// Read-only query, rate-limited even if several visible views request a refresh.
    func requestBattery() {
        guard state == .ready, Date().timeIntervalSince(lastBatteryRequest) >= 30 else { return }
        lastBatteryRequest = Date()
        send(Command.getBatteryLevel(sequence: nextSequence()))
        if let request = packRequest, Date().timeIntervalSince(request.at) > Self.packRequestTimeout {
            packQueryUnavailable = true
            packRequest = nil
        }
        if !packQueryUnavailable {
            let sequence = nextSequence()
            packRequest = (sequence, Date())
            send(Command.getBatteryPackInfo(sequence: sequence))
        }
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
        let epoch = connectionEpoch
        let receivedAt = Date(), uptime = ProcessInfo.processInfo.systemUptime
        onFrame?(frame, channel) { [weak self] in
            guard let self, self.connectionEpoch == epoch else { return }
            self.handleSaved(frame: frame, channel: channel, receivedAt: receivedAt, uptime: uptime)
        }
    }

    private func handleSaved(frame: [UInt8], channel: Int, receivedAt: Date, uptime: TimeInterval) {
        let decoded: Decoded
        do { decoded = try FrameDecoder.decode(frame) } catch {
            log.error("frame on channel \(channel) failed to decode: \(String(describing: error))")
            if frame.count > 9, frame[8] == PacketType.realtimeRawDataByte, [16, 17].contains(frame[9]) {
                onECGInvalidFrame?()
            }
            return
        }
        if framesReceived <= 20 || framesReceived % 500 == 0 {
            log.info("frame #\(self.framesReceived) ch\(channel) type \(frame[8]) len \(frame.count)")
        }
        switch decoded {
        case .ecg:
            if frame[8] == PacketType.realtimeRawDataByte { onECGFrame?(Data(frame), receivedAt, uptime) }
        case let .realtimeHeartRate(hr):
            recordLive(hr.heartRate, rr: hr.rrMilliseconds)
        case let .biometric(b):
            lastBiometric = b
            if !realtimeStreaming { recordLive(b.heartRate, rr: b.rrMilliseconds) }
        case let .event(event):
            let at = Date(timeIntervalSince1970: event.timestamp)
            let live = channel == 4
            if case let .batteryLevel(level) = event.payload {
                // Stored events replay in offload order; keep the newest reading.
                if level.stateOfChargeTenths <= 1000, at <= Date().addingTimeInterval(60), batteryUpdatedAt.map({ at >= $0 }) ?? true {
                    batteryPercent = Double(level.stateOfChargeTenths) / 10
                    batteryUpdatedAt = at
                }
                onBatteryLevel?(Double(level.stateOfChargeTenths) / 10, at, live, .event)
            } else if case let .charging(charging) = event.payload {
                log.info("charging event: \(charging), live channel: \(live)")
                onCharging?(charging, at, live)
                requestBattery()
            } else if case let .batteryPack(info) = event.payload {
                log.info("pack event: present \(info.present), charge raw \(info.rawCharge), live \(live)")
                onPackInfo?(info, at, live, false)
            } else if case let .packPresence(present) = event.payload {
                onPackPresence?(present, at, live)
            }
        case let .metadata(meta):
            if !storagePaused, let token = meta.historyEndToken, let ack = try? Command.historyAck(sequence: nextSequence(), token: token) {
                offloadChunks += 1
                send(ack)
            } else if meta.kind == .historyComplete {
                send(Command.abortHistoricalTransmits(sequence: nextSequence()))
            }
        case let .commandResponse(response):
            if channel == 3, let pending = ecgRequest,
               response.command == pending.command, response.originSequence == pending.sequence,
               response.result != .pending {
                log.info("ECG ack command=\(response.command) result=\(String(describing: response.result), privacy: .public)")
                if response.result == .success { finishECGRequest(id: pending.id, result: .success(())) }
                else { finishECGRequest(id: pending.id, result: .failure(ECGTransportError.refused(response.command, String(describing: response.result)))) }
            }
            if response.command == Command.getBatteryPackInfo.code,
               let request = packRequest, response.originSequence == request.sequence,
               channel == 3, Date().timeIntervalSince(request.at) <= Self.packRequestTimeout {
                if response.result != .pending { packRequest = nil }
                if let info = response.batteryPack {
                    log.info("pack cache: present \(info.present), charge raw \(info.rawCharge)")
                    onPackInfo?(info, Date(), false, true)
                } else if response.result == .failure || response.result == .unsupported {
                    packQueryUnavailable = true
                    log.info("pack query unavailable; waiting for live pack events")
                }
            }
            if let range = response.dataRange { lastDataRange = range }
            if let percent = response.batteryPercent {
                log.info("battery query: \(percent) percent")
                let at = Date()
                batteryPercent = percent
                batteryUpdatedAt = at
                onBatteryLevel?(percent, at, true, .query)
            }
            if response.command == Command.getHello.code, response.result == .success {
                state = .ready
                onECGAvailability?()
                // The handshake has passed the persistence barrier; history can start.
                requestOffload()
            }
        default:
            break
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension StrapManager: @preconcurrency CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn: log.info("bluetooth on"); connect()
        case .poweredOff:
            ecgDisconnected()
            onBatteryDisconnect?()
            lastBatteryRequest = .distantPast
            log.warning("bluetooth off")
            state = .bluetoothOff
            onECGAvailability?()
        case .unauthorized:
            ecgDisconnected()
            onBatteryDisconnect?()
            state = .failed("Bluetooth permission denied")
            onECGAvailability?()
        default: break
        }
    }

    func centralManager(_ central: CBCentralManager, willRestoreState dict: [String: Any]) {
        if let restored = (dict[CBCentralManagerRestoredStatePeripheralsKey] as? [CBPeripheral])?.first {
            peripheral = restored
            onBatteryDevice?(restored.identifier.uuidString)
            restored.delegate = self
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        attach(peripheral)
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        packRequest = nil
        packQueryUnavailable = false
        lastBatteryRequest = .distantPast
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
        connectionEpoch = UUID()
        packRequest = nil
        onBatteryDisconnect?()
        lastBatteryRequest = .distantPast
        log.warning("disconnected: \(error?.localizedDescription ?? "clean")")
        state = .connecting
        ecgDisconnected()
        onECGAvailability?()
        realtimeStreaming = false
        offloadTimer?.invalidate()
        central.connect(peripheral, options: nil) // iOS retries this until the strap is in range again
    }

    private func scheduleReconnect() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.connect() }
    }
}

extension StrapManager: ECGTransport {
    var ecgDevice: ECGDevice? {
        guard state == .ready, !serial.isEmpty else { return nil }
        return .init(serial: serial, firmware: firmware,
                     isMG: model.uppercased().contains("MG") || serial.hasPrefix(GATT.serialPrefixMG))
    }

    func performECG(_ operation: ECGOperation) async throws {
        try Task.checkCancellation()
        guard ecgDevice != nil, peripheral != nil, commandCharacteristic != nil else { throw ECGTransportError.disconnected }
        guard ecgRequest == nil else { throw ECGTransportError.busy }
        let isCleanup = operation == .generation(false) || operation == .rawLive(false) || operation == .filteredLive(false)
        guard !storagePaused || isCleanup else { throw ECGTransportError.storage }
        let id = UUID(), sequence = nextSequence()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let pending = ECGCommandRequest(id: id, command: operation.command.code, sequence: sequence, continuation: continuation)
                ecgRequest = pending
                pending.timeout = Task { [weak self] in
                    do { try await Task.sleep(for: Self.ecgCommandTimeout) } catch { return }
                    self?.finishECGRequest(id: id, result: .failure(ECGTransportError.timeout(operation.command.code)))
                }
                log.info("ECG request command=\(operation.command.code)")
                send(operation.frame(sequence: sequence))
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finishECGRequest(id: id, result: .failure(CancellationError())) }
        }
    }

    private func finishECGRequest(id: UUID, result: Result<Void, Error>) {
        guard let pending = ecgRequest, pending.id == id else { return }
        ecgRequest = nil
        pending.timeout?.cancel()
        pending.continuation.resume(with: result)
    }

    private func ecgDisconnected() {
        if let pending = ecgRequest { finishECGRequest(id: pending.id, result: .failure(ECGTransportError.disconnected)) }
    }
}

// MARK: - CBPeripheralDelegate

extension StrapManager: @preconcurrency CBPeripheralDelegate {
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
            offloadTimer?.invalidate()
            offloadTimer = Timer.scheduledTimer(withTimeInterval: Self.offloadInterval, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.requestOffload() }
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
            if !serial.isEmpty { onSerial?(serial) }
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

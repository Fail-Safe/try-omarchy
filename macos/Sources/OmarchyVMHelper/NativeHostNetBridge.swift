import CoreWLAN
import Darwin
import Foundation

/// One complete Mac Wi‑Fi snapshot for the guest hostnet channel.
/// Built from injectable values so CoreWLAN-free tests can cover the wire
/// contract; `capture()` is the only live CoreWLAN entry point.
struct HostWifiSnapshot: Equatable {
    let powered: Bool
    let associated: Bool
    let ssid: String?
    let rssiDbm: Int?
    let noiseDbm: Int?
    let txRateMbps: Double?
    let channel: Int?
    let channelWidthMhz: Int?
    let band: String?
    let security: String?
    let interfaceName: String?
    let ssidUnavailable: Bool
    let ipAddress: String?
    let bssid: String?
    let phyMode: String?

    init(
        powered: Bool,
        associated: Bool,
        ssid: String?,
        rssiDbm: Int?,
        noiseDbm: Int?,
        txRateMbps: Double?,
        channel: Int?,
        channelWidthMhz: Int?,
        band: String?,
        security: String?,
        interfaceName: String?,
        ssidUnavailable: Bool = false,
        ipAddress: String? = nil,
        bssid: String? = nil,
        phyMode: String? = nil
    ) {
        self.powered = powered
        self.associated = associated
        self.ssid = ssid
        self.rssiDbm = rssiDbm
        self.noiseDbm = noiseDbm
        self.txRateMbps = txRateMbps
        self.channel = channel
        self.channelWidthMhz = channelWidthMhz
        self.band = band
        self.security = security
        self.interfaceName = interfaceName
        self.ssidUnavailable = ssidUnavailable
        self.ipAddress = ipAddress
        self.bssid = bssid
        self.phyMode = phyMode
    }

    static func bandName(for channelNumber: Int?, bandHint: CWChannelBand?) -> String? {
        if let bandHint {
            switch bandHint {
            case .band2GHz: return "2g"
            case .band5GHz: return "5g"
            case .band6GHz: return "6g"
            case .bandUnknown: break
            @unknown default: break
            }
        }
        guard let channelNumber else { return nil }
        if (1...14).contains(channelNumber) { return "2g" }
        if (32...177).contains(channelNumber) { return "5g" }

        return nil
    }

    static func channelWidthMhz(for width: CWChannelWidth?) -> Int? {
        guard let width else { return nil }
        switch width {
        case .widthUnknown: return nil
        case .width20MHz: return 20
        case .width40MHz: return 40
        case .width80MHz: return 80
        case .width160MHz: return 160
        @unknown default: return nil
        }
    }

    static func securityName(for security: CWSecurity?) -> String? {
        guard let security else { return nil }
        switch security {
        case .none: return "open"
        case .WEP: return "wep"
        case .wpaPersonal, .wpaPersonalMixed: return "wpa-personal"
        case .wpa2Personal: return "wpa2-personal"
        case .wpa3Personal: return "wpa3-personal"
        case .wpaEnterprise, .wpaEnterpriseMixed: return "wpa-enterprise"
        case .wpa2Enterprise: return "wpa2-enterprise"
        case .wpa3Enterprise: return "wpa3-enterprise"
        case .dynamicWEP: return "dynamic-wep"
        case .personal: return "personal"
        case .enterprise: return "enterprise"
        case .wpa3Transition: return "wpa3-transition"
        case .OWE: return "owe"
        case .oweTransition: return "owe-transition"
        case .unknown: return nil
        @unknown default: return nil
        }
    }

    static func phyName(for mode: CWPHYMode) -> String? {
        switch mode.rawValue {
        case 1: return "802.11a"
        case 2: return "802.11b"
        case 3: return "802.11g"
        case 4: return "802.11n"
        case 5: return "802.11ac"
        case 6: return "802.11ax"
        case 7: return "802.11be"
        default: return nil
        }
    }

    static func ipv4Address(for interfaceName: String?) -> String? {
        guard let interfaceName else { return nil }
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return nil }
        defer { freeifaddrs(interfaces) }
        var current = interfaces
        while let entry = current {
            defer { current = entry.pointee.ifa_next }
            guard String(cString: entry.pointee.ifa_name) == interfaceName,
                  let address = entry.pointee.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_INET) else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            if getnameinfo(address, socklen_t(address.pointee.sa_len), &host,
                           socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                return String(cString: host)
            }
        }
        return nil
    }

    func encode(networkMode: String? = nil, bridgeInterface: String? = nil) -> Data {
        let snr: Any
        if let rssiDbm, let noiseDbm {
            snr = rssiDbm - noiseDbm
        } else {
            snr = NSNull()
        }
        var object: [String: Any] = [
            "type": "wifi",
            "powered": powered,
            "associated": associated,
            "ssid": ssid as Any? ?? NSNull(),
            "rssiDbm": rssiDbm as Any? ?? NSNull(),
            "noiseDbm": noiseDbm as Any? ?? NSNull(),
            "snrDb": snr,
            "txRateMbps": txRateMbps as Any? ?? NSNull(),
            "channel": channel as Any? ?? NSNull(),
            "channelWidthMhz": channelWidthMhz as Any? ?? NSNull(),
            "band": band as Any? ?? NSNull(),
            "security": security as Any? ?? NSNull(),
            "interface": interfaceName as Any? ?? NSNull(),
            "ssidUnavailable": ssidUnavailable,
            "ipAddress": ipAddress as Any? ?? NSNull(),
            "bssid": bssid as Any? ?? NSNull(),
            "phyMode": phyMode as Any? ?? NSNull(),
        ]
        if let networkMode {
            object["networkMode"] = networkMode
            object["bridgeInterface"] = bridgeInterface as Any? ?? NSNull()
        }
        var data = try! JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        return data
    }

    static func capture(interface: CWInterface? = CWWiFiClient.shared().interface()) -> HostWifiSnapshot {
        guard let interface else {
            return HostWifiSnapshot(
                powered: false,
                associated: false,
                ssid: nil,
                rssiDbm: nil,
                noiseDbm: nil,
                txRateMbps: nil,
                channel: nil,
                channelWidthMhz: nil,
                band: nil,
                security: nil,
                interfaceName: nil
            )
        }
        let powered = interface.powerOn()
        let ssid = interface.ssid()
        let associated = powered && (ssid != nil || interface.rssiValue() != 0)
        let channelObject = interface.wlanChannel()
        let channelNumber = channelObject.map { Int($0.channelNumber) }
        let ssidUnavailable = associated && (ssid == nil || ssid?.isEmpty == true)
        return HostWifiSnapshot(
            powered: powered,
            associated: associated,
            ssid: (ssid?.isEmpty == false) ? ssid : nil,
            rssiDbm: associated ? Int(interface.rssiValue()) : nil,
            noiseDbm: associated ? Int(interface.noiseMeasurement()) : nil,
            txRateMbps: associated ? Double(interface.transmitRate()) : nil,
            channel: channelNumber,
            channelWidthMhz: Self.channelWidthMhz(for: channelObject?.channelWidth),
            band: Self.bandName(for: channelNumber, bandHint: channelObject?.channelBand),
            security: associated ? Self.securityName(for: interface.security()) : nil,
            interfaceName: interface.interfaceName,
            ssidUnavailable: ssidUnavailable,
            ipAddress: associated ? Self.ipv4Address(for: interface.interfaceName) : nil,
            bssid: associated ? interface.bssid() : nil,
            phyMode: associated ? Self.phyName(for: interface.activePHYMode()) : nil
        )
    }
}

/// Dedupe by value so a polling burst cannot spam the port; a forced send
/// (guest refresh, heartbeat) always goes through.
struct WifiSendPolicy {
    private var lastSent: HostWifiSnapshot?

    func shouldSend(_ snapshot: HostWifiSnapshot, forced: Bool) -> Bool {
        forced || snapshot != lastSent
    }

    mutating func markSent(_ snapshot: HostWifiSnapshot) {
        lastSent = snapshot
    }
}

final class NativeHostNetBridge: @unchecked Sendable {
    static let heartbeatSeconds = 5.0

    private let bluetooth = NativeBluetooth()
    private let networkMode: String?
    private let bridgeInterface: String?
    private let descriptor: Int32
    private let stateQueue = DispatchQueue(label: "dev.tryomarchy.native.hostnet-bridge-state")
    private let stopLock = NSLock()
    private var policy = WifiSendPolicy()
    private var bluetoothEnabled = false
    private var heartbeat: DispatchSourceTimer?
    private var stopped = false

    init(targetPID: pid_t, socketPath: String, networkMode: String? = nil, bridgeInterface: String? = nil) throws {
        self.networkMode = networkMode
        self.bridgeInterface = bridgeInterface
        guard let processIdentity = KernelProcessIdentity.capture(processIdentifier: targetPID),
              processIdentity.isQEMUSystemProcess else {
            throw HelperError.io("native hostnet bridge target is not a QEMU system process")
        }
        descriptor = try NativeBridgeSocket.connectSecure(path: socketPath, label: "hostnet bridge")
    }

    deinit {
        stop()
    }

    static func isRefreshRequest(_ line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return false
        }
        return object["type"] as? String == "refresh"
    }

    func run() throws {
        startHeartbeat()
        send(forced: true)
        var reader = GuestLineReader()
        var chunk = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = chunk.withUnsafeMutableBytes { Darwin.read(descriptor, $0.baseAddress, $0.count) }
            if count > 0 {
                for line in reader.feed(chunk[0..<count]) {
                    if let command = HostBluetoothCommand.decode(line) {
                        enableBluetooth()
                        bluetooth.perform(command) { [weak self] result in
                            self?.stateQueue.async { [weak self] in
                                guard let self, !self.hasStopped() else { return }
                                do {
                                    try self.writeMessage(result)
                                    try self.writeMessage(self.bluetooth.snapshot())
                                } catch { self.stop() }
                            }
                        }
                    } else if Self.isRefreshRequest(line) {
                        if Self.requestsBluetooth(line) { enableBluetooth() }
                        sendSync(forced: true)
                    }
                }
            } else if count == 0 {
                return
            } else if errno != EINTR {
                throw HelperError.io("cannot read the guest hostnet channel")
            }
        }
    }

    func stop() {
        stopLock.lock()
        guard !stopped else {
            stopLock.unlock()
            return
        }
        stopped = true
        stopLock.unlock()
        bluetooth.stop()
        heartbeat?.cancel()
        heartbeat = nil
        Darwin.shutdown(descriptor, SHUT_RDWR)
        Darwin.close(descriptor)
    }

    private func hasStopped() -> Bool {
        stopLock.lock()
        defer { stopLock.unlock() }
        return stopped
    }

    private func startHeartbeat() {
        let timer = DispatchSource.makeTimerSource(queue: stateQueue)
        timer.schedule(
            deadline: .now() + Self.heartbeatSeconds,
            repeating: Self.heartbeatSeconds,
            leeway: .milliseconds(250)
        )
        timer.setEventHandler { [weak self] in
            self?.sendOnQueue(forced: true)
        }
        timer.resume()
        heartbeat = timer
    }

    private func send(forced: Bool) {
        stateQueue.async { [weak self] in
            self?.sendOnQueue(forced: forced)
        }
    }

    private func sendSync(forced: Bool) {
        stateQueue.sync {
            sendOnQueue(forced: forced)
        }
    }

    static func requestsBluetooth(_ line: Data) -> Bool {
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "refresh",
              let services = object["services"] as? [String] else { return false }
        return services.contains("bluetooth")
    }

    private func enableBluetooth() {
        stateQueue.sync {
            if !bluetoothEnabled {
                bluetoothEnabled = true
                bluetooth.start()
            }
        }
    }

    private func writeMessage(_ object: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        data.append(0x0A)
        try NativeBridgeSocket.writeAll(data, to: descriptor, label: "hostnet")
    }

    private func sendOnQueue(forced: Bool) {
        guard !hasStopped() else { return }
        let snapshot = HostWifiSnapshot.capture()
        guard policy.shouldSend(snapshot, forced: forced) else { return }
        do {
            try NativeBridgeSocket.writeAll(snapshot.encode(networkMode: networkMode, bridgeInterface: bridgeInterface), to: descriptor, label: "hostnet")
            if bluetoothEnabled { try writeMessage(bluetooth.snapshot()) }
            policy.markSent(snapshot)
        } catch {
            fputs("[hostnet-bridge] \(error.localizedDescription)\n", stderr)
            stop()
        }
    }
}

import AppKit
import CoreBluetooth
import IOBluetooth
import Foundation

struct HostBluetoothCommand: Equatable {
    let id: String
    let action: String
    let deviceID: String?

    static func decode(_ line: Data) -> HostBluetoothCommand? {
        guard line.count <= 1024,
              let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
              object["type"] as? String == "bluetooth-action",
              Set(object.keys).isSubset(of: ["type", "id", "action", "device"]),
              let id = object["id"] as? String, UUID(uuidString: id) != nil,
              let action = object["action"] as? String,
              ["refresh", "connect", "disconnect", "settings"].contains(action) else { return nil }
        let device = object["device"] as? String
        if action == "connect" || action == "disconnect" {
            guard let device, device.range(of: "^[0-9A-Fa-f]{2}(:[0-9A-Fa-f]{2}){5}$", options: .regularExpression) != nil else { return nil }
        } else if object["device"] != nil { return nil }
        return HostBluetoothCommand(id: id, action: action, deviceID: device?.uppercased())
    }
}

final class NativeBluetooth: NSObject, CBCentralManagerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "dev.tryomarchy.bluetooth")
    private let lock = NSLock()
    private var cached: [String: Any] = ["type": "bluetooth", "authorization": "not-determined", "powered": false, "devices": []]
    private var actionPending = false
    private var central: CBCentralManager?
    private var timer: DispatchSourceTimer?

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            let timer = DispatchSource.makeTimerSource(queue: self.queue)
            timer.schedule(deadline: .now(), repeating: 5)
            timer.setEventHandler { [weak self] in self?.capture() }
            timer.resume()
            self.timer = timer
        }
    }

    func stop() {
        queue.async { [weak self] in self?.timer?.cancel(); self?.timer = nil }
    }

    func snapshot() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return cached
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) { capture() }

    private func capture() {
        let authorization: String
        switch CBManager.authorization {
        case .allowedAlways: authorization = "allowed"
        case .denied: authorization = "denied"
        case .restricted: authorization = "restricted"
        case .notDetermined: authorization = "not-determined"
        @unknown default: authorization = "unavailable"
        }
        var powered = false
        var devices: [[String: Any]] = []
        if authorization == "allowed" {
            powered = IOBluetoothHostController.default()?.powerState.rawValue == 1
            let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
            devices = paired.prefix(64).compactMap { device in
                guard let address = device.addressString else { return nil }
                let major = device.deviceClassMajor
                return ["id": address.replacingOccurrences(of: "-", with: ":").uppercased(),
                        "name": String((device.nameOrAddress ?? "Bluetooth device").prefix(128)),
                        "connected": device.isConnected(),
                        "kind": major == 4 ? "audio" : major == 5 ? "input" : "other"]
            }.sorted { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
        }
        lock.lock()
        cached = ["type": "bluetooth", "authorization": authorization, "powered": powered, "devices": devices]
        lock.unlock()
    }

    func perform(_ command: HostBluetoothCommand, completion: @escaping @Sendable ([String: Any]) -> Void) {
        lock.lock()
        guard !actionPending else {
            lock.unlock()
            completion(["type": "bluetooth-result", "id": command.id, "ok": false, "message": "Another Mac Bluetooth action is pending"])
            return
        }
        actionPending = true
        lock.unlock()
        queue.async { [weak self] in
            guard let self else { return }
            defer { self.lock.lock(); self.actionPending = false; self.lock.unlock() }
            var ok = true
            var message = "Status refreshed"
            if command.action == "settings" {
                ok = NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                message = ok ? "Opened Mac Bluetooth Settings" : "Could not open Mac Bluetooth Settings"
            } else if command.action == "refresh" {
                if self.central == nil { self.central = CBCentralManager(delegate: self, queue: self.queue) }
                message = CBManager.authorization == .notDetermined ? "Allow Bluetooth access in the Mac permission prompt" : "Status refreshed"
            } else if CBManager.authorization != .allowedAlways {
                ok = false; message = "Allow Bluetooth access in macOS Privacy & Security settings"
            } else {
                let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
                let device = paired.first { $0.addressString?.replacingOccurrences(of: "-", with: ":").uppercased() == command.deviceID }
                if let device {
                    let result: IOReturn
                    if command.action == "connect" {
                        result = device.isConnected() ? kIOReturnSuccess : device.openConnection(nil, withPageTimeout: 8000, authenticationRequired: true)
                    } else {
                        result = device.isConnected() ? device.closeConnection() : kIOReturnSuccess
                    }
                    ok = result == kIOReturnSuccess
                    message = ok ? (command.action == "connect" ? "Connection requested" : "Disconnection requested") : "macOS Bluetooth action failed (\(result))"
                } else { ok = false; message = "Device is no longer paired with this Mac" }
            }
            self.capture()
            completion(["type": "bluetooth-result", "id": command.id, "ok": ok, "message": message])
        }
    }
}

import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite struct BluetoothCommandTests {
    private func command(_ action: String, device: String? = nil) throws -> Data {
        var object = ["type": "bluetooth-action", "id": UUID().uuidString, "action": action]
        if let device { object["device"] = device }
        return try JSONSerialization.data(withJSONObject: object)
    }

    @Test func oldGuestsKeepWifiOnlyMessages() {
        #expect(!NativeHostNetBridge.requestsBluetooth(Data(#"{"type":"refresh"}"#.utf8)))
        #expect(!NativeHostNetBridge.requestsBluetooth(Data(#"{"type":"refresh","services":["wifi"]}"#.utf8)))
        #expect(NativeHostNetBridge.requestsBluetooth(Data(#"{"type":"refresh","services":["wifi","bluetooth"]}"#.utf8)))
        #expect(!NativeHostNetBridge.requestsBluetooth(Data(#"{"type":"other","services":["bluetooth"]}"#.utf8)))
    }

    @Test func onlyPairedDeviceActionsAndFixedSettingsAreAccepted() throws {
        for action in ["refresh", "settings"] {
            #expect(HostBluetoothCommand.decode(try command(action))?.action == action)
            #expect(HostBluetoothCommand.decode(try command(action, device: "00:11:22:33:44:55")) == nil)
        }
        for action in ["connect", "disconnect"] {
            #expect(HostBluetoothCommand.decode(try command(action, device: "aa:11:22:33:44:55"))?.deviceID == "AA:11:22:33:44:55")
            #expect(HostBluetoothCommand.decode(try command(action)) == nil)
            #expect(HostBluetoothCommand.decode(try command(action, device: "$(touch /tmp/example)")) == nil)
        }
        for action in ["pair", "forget", "power", "shell", "open"] {
            #expect(HostBluetoothCommand.decode(try command(action)) == nil)
        }
        #expect(HostBluetoothCommand.decode(Data(repeating: 32, count: 1025)) == nil)
        #expect(HostBluetoothCommand.decode(Data(#"{"type":"bluetooth-action","id":"bad","action":"refresh"}"#.utf8)) == nil)
    }
}

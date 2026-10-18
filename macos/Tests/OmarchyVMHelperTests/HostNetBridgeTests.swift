import CoreWLAN
import Foundation
import Testing

@testable import OmarchyVMHelper

@Suite struct HostWifiSnapshotTests {
    @Test func associatedSnapshotEncodesTheWireContract() throws {
        let snapshot = HostWifiSnapshot(
            powered: true,
            associated: true,
            ssid: "HomeNet",
            rssiDbm: -55,
            noiseDbm: -92,
            txRateMbps: 600,
            channel: 149,
            channelWidthMhz: 80,
            band: "5g",
            security: "wpa3-personal",
            interfaceName: "en0"
        )
        let line = String(data: snapshot.encode(), encoding: .utf8)!
        #expect(line.hasSuffix("\n"))
        let object = try JSONSerialization.jsonObject(with: snapshot.encode()) as! [String: Any]
        let bridged = try JSONSerialization.jsonObject(with: snapshot.encode(networkMode: "bridged", bridgeInterface: "en0")) as! [String: Any]
        #expect(bridged["networkMode"] as? String == "bridged")
        #expect(bridged["bridgeInterface"] as? String == "en0")
        #expect(object["networkMode"] == nil)
        #expect(object["type"] as? String == "wifi")
        #expect(object["ssid"] as? String == "HomeNet")
        #expect(object["rssiDbm"] as? Int == -55)
        #expect(object["noiseDbm"] as? Int == -92)
        #expect(object["snrDb"] as? Int == 37)
        #expect(object["channel"] as? Int == 149)
        #expect(object["band"] as? String == "5g")
        #expect(object["ssidUnavailable"] as? Bool == false)
        #expect(
            Set(object.keys) == [
                "associated", "band", "channel", "channelWidthMhz", "interface",
                "noiseDbm", "powered", "rssiDbm", "security", "snrDb", "ssid",
                "ssidUnavailable", "txRateMbps", "type", "ipAddress", "bssid", "phyMode",
            ]
        )
    }

    @Test func radioDetailsAndInterfaceScopedAddress() throws {
        let snapshot = HostWifiSnapshot(powered: true, associated: true, ssid: "Example",
            rssiDbm: -55, noiseDbm: -95, txRateMbps: 1200, channel: 52,
            channelWidthMhz: 80, band: "5g", security: "wpa3-personal", interfaceName: "en0",
            ipAddress: "192.0.2.10", bssid: "02:00:00:00:00:01", phyMode: "802.11ax")
        let object = try JSONSerialization.jsonObject(with: snapshot.encode()) as! [String: Any]
        #expect(object["ipAddress"] as? String == "192.0.2.10")
        #expect(object["bssid"] as? String == "02:00:00:00:00:01")
        #expect(object["phyMode"] as? String == "802.11ax")
        #expect(HostWifiSnapshot.ipv4Address(for: "lo0") == "127.0.0.1")
        #expect(HostWifiSnapshot.ipv4Address(for: "missing-interface") == nil)
        #expect(HostWifiSnapshot.phyName(for: CWPHYMode(rawValue: 6)!) == "802.11ax")
        #expect(HostWifiSnapshot.phyName(for: CWPHYMode(rawValue: 0)!) == nil)
    }

    @Test func missingSsidWhileAssociatedIsFlagged() throws {
        let snapshot = HostWifiSnapshot(
            powered: true,
            associated: true,
            ssid: nil,
            rssiDbm: -60,
            noiseDbm: -90,
            txRateMbps: 144,
            channel: 36,
            channelWidthMhz: 40,
            band: "5g",
            security: "wpa2-personal",
            interfaceName: "en0",
            ssidUnavailable: true
        )
        let object = try JSONSerialization.jsonObject(with: snapshot.encode()) as! [String: Any]
        #expect(object["ssid"] is NSNull)
        #expect(object["ssidUnavailable"] as? Bool == true)
    }

    @Test func poweredOffSnapshotClearsLinkFields() throws {
        let snapshot = HostWifiSnapshot(
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
            interfaceName: "en0"
        )
        let object = try JSONSerialization.jsonObject(with: snapshot.encode()) as! [String: Any]
        #expect(object["powered"] as? Bool == false)
        #expect(object["associated"] as? Bool == false)
        #expect(object["rssiDbm"] is NSNull)
    }

    @Test func bandHelperMapsCommonChannelNumbers() {
        #expect(HostWifiSnapshot.bandName(for: 6, bandHint: nil) == "2g")
        #expect(HostWifiSnapshot.bandName(for: 149, bandHint: nil) == "5g")
        #expect(HostWifiSnapshot.bandName(for: 5, bandHint: .band6GHz) == "6g")
        #expect(HostWifiSnapshot.bandName(for: 197, bandHint: nil) == nil)
    }
}

@Suite struct WifiSendPolicyTests {
    @Test func duplicateSnapshotsAreCoalescedUntilForced() {
        var policy = WifiSendPolicy()
        let snapshot = HostWifiSnapshot(
            powered: true,
            associated: false,
            ssid: nil,
            rssiDbm: nil,
            noiseDbm: nil,
            txRateMbps: nil,
            channel: nil,
            channelWidthMhz: nil,
            band: nil,
            security: nil,
            interfaceName: "en0"
        )
        #expect(policy.shouldSend(snapshot, forced: false))
        policy.markSent(snapshot)
        #expect(!policy.shouldSend(snapshot, forced: false))
        #expect(policy.shouldSend(snapshot, forced: true))
    }
}

@Suite struct HostNetRefreshRequestTests {
    @Test func onlyRefreshLinesAreAccepted() {
        #expect(NativeHostNetBridge.isRefreshRequest(Data(#"{"type":"refresh"}"#.utf8)))
        #expect(!NativeHostNetBridge.isRefreshRequest(Data(#"{"type":"wifi"}"#.utf8)))
        #expect(!NativeHostNetBridge.isRefreshRequest(Data(#"[]"#.utf8)))
    }
}

import Foundation

/// Hot-swaps the guest pointer between absolute tablet and relative mouse over
/// QMP. Absolute remains the default for desktop trackpad use; relative is what
/// Cocoa needs before games can lock the host cursor.
final class QMPPointerInputController {
    static let tabletDeviceID = "omarchy-tablet"
    static let mouseDeviceID = "omarchy-mouse"

    typealias ConnectionFactory = () throws -> QMPConnection

    private let makeConnection: ConnectionFactory
    private(set) var mode: PointerInputMode

    init(socketPath: String, initialMode: PointerInputMode) {
        makeConnection = {
            try QMPConnection(
                socketPath: socketPath,
                identifierPrefix: "omarchy-pointer"
            )
        }
        mode = initialMode
    }

    init(
        connectionFactory: @escaping ConnectionFactory,
        initialMode: PointerInputMode
    ) {
        makeConnection = connectionFactory
        mode = initialMode
    }

    func setMode(_ mode: PointerInputMode) throws {
        guard mode != self.mode else { return }
        let connection = try makeConnection()
        defer { connection.close() }

        // Add the new device first so the guest never loses its only pointer;
        // the outgoing device stays until the replacement is attached.
        let addDriver: String
        let addID: String
        let removeID: String
        switch mode {
        case .relative:
            addDriver = "virtio-mouse-pci"
            addID = Self.mouseDeviceID
            removeID = Self.tabletDeviceID
        case .absolute:
            addDriver = "virtio-tablet-pci"
            addID = Self.tabletDeviceID
            removeID = Self.mouseDeviceID
        }
        _ = try connection.execute(
            "device_add",
            arguments: [
                "driver": addDriver,
                "id": addID,
                "romfile": "",
            ]
        )
        _ = try connection.execute(
            "device_del",
            arguments: ["id": removeID]
        )
        self.mode = mode
    }
}

import Darwin
import Foundation
import Testing
@testable import OmarchyVMHelper

@Suite("Pointer preferences")
struct PointerPreferenceStoreTests {
    @Test("Absolute mode is the default until the user changes it")
    func defaultsToAbsolute() {
        let fixture = DefaultsFixture()

        #expect(fixture.store.load() == .defaults)
        #expect(fixture.store.load().mode == .absolute)
    }

    @Test("Pointer mode choice persists")
    func savesChoice() {
        let fixture = DefaultsFixture()
        fixture.store.save(PointerPreferences(mode: .relative))

        let reopened = PointerPreferenceStore(defaults: fixture.defaults)
        #expect(reopened.load() == PointerPreferences(mode: .relative))
    }

    @Test("Invalid or future preferences fail safely")
    func invalidPreferencesUseDefault() throws {
        let fixture = DefaultsFixture()
        fixture.defaults.set(Data("junk".utf8), forKey: PointerPreferenceStore.key)
        #expect(fixture.store.load() == .defaults)

        let future = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": PointerPreferenceStore.schemaVersion + 1,
            "mode": "relative",
        ])
        fixture.defaults.set(future, forKey: PointerPreferenceStore.key)
        #expect(fixture.store.load() == .defaults)
    }

    private final class DefaultsFixture {
        let suiteName = "PointerPreferenceStoreTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let store: PointerPreferenceStore

        init() {
            defaults = UserDefaults(suiteName: suiteName)!
            defaults.removePersistentDomain(forName: suiteName)
            store = PointerPreferenceStore(defaults: defaults)
        }

        deinit {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

@Suite("Pointer launch configuration")
struct PointerLaunchConfigurationTests {
    @Test("Publishes pointer mode and replaces inherited values")
    func publishesChoice() {
        let inherited = [
            "KEEP_ME": "yes",
            PointerLaunchConfiguration.environmentKey: "invalid",
        ]

        let absolute = PointerLaunchConfiguration.make(
            baseEnvironment: inherited,
            preferences: PointerPreferences(mode: .absolute)
        )
        #expect(absolute.environment["KEEP_ME"] == "yes")
        #expect(absolute.environment[PointerLaunchConfiguration.environmentKey] == "absolute")

        let relative = PointerLaunchConfiguration.make(
            baseEnvironment: inherited,
            preferences: PointerPreferences(mode: .relative)
        )
        #expect(relative.environment["KEEP_ME"] == "yes")
        #expect(relative.environment[PointerLaunchConfiguration.environmentKey] == "relative")
    }
}

@Suite("Pointer input native contract")
struct PointerInputNativeContractTests {
    @Test("Runner keeps stable pointer device ids for QMP hot-swap")
    func runnerMapping() throws {
        let runner = try source(named: "run-qemu-gpu.sh")

        #expect(runner.contains("case ${OMARCHY_QEMU_POINTER_MODE:-absolute} in"))
        #expect(runner.contains(
            "pointer_device='virtio-tablet-pci,id=omarchy-tablet,romfile='"
        ))
        #expect(runner.contains(
            "pointer_device='virtio-mouse-pci,id=omarchy-mouse,romfile='"
        ))
        #expect(runner.contains("OMARCHY_QEMU_POINTER_MODE must be absolute or relative"))
        #expect(runner.contains("-device \"$pointer_device\""))
        #expect(runner.contains("virtio-mouse-pci \\"))
        #expect(runner.contains(
            "Full grab keeps every Command chord with the focused guest"
        ))
        #expect(runner.contains(
            "keyboard capture only, not relative mouse lock"
        ))
    }

    private func source(named relativePath: String) throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        let macosDirectory = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: macosDirectory.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@Suite("QMP pointer input control")
struct QMPPointerInputControllerTests {
    @Test("hot-swaps tablet and mouse without a pointer gap")
    func switchesModesWithAddBeforeDelete() throws {
        let transcript = LockedQMPTranscript()
        let sessions = try [
            Self.startServer(steps: [
                PointerQMPStep(
                    command: "device_add",
                    driver: "virtio-mouse-pci",
                    id: QMPPointerInputController.mouseDeviceID
                ),
                PointerQMPStep(
                    command: "device_del",
                    id: QMPPointerInputController.tabletDeviceID
                ),
            ], transcript: transcript),
            Self.startServer(steps: [
                PointerQMPStep(
                    command: "device_add",
                    driver: "virtio-tablet-pci",
                    id: QMPPointerInputController.tabletDeviceID
                ),
                PointerQMPStep(
                    command: "device_del",
                    id: QMPPointerInputController.mouseDeviceID
                ),
            ], transcript: transcript),
        ]
        let descriptors = LockedDescriptorQueue(sessions.map(\.clientDescriptor))
        let controller = QMPPointerInputController(
            connectionFactory: {
                guard let descriptor = descriptors.take() else {
                    throw HelperError.io("unexpected extra QMP connection")
                }
                return try QMPConnection(
                    connectedDescriptor: descriptor,
                    identifierPrefix: "test-pointer"
                )
            },
            initialMode: .absolute
        )

        try controller.setMode(.relative)
        #expect(controller.mode == .relative)
        try controller.setMode(.absolute)
        #expect(controller.mode == .absolute)
        try controller.setMode(.absolute)

        for session in sessions {
            #expect(session.finished.wait(timeout: .now() + 2) == .success)
        }
        #expect(transcript.errorDescription == nil)
        #expect(transcript.commands == [
            "qmp_capabilities",
            "device_add",
            "device_del",
            "qmp_capabilities",
            "device_add",
            "device_del",
        ])
        #expect(descriptors.isEmpty)
    }

    private struct PointerQMPStep {
        let command: String
        let driver: String?
        let id: String

        init(command: String, driver: String? = nil, id: String) {
            self.command = command
            self.driver = driver
            self.id = id
        }
    }

    private struct TestSession {
        let clientDescriptor: Int32
        let finished: DispatchSemaphore
    }

    private static func startServer(
        steps: [PointerQMPStep],
        transcript: LockedQMPTranscript
    ) throws -> TestSession {
        var descriptors: [Int32] = [-1, -1]
        guard socketpair(AF_UNIX, SOCK_STREAM, 0, &descriptors) == 0 else {
            throw HelperError.io("cannot create test QMP socket pair")
        }
        let serverDescriptor = descriptors[1]
        let finished = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            defer {
                Darwin.close(serverDescriptor)
                finished.signal()
            }
            do {
                try QMPConnection.writeJSON([
                    "QMP": [
                        "version": [
                            "qemu": ["major": 10, "minor": 2, "micro": 0],
                            "package": "",
                        ],
                        "capabilities": [],
                    ],
                ], to: serverDescriptor)
                let capabilities = try readJSON(from: serverDescriptor)
                let capabilitiesCommand = try string("execute", in: capabilities)
                guard capabilitiesCommand == "qmp_capabilities" else {
                    throw HelperError.io(
                        "expected qmp_capabilities, received \(capabilitiesCommand)"
                    )
                }
                transcript.append(capabilitiesCommand)
                try respond(
                    id: try string("id", in: capabilities),
                    result: [:],
                    to: serverDescriptor
                )

                for step in steps {
                    let request = try readJSON(from: serverDescriptor)
                    let command = try string("execute", in: request)
                    guard command == step.command else {
                        throw HelperError.io(
                            "expected QMP command \(step.command), received \(command)"
                        )
                    }
                    let arguments = try requireObject("arguments", in: request)
                    let deviceID = try string("id", in: arguments)
                    guard deviceID == step.id else {
                        throw HelperError.io(
                            "expected device id \(step.id), received \(deviceID)"
                        )
                    }
                    if let driver = step.driver {
                        let actualDriver = try string("driver", in: arguments)
                        guard actualDriver == driver else {
                            throw HelperError.io(
                                "expected driver \(driver), received \(actualDriver)"
                            )
                        }
                    }
                    transcript.append(command)
                    try respond(
                        id: try string("id", in: request),
                        result: [:],
                        to: serverDescriptor
                    )
                }
            } catch {
                transcript.record(error)
            }
        }
        return TestSession(clientDescriptor: descriptors[0], finished: finished)
    }

    private static func readJSON(from descriptor: Int32) throws -> [String: Any] {
        var data = Data()
        while data.count <= 1_048_576 {
            var byte: UInt8 = 0
            let count = Darwin.read(descriptor, &byte, 1)
            if count == 1 {
                if byte == 0x0A {
                    guard let object = try JSONSerialization.jsonObject(with: data)
                        as? [String: Any] else {
                        throw HelperError.io("test QMP request is not an object")
                    }
                    return object
                }
                if byte != 0x0D { data.append(byte) }
            } else if count == 0 {
                throw HelperError.io("test QMP client closed early")
            } else if errno != EINTR {
                throw HelperError.io("cannot read test QMP request")
            }
        }
        throw HelperError.io("test QMP request is too large")
    }

    private static func string(_ key: String, in object: [String: Any]) throws -> String {
        guard let value = object[key] as? String else {
            throw HelperError.io("test QMP request omitted \(key)")
        }
        return value
    }

    private static func requireObject(
        _ key: String,
        in object: [String: Any]
    ) throws -> [String: Any] {
        guard let value = object[key] as? [String: Any] else {
            throw HelperError.io("test QMP request omitted \(key)")
        }
        return value
    }

    private static func respond(
        id: String,
        result: [String: Any],
        to descriptor: Int32
    ) throws {
        try QMPConnection.writeJSON([
            "return": result,
            "id": id,
        ], to: descriptor)
    }
}

private final class LockedQMPTranscript: @unchecked Sendable {
    private let lock = NSLock()
    private var storedCommands: [String] = []
    private var storedErrorDescription: String?

    var commands: [String] {
        lock.withLock { storedCommands }
    }

    var errorDescription: String? {
        lock.withLock { storedErrorDescription }
    }

    func append(_ command: String) {
        lock.withLock {
            storedCommands.append(command)
        }
    }

    func record(_ error: Error) {
        lock.withLock {
            storedErrorDescription = error.localizedDescription
        }
    }
}

private final class LockedDescriptorQueue: @unchecked Sendable {
    private let lock = NSLock()
    private var descriptors: [Int32]

    init(_ descriptors: [Int32]) {
        self.descriptors = descriptors
    }

    deinit {
        for descriptor in descriptors {
            Darwin.close(descriptor)
        }
    }

    var isEmpty: Bool {
        lock.withLock { descriptors.isEmpty }
    }

    func take() -> Int32? {
        lock.withLock {
            guard !descriptors.isEmpty else { return nil }
            return descriptors.removeFirst()
        }
    }
}

import Foundation

struct VMNetworkIdentityAccess {
    var read: () throws -> String
    var canReplace: () -> Bool = { false }
    var replace: (_ expected: String, _ proposed: String) throws -> String

    static let unavailable = Self(
        read: { "" },
        replace: { _, _ in throw HelperError.io("Start this VM once before changing its MAC address.") }
    )

    static func proposedMAC() -> String {
        "02:" + (0..<5).map { _ in String(format: "%02x", UInt8.random(in: .min ... .max)) }.joined(separator: ":")
    }

    static func operation(_ arguments: [String], root: URL, resources: URL) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", resources.appendingPathComponent("scripts/network-identity.py").path,
                             arguments[0], root.path, "current"] + arguments.dropFirst()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let result = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw HelperError.io(error.isEmpty ? "The VM network identity could not be read." : error)
        }
        return result
    }
}

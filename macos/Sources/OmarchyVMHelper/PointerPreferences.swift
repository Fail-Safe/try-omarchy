import Foundation

enum PointerInputMode: String, Equatable {
    case absolute
    case relative
}

struct PointerPreferences: Equatable {
    var mode: PointerInputMode

    static let defaults = Self(mode: .absolute)
}

struct PointerPreferenceStore {
    static let key = "pointerPreferences"
    static let schemaVersion = 1

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> PointerPreferences {
        guard let data = defaults.data(forKey: Self.key),
              let payload = try? JSONDecoder().decode(Payload.self, from: data),
              payload.schemaVersion == Self.schemaVersion,
              let mode = PointerInputMode(rawValue: payload.mode) else {
            return .defaults
        }
        return PointerPreferences(mode: mode)
    }

    func save(_ preferences: PointerPreferences) {
        let payload = Payload(
            schemaVersion: Self.schemaVersion,
            mode: preferences.mode.rawValue
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        defaults.set(data, forKey: Self.key)
    }

    private struct Payload: Codable {
        let schemaVersion: Int
        let mode: String
    }
}

struct PointerLaunchConfiguration: Equatable {
    static let environmentKey = "OMARCHY_QEMU_POINTER_MODE"

    let environment: [String: String]

    static func make(
        baseEnvironment: [String: String],
        preferences: PointerPreferences
    ) -> Self {
        var environment = baseEnvironment
        environment.removeValue(forKey: environmentKey)
        environment[environmentKey] = preferences.mode.rawValue
        return Self(environment: environment)
    }
}

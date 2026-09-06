import Foundation

@MainActor @Observable
final class PersonalSetupStore {
    static let shared = PersonalSetupStore()
    private let defaults: UserDefaults
    private static let key = "zoon.personalSetup.v1"
    var value: PersonalSetup {
        didSet {
            if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: Self.key) }
        }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let saved = try? JSONDecoder().decode(PersonalSetup.self, from: data), saved.isValid { value = saved }
        else { value = PersonalSetup() }
    }

    func clearAll() {
        value = PersonalSetup()
        defaults.removeObject(forKey: Self.key)
    }
}

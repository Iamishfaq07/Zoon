import Foundation
import Observation

struct CustomBehavior: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var symbol: String
    var isActive: Bool

    init(name: String, symbol: String = "circle.fill", isActive: Bool = true) {
        id = UUID(); self.name = name; self.symbol = symbol; self.isActive = isActive
    }
}

@MainActor
@Observable
final class CustomBehaviorStore {
    static let shared = CustomBehaviorStore()
    private let key = "zoon.customBehaviors.v1"
    private(set) var behaviors: [CustomBehavior]

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let decoded = try? JSONDecoder().decode([CustomBehavior].self, from: data) {
            behaviors = decoded
        } else { behaviors = [] }
    }

    func add(name: String, symbol: String = "circle.fill") {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !behaviors.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
        behaviors.append(CustomBehavior(name: trimmed, symbol: symbol)); save()
    }
    func toggle(_ behavior: CustomBehavior) {
        guard let index = behaviors.firstIndex(where: { $0.id == behavior.id }) else { return }
        behaviors[index].isActive.toggle(); save()
    }
    func remove(_ behavior: CustomBehavior) { behaviors.removeAll { $0.id == behavior.id }; save() }
    /// Delete Everything. Removes the key rather than saving an empty list so
    /// nothing of the user's is left behind in defaults.
    func deleteAll() { behaviors = []; UserDefaults.standard.removeObject(forKey: key) }
    private func save() { UserDefaults.standard.set(try? JSONEncoder().encode(behaviors), forKey: key) }
}

import SwiftUI

struct CustomBehaviorsView: View {
    @State private var store = CustomBehaviorStore.shared
    @State private var newName = ""

    var body: some View {
        Form {
            Section("Add your own signal") {
                HStack {
                    TextField("e.g. evening medication", text: $newName)
                    Button("Add") { store.add(name: newName); newName = "" }.disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Text("Custom signals stay on this device and appear as optional journal prompts. Zoon will not infer health effects until you have enough observations.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Section("Your signals") {
                if store.behaviors.isEmpty { Text("No custom signals yet.").foregroundStyle(Theme.inkSecondary) }
                ForEach(store.behaviors) { behavior in
                    HStack {
                        Label(behavior.name, systemImage: behavior.symbol)
                        Spacer()
                        Toggle("Active", isOn: Binding(get: { behavior.isActive }, set: { _ in store.toggle(behavior) })).labelsHidden()
                    }
                    .swipeActions { Button("Delete", role: .destructive) { store.remove(behavior) } }
                }
            }
        }
        .scrollContentBackground(.hidden).nightBackground()
        .navigationTitle("Custom behaviours").navigationBarTitleDisplayMode(.inline)
    }
}

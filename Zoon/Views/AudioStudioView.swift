import SwiftUI

struct AudioStudioView: View {
    @Environment(SoundscapeEngine.self) private var engine
    @State private var store = PersonalSetupStore.shared
    @State private var name = "My night scene"
    @State private var layers = [PersonalSetup.Layer(sound: "rain", level: 0.6), PersonalSetup.Layer(sound: "brownNoise", level: 0.25)]

    var body: some View {
        Form {
            Section("Your mix") {
                TextField("Scene name", text: $name)
                ForEach($layers) { $layer in
                    VStack(alignment: .leading) {
                        Picker("Sound", selection: $layer.sound) {
                            ForEach(SoundscapeEngine.Sound.allCases) { Text($0.label).tag($0.rawValue) }
                        }
                        Slider(value: $layer.level, in: 0...1) { Text("Layer volume") }
                            .accessibilityValue("\(Int(layer.level * 100)) percent")
                    }
                }
                if layers.count < 3 {
                    Button("Add a third layer") { layers.append(.init(sound: "wind", level: 0.2)) }
                }
                if layers.count > 1 { Button("Remove last layer") { layers.removeLast() } }
                Button("Play mix") { engine.playScene(.init(name: name, layers: layers)) }
                    .accessibilityIdentifier("playScene")
                Button("Stop audio", role: .destructive) { engine.stop() }
                Button("Save scene") {
                    store.value.scenes.append(.init(name: name.trimmingCharacters(in: .whitespacesAndNewlines), layers: layers))
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Section("Saved scenes") {
                ForEach(store.value.scenes) { scene in
                    Button(scene.name) { name = scene.name; layers = scene.layers }
                        .swipeActions { Button("Delete", role: .destructive) { store.value.scenes.removeAll { $0.id == scene.id } } }
                }
                Text("Loading a scene is silent. Tap Play mix to listen.").font(.caption).foregroundStyle(Theme.inkSecondary)
            }
            Section("Sleep timer") {
                ForEach([15, 30, 60, 90], id: \.self) { minutes in
                    Button("Stop in \(minutes) minutes") { engine.setTimer(minutes: minutes) }
                }
                if engine.timerMinutes != nil { Text("Remaining: \(engine.formattedRemaining)").monospacedDigit() }
            }
            Section {
                Text("Brown, pink and white are generated so they never seam. Rain, wind, fire and the rest are the recorded loops bundled in the app. Levels mix at reduced gain. Switching scenes keeps the timer's original end time.")
                    .font(.caption).foregroundStyle(Theme.inkSecondary)
            }
        }
        .navigationTitle("Audio Studio")
        .scrollContentBackground(.hidden).nightBackground()
        .onChange(of: layers) { _, updated in engine.updateSceneLevels(updated) }
    }
}

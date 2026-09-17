import SwiftUI

/// The review step for the structured part of an observation.
///
/// §9's rule is that quantity and time are never silently inferred — the
/// person confirms them. A proposal that could only be accepted or discarded
/// whole would not satisfy that: "two coffees, last one around 5" is two facts
/// and a guess, and somebody has to be able to keep the two and correct the
/// five. That is what this is for.
///
/// **Removing is as easy as keeping.** The parser is a suggestion, and the
/// most important thing this sheet does is make "no, Zoon does not know how
/// many" a single tap. A detail that is hard to clear is a detail people leave
/// in, and a curve built from those is worse than no curve.
///
/// Intensity appears only where `BehaviorTag.takesIntensity` allows it. A hard
/// cup of coffee is not a thing, and a control offering to rate one invites an
/// answer nobody meant.
struct BehaviorDetailEditor: View {

    let label: String
    /// The day the night is filed under, so a time lands on the right evening.
    let nightDay: Date
    /// Whether "hard" or "easy" means anything here.
    let takesIntensity: Bool

    @Binding var detail: BehaviorDetail?
    @Environment(\.dismiss) private var dismiss

    @State private var hasQuantity = false
    @State private var quantity = 1.0
    @State private var unit = ""
    @State private var hasTime = false
    @State private var time = Date()
    @State private var hasIntensity = false
    @State private var intensity = 0.5

    private var calendar: Calendar { .current }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Record how many", isOn: $hasQuantity.animation())
                    if hasQuantity {
                        Stepper(value: $quantity, in: 1...50, step: 1) {
                            HStack {
                                Text("How many")
                                Spacer()
                                Text(quantity.formatted(.number.precision(.fractionLength(0))))
                                    .font(Theme.numeral(17))
                                    .monospacedDigit()
                            }
                        }
                        TextField("What you are counting (optional)", text: $unit)
                            .textInputAutocapitalization(.never)
                    }
                } footer: {
                    Text("Left off, Zoon records that this happened without claiming a number. That is not the same as one.")
                }

                Section {
                    Toggle("Record when", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker(
                            "Time", selection: $time, displayedComponents: .hourAndMinute
                        )
                    }
                } footer: {
                    Text("Where there were several, this is the last one — the one closest to your night.")
                }

                if takesIntensity {
                    Section {
                        Toggle("Record how hard", isOn: $hasIntensity.animation())
                        if hasIntensity {
                            Picker("How hard", selection: $intensity) {
                                Text("Easy").tag(0.2)
                                Text("Moderate").tag(0.5)
                                Text("Hard").tag(0.85)
                            }
                            .pickerStyle(.segmented)
                        }
                    } footer: {
                        Text("Your own reading of the session, kept separate from anything measured.")
                    }
                }

                Section {
                    Button("Remove all detail", role: .destructive) {
                        detail = nil
                        Haptics.tap()
                        dismiss()
                    }
                }
            }
            .navigationTitle(label)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        detail = assembled()
                        Haptics.select()
                        dismiss()
                    }
                }
            }
        }
        .onAppear(perform: load)
    }

    /// Seeds the controls from whatever was proposed, so the sheet opens on
    /// what Zoon understood rather than on a blank form somebody has to
    /// re-enter.
    private func load() {
        if let quantity = detail?.quantity {
            hasQuantity = true
            self.quantity = quantity
        }
        unit = detail?.unit ?? ""
        if let eventTime = detail?.eventTime {
            hasTime = true
            time = eventTime
        } else {
            // A sensible place to start, not a value that gets stored unless
            // the toggle is on: early evening is where most of what this
            // records actually happens.
            time = calendar.date(
                bySettingHour: 18, minute: 0, second: 0,
                of: calendar.date(byAdding: .day, value: -1, to: nightDay) ?? nightDay
            ) ?? nightDay
        }
        if let intensity = detail?.intensity {
            hasIntensity = true
            self.intensity = [0.2, 0.5, 0.85]
                .min { abs($0 - intensity) < abs($1 - intensity) } ?? 0.5
        }
    }

    /// Only what the toggles say to keep. An untouched section contributes
    /// nothing rather than a default.
    private func assembled() -> BehaviorDetail? {
        let built = BehaviorDetail(
            quantity: hasQuantity ? quantity : nil,
            unit: hasQuantity ? unit : nil,
            eventTime: hasTime ? anchoredTime() : nil,
            intensity: takesIntensity && hasIntensity ? intensity : nil
        )
        return built.isEmpty ? nil : built
    }

    /// Puts the picked clock time onto the night's own evening or morning, the
    /// same rule the parser follows: an evening time belongs to the evening
    /// before the morning the night is filed under.
    private func anchoredTime() -> Date? {
        let components = calendar.dateComponents([.hour, .minute], from: time)
        let hour = components.hour ?? 0
        let day = hour >= 12
            ? calendar.date(byAdding: .day, value: -1, to: nightDay) ?? nightDay
            : nightDay
        var anchored = calendar.dateComponents([.year, .month, .day], from: day)
        anchored.hour = hour
        anchored.minute = components.minute ?? 0
        anchored.second = 0
        return calendar.date(from: anchored)
    }
}

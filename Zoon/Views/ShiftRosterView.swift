import SwiftUI

/// Entering and editing a work roster.
///
/// **Why entry is a pattern, not a calendar.** Asking somebody to tap out
/// every night of a Monday–Thursday rota is asking them to do the computer's
/// job, and a roster entered that way goes stale the moment it rolls over.
/// The screen takes the shape people describe — a start time, a length, and
/// the days it repeats on — and `ShiftRoster` expands it whenever a date is
/// needed.
///
/// **Why there is no import.** The brief allows an imported work schedule
/// "where appropriate", and it is not appropriate yet: the only source Zoon
/// can read is EventKit, a work calendar there is indistinguishable from any
/// other calendar, and guessing which events are shifts would produce a roster
/// somebody did not enter and cannot easily correct. Entry is manual until
/// there is a signal that is actually about work.
struct ShiftRosterView: View {

    @Environment(UserPreferences.self) private var preferences
    @State private var editing: ShiftRoster.Shift?

    private var shifts: [ShiftRoster.Shift] {
        preferences.shiftRoster.shifts.sorted { $0.startMinutes < $1.startMinutes }
    }

    var body: some View {
        @Bindable var preferences = preferences

        List {
            Section {
                if shifts.isEmpty {
                    Text("No shifts yet. Zoon only plans around a roster when you keep one.")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.inkSecondary)
                } else {
                    ForEach(shifts) { shift in
                        Button {
                            Haptics.tap()
                            editing = shift
                        } label: {
                            row(shift)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: delete)
                }

                Button("Add a shift") {
                    Haptics.tap()
                    editing = ShiftRoster.Shift(
                        startMinutes: 22 * 60, durationMinutes: 8 * 60, weekdays: [2, 3, 4, 5]
                    )
                }
            } header: {
                Text("Your shifts")
            } footer: {
                Text("Start time and length, and the days it repeats on. Zoon works out the dates.")
            }

            Section {
                Stepper(
                    "Commute \(Int(preferences.shiftCommuteMinutes)) min",
                    value: $preferences.shiftCommuteMinutes,
                    in: 0...120,
                    step: 5
                )
            } footer: {
                Text("Door to door, each way. It sets how early the sleep before a shift has to end and how late the sleep after it can start.")
            }

            Section {
                Text("Schedule support only. Nothing here is a judgement about the work itself, and nothing about your roster leaves this device.")
                    .font(Theme.evidence)
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .navigationTitle("Work roster")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { shift in
            ShiftEditorView(shift: shift) { edited in
                save(edited)
            }
        }
    }

    private func row(_ shift: ShiftRoster.Shift) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clock(shift.startMinutes) + "–" + clock(shift.startMinutes + shift.durationMinutes))
                .font(Theme.numeral(15))
            Text(describe(shift))
                .font(Theme.text(12))
                .foregroundStyle(Theme.inkSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    /// Minutes past midnight as a clock time, wrapping so a shift that runs to
    /// 30:00 reads as 06:00 rather than as a number no clock shows.
    private func clock(_ minutes: Int) -> String {
        let wrapped = ((minutes % 1440) + 1440) % 1440
        return String(format: "%02d:%02d", wrapped / 60, wrapped % 60)
    }

    private func describe(_ shift: ShiftRoster.Shift) -> String {
        guard shift.isRepeating else {
            return shift.date.map { $0.formatted(.dateTime.weekday(.wide).day().month()) } ?? "Once"
        }
        let symbols = Calendar.current.shortWeekdaySymbols
        let names = shift.weekdays.sorted().compactMap { weekday -> String? in
            let index = weekday - 1
            return symbols.indices.contains(index) ? symbols[index] : nil
        }
        return names.joined(separator: ", ")
    }

    private func save(_ shift: ShiftRoster.Shift) {
        var roster = preferences.shiftRoster
        if let index = roster.shifts.firstIndex(where: { $0.id == shift.id }) {
            roster.shifts[index] = shift
        } else {
            roster.shifts.append(shift)
        }
        preferences.shiftRoster = roster
        Haptics.success()
    }

    private func delete(_ offsets: IndexSet) {
        let removing = Set(offsets.map { shifts[$0].id })
        var roster = preferences.shiftRoster
        roster.shifts.removeAll { removing.contains($0.id) }
        // The cancellations belonged to a shift that no longer exists. Leaving
        // them would keep a growing set of dates alive against an id nothing
        // can ever match again.
        for id in removing { roster.skipped[id] = nil }
        preferences.shiftRoster = roster
    }
}

/// One shift's start, length and days.
private struct ShiftEditorView: View {

    @Environment(\.dismiss) private var dismiss
    @State private var start: Date
    @State private var hours: Double
    @State private var weekdays: Set<Int>
    @State private var label: String

    private let original: ShiftRoster.Shift
    private let onSave: (ShiftRoster.Shift) -> Void

    init(shift: ShiftRoster.Shift, onSave: @escaping (ShiftRoster.Shift) -> Void) {
        self.original = shift
        self.onSave = onSave
        let midnight = Calendar.current.startOfDay(for: .now)
        _start = State(
            initialValue: midnight.addingTimeInterval(Double(shift.startMinutes) * 60)
        )
        _hours = State(initialValue: Double(shift.durationMinutes) / 60)
        _weekdays = State(initialValue: shift.weekdays)
        _label = State(initialValue: shift.label ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Starts", selection: $start, displayedComponents: .hourAndMinute)

                // A stepper rather than a second time picker: an end time
                // picker would let somebody enter an end before the start,
                // which for a shift crossing midnight is indistinguishable
                // from a sixteen-hour night.
                Stepper(value: $hours, in: 0.5...16, step: 0.5) {
                    Text("Length \(SleepNightFeatures.formatMinutes(hours * 60))")
                }

                Section("Repeats on") {
                    ZoonFlowLayout(spacing: 8) {
                        ForEach(1...7, id: \.self) { weekday in
                            dayChip(weekday)
                        }
                    }
                    if weekdays.isEmpty {
                        Text("Pick at least one day. A shift with no days never happens.")
                            .font(Theme.evidence)
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }

                Section("Name") {
                    TextField("Nights", text: $label)
                }
            }
            .navigationTitle("Shift")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(weekdays.isEmpty)
                }
            }
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let symbols = Calendar.current.veryShortWeekdaySymbols
        let name = symbols.indices.contains(weekday - 1) ? symbols[weekday - 1] : "?"
        let isOn = weekdays.contains(weekday)
        return Button {
            Haptics.select()
            if isOn { weekdays.remove(weekday) } else { weekdays.insert(weekday) }
        } label: {
            Text(name)
                .font(Theme.label(13, weight: .semibold))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background {
                    Capsule().fill(isOn ? Theme.Metric.sleep.opacity(0.28) : Theme.neutral(0.06))
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func save() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: start)
        var shift = original
        shift.startMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        shift.durationMinutes = Int((hours * 60).rounded())
        shift.weekdays = weekdays
        shift.date = nil
        shift.label = label.trimmingCharacters(in: .whitespaces).isEmpty ? nil : label
        onSave(shift)
        dismiss()
    }
}

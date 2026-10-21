import SvegliaCore
import SwiftUI

struct AlarmEditorView: View {
    let item: AlarmItem?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var time: Date
    @State private var weekdays: Set<Int>
    @State private var label: String
    @State private var soundName: String
    @State private var confirmsDelete = false
    /// Nil for a new alarm until the user picks: the default depends on whether a tag is paired.
    @State private var chosenMethod: DismissMethod?
    @State private var difficulty: MissionDifficulty

    init(item: AlarmItem?) {
        self.item = item
        let hour = item?.hour ?? 7
        let minute = item?.minute ?? 0
        _time = State(initialValue: Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now)
        _weekdays = State(initialValue: Set(item?.weekdays ?? Array(2...6)))
        _label = State(initialValue: item?.label ?? "")
        _soundName = State(initialValue: item?.soundName ?? RingtoneCatalog.systemSoundName)
        _chosenMethod = State(initialValue: item?.method)
        _difficulty = State(initialValue: item?.difficulty ?? .medium)
    }

    private var method: Binding<DismissMethod> {
        Binding(
            get: { chosenMethod ?? (model.tags.isEmpty ? .math : .tag) },
            set: { chosenMethod = $0 }
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    DatePicker("Ora", selection: $time, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                        .frame(maxWidth: .infinity)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ripeti").font(.headline)
                        WeekdayPicker(selection: $weekdays)
                        DayPresets(selection: $weekdays)
                    }
                    .card()

                    DismissMethodSection(method: method, difficulty: $difficulty, hasTag: !model.tags.isEmpty)
                        .card()
                    SoundRow(soundName: $soundName)

                    TextField("Nome (facoltativo)", text: $label)
                        .textInputAutocapitalization(.sentences)
                        .card()

                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)

                    if item != nil {
                        Button("Elimina sveglia", role: .destructive) { confirmsDelete = true }
                            .buttonStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle(item == nil ? "Nuova sveglia" : "Modifica sveglia")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }.fontWeight(.semibold)
                }
            }
            .confirmationDialog("Eliminare la sveglia?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    if let item { Task { await model.delete(item) } }
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var components: (hour: Int, minute: Int) {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
        return (parts.hour ?? 7, parts.minute ?? 0)
    }

    private var summary: String {
        let rule = AlarmRule(hour: components.hour, minute: components.minute, weekdays: weekdays)
        guard let next = Occurrences.upcoming(rule: rule, armedAt: .now, now: .now, count: 1).first else { return "" }
        let when = String(localized: "Suonerà \(Format.day(of: next).lowercased()) alle \(Format.time(next)), \(Format.countdown(to: next, from: .now)).")
        let how = method.wrappedValue == .tag && !model.tags.isEmpty
            ? String(localized: "Niente posticipo: per spegnerla serve il tag.")
            : String(localized: "Niente posticipo: per spegnerla serve la missione.")
        return "\(when) \(how)"
    }

    private func save() {
        let (hour, minute) = components
        let days = Format.mondayFirst.filter(weekdays.contains)
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        if let item {
            item.hour = hour
            item.minute = minute
            item.weekdays = days
            item.label = trimmed
            item.soundName = soundName
            item.isEnabled = true
            item.method = method.wrappedValue
            item.difficulty = difficulty
            Task { await model.commitChanges(to: item) }
        } else {
            let newItem = AlarmItem(hour: hour, minute: minute, weekdays: days, label: trimmed)
            newItem.method = method.wrappedValue
            newItem.difficulty = difficulty
            newItem.soundName = soundName
            Task { await model.add(newItem) }
        }
        dismiss()
    }
}

struct WeekdayPicker: View {
    @Binding var selection: Set<Int>

    var body: some View {
        let symbols = Calendar.current.veryShortStandaloneWeekdaySymbols
        let names = Calendar.current.standaloneWeekdaySymbols
        HStack(spacing: 8) {
            ForEach(Format.mondayFirst, id: \.self) { day in
                let isOn = selection.contains(day)
                Button {
                    if isOn { selection.remove(day) } else { selection.insert(day) }
                } label: {
                    Text(symbols[day - 1])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .foregroundStyle(isOn ? .black.opacity(0.85) : .white)
                        .background(isOn ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(names[day - 1])
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

private struct DayPresets: View {
    @Binding var selection: Set<Int>

    private let presets: [(LocalizedStringKey, Set<Int>)] = [
        ("Feriali", Set(2...6)),
        ("Ogni giorno", Set(1...7)),
        ("Weekend", [1, 7]),
        ("Una volta", []),
    ]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(presets.indices, id: \.self) { index in
                    let (title, days) = presets[index]
                    Button { selection = days } label: {
                        Text(title)
                            .font(.footnote.weight(.medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selection == days ? Theme.sunrise.opacity(0.25) : Theme.surface, in: .capsule)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollIndicators(.hidden)
    }
}

/// "Suoneria" row of the editor: shows the current sound, opens the picker.
private struct SoundRow: View {
    @Binding var soundName: String

    var body: some View {
        NavigationLink {
            RingtonePickerView(selection: $soundName)
        } label: {
            HStack(spacing: 12) {
                Text("Suoneria").font(.headline)
                Spacer(minLength: 8)
                Text(RingtoneCatalog.displayName(for: soundName))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.muted)
                    .accessibilityHidden(true)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityHint("Scegli il suono della sveglia")
    }
}

import SvegliaCore
import SwiftData
import SwiftUI

/// One screen: the next alarm, big, with its switch. Everything else is one tap away.
struct HomeView: View {
    @Environment(AppModel.self) private var model
    @Query(sort: [SortDescriptor(\AlarmItem.hour), SortDescriptor(\AlarmItem.minute)]) private var alarms: [AlarmItem]
    @Query(sort: \PairedTag.pairedAt) private var tags: [PairedTag]
    @Query(sort: \WakeRecord.alarmStart, order: .reverse) private var records: [WakeRecord]

    @State private var editor: EditorTarget?
    @State private var pendingChange: PendingChange?
    @State private var showsSettings = false
    @State private var showsPairing = false

    var body: some View {
        NavigationStack {
            TimelineView(.everyMinute) { timeline in
                let now = timeline.date
                let next = model.nextAlarm(now: now)
                let hero = next?.item ?? alarms.first
                ScrollView {
                    VStack(spacing: 16) {
                        notices
                        BlockStatusCard(now: now)
                        if GoodNightButton.isEvening(now) {
                            GoodNightButton(style: .hero)
                        }
                        if let hero {
                            NextAlarmCard(
                                item: hero,
                                start: next?.start,
                                now: now,
                                streak: WakeInsights.streak(records.map(\.result)),
                                isOn: enabledBinding(hero),
                                onEdit: { open(hero) }
                            )
                        } else {
                            EmptyAlarmCard { editor = .new }
                        }
                        SleepScoreCard(now: now)
                        if WakeInsights.tagSeemsTooClose(records.map(\.result)) {
                            TooCloseCard()
                        }
                        let others = alarms.filter { $0.id != hero?.id }
                        if !others.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(others) { item in
                                    AlarmRow(item: item, isOn: enabledBinding(item)) { open(item) }
                                    if item.id != others.last?.id { Divider().overlay(Theme.stroke) }
                                }
                            }
                            .card()
                        }
                        if hero != nil {
                            Button { editor = .new } label: {
                                Label("Aggiungi sveglia", systemImage: "plus")
                            }
                            .buttonStyle(.secondary)
                        }
                        if !GoodNightButton.isEvening(now) {
                            GoodNightButton(style: .compact)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 40)
                }
                .scrollIndicators(.hidden)
                .navigationTitle(Format.greeting(at: now))
            }
            .background(Theme.night.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showsSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Impostazioni")
                }
            }
        }
        .overlay {
            // The night screen covers Home while the sleep is tracked (not a modal, so the ringing screen still shows).
            if model.sleep.isListening {
                NightView().transition(.opacity)
            }
        }
        .animation(.smooth, value: model.sleep.isListening)
        .sheet(item: $editor) { target in
            AlarmEditorView(item: target.item)
        }
        .sheet(item: $pendingChange) { change in
            UnlockSheet { perform(change) }
        }
        .sheet(isPresented: $showsSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showsPairing) {
            PairTagSheet()
        }
    }

    @ViewBuilder private var notices: some View {
        if model.scheduler.isDenied {
            NoticeCard(
                icon: "bell.slash.fill",
                title: "Le sveglie sono disattivate",
                message: "Senza il permesso, iOS non le fa suonare. Attivalo nelle Impostazioni.",
                action: "Apri Impostazioni"
            ) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
        }
        if let error = model.scheduler.lastError {
            NoticeCard(icon: "exclamationmark.triangle.fill", title: "Qualcosa non va", message: LocalizedStringKey(error))
        }
        if tags.isEmpty {
            NoticeCard(
                icon: "wave.3.right",
                title: "Abbina il tuo tag",
                message: "È l'unico modo per spegnere la sveglia. Senza, si ferma da sola dopo 30 minuti.",
                action: "Abbina ora"
            ) { showsPairing = true }
        }
    }

    private func enabledBinding(_ item: AlarmItem) -> Binding<Bool> {
        Binding(
            get: { item.isEnabled },
            set: { on in
                if !on, model.needsUnlock(toChange: item) {
                    pendingChange = .toggle(item, on: on)
                } else {
                    Task { await model.setEnabled(on, for: item) }
                }
            }
        )
    }

    private func open(_ item: AlarmItem) {
        if model.needsUnlock(toChange: item) {
            pendingChange = .edit(item)
        } else {
            editor = .existing(item)
        }
    }

    private func perform(_ change: PendingChange) {
        switch change {
        case .toggle(let item, let on): Task { await model.setEnabled(on, for: item) }
        case .edit(let item): editor = .existing(item)
        }
    }
}

enum EditorTarget: Identifiable {
    case new
    case existing(AlarmItem)

    var id: String {
        switch self {
        case .new: "new"
        case .existing(let item): item.id.uuidString
        }
    }

    var item: AlarmItem? {
        if case .existing(let item) = self { item } else { nil }
    }
}

enum PendingChange: Identifiable {
    case toggle(AlarmItem, on: Bool)
    case edit(AlarmItem)

    var id: String {
        switch self {
        case .toggle(let item, _): "toggle-\(item.id)"
        case .edit(let item): "edit-\(item.id)"
        }
    }
}

// MARK: - Cards

private struct NextAlarmCard: View {
    let item: AlarmItem
    let start: Date?
    let now: Date
    let streak: Int
    @Binding var isOn: Bool
    let onEdit: () -> Void

    @ScaledMetric(relativeTo: .largeTitle) private var timeSize: CGFloat = 88

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(dayText, systemImage: isOn ? "alarm.fill" : "alarm")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(isOn ? Theme.sunrise : Theme.muted)
                Spacer()
                Toggle("Attiva", isOn: $isOn)
                    .labelsHidden()
            }
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(Format.time(hour: item.hour, minute: item.minute))
                        .font(.system(size: timeSize, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? .white : Theme.muted)
                        .minimumScaleFactor(0.6)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Modifica la sveglia")

            if isOn, let start {
                Divider().overlay(Theme.stroke)
                Label {
                    Text("Vai a letto alle \(Format.time(Bedtime.suggestion(forWakeUp: start))) per \(Bedtime.recommendedCycles) cicli di sonno")
                } icon: {
                    Image(systemName: "moon.stars.fill").foregroundStyle(Theme.sunrise)
                }
                .font(.footnote)
                .foregroundStyle(Theme.muted)
            }
            if streak > 0 {
                Label("\(streak) mattine di fila", systemImage: "flame.fill")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.sunrise)
            }
        }
        .card()
        .background(alignment: .topTrailing) {
            if isOn {
                Circle()
                    .fill(Theme.sunrise.opacity(0.22))
                    .frame(width: 220)
                    .blur(radius: 70)
                    .offset(x: 40, y: -60)
                    .allowsHitTesting(false)
            }
        }
    }

    private var dayText: String {
        guard isOn, let start else { return String(localized: "Disattivata") }
        return Format.day(of: start, now: now)
    }

    private var subtitle: String {
        var parts: [String] = []
        if isOn, let start { parts.append(String(localized: "Suona \(Format.countdown(to: start, from: now))")) }
        parts.append(Format.days(item.weekdays))
        if !item.label.isEmpty { parts.append(item.label) }
        return parts.joined(separator: " · ")
    }
}

private struct AlarmRow: View {
    let item: AlarmItem
    @Binding var isOn: Bool
    let onEdit: () -> Void

    var body: some View {
        HStack {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Format.time(hour: item.hour, minute: item.minute))
                        .font(.system(.title, design: .rounded).weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(isOn ? .white : Theme.muted)
                    Text(item.label.isEmpty ? Format.days(item.weekdays) : "\(Format.days(item.weekdays)) · \(item.label)")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            Toggle("Attiva", isOn: $isOn)
                .labelsHidden()
        }
        .padding(.vertical, 10)
    }
}

private struct EmptyAlarmCard: View {
    let onCreate: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            PuckIllustration(size: 90)
            Text("Nessuna sveglia")
                .font(.system(.title2, design: .rounded).weight(.bold))
            Text("Imposta l'ora: per spegnerla dovrai alzarti e raggiungere il tuo tag.")
                .font(.callout)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            Button("Imposta la sveglia", action: onCreate)
                .buttonStyle(.primary)
        }
        .frame(maxWidth: .infinity)
        .card()
    }
}

private struct TooCloseCard: View {
    var body: some View {
        NoticeCard(
            icon: "figure.walk",
            title: "Il tag è troppo vicino al letto?",
            message: "Nelle ultime mattine l'hai raggiunto in pochi secondi. Spostalo in un'altra stanza: funziona meglio."
        )
    }
}

struct NoticeCard: View {
    let icon: String
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    var action: LocalizedStringKey?
    var onAction: (() -> Void)?

    init(icon: String, title: LocalizedStringKey, message: LocalizedStringKey, action: LocalizedStringKey? = nil, onAction: (() -> Void)? = nil) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
        self.onAction = onAction
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.sunrise)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.headline)
                Text(message).font(.subheadline).foregroundStyle(Theme.muted)
                if let action, let onAction {
                    Button(action: onAction) {
                        Text(action).font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 2)
                }
            }
        }
        .card()
    }
}

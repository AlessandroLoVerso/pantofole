import FamilyControls
import ManagedSettings
import SvegliaCore
import SwiftData
import SwiftUI

// MARK: - Settings section

/// "Blocco app" in Settings: the list of blocks, or the invitation to start.
struct BlocksSection: View {
    @Environment(AppModel.self) private var model

    @State private var showsIntro = false
    @State private var editing: BlockDraft?
    @State private var afterIntro: BlockDraft?
    @State private var locked: LockedAction?
    @State private var unlocked: LockedAction?
    @State private var toDelete: AppBlock?

    private var controller: BlockController { model.blocks }

    var body: some View {
        Section {
            if !controller.isAuthorized {
                Button { showsIntro = true } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Metti in pausa le distrazioni").foregroundStyle(.white)
                            Text("Scegli le app e gli orari: le sblocchi prima solo con il tag.")
                                .font(.footnote)
                                .foregroundStyle(Theme.muted)
                        }
                    } icon: {
                        Image(systemName: "moon.zzz.fill").foregroundStyle(Theme.sunrise)
                    }
                }
            } else {
                ForEach(controller.blocks) { block in
                    BlockRow(
                        block: block,
                        now: .now,
                        isOn: enabledBinding(block),
                        onEdit: { perform(.edit(block)) },
                        onUnlock: { locked = .unlock(block) }
                    )
                    .swipeActions {
                        Button("Elimina", role: .destructive) { perform(.delete(block)) }
                    }
                }
                Button {
                    editing = BlockDraft(block: controller.suggestedBlock(), isNew: true)
                } label: {
                    Label(controller.blocks.isEmpty ? "Crea un blocco" : "Aggiungi blocco", systemImage: "plus.circle")
                }
                if let error = controller.lastError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(Theme.dawn)
                }
            }
        } header: {
            Text("Blocco app")
        } footer: {
            Text("Durante la fascia oraria le app scelte restano in pausa. Per sbloccarle prima serve il tag. Ci pensa Tempo di utilizzo di iOS: Pantofole non sa quali app hai scelto.")
        }
        .sheet(isPresented: $showsIntro, onDismiss: {
            if let draft = afterIntro {
                afterIntro = nil
                editing = draft
            }
        }) {
            BlockIntroSheet {
                afterIntro = BlockDraft(block: controller.suggestedBlock(), isNew: true)
            }
        }
        .sheet(item: $editing) { draft in
            BlockEditorView(draft: draft)
        }
        .sheet(item: $locked, onDismiss: {
            // The follow-up opens once the unlock sheet is gone.
            if let action = unlocked {
                unlocked = nil
                run(action)
            }
        }) { action in
            BlockUnlockSheet(until: action.block.activeInterval(at: .now)?.end) {
                controller.unlock(action.block)
                unlocked = action
            }
        }
        .confirmationDialog(
            "Eliminare il blocco?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            titleVisibility: .visible,
            presenting: toDelete
        ) { block in
            Button("Elimina \(block.name)", role: .destructive) { controller.delete(block) }
        } message: { _ in
            Text("Le app di questo blocco non verranno più messe in pausa.")
        }
    }

    /// While a block is running, changing it needs the tag (otherwise it would be a way out).
    private func perform(_ action: LockedAction) {
        if action.block.activeInterval(at: .now) != nil {
            locked = action
        } else {
            run(action)
        }
    }

    private func run(_ action: LockedAction) {
        switch action {
        case .unlock: break
        case .edit(let block): editing = BlockDraft(block: block, isNew: false)
        case .delete(let block): toDelete = block
        case .disable(let block): controller.setEnabled(false, for: block)
        }
    }

    private func enabledBinding(_ block: AppBlock) -> Binding<Bool> {
        Binding(
            get: { block.isEnabled },
            set: { on in
                if on { controller.setEnabled(true, for: block) } else { perform(.disable(block)) }
            }
        )
    }
}

private enum LockedAction: Identifiable {
    case unlock(AppBlock), edit(AppBlock), delete(AppBlock), disable(AppBlock)

    var block: AppBlock {
        switch self {
        case .unlock(let block), .edit(let block), .delete(let block), .disable(let block): block
        }
    }

    var id: String {
        switch self {
        case .unlock(let block): "unlock-\(block.id)"
        case .edit(let block): "edit-\(block.id)"
        case .delete(let block): "delete-\(block.id)"
        case .disable(let block): "disable-\(block.id)"
        }
    }
}

struct BlockDraft: Identifiable {
    var block: AppBlock
    var isNew: Bool
    var id: UUID { block.id }
}

private struct BlockRow: View {
    let block: AppBlock
    let now: Date
    @Binding var isOn: Bool
    let onEdit: () -> Void
    let onUnlock: () -> Void

    var body: some View {
        let active = block.activeInterval(at: now)
        HStack(spacing: 12) {
            Button(action: onEdit) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(block.name).foregroundStyle(isOn ? .white : Theme.muted)
                    Text("\(BlockText.window(block.window)) · \(BlockText.days(block.window))")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                    if let active {
                        Label("In pausa fino alle \(Format.time(active.end))", systemImage: "pause.circle.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.sunrise)
                    } else if block.isEnabled, let until = block.unlockedUntil, now < until {
                        Label("Sbloccate fino alle \(Format.time(until))", systemImage: "lock.open.fill")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.borderless)
            .accessibilityHint("Modifica il blocco")

            if active != nil {
                Button("Sblocca", action: onUnlock)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.borderless)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.sunrise.opacity(0.2), in: .capsule)
                    .accessibilityLabel("Sblocca ora \(block.name)")
            }
            Toggle("Attivo", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel("\(block.name) attivo")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Home card

/// Shown on Home while a block is pausing apps.
struct BlockStatusCard: View {
    let now: Date

    @Environment(AppModel.self) private var model
    @State private var showsUnlock = false

    var body: some View {
        if let until = model.blocks.pausedUntil(now: now) {
            HStack(spacing: 14) {
                Image(systemName: "moon.zzz.fill")
                    .font(.title3)
                    .foregroundStyle(Theme.sunrise)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("App in pausa fino alle \(Format.time(until))").font(.headline)
                    Text("Per sbloccarle prima serve il tag.").font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 0)
                Button("Sblocca") { showsUnlock = true }
                    .font(.subheadline.weight(.semibold))
                    .accessibilityLabel("Sblocca ora le app")
            }
            .card()
            .sheet(isPresented: $showsUnlock) {
                BlockUnlockSheet(until: until) { model.blocks.unlockAll() }
            }
        }
    }
}

// MARK: - Unlock with the tag

/// Scan the tag to free the paused apps until the end of the window.
struct BlockUnlockSheet: View {
    let until: Date?
    var onUnlocked: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Query private var tags: [PairedTag]
    @State private var message: LocalizedStringKey?
    @State private var isScanning = false
    @State private var showsPairing = false
    @State private var unlockedCount = 0

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: tags.isEmpty ? "wave.3.right" : "lock.open.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.sunrise)
                .padding(.top, 28)
                .accessibilityHidden(true)
            if tags.isEmpty {
                Text("Serve il tuo tag")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text("Le app si sbloccano prima solo scansionando il tag. Abbinane uno: poi tienilo lontano dal letto.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            } else {
                Text("Sblocca le app")
                    .font(.system(.title, design: .rounded).weight(.bold))
                Text(subtitle)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
            }
            if let message {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.dawn)
                    .multilineTextAlignment(.center)
            }
            Spacer(minLength: 0)
            if tags.isEmpty {
                Button {
                    showsPairing = true
                } label: {
                    Label("Abbina un tag", systemImage: "plus")
                }
                .buttonStyle(.primary)
            } else {
                Button {
                    Task { await unlock() }
                } label: {
                    Label(isScanning ? "Avvicina il tag…" : "Scansiona il tag", systemImage: "wave.3.right")
                }
                .buttonStyle(.primary)
                .disabled(isScanning)
            }
            Button("Annulla") { dismiss() }
                .foregroundStyle(Theme.muted)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Theme.night)
        .sensoryFeedback(.success, trigger: unlockedCount)
        .sheet(isPresented: $showsPairing) { PairTagSheet() }
    }

    private var subtitle: String {
        if let until {
            return String(localized: "Restano libere fino alle \(Format.time(until)), poi il blocco riparte come sempre.")
        }
        return String(localized: "Restano libere fino alla fine della fascia oraria.")
    }

    private func unlock() async {
        isScanning = true
        defer { isScanning = false }
        switch await model.scanTag() {
        case .unlocked, .stoppedAlarm:
            unlockedCount += 1
            onUnlocked()
            dismiss()
        case .wrongTag: message = "Questo non è il tuo tag."
        case .noPairedTag: message = "Non hai ancora abbinato un tag."
        case .failed(let text): message = LocalizedStringKey(text)
        case .cancelled: break
        }
    }
}

// MARK: - First time

/// Explains what happens before iOS asks for the Screen Time permission.
struct BlockIntroSheet: View {
    var onAuthorized: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var isAsking = false
    @State private var failed = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(Theme.sunriseGradient)
                        .padding(.top, 12)
                        .accessibilityHidden(true)
                    Text("Metti in pausa le distrazioni")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .multilineTextAlignment(.center)
                    VStack(alignment: .leading, spacing: 18) {
                        point("apps.iphone", "Scegli app e orari", "Per esempio i social dalle 23 alle 7: niente scroll a letto, niente scroll appena sveglio.")
                        point("hourglass", "Ci pensa iOS", "Tempo di utilizzo le mette in pausa e le libera da solo. Pantofole non sa quali app hai scelto.")
                        point("wave.3.right", "Sblocco solo col tag", "Se ti servono prima, scansiona il tag: devi alzarti per farlo.")
                    }
                    .card()
                    if failed {
                        Text("Permesso non concesso. Riprova, o controlla Impostazioni › Tempo di utilizzo.")
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(Theme.dawn)
                            .multilineTextAlignment(.center)
                    }
                    Button {
                        Task { await ask() }
                    } label: {
                        Text(isAsking ? "Un attimo…" : "Continua")
                    }
                    .buttonStyle(.primary)
                    .disabled(isAsking)
                    Text("iOS ti chiederà di confermare con Face ID o con il codice.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                }
                .padding(24)
            }
            .background(Theme.night.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .sensoryFeedback(.error, trigger: failed) { _, new in new }
    }

    private func point(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.sunrise)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func ask() async {
        isAsking = true
        defer { isAsking = false }
        if await model.blocks.requestAuthorization() {
            onAuthorized()
            dismiss()
        } else {
            failed = true
        }
    }
}

// MARK: - Editor

struct BlockEditorView: View {
    let isNew: Bool

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var block: AppBlock
    @State private var start: Date
    @State private var end: Date
    @State private var weekdays: Set<Int>
    @State private var selection: FamilyActivitySelection
    @State private var showsPicker = false
    @State private var confirmsDelete = false

    init(draft: BlockDraft) {
        isNew = draft.isNew
        let block = draft.block
        _block = State(initialValue: block)
        _start = State(initialValue: Self.date(block.window.startHour, block.window.startMinute))
        _end = State(initialValue: Self.date(block.window.endHour, block.window.endMinute))
        _weekdays = State(initialValue: block.window.startsEveryDay ? Set(1...7) : block.window.weekdays)
        _selection = State(initialValue: block.selection)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    if isNew { presets }

                    VStack(spacing: 14) {
                        TextField("Nome", text: $block.name)
                            .font(.title3.weight(.semibold))
                            .textInputAutocapitalization(.sentences)
                        Divider().overlay(Theme.stroke)
                        DatePicker("Dalle", selection: $start, displayedComponents: .hourAndMinute)
                        DatePicker("Alle", selection: $end, displayedComponents: .hourAndMinute)
                    }
                    .card()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Giorni").font(.headline)
                        WeekdayPicker(selection: $weekdays)
                    }
                    .card()

                    appsCard

                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(isValid ? Theme.muted : Theme.dawn)
                        .multilineTextAlignment(.center)

                    if !isNew {
                        Button("Elimina blocco", role: .destructive) { confirmsDelete = true }
                            .buttonStyle(.secondary)
                    }
                }
                .padding(20)
            }
            .background(Theme.night.ignoresSafeArea())
            .navigationTitle(isNew ? "Nuovo blocco" : "Modifica blocco")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annulla") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Salva") { save() }
                        .fontWeight(.semibold)
                        .disabled(!isValid)
                }
            }
            .familyActivityPicker(
                headerText: String(localized: "Scegli cosa mettere in pausa durante \"\(block.name)\"."),
                isPresented: $showsPicker,
                selection: $selection
            )
            .confirmationDialog("Eliminare il blocco?", isPresented: $confirmsDelete, titleVisibility: .visible) {
                Button("Elimina", role: .destructive) {
                    model.blocks.delete(block)
                    dismiss()
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    private var presets: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(BlockPreset.allCases) { preset in
                    let isOn = preset.window == window && block.name == preset.title
                    Button {
                        block.name = preset.title
                        start = Self.date(preset.window.startHour, preset.window.startMinute)
                        end = Self.date(preset.window.endHour, preset.window.endMinute)
                        weekdays = preset.window.startsEveryDay ? Set(1...7) : preset.window.weekdays
                    } label: {
                        Text("\(preset.title) \(BlockText.window(preset.window))")
                            .font(.footnote.weight(.semibold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .foregroundStyle(isOn ? .black.opacity(0.85) : .white)
                            .background(isOn ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                }
            }
        }
        .scrollIndicators(.hidden)
        .sensoryFeedback(.selection, trigger: block.name)
    }

    private var appsCard: some View {
        Button { showsPicker = true } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("App da mettere in pausa").font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                }
                if selectionIsEmpty {
                    Text("Tocca per scegliere app, categorie o siti.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.sunrise)
                } else {
                    HStack(spacing: 8) {
                        ForEach(Array(selection.applicationTokens.prefix(6)), id: \.self) { token in
                            Label(token).labelStyle(.iconOnly)
                        }
                        ForEach(Array(selection.categoryTokens.prefix(max(0, 6 - selection.applicationTokens.count))), id: \.self) { token in
                            Label(token).labelStyle(.iconOnly)
                        }
                    }
                    .font(.title2)
                    .accessibilityHidden(true)
                    Text(BlockText.selection(selection))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .card()
        .accessibilityHint("Apre l'elenco delle app")
    }

    private var window: BlockWindow {
        let calendar = Calendar.current
        let s = calendar.dateComponents([.hour, .minute], from: start)
        let e = calendar.dateComponents([.hour, .minute], from: end)
        return BlockWindow(
            startHour: s.hour ?? 0, startMinute: s.minute ?? 0,
            endHour: e.hour ?? 0, endMinute: e.minute ?? 0,
            weekdays: weekdays == Set(1...7) ? [] : weekdays
        )
    }

    private var selectionIsEmpty: Bool {
        selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty && selection.webDomainTokens.isEmpty
    }

    private var isValid: Bool {
        window.isValid && !weekdays.isEmpty && !selectionIsEmpty
            && !block.name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var summary: String {
        if !window.isValid { return String(localized: "La fascia deve durare almeno 15 minuti.") }
        if weekdays.isEmpty { return String(localized: "Scegli almeno un giorno.") }
        if selectionIsEmpty { return String(localized: "Scegli le app da mettere in pausa.") }
        let from = Format.time(hour: window.startHour, minute: window.startMinute)
        let to = Format.time(hour: window.endHour, minute: window.endMinute)
        let days = BlockText.days(window)
        return String(localized: "In pausa dalle \(from) alle \(to) · \(days). Per sbloccarle prima serve il tag.")
    }

    private func save() {
        var saved = block
        saved.name = block.name.trimmingCharacters(in: .whitespaces)
        saved.window = window
        saved.selection = selection
        saved.isEnabled = true
        model.blocks.save(saved)
        dismiss()
    }

    private static func date(_ hour: Int, _ minute: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }
}

// MARK: - Text

enum BlockText {
    /// "23:00–07:00".
    static func window(_ window: BlockWindow) -> String {
        "\(Format.time(hour: window.startHour, minute: window.startMinute))–\(Format.time(hour: window.endHour, minute: window.endMinute))"
    }

    static func days(_ window: BlockWindow) -> String {
        window.startsEveryDay ? String(localized: "Ogni giorno") : Format.days(Array(window.weekdays))
    }

    /// "3 app · 1 categoria · 2 siti".
    static func selection(_ selection: FamilyActivitySelection) -> String {
        var parts: [String] = []
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        let sites = selection.webDomainTokens.count
        if apps > 0 { parts.append(String(localized: "\(apps) app")) }
        if categories > 0 {
            parts.append(categories == 1 ? String(localized: "1 categoria") : String(localized: "\(categories) categorie"))
        }
        if sites > 0 { parts.append(sites == 1 ? String(localized: "1 sito") : String(localized: "\(sites) siti")) }
        return parts.joined(separator: " · ")
    }
}

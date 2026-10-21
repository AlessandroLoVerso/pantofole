import SwiftUI

/// Pair a tag, then say where it will live. Used in onboarding and in Settings.
struct PairTagFlow: View {
    var onFinished: (PairedTag) -> Void
    /// Shown under the main button until a tag is paired (onboarding: "I don't have a tag yet").
    var onSkip: (() -> Void)?

    @Environment(AppModel.self) private var model
    @State private var phase = Phase.ready
    @State private var place: String?

    private enum Phase: Equatable {
        case ready
        case scanning
        case naming(PairedTag)
        case problem(String)
    }

    private let places: [String] = [
        String(localized: "Bagno"),
        String(localized: "Cucina"),
        String(localized: "Corridoio"),
        String(localized: "Ingresso"),
        String(localized: "Altro"),
    ]

    var body: some View {
        VStack(spacing: 22) {
            switch phase {
            case .ready, .scanning, .problem:
                PuckIllustration(size: 110, pulsing: phase == .scanning)
                Text("Abbina il tuo tag")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Va bene il nostro dischetto o qualsiasi tag NFC. Avvicina la parte alta dell'iPhone al tag.")
                    .font(.body)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                if case .problem(let message) = phase {
                    Text(message)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(Theme.dawn)
                        .multilineTextAlignment(.center)
                }
                Button {
                    Task { await pair() }
                } label: {
                    Label(phase == .scanning ? "Avvicina il tag…" : "Abbina il tag", systemImage: "wave.3.right")
                }
                .buttonStyle(.primary)
                .disabled(phase == .scanning)
                if let onSkip {
                    Button("Non ho ancora un tag", action: onSkip)
                        .foregroundStyle(Theme.muted)
                }

            case .naming(let tag):
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.sunriseGradient)
                    .symbolEffect(.bounce, value: phase)
                Text("Tag abbinato!")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Dove lo metterai? Più è lontano dal letto, meglio funziona.")
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                FlowChips(options: places, selection: $place)
                Button("Fatto") {
                    tag.name = place ?? String(localized: "Il mio tag")
                    model.save()
                    onFinished(tag)
                }
                .buttonStyle(.primary)
                .disabled(place == nil)
            }
        }
        .sensoryFeedback(.success, trigger: phase) { _, new in
            if case .naming = new { true } else { false }
        }
    }

    private func pair() async {
        phase = .scanning
        switch await model.pairNewTag() {
        case .paired(let tag): withAnimation(.spring) { phase = .naming(tag) }
        case .alreadyPaired: phase = .problem(String(localized: "Questo tag è già abbinato."))
        case .failed(let message): phase = .problem(message)
        case .cancelled: phase = .ready
        }
    }
}

/// A wrapping row of selectable capsules.
private struct FlowChips: View {
    let options: [String]
    @Binding var selection: String?

    var body: some View {
        let columns = [GridItem(.adaptive(minimum: 100), spacing: 8)]
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(options, id: \.self) { option in
                let isOn = selection == option
                Button { selection = option } label: {
                    Text(option)
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isOn ? .black.opacity(0.85) : .white)
                        .background(isOn ? AnyShapeStyle(Theme.sunriseGradient) : AnyShapeStyle(Theme.surface), in: .capsule)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: selection)
    }
}

struct PairTagSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                PairTagFlow { _ in dismiss() }
                    .padding(24)
            }
            .background(Theme.night.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
    }
}

/// Asked before changing an alarm in the hours before it rings.
struct UnlockSheet: View {
    var onUnlocked: () -> Void

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var message: LocalizedStringKey?
    @State private var isScanning = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Theme.sunrise)
                .padding(.top, 28)
            Text("Modifica bloccata")
                .font(.system(.title, design: .rounded).weight(.bold))
            Text("Mancano meno di 8 ore alla sveglia. Per cambiarla scansiona il tuo tag: così non la spegni dal letto.")
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let message {
                Text(message)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.dawn)
            }
            Spacer(minLength: 0)
            Button {
                Task { await unlock() }
            } label: {
                Label("Scansiona il tag", systemImage: "wave.3.right")
            }
            .buttonStyle(.primary)
            .disabled(isScanning)
            Button("Annulla") { dismiss() }
                .foregroundStyle(Theme.muted)
        }
        .padding(24)
        .presentationDetents([.medium])
        .presentationBackground(Theme.night)
    }

    private func unlock() async {
        isScanning = true
        defer { isScanning = false }
        switch await model.scanTag() {
        case .unlocked, .stoppedAlarm:
            dismiss()
            onUnlocked()
        case .wrongTag: message = "Questo non è il tuo tag."
        case .noPairedTag: message = "Non hai ancora abbinato un tag."
        case .failed(let text): message = LocalizedStringKey(text)
        case .cancelled: break
        }
    }
}

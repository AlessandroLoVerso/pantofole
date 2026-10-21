import SwiftUI

/// Before the first night: where to put the iPhone, plus a 10-second position test.
struct PlacementSheet: View {
    /// Nil when opened only to read the tips (from the history).
    var onStart: (() -> Void)?

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var test = TestState.idle
    @State private var testEnds = Date.now

    enum TestState: Equatable {
        case idle, running, good, tooFar, unavailable
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    Text("Dove metto l'iPhone?")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    VStack(alignment: .leading, spacing: 18) {
                        tip("bed.double.fill", "Sul comodino", "A mezzo metro, un metro al massimo, dalla tua testa.")
                        tip("mic.fill", "Microfono verso il letto", "Il bordo in basso dell'iPhone, dove c'è il microfono, rivolto verso di te.")
                        tip("battery.100percent.bolt", "In carica tutta la notte", "L'ascolto dura ore: collegalo prima di dormire.")
                        tip("xmark.octagon.fill", "Mai sotto il cuscino", "Né sul materasso: si scalda e non sente bene.")
                        tip("person.2.fill", "Se dormite in due", "Tienilo dal tuo lato del letto.")
                        tip("fan.fill", "Ventilatore o rumore bianco vanno bene", "Un suono costante diventa il nuovo silenzio.")
                        tip("lock.fill", "L'audio non lascia mai la stanza", "Viene analizzato in memoria e mai registrato, salvato o inviato. Restano solo numeri, minuto per minuto, sul tuo iPhone.")
                    }
                    .card()
                    testCard
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
            .background(Theme.night.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                if let onStart {
                    Button(action: onStart) {
                        Label("Buonanotte", systemImage: "moon.zzz.fill")
                    }
                    .buttonStyle(.primary)
                    .disabled(test == .running)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 8)
                    .background(Theme.night.opacity(0.9))
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chiudi") { dismiss() }
                }
            }
        }
        .sensoryFeedback(trigger: test) { _, new in
            switch new {
            case .good: .success
            case .tooFar, .unavailable: .warning
            default: nil
            }
        }
    }

    private var testCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Prova la posizione", systemImage: "waveform")
                .font(.headline)
            switch test {
            case .idle:
                Text("Appoggia l'iPhone dove dormirà, sdraiati e muoviti un po' sotto le coperte per 10 secondi.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                Button("Inizia la prova") { runTest() }
                    .buttonStyle(.secondary)
            case .running:
                Text("Ora muoviti un po' sotto le coperte…")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                LevelMeter(level: model.sleep.testLevel)
                ProgressView(timerInterval: testEnds.addingTimeInterval(-10)...testEnds, countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(Theme.sunrise)
            case .good:
                result("checkmark.circle.fill", "Posizione buona", "Ti sento bene da qui. Lascialo così.")
                Button("Riprova") { runTest() }.font(.subheadline)
            case .tooFar:
                result("arrow.down.right.and.arrow.up.left.circle.fill", "Avvicinalo", "Ti sento poco: avvicina l'iPhone alla testa, con il microfono verso di te, e riprova.")
                Button("Riprova") { runTest() }.buttonStyle(.secondary)
            case .unavailable:
                result("mic.slash.fill", "Microfono non disponibile", "Consenti l'uso del microfono nelle Impostazioni per provare la posizione.")
            }
        }
        .card()
        .animation(.smooth, value: test)
    }

    private func runTest() {
        testEnds = .now.addingTimeInterval(10)
        test = .running
        Task {
            switch await model.sleep.runPlacementTest() {
            case true?: test = .good
            case false?: test = .tooFar
            case nil: test = .unavailable
            }
        }
    }

    private func tip(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(Theme.sunrise)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func result(_ icon: String, _ title: LocalizedStringKey, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title)
                .foregroundStyle(Theme.sunriseGradient)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.title3.weight(.bold))
                Text(text).font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Live loudness bar for the position test.
private struct LevelMeter: View {
    let level: Double

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(Theme.surface)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(Theme.sunriseGradient)
                        .frame(width: geometry.size.width * min(1, max(0.03, level / 30)))
                        .animation(.easeOut(duration: 0.15), value: level)
                }
        }
        .frame(height: 10)
        .accessibilityHidden(true)
    }
}

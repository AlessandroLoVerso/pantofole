import SwiftUI

/// Full screen while an alarm rings: one thing to do, "go to the tag". After the scan, the reward.
struct RingingView: View {
    @Environment(AppModel.self) private var model
    @State private var isScanning = false
    @State private var hint: LocalizedStringKey?
    @State private var glow = false

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            RadialGradient(
                colors: [Theme.sunrise.opacity(glow ? 0.45 : 0.25), .clear],
                center: .bottom,
                startRadius: 10,
                endRadius: 520
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 2.2).repeatForever(), value: glow)

            if let wake = model.lastWake {
                success(wake)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            } else {
                ringing
                    .transition(.opacity)
            }
        }
        .animation(.spring(duration: 0.5), value: model.lastWake)
        .sensoryFeedback(.success, trigger: model.lastWake)
        .onAppear { glow = true }
        .task(id: ScanRequest.shared.isPending) {
            guard ScanRequest.shared.isPending else { return }
            ScanRequest.shared.isPending = false
            await scan()
        }
        .onChange(of: model.ringingStart) { _, start in
            // The chain ended without a scan (emergency exit) or was stopped elsewhere.
            if start == nil, model.lastWake == nil { model.dismissRingingScreen() }
        }
        .interactiveDismissDisabled()
    }

    private var ringing: some View {
        VStack(spacing: 24) {
            Spacer()
            PuckIllustration(size: 120)
            TimelineView(.everyMinute) { timeline in
                Text(Format.time(timeline.date))
                    .font(.system(.title2, design: .rounded).weight(.medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.muted)
            }
            Text("Alzati.")
                .font(.system(size: 60, weight: .bold, design: .rounded))
            Text("Vai al tuo tag e appoggiaci sopra l'iPhone.")
                .font(.title3)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if let hint {
                Text(hint)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(Theme.dawn)
                    .multilineTextAlignment(.center)
                    .transition(.opacity)
            }
            Spacer()
            Button {
                Task { await scan() }
            } label: {
                Label(isScanning ? "Avvicina il tag…" : "Scansiona il tag", systemImage: "wave.3.right")
            }
            .buttonStyle(.primary)
            .disabled(isScanning)
            Text("Puoi zittirla, ma ricomincia dopo un minuto.")
                .font(.footnote)
                .foregroundStyle(Theme.muted)
        }
        .padding(24)
    }

    private func success(_ wake: WakeSummary) -> some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "sun.max.fill")
                .font(.system(size: 84))
                .foregroundStyle(Theme.sunriseGradient)
                .symbolEffect(.bounce, value: wake)
            Text("Buongiorno!")
                .font(.system(size: 48, weight: .bold, design: .rounded))
            Text("In piedi in \(Format.duration(wake.secondsToScan)).")
                .font(.title3)
                .foregroundStyle(Theme.muted)
            if wake.streak > 1 {
                Label("\(wake.streak) mattine di fila", systemImage: "flame.fill")
                    .font(.headline)
                    .foregroundStyle(Theme.sunrise)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Theme.sunrise.opacity(0.15), in: .capsule)
            }
            Spacer()
            Button("Inizia la giornata") { model.dismissRingingScreen() }
                .buttonStyle(.primary)
        }
        .padding(24)
    }

    private func scan() async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        withAnimation { hint = nil }
        let outcome = await model.scanTag()
        withAnimation {
            switch outcome {
            case .stoppedAlarm, .cancelled: hint = nil
            case .unlocked: model.dismissRingingScreen()
            case .wrongTag: hint = "Questo non è il tuo tag."
            case .noPairedTag: hint = "Non hai ancora abbinato un tag: la sveglia si fermerà da sola dopo 30 minuti."
            case .failed(let message): hint = LocalizedStringKey(message)
            }
        }
    }
}

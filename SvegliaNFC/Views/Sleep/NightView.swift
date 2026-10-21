import SwiftUI

/// While the night is tracked: almost black, a big dim clock, nothing to do but sleep.
struct NightView: View {
    @Environment(AppModel.self) private var model
    @State private var confirmsWake = false
    @State private var isCharging = Battery.isCharging
    @State private var breathe = false

    @ScaledMetric(relativeTo: .largeTitle) private var clockSize: CGFloat = 76

    private static let tips: [LocalizedStringKey] = [
        "Puoi bloccare l'iPhone: continuo ad ascoltare.",
        "Lascialo in carica, con il microfono verso il letto.",
        "La sveglia suona comunque, come sempre.",
        "Quando spegni la sveglia con il tag, chiudo la notte da solo.",
        "Un ventilatore o il rumore bianco non danno fastidio.",
        "L'audio non viene mai registrato: restano solo numeri.",
    ]

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            TimelineView(.everyMinute) { timeline in
                VStack(spacing: 18) {
                    Spacer()
                    Circle()
                        .fill(Theme.sunrise.opacity(0.5))
                        .frame(width: 8, height: 8)
                        .scaleEffect(breathe ? 1.4 : 0.8)
                        .opacity(breathe ? 0.9 : 0.35)
                        .animation(.easeInOut(duration: 4).repeatForever(), value: breathe)
                        .accessibilityHidden(true)
                    Text(Format.time(timeline.date))
                        .font(.system(size: clockSize, weight: .thin, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                    Text("Sto ascoltando il tuo sonno")
                        .font(.title3)
                        .foregroundStyle(Theme.muted)
                    if let next = model.nextAlarm(now: timeline.date) {
                        Label("Sveglia \(Format.day(of: next.start, now: timeline.date).lowercased()) alle \(Format.time(next.start))", systemImage: "alarm")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                    }
                    Spacer()
                    if !isCharging {
                        Label("Collega il caricatore: l'ascolto dura tutta la notte.", systemImage: "bolt.fill")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.sunrise)
                            .multilineTextAlignment(.center)
                    }
                    if let error = model.sleep.lastError {
                        Label(error, systemImage: "mic.slash")
                            .font(.footnote)
                            .foregroundStyle(Theme.dawn)
                    }
                    Text(Self.tip(at: timeline.date))
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                        .multilineTextAlignment(.center)
                        .contentTransition(.opacity)
                        .frame(minHeight: 40)
                    Button("Sono sveglio") { confirmsWake = true }
                        .buttonStyle(.secondary)
                        .accessibilityHint("Termina l'ascolto della notte")
                }
                .padding(24)
            }
            .foregroundStyle(.white)
            .opacity(0.7)
        }
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onAppear { breathe = true }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            isCharging = Battery.isCharging
        }
        .confirmationDialog("Chiudere la notte?", isPresented: $confirmsWake, titleVisibility: .visible) {
            Button("Sono sveglio") { model.sleep.finish() }
            Button("Continua ad ascoltare", role: .cancel) {}
        } message: {
            Text("Smetto di ascoltare e preparo il riepilogo.")
        }
        .sensoryFeedback(.impact(weight: .light), trigger: confirmsWake)
    }

    /// A different tip every few minutes.
    private static func tip(at date: Date) -> LocalizedStringKey {
        let minutes = Int(date.timeIntervalSinceReferenceDate / 60)
        return tips[(minutes / 3) % tips.count]
    }
}

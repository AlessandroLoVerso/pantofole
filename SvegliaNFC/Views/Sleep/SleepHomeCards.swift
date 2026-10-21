import SvegliaCore
import SwiftData
import SwiftUI

/// "Buonanotte": the big evening card, or a quiet button during the day.
/// The first time it shows the placement tips; it warns when the battery is low.
struct GoodNightButton: View {
    enum Style { case hero, compact }

    let style: Style

    /// Prominent from 20:00 to 4:00.
    static func isEvening(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 20 || hour < 4
    }

    @Environment(AppModel.self) private var model
    @AppStorage("sleepTipsSeen") private var tipsSeen = false
    @State private var showsTips = false
    @State private var startAfterTips = false
    @State private var warnsLowBattery = false
    @State private var micDenied = false
    @State private var taps = 0

    var body: some View {
        content
            .sheet(isPresented: $showsTips, onDismiss: {
                if startAfterTips { startAfterTips = false; begin() }
            }) {
                PlacementSheet {
                    tipsSeen = true
                    startAfterTips = true
                    showsTips = false
                }
            }
            .alert("Batteria bassa", isPresented: $warnsLowBattery) {
                Button("Inizia comunque") { Task { await start() } }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("L'iPhone è al \(Int((Battery.level ?? 0) * 100))% e non è in carica. Collegalo, o l'ascolto potrebbe fermarsi prima del mattino.")
            }
            .alert("Serve il microfono", isPresented: $micDenied) {
                Button("Apri Impostazioni") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                Button("Annulla", role: .cancel) {}
            } message: {
                Text("Per ascoltare il sonno serve il microfono. L'audio viene analizzato sull'iPhone e mai registrato, salvato o inviato.")
            }
            .sensoryFeedback(.impact(weight: .light), trigger: taps)
    }

    @ViewBuilder private var content: some View {
        switch style {
        case .hero:
            VStack(alignment: .leading, spacing: 14) {
                Label("È ora di riposare", systemImage: "moon.stars.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.sunrise)
                Text("Metti l'iPhone sul comodino, in carica. Ascolto il tuo sonno e domattina trovi il punteggio.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                Button(action: tap) {
                    Label("Buonanotte", systemImage: "moon.zzz.fill")
                }
                .buttonStyle(.primary)
                .accessibilityHint("Inizia ad ascoltare il sonno")
                Label("L'audio resta sull'iPhone e non viene mai registrato.", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .card()
        case .compact:
            Button(action: tap) {
                Label("Traccia il sonno", systemImage: "moon.zzz.fill")
            }
            .buttonStyle(.secondary)
            .accessibilityHint("Inizia ad ascoltare il sonno")
        }
    }

    private func tap() {
        taps += 1
        if tipsSeen { begin() } else { showsTips = true }
    }

    private func begin() {
        if Battery.isLowForTheNight {
            warnsLowBattery = true
        } else {
            Task { await start() }
        }
    }

    private func start() async {
        if await model.sleep.start() == .microphoneDenied { micDenied = true }
    }
}

/// Today's score on Home: ring, one line of explanation, tap for the history.
struct SleepScoreCard: View {
    let now: Date

    @Query(filter: #Predicate<SleepSession> { $0.end != nil }, sort: \SleepSession.start, order: .reverse)
    private var sessions: [SleepSession]
    @Query(sort: \WakeRecord.alarmStart, order: .reverse) private var records: [WakeRecord]

    var body: some View {
        if let latest = DayScore.all(sessions: Array(sessions.prefix(40)), records: Array(records.prefix(40))).first {
            NavigationLink {
                SleepHistoryView()
            } label: {
                HStack(spacing: 18) {
                    ScoreRing(score: latest.score, size: 84, lineWidth: 9)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(title(for: latest.day))
                            .font(.headline)
                        Text(SleepFormat.note(latest.note))
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if latest.sleepQuality == nil {
                            Text("Stasera tocca Buonanotte per contare anche il sonno.")
                                .font(.caption)
                                .foregroundStyle(Theme.sunrise)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
                .card()
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Mostra l'andamento del punteggio")
        }
    }

    private func title(for day: Date) -> LocalizedStringKey {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: now) { return "Punteggio di oggi" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Punteggio di ieri"
        }
        return "Punteggio di \(day.formatted(.dateTime.weekday(.wide).day()))"
    }
}

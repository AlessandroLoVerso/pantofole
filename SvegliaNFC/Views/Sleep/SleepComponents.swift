import SvegliaCore
import SwiftData
import SwiftUI

/// Ring gauge 0–100 with the number in the middle.
struct ScoreRing: View {
    let score: Int
    var size: CGFloat = 96
    var lineWidth: CGFloat = 10
    var caption: LocalizedStringKey?

    @State private var shown = 0.0

    var body: some View {
        ZStack {
            Circle().stroke(Theme.stroke, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(
                    AngularGradient(colors: [Theme.dawn, Theme.sunrise, Color(red: 1, green: 0.78, blue: 0.38)], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text("\(score)")
                    .font(.system(size: size * 0.34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                if let caption {
                    Text(caption)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.smooth(duration: 0.9)) { shown = Double(score) / 100 } }
        .onChange(of: score) { _, new in withAnimation(.smooth) { shown = Double(new) / 100 } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Punteggio \(score) su 100")
    }
}

/// Small number + label used in the stats grids.
struct StatTile: View {
    let value: String
    let label: LocalizedStringKey
    var icon: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let icon {
                Image(systemName: icon).font(.footnote).foregroundStyle(Theme.sunrise)
            }
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Theme.surface, in: .rect(cornerRadius: 18))
        .accessibilityElement(children: .combine)
    }
}

enum SleepFormat {
    /// "7 h 25 min".
    static func hours(minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return String(localized: "\(rest) min") }
        if rest == 0 { return String(localized: "\(hours) h") }
        return String(localized: "\(hours) h \(rest) min")
    }

    static func note(_ note: DayScore.Note) -> LocalizedStringKey {
        switch note {
        case .great: "Notte piena e risveglio pronto: giornata perfetta."
        case .good: "Buon equilibrio tra sonno e risveglio."
        case .shortSleep: "Meno di 6 ore di sonno: stasera prova ad andare a letto prima."
        case .restlessNight: "Notte agitata: risvegli e rumori hanno pesato."
        case .slowWake: "Ci hai messo un po' a raggiungere il tag."
        case .missedWake: "Il tag non è stato scansionato: si è fermata da sola."
        }
    }

    static func eventName(_ kind: SleepEvent.Kind) -> LocalizedStringKey {
        switch kind {
        case .snoring: "Russamento"
        case .talking: "Parlato"
        case .cough: "Tosse"
        case .noise: "Rumore"
        }
    }

    static func eventIcon(_ kind: SleepEvent.Kind) -> String {
        switch kind {
        case .snoring: "zzz"
        case .talking: "quote.bubble.fill"
        case .cough: "lungs.fill"
        case .noise: "speaker.wave.3.fill"
        }
    }

    static func phaseName(_ phase: SleepPhase) -> String {
        switch phase {
        case .awake: String(localized: "Sveglio")
        case .light: String(localized: "Leggero")
        case .deep: String(localized: "Profondo")
        }
    }
}

extension DayScore {
    /// Daily scores from what is stored: finished nights and alarm mornings.
    static func all(sessions: [SleepSession], records: [WakeRecord]) -> [DayScore] {
        DailyScore.days(nights: sessions.compactMap(\.night), wakes: records.map(\.result))
    }
}

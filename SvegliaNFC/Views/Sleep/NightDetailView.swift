import Charts
import SvegliaCore
import SwiftUI

/// One night: quality, timeline of sounds and movement with the estimated phases, events.
struct NightDetailView: View {
    let session: SleepSession

    var body: some View {
        let report = session.report
        let minutes = session.minutes
        let buckets = Bucket.make(minutes: minutes, phases: report.phases, start: session.start)
        let events = session.events.filter { $0.kind != .snoring }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 18) {
                    ScoreRing(score: report.quality, size: 104, lineWidth: 11, caption: "qualità")
                    VStack(alignment: .leading, spacing: 4) {
                        Text(SleepFormat.hours(minutes: report.minutesAsleep))
                            .font(.system(.title, design: .rounded).weight(.bold))
                        Text("di sonno")
                            .font(.subheadline)
                            .foregroundStyle(Theme.muted)
                        Text("\(Format.time(session.start)) – \(Format.time(session.end ?? report.end))")
                            .font(.footnote)
                            .foregroundStyle(Theme.muted)
                    }
                }
                .card()

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    StatTile(value: report.fellAsleep.map { Format.time($0) } ?? "–", label: "Addormentato alle", icon: "moon.fill")
                    StatTile(value: report.wokeUp.map { Format.time($0) } ?? "–", label: "Ultimo risveglio", icon: "sunrise.fill")
                    StatTile(value: "\(report.awakenings)", label: "Risvegli", icon: "eye.fill")
                    StatTile(value: SleepFormat.hours(minutes: report.snoringMinutes), label: "Russamento", icon: "zzz")
                    StatTile(value: "\(Int((report.restlessness * 100).rounded()))%", label: "Irrequietezza", icon: "figure.walk.motion")
                    StatTile(value: SleepFormat.hours(minutes: report.minutesInBed), label: "A letto", icon: "bed.double.fill")
                }

                timeline(buckets)
                phases(buckets)

                if !events.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Cosa ho sentito").font(.headline)
                        ForEach(Array(events.prefix(30).enumerated()), id: \.offset) { _, event in
                            HStack {
                                Image(systemName: SleepFormat.eventIcon(event.kind))
                                    .foregroundStyle(Theme.sunrise)
                                    .frame(width: 26)
                                    .accessibilityHidden(true)
                                Text(SleepFormat.eventName(event.kind))
                                Spacer()
                                Text(Format.time(session.start.addingTimeInterval(event.offset)))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.muted)
                            }
                            .font(.subheadline)
                            .accessibilityElement(children: .combine)
                        }
                        if events.count > 30 {
                            Text("e altri \(events.count - 30)").font(.footnote).foregroundStyle(Theme.muted)
                        }
                    }
                    .card()
                }

                Label("Le fasi sono una stima basata su suoni e movimenti, non una misura medica. L'audio non è mai stato registrato.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle(session.start.formatted(.dateTime.weekday(.wide).day().month()).capitalized)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timeline(_ buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Suoni e movimenti").font(.headline)
            Chart(buckets) { bucket in
                BarMark(
                    x: .value("Ora", bucket.start, unit: .minute),
                    y: .value("Attività", bucket.activity),
                    width: .ratio(0.8)
                )
                .foregroundStyle(by: .value("Tipo", bucket.snoring ? String(localized: "Russamento") : String(localized: "Movimento")))
            }
            .chartForegroundStyleScale([
                String(localized: "Movimento"): Theme.sunrise,
                String(localized: "Russamento"): Color(red: 0.55, green: 0.5, blue: 1),
            ])
            .chartYAxis(.hidden)
            .chartXAxis { hourAxis }
            .chartLegend(position: .bottom, alignment: .leading)
            .frame(height: 140)
            .accessibilityLabel("Grafico di suoni e movimenti durante la notte")
        }
        .card()
    }

    private func phases(_ buckets: [Bucket]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Fasi stimate").font(.headline)
                Spacer()
                Text("stima").font(.caption.weight(.semibold)).foregroundStyle(Theme.muted)
            }
            Chart(buckets) { bucket in
                RectangleMark(
                    xStart: .value("Inizio", bucket.start),
                    xEnd: .value("Fine", bucket.start.addingTimeInterval(Bucket.length)),
                    y: .value("Fase", SleepFormat.phaseName(bucket.phase))
                )
                .foregroundStyle(color(bucket.phase))
                .cornerRadius(2)
            }
            .chartYScale(domain: SleepPhase.allCases.map { SleepFormat.phaseName($0) })
            .chartXAxis { hourAxis }
            .frame(height: 120)
            .accessibilityLabel(phaseSummary(buckets))
        }
        .card()
    }

    private var hourAxis: some AxisContent {
        AxisMarks(values: .stride(by: .hour, count: 2)) { _ in
            AxisGridLine().foregroundStyle(Theme.stroke)
            AxisValueLabel(format: .dateTime.hour())
        }
    }

    private func color(_ phase: SleepPhase) -> Color {
        switch phase {
        case .awake: Theme.dawn
        case .light: Theme.sunrise.opacity(0.6)
        case .deep: Color(red: 0.35, green: 0.4, blue: 0.95)
        }
    }

    private func phaseSummary(_ buckets: [Bucket]) -> String {
        let minutes = { (phase: SleepPhase) in buckets.filter { $0.phase == phase }.count * Int(Bucket.length / 60) }
        return String(localized: "Fasi stimate: sonno profondo \(SleepFormat.hours(minutes: minutes(.deep))), leggero \(SleepFormat.hours(minutes: minutes(.light))), sveglio \(SleepFormat.hours(minutes: minutes(.awake)))")
    }
}

/// Five minutes of the night, for readable charts.
private struct Bucket: Identifiable {
    static let length: TimeInterval = 5 * 60

    let start: Date
    let activity: Double
    let snoring: Bool
    let phase: SleepPhase

    var id: Date { start }

    static func make(minutes: [SleepMinute], phases: [SleepPhase], start: Date) -> [Bucket] {
        stride(from: 0, to: minutes.count, by: 5).map { (i: Int) -> Bucket in
            let range = i..<min(i + 5, minutes.count)
            let slice = minutes[range]
            let activity = slice.map { SleepAnalysis.activity($0) + $0.level / 4 }.reduce(0, +) / Double(slice.count)
            let snoring = slice.filter(\.snoring).count * 2 > slice.count
            // The most "awake" phase of the five minutes, so short awakenings stay visible.
            let phase = phases[range].max { $0.rank < $1.rank } ?? .light
            return Bucket(start: start.addingTimeInterval(Double(i) * 60), activity: activity, snoring: snoring, phase: phase)
        }
    }
}

private extension SleepPhase {
    var rank: Int {
        switch self {
        case .deep: 0
        case .light: 1
        case .awake: 2
        }
    }
}

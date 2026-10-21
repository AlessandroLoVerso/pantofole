import Charts
import SvegliaCore
import SwiftData
import SwiftUI

/// The daily score over the last 7 or 30 days, with the nights behind it.
struct SleepHistoryView: View {
    @Query(filter: #Predicate<SleepSession> { $0.end != nil }, sort: \SleepSession.start, order: .reverse)
    private var sessions: [SleepSession]
    @Query(sort: \WakeRecord.alarmStart, order: .reverse) private var records: [WakeRecord]
    @Environment(\.modelContext) private var context

    @State private var range = 7
    @State private var showsTips = false

    var body: some View {
        let from = Calendar.current.date(byAdding: .day, value: -(range - 1), to: Calendar.current.startOfDay(for: .now)) ?? .now
        let days = DayScore.all(sessions: sessions, records: records).filter { $0.day >= from }
        let nights = sessions.filter { ($0.end ?? $0.start) >= from }
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Picker("Periodo", selection: $range) {
                    Text("7 giorni").tag(7)
                    Text("30 giorni").tag(30)
                }
                .pickerStyle(.segmented)

                chart(days, from: from)

                HStack(spacing: 10) {
                    StatTile(
                        value: days.isEmpty ? "–" : "\(days.map(\.score).reduce(0, +) / days.count)",
                        label: "Punteggio medio", icon: "sparkles"
                    )
                    StatTile(
                        value: nights.isEmpty ? "–" : SleepFormat.hours(minutes: nights.map(\.minutesAsleep).reduce(0, +) / nights.count),
                        label: "Sonno medio", icon: "moon.zzz.fill"
                    )
                    StatTile(
                        value: "\(DailyScore.bestStreak(records.map(\.result)))",
                        label: "Serie migliore", icon: "flame.fill"
                    )
                }

                Text("Le notti")
                    .font(.title3.weight(.bold))
                    .padding(.top, 8)
                if nights.isEmpty {
                    Text("Ancora nessuna notte in questo periodo. Stasera tocca Buonanotte e appoggia l'iPhone sul comodino.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                        .card()
                } else {
                    VStack(spacing: 0) {
                        ForEach(nights) { session in
                            NavigationLink {
                                NightDetailView(session: session)
                            } label: {
                                NightRow(session: session)
                            }
                            .buttonStyle(.plain)
                            if session.id != nights.last?.id { Divider().overlay(Theme.stroke) }
                        }
                    }
                    .card()
                }
                Text("Il punteggio unisce per due terzi la qualità del sonno e per un terzo la velocità con cui hai raggiunto il tag. Senza notte registrata conta solo il risveglio.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.night.ignoresSafeArea())
        .navigationTitle("Il tuo sonno")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showsTips = true } label: { Image(systemName: "iphone.radiowaves.left.and.right") }
                    .accessibilityLabel("Dove mettere l'iPhone")
            }
            #if DEBUG
            ToolbarItem(placement: .topBarTrailing) {
                Button { SleepSampleData.seed(into: context) } label: { Image(systemName: "wand.and.stars") }
                    .accessibilityLabel("Dati di esempio")
            }
            #endif
        }
        .sheet(isPresented: $showsTips) { PlacementSheet() }
        .sensoryFeedback(.selection, trigger: range)
    }

    @ViewBuilder
    private func chart(_ days: [DayScore], from: Date) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Punteggio giornaliero")
                .font(.headline)
            if days.isEmpty {
                Text("Il primo punteggio arriva domattina, quando spegni la sveglia con il tag.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, minHeight: 120, alignment: .center)
            } else {
                let average = Double(days.map(\.score).reduce(0, +)) / Double(days.count)
                Chart {
                    ForEach(days, id: \.day) { day in
                        BarMark(x: .value("Giorno", day.day, unit: .day), y: .value("Punteggio", day.score))
                            .foregroundStyle(Theme.sunriseGradient)
                            .clipShape(.rect(cornerRadius: range == 7 ? 6 : 2))
                    }
                    RuleMark(y: .value("Media", average))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                }
                .chartYScale(domain: 0...100)
                .chartXScale(domain: from...Calendar.current.startOfDay(for: .now).addingTimeInterval(86_400))
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day, count: range == 7 ? 1 : 7)) { _ in
                        AxisValueLabel(format: range == 7 ? .dateTime.weekday(.narrow) : .dateTime.day().month(.abbreviated), centered: true)
                    }
                }
                .chartYAxis {
                    AxisMarks(values: [0, 50, 100]) { _ in
                        AxisGridLine().foregroundStyle(Theme.stroke)
                        AxisValueLabel()
                    }
                }
                .frame(height: 180)
                .accessibilityLabel("Punteggio medio \(Int(average.rounded())) su 100")
            }
        }
        .card()
    }
}

private struct NightRow: View {
    let session: SleepSession

    var body: some View {
        HStack(spacing: 14) {
            ScoreRing(score: session.quality, size: 44, lineWidth: 5)
            VStack(alignment: .leading, spacing: 2) {
                Text(session.start.formatted(.dateTime.weekday(.wide).day().month(.wide)).capitalized)
                    .font(.headline)
                Text("\(SleepFormat.hours(minutes: session.minutesAsleep)) di sonno · \(Format.time(session.start))–\(Format.time(session.end ?? session.start))")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 10)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
    }
}

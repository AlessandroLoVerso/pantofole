import SwiftUI

/// Shown between "Fai una sveglia di prova" and the ring: a countdown, so it's clear something is coming.
struct TestCountdownView: View {
    let start: Date

    @Environment(AppModel.self) private var model

    var body: some View {
        ZStack {
            Theme.night.ignoresSafeArea()
            VStack(spacing: 22) {
                Spacer()
                TimelineView(.periodic(from: .now, by: 0.2)) { timeline in
                    let left = max(0, start.timeIntervalSince(timeline.date))
                    ZStack {
                        Circle()
                            .stroke(Theme.surface, lineWidth: 14)
                        Circle()
                            .trim(from: 0, to: left / AppConfig.testDelay)
                            .stroke(Theme.sunriseGradient, style: StrokeStyle(lineWidth: 14, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.linear(duration: 0.2), value: left)
                        Text(left > 0 ? "\(Int(left.rounded(.up)))" : "…")
                            .font(.system(size: 96, weight: .bold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: Int(left.rounded(.up)))
                    }
                    .frame(width: 220, height: 220)
                    .accessibilityElement()
                    .accessibilityLabel("Suona tra \(Int(left.rounded(.up))) secondi")
                }
                Text("Sta per suonare")
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                Text("Per provarla come al mattino, blocca l'iPhone e appoggialo senza guardarlo: se lo guardi, iOS abbassa il volume delle sveglie.")
                    .font(.callout)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                Spacer()
                Button("Annulla la prova") { model.cancelTestAlarm() }
                    .buttonStyle(.secondary)
            }
            .padding(24)
        }
        .sensoryFeedback(.start, trigger: start)
    }
}
